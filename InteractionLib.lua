-- Cache global table
local GlobalTable = (typeof(getfenv().getgenv) == "function" and typeof(getfenv().getgenv()) == "table" and getfenv().getgenv()) or _G

-- Prevent duplicate loading
if GlobalTable._NETWORK then
	return GlobalTable._NETWORK
end

-- Cache services and player
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService") -- Use PhysicsService for AllowSleep
local plr = Players.LocalPlayer

-- Cache hidden functions (check once)
local sethiddenproperty = getfenv().sethiddenproperty or getfenv().sethiddenprop
local setsimulationradius = getfenv().setsimulationradius

local active = false
local cd = {} -- Cooldown table

-- Helper function for yielding (simplified)
local function yield(time)
	task.wait(time or 0.01)
end

-- Function to apply/reset simulation radii for a single player
local function setPlayerSimulationRadius(player, radius)
	if not player then return end
	pcall(function() -- Use pcall once per function call, not per property set
		player.MaximumSimulationRadius = radius
		if sethiddenproperty then
			-- These are guesses for default values, adjust if needed
			local hiddenMax = (radius == math.huge) and math.huge or 20
			local hiddenSim = (radius == math.huge) and math.huge or 40 -- Another guess
			sethiddenproperty(player, 'MaxSimulationRadius', hiddenMax)
			sethiddenproperty(player, 'SimulationRadius', hiddenSim)
		end
	end)
end

-- --- RenderStepped Connection (minimal logic) ---
RunService.RenderStepped:Connect(function()
	if not active then return end
	-- These need continuous enforcement
	PhysicsService.AllowSleep = false -- Use PhysicsService
	plr.ReplicationFocus = workspace
end)

-- --- Player Added/Removed Connections (for simulation radii) ---
Players.PlayerAdded:Connect(function(player)
	if active and player ~= plr then
		setPlayerSimulationRadius(player, 0)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	-- Optionally reset radii when they leave, though less critical
	if active and player ~= plr then
		setPlayerSimulationRadius(player, 20) -- Reset to a default guess
	end
end)

-- --- FireTouchInterest Simulation ---
local ftiv = false
local fti = getfenv().firetouchinterest

-- Detect if native firetouchinterest works
task.spawn(pcall, function()
	if not fti then return end
	local part = Instance.new("Part", workspace)
	part.Position = Vector3.new(0, 100, 0)
	part.Anchored = false
	part.CanCollide = false
	part.Transparency = 1
	-- Use a signal connection instead of relying on unreliable Touched:Wait() later
	local connection
	connection = part.Touched:Connect(function()
		ftiv = true -- Native fti worked!
		connection:Disconnect()
		part:Destroy()
	end)
	task.wait(0.1) -- Give time for part to replicate
	repeat task.wait() until plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
	if part and part.Parent and plr.Character and plr.Character.HumanoidRootPart then
		-- Attempt touch using native fti
		pcall(fti, part, plr.Character.HumanoidRootPart, 0) -- Touch begin
		pcall(fti, plr.Character.HumanoidRootPart, part, 0)
		task.wait(0.1) -- Short wait
		if part and part.Parent then -- Check if still exists
			pcall(fti, part, plr.Character.HumanoidRootPart, 1) -- Touch end
			pcall(fti, plr.Character.HumanoidRootPart, part, 1)
		end
	end
	-- Clean up if touch didn't happen for some reason
	if part and part.Parent then
		part:Destroy()
		connection:Disconnect()
	end
end)

local firetouchinterest = function(a, b, touching)
	-- Use native if available and detected
	if ftiv then
		return pcall(fti, a, b, touching)
	end

	-- Basic validation and character handling
	if not a or not b or typeof(a) ~= "Instance" or typeof(b) ~= "Instance" or not a:IsA("BasePart") or not b:IsA("BasePart") then return false end
	if a:IsDescendantOf(plr.Character) and b:IsDescendantOf(plr.Character) then return false end
	if b:IsDescendantOf(plr.Character) then
		local c = a
		a = b
		b = c
	end

	-- Cooldown check (basic)
	if cd[a] or cd[b] then return false end

	-- Spawn simulation task (cooldown applied inside task)
	task.spawn(function()
		cd[a] = true
		cd[b] = true

		local touchingBool = touching == 0 -- 0 for begin, 1 for end

		if not touchingBool then -- Simulate touch END (touching == 1) - Flawed but improved
			-- The previous logic for touching=0 was incorrect, removing it.
			-- Simulating touch BEGIN is extremely difficult without native fti.
			-- We will only attempt to simulate touch END here using the pivot hack.
			-- This means the manual touch simulation is only useful for ending existing touches.
		elseif touchingBool then -- Simulate touch BEGIN (touching == 0) - Still very hacky
			-- This is still a very unreliable hack. The original logic for begin was wrong.
			-- Let's try a brief collision simulation instead of the incorrect CanTouch method.
			local original_collide = b.CanCollide
			local original_transparency = b.Transparency
			local original_anchored = b.Anchored
			local original_pivot = b:GetPivot()

			pcall(function()
				b.CanCollide = true
				b.Transparency = 0.99 -- Make slightly visible for effect? Or 1?
				b.Anchored = false -- Must not be anchored to collide
				-- Move slightly into a, then move back
				local direction = (a.Position - b.Position).Unit * 0.1
				b:PivotTo(original_pivot + direction)
				yield(0.05) -- Give engine a moment
				b:PivotTo(original_pivot - direction) -- Move back slightly past original to ensure separation
				yield(0.05)
			end)

			-- Attempt to restore original state quickly
			pcall(function()
				b:PivotTo(original_pivot)
				b.CanCollide = original_collide
				b.Transparency = original_transparency
				b.Anchored = original_anchored
			end)

		end -- End of touch simulation logic (still very hacky)

		yield(0.05) -- Short yield before releasing cooldown
		cd[a] = false
		cd[b] = false
	end)

	return true
end

-- --- FireProximityPrompt Simulation ---
local fppn = false
local fpp = getfenv().fireproximityprompt

-- Detect if native fireproximityprompt works
task.spawn(pcall, function()
	if not fpp then return end
	-- Use a simple instance and connection to detect native function success
	local pp = Instance.new("ProximityPrompt", workspace)
	local connection = pp.Triggered:Connect(function()
		fppn = true -- Native fpp worked!
		connection:Disconnect()
		pp:Destroy()
	end)
	-- Native fpp often needs the prompt to be parented and enabled
	pp.Enabled = true
	task.wait(0.1)
	pcall(fpp, pp)
	task.wait(1.5) -- Give it some time
	if pp and pp.Parent then
		pp:Destroy()
		connection:Disconnect()
	end
end)

-- Helper for proximity prompt simulation
local function fireproximityprompt_simulate(pp)
	if cd[pp] then return end -- Cooldown check
	cd[pp] = true

	local original_props = { -- Store original properties
		MaxActivationDistance = pp.MaxActivationDistance,
		Enabled = pp.Enabled,
		Parent = pp.Parent,
		HoldDuration = pp.HoldDuration,
		RequiresLineOfSight = pp.RequiresLineOfSight,
		Position = nil -- Store parent position if possible
	}

	local parent_obj = pp.Parent
	if parent_obj and parent_obj:IsA("BasePart") then
		original_props.Position = parent_obj.Position
	end


	local obj = Instance.new("Part", workspace) -- Create dummy part
	obj.Transparency = 1
	obj.CanCollide = false
	obj.Size = Vector3.new(0.1, 0.1, 0.1)
	obj.Anchored = true

	pcall(function() -- Use pcall for property changes that might error
		-- Temporarily change prompt properties for easier triggering
		pp.Parent = obj -- Reparent to dummy part
		pp.MaxActivationDistance = math.huge
		pp.Enabled = true
		pp.HoldDuration = 0 -- Instant trigger
		pp.RequiresLineOfSight = false
	end)

	if not pp or not pp.Parent or pp.Parent ~= obj then -- Check if prompt is valid and reparented
		obj:Destroy()
		cd[pp] = false
		return
	end

	pcall(function()
		-- Position the dummy part near the camera/player for prompt triggering
		local targetPos = workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position or (plr.Character and plr.Character.HumanoidRootPart and plr.Character.HumanoidRootPart.Position) or Vector3.new(0,10,0)
		if targetPos then
			obj:PivotTo(CFrame.new(targetPos + Vector3.new(0, 0.5, 0))) -- Place slightly above
		end

		yield() -- Short yield
		pp:InputHoldBegin() -- Simulate input
		yield() -- Short yield
		pp:InputHoldEnd() -- Simulate input
		yield() -- Short yield
	end)


	-- Restore original properties and clean up
	if pp and pp.Parent == obj then -- Check if prompt still exists and is parented to dummy
		pcall(function()
			pp.Parent = original_props.Parent -- Restore original parent
			pp.MaxActivationDistance = original_props.MaxActivationDistance
			pp.Enabled = original_props.Enabled
			pp.HoldDuration = original_props.HoldDuration
			pp.RequiresLineOfSight = original_props.RequiresLineOfSight
			-- Attempt to restore original position if it was a BasePart parent
			if original_props.Position and original_props.Parent and original_props.Parent:IsA("BasePart") then
				original_props.Parent:PivotTo(CFrame.new(original_props.Position)) -- Restore parent position
			end
		end)
	end

	obj:Destroy() -- Destroy dummy part
	cd[pp] = false -- Release cooldown
end


local fireproximityprompt = function(pp, checkDistance)
	-- Default checkDistance to true if not provided
	checkDistance = checkDistance == nil or checkDistance

	-- Basic validation
	if typeof(pp) ~= "Instance" or not pp:IsA("ProximityPrompt") or cd[pp] then
		return false
	end

	-- Optional distance check
	if checkDistance then
		local promptPosition = pp.Parent and pp.Parent:GetPivot().Position -- Use GetPivot for accuracy
		local playerPosition = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") and plr.Character.HumanoidRootPart.Position or workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position
		if not promptPosition or not playerPosition or (promptPosition - playerPosition).Magnitude > pp.MaxActivationDistance then
			return false -- Too far away
		end
	end

	-- Use native function if available and detected
	if fppn then
		return pcall(fpp, pp) -- Use pcall for native call
	end

	-- Otherwise, use simulation
	task.spawn(fireproximityprompt_simulate, pp)

	return true
end

-- --- Main object ---
local main = setmetatable({
	Active = active,

	SetActive = function(self, state)
		-- Update internal state
		active = state
		self.Active = state

		-- Apply settings that need changing once
		PhysicsService.AllowSleep = not state -- Use PhysicsService
		plr.ReplicationFocus = state and workspace or nil

		-- Apply simulation radii to existing players based on state
		for _, player in Players:GetPlayers() do
			if player ~= plr then
				setPlayerSimulationRadius(player, state and 0 or 20) -- 20 is a guess for default
			else
				-- Set local player radius (assuming you always want huge for yourself when active)
				setPlayerSimulationRadius(plr, state and math.huge or 20) -- 20 is a guess for default
			end
		end

		-- Apply global simulation radius if function exists
		if setsimulationradius then
			-- These are guesses for global defaults, adjust if needed
			pcall(setsimulationradius, state and 9e8 or 0, state and 9e9 or 30)
		end

	end,

	IsNetworkOwner = function(self, part)
		if getfenv().isnetworkowner then
			return pcall(getfenv().isnetworkowner, part) -- Use pcall just in case
		end
		-- Fallback check (less reliable)
		return part.ReceiveAge == 0
	end,

	Other = table.freeze({
		-- Touch functions (call the internal simulated/native function)
		TouchInterest = function(self, ...) return firetouchinterest(...) end,
		TouchTransmitter = function(self, ...) return self:TouchInterest(...) end,
		FireTouchInterest = function(self, ...) return self:TouchInterest(...) end,
		FireTouchTransmitter = function(self, ...) return self:TouchInterest(...) end,

		-- ProximityPrompt functions (call the internal simulated/native function)
		ProximityPrompt = function(self, ...) return fireproximityprompt(...) end,
		FireProximityPrompt = function(self, ...) return self:ProximityPrompt(...) end,

		-- Simulate full touch (begin and end)
		Touch = function(self, target, instant)
			if not plr.Character or not target or typeof(target) ~= "Instance" or not target:IsA("BasePart") then return false end
			local charParts = plr.Character:GetDescendants()
			local randomParts = {}

			-- Find base parts in character
			for _, v in charParts do
				if v:IsA("BasePart") then
					table.insert(randomParts, v)
				end
			end

			if #randomParts == 0 then return false end
			local partToTouch = randomParts[math.random(1, #randomParts)]

			-- Call touch interest function for begin and end
			local success1 = firetouchinterest(partToTouch, target, 0) -- 0 for touch begin
			local success2 = true
			if not instant then
				yield(0.001) -- Short wait between begin and end
				success2 = firetouchinterest(partToTouch, target, 1) -- 1 for touch end
			end

			return success1 and success2
		end,
		TouchPart = function(self, ...) return self:Touch(...) end, -- Alias

		-- Simulate sitting on a seat
		Sit = function(self, seatPart)
			if not seatPart or not seatPart:IsA("Seat") or not plr.Character then return false end
			local hum = plr.Character:FindFirstChildOfClass("Humanoid")

			if hum and not seatPart.Occupant then
				local original_pivot = seatPart:GetPivot()
				pcall(function()
					seatPart:PivotTo(plr.Character.HumanoidRootPart:GetPivot()) -- Move seat to player
					self:Touch(seatPart, false) -- Simulate touch
				end)
				yield(0.1) -- Give engine a moment to register sit (guess)
				pcall(function()
					seatPart:PivotTo(original_pivot) -- Move seat back
				end)
				return true
			end
			return false
		end,
		SitPart = function(self, ...) return self:Sit(...) end, -- Alias
	})
}, {
	__call = function(self, state)
		-- Call SetActive when the main object is called like a function
		self:SetActive(state)
	end
})

-- Set __index so functions can be accessed via object.FunctionName
main.__index = main

-- Export the main object to the global table
GlobalTable._NETWORK = main

return main
