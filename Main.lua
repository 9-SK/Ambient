-- NOTE: This script relies on an external library loaded via HTTP.
-- Its functionality and safety depend entirely on the content of that URL.
-- The performance of teleportation and scanning is determined by the loaded script.

-- Cache services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Load external teleport script safely
local tps_success, tps = pcall(loadstring(game:HttpGet("https://raw.githubusercontent.com/9-SK/Ambient/refs/heads/main/Teleportscript.lua", true)))
if not tps_success or not tps then
	warn("Failed to load teleport script:", tps)
	-- Decide how to handle failure (e.g., stop execution, notify user)
	return
end

-- Cache player and necessary character components (wait for them if needed)
local plr = Players.LocalPlayer
local char = plr.Character or plr.CharacterAdded:Wait()

-- Wait for HumanoidRootPart and Humanoid if they don't exist immediately
local hrp = char:FindFirstChild("HumanoidRootPart")
local humanoid = char:FindFirstChildOfClass("Humanoid")

-- Use task.spawn to wait for these without blocking the main script flow
task.spawn(function()
    if not hrp then hrp = char.ChildAdded:Wait("HumanoidRootPart") end
    if not humanoid then humanoid = char.ChildAdded:WaitOfClass("Humanoid") end
    -- print("Character components (HRP, Humanoid) are ready.") -- Optional debug
end)

-- Cache game-specific objects/locations if they exist
local RuntimeItems = Workspace:FindFirstChild("RuntimeItems")
if not RuntimeItems then
	warn("RuntimeItems container (Workspace.RuntimeItems) not found!")
	-- The script can proceed, but won't find local bonds until this appears.
end

-- Cache the RemoteEvent used to activate objects
local ActivateObjectRemote = ReplicatedStorage:FindFirstChild("C_ActivateObject", true)
if not ActivateObjectRemote then
	warn("C_ActivateObject RemoteEvent not found in ReplicatedStorage!")
	-- The script can find bonds, but won't be able to activate them.
end


local bondFarm = {
	Collected = 0,
	Active = false,
	Finished = false
}

-- Store connections for bond tracking
local bondTrackingConnections = {}

-- Function to find the closest "Bond" instance among the CURRENT children of RuntimeItems
function bondFarm.GetClosestBond()
	-- Ensure RuntimeItems container exists and is valid
	if not RuntimeItems or not RuntimeItems:IsA("Folder") then -- Add a type check
		return nil
	end

	local closest, minDist = nil, math.huge
	local playerPos = hrp and hrp.Position -- Use cached HRP position

	-- Cannot calculate distance without player position
	if not playerPos then
		-- print("Player HRP not available to find closest bond.") -- Optional debug
		return nil
	end

	local children = RuntimeItems:GetChildren() -- Get children once per call
	for _, v in children do
		-- Basic validation: check if it's a valid instance, named "Bond", and is a part-like instance
		-- Checking Parent ensures it hasn't been destroyed yet in this frame
		if v and v.Parent == RuntimeItems and v.Name == "Bond" and v:IsA("BasePart") then
			local dist = (playerPos - v.Position).Magnitude -- Use Position for simpler distance check
			if dist < minDist then
				minDist = dist
				closest = v
			end
		end
	end

	return closest -- Returns the closest bond instance found or nil
end

-- Function to handle scanning and teleporting using the external script
-- This is called when no local bonds are found by GetClosestBond
function bondFarm.ScanAndTeleportToBond()
	-- Ensure external script and necessary functions are available
	if not tps or not tps.Teleports or not tps.Teleports.Train or not tps.ScanFor or not tps.Teleport then
		warn("Teleport script or its functions are not fully available.")
		return nil -- Cannot scan/teleport if dependencies are missing
	end
	if not RuntimeItems then
		warn("RuntimeItems container not available for external scan.")
		return nil -- Cannot scan if container is missing
	end

	-- Teleport to a safe spot first (like the train station)
	pcall(tps.Teleports.Train) -- Use pcall for external calls

	-- Wait briefly for potential game state changes after initial teleport
	task.wait(0.5)

	-- Use the loaded script's scan function to find a bond instance
	-- Assume tps.ScanFor arguments are container, object_name
	-- Assume it returns the found instance or nil
	local foundBond_pcall_success, foundBond = pcall(tps.ScanFor, RuntimeItems, "Bond")

	if foundBond_pcall_success and foundBond and typeof(foundBond) == "Instance" and foundBond:IsA("BasePart") then
		-- If a valid bond is found by the scan, attempt to teleport to it
		-- Assume tps.Teleport arguments are position, ...
		-- Use the position of the found bond with an offset (original offset was -Vector3.new(0, 2.5))
		local teleportPos = foundBond.Position - Vector3.new(0, 2.5) -- Use Position
		local teleport_pcall_success = pcall(tps.Teleport, teleportPos, nil, nil, false) -- Use pcall

		if teleport_pcall_success then
			-- Return the found bond if teleport was successful
			return foundBond
		else
			warn("Failed to teleport to the scanned bond position.")
			return nil -- Teleport failed
		end
	else
		-- warn("External scan did not find a valid bond.") -- Optional debug
		return nil -- Scan failed or found invalid object
	end
end

-- Removed CheckY as its purpose is unclear and called frequently.
-- If needed, it could be called once after teleporting.

-- The BondStep function now focuses purely on interacting with the bond via RemoteEvent
function bondFarm.BondStep(bond)
	-- Validate bond instance before interacting
	-- Check Parent == RuntimeItems ensures it's still in the collection container
	if not bond or typeof(bond) ~= "Instance" or not bond:IsA("BasePart") or bond.Parent ~= RuntimeItems then
		-- print("Attempted BondStep with invalid or collected bond.") -- Optional debug
		return false -- Indicate failure
	end

	-- Ensure the RemoteEvent is available
	if not ActivateObjectRemote then
		warn("ActivateObject RemoteEvent is nil, cannot interact with bond.")
		return false -- Indicate failure
	end

	-- Fire the RemoteEvent to activate the bond
	local fire_pcall_success, err = pcall(ActivateObjectRemote.FireServer, ActivateObjectRemote, bond) -- Use pcall for RemoteEvent call
	if not fire_pcall_success then
		warn("FireServer failed for bond:", bond.Name, "Error:", err)
	end

	return fire_pcall_success -- Return success status
end

-- Function to set up tracking for new and existing bonds being destroyed
local function setupBondTracking()
    if not RuntimeItems then return end -- Cannot track if container doesn't exist

	-- Disconnect any old tracking connections if this function is called multiple times
    for _, conn in pairs(bondTrackingConnections) do
        if type(conn) == 'userdata' and typeof(conn) == 'RBXScriptConnection' and conn.Connected then
             conn:Disconnect()
        end
    end
    table.clear(bondTrackingConnections) -- Clear the table

	-- Connect Destroying for existing bonds
	local children = RuntimeItems:GetChildren()
	for _, v in children do
		if v and v.Name == "Bond" and v:IsA("Instance") then -- Basic checks
            -- Check if a connection for this instance already exists (unlikely after clear, but safe)
            if not bondTrackingConnections[v] then
                bondTrackingConnections[v] = v.Destroying:Connect(function()
                    bondFarm.Collected += 1
                    -- Clean up the connection entry when the instance is destroyed
                    if bondTrackingConnections[v] and bondTrackingConnections[v].Connected then
                         bondTrackingConnections[v]:Disconnect()
                    end
                    bondTrackingConnections[v] = nil
                end)
            end
		end
	end

	-- Connect ChildAdded for new bonds
	-- Store this connection under a key related to RuntimeItems itself
	if not bondTrackingConnections[RuntimeItems] then -- Prevent connecting ChildAdded multiple times
        bondTrackingConnections[RuntimeItems] = RuntimeItems.ChildAdded:Connect(function(v)
            if v and v.Name == "Bond" and v:IsA("Instance") then -- Basic checks for new child
                -- Check if a connection for this instance already exists (shouldn't for new children)
                if not bondTrackingConnections[v] then
                     bondTrackingConnections[v] = v.Destroying:Connect(function()
                        bondFarm.Collected += 1
                         -- Clean up the connection entry
                        if bondTrackingConnections[v] and bondTrackingConnections[v].Connected then
                             bondTrackingConnections[v]:Disconnect()
                        end
                        bondTrackingConnections[v] = nil
                    })
                end
            end
        end)
    end
end

-- Initial setup for bond tracking
-- Use task.spawn to avoid yielding the main script load if RuntimeItems is not immediately available
task.spawn(setupBondTracking)


-- Start the main bond farming loop in a separate thread
task.spawn(function()
	-- Wait until necessary player components and RemoteEvent are ready
	-- The tps script loading is checked at the top.
	repeat task.wait() until hrp and humanoid and ActivateObjectRemote and tps and tps.Teleport and tps.ScanFor

    -- Wait briefly to ensure setupBondTracking has had a chance to run
    task.wait(0.1)

	while task.wait(0.05) do -- Loop interval (adjust as needed)
		if bondFarm.Active then
            -- 1. Try to find the closest bond that currently exists locally in RuntimeItems
			local targetBond = bondFarm.GetClosestBond()

			if not targetBond then
				-- 2. If no local bond is found, attempt to scan externally and teleport
				-- This function also handles the player movement to the scanned bond's location
				targetBond = bondFarm.ScanAndTeleportToBond()

				-- Check again if a bond was found after the external scan/teleport attempt
				if not targetBond then
					-- 3. If still no bond is found after scanning and teleporting:
                    -- Check for the final plate (game specific logic for determining "Finished")
					local finalPlateExists = Workspace:FindFirstChild("Baseplates") and Workspace.Baseplates:FindFirstChild("FinalBasePlate")

					if finalPlateExists then
						-- Assume farming is finished if final plate exists and no more bonds are found
						bondFarm.Finished = true
						-- print("Bond farming finished (final plate found, no bonds).") -- Optional debug
						break -- Exit the loop as farming is complete
					else
						-- If no final plate and no bonds, maybe wait longer or retry?
						-- Just continue the loop; ScanAndTeleportToBond might find one eventually.
						-- Add a longer wait here to prevent spamming ScanAndTeleport
						-- print("No bonds found after scan/teleport, waiting before next attempt...") -- Optional debug
						task.wait(1) -- Wait a bit longer
						continue -- Skip to the next loop iteration
					end
				end
			end

			-- 4. If a target bond was found (either locally or via scan/teleport):
			-- The ScanAndTeleportToBond function handles teleporting if it finds one.
			-- If GetClosestBond found it, we need to teleport to it here.
			-- Let's add a teleport step here regardless, just before activating, to ensure proximity.
            -- Use the position of the found bond with the same offset
            local teleportPos = targetBond.Position - Vector3.new(0, 2.5) -- Use Position
            local teleport_pcall_success = pcall(tps.Teleport, teleportPos, nil, nil, false) -- Use pcall

            if not teleport_pcall_success then
                warn("Failed to teleport to target bond position before stepping.")
                 -- Decide if you want to skip stepping this bond if teleport fails
                 -- For now, let's skip to avoid potential issues
                -- print("Skipping BondStep due to failed pre-step teleport.")
                -- continue -- Skip BondStep
            end

            -- Add a small yield after teleporting to allow client/server sync before interacting
            task.wait(0.1) -- Short wait after teleport

			-- 5. Attempt to activate the bond using BondStep
			local stepSuccess = bondFarm.BondStep(targetBond)

            -- Add a small wait after stepping a bond before looking for the next one
            -- This helps prevent spamming and gives the game time to register the collection
            task.wait(0.2) -- Adjust this yield as needed

		else
			-- If not active, wait longer to reduce resource usage
			task.wait(0.5)
		end
	end
	-- print("Bond farming main loop has exited.") -- Optional debug
end)

return bondFarm
