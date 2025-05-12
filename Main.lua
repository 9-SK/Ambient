local plr = game:GetService("Players").LocalPlayer
local tps = loadstring(game:HttpGet("https://raw.githubusercontent.com/InfernusScripts/Null-Fire/refs/heads/main/Core/Loaders/Dead-Rails/Teleports.lua", true))()

local cons = {}
local bondFarm = {
	Collected = 0,
	Active = false,
	Finished = false
}

function bondFarm.GetClosestBond()
	local closest, minDist = nil, math.huge

	for _, v in pairs(workspace.RuntimeItems:GetChildren()) do
		if v.Name == "Bond" then
			local dist = (plr.Character:GetPivot().Position - v:GetPivot().Position).Magnitude
			if dist < minDist then
				minDist = dist
				closest = v
			end
		end
	end

	if not closest then
		bondFarm.TeleportToSafeSpot()
		plr.Character.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		closest = tps.ScanFor(game.FindFirstChild, workspace.RuntimeItems, "Bond")
	end

	return closest
end

function bondFarm.CheckY()
	if plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
		plr.Character.HumanoidRootPart.AssemblyLinearVelocity = Vector3.new(0, 1)
	end
end

function bondFarm.TeleportToSafeSpot()
	tps.Teleports.Train()
	plr.Character.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
end

function bondFarm.BondStep(bond)
	if bond then
		bondFarm.CheckY()
		game:GetService("ReplicatedStorage"):FindFirstChild("C_ActivateObject", true):FireServer(bond)
		plr.Character.Humanoid:MoveTo(bond:GetPivot().Position)
		tps.Teleport(bond:GetPivot().Position - Vector3.new(0, 2.5), nil, nil, false)
	end
end

-- Track bond collections
for _, v in pairs(workspace.RuntimeItems:GetChildren()) do
	if v.Name == "Bond" and not cons[v] then
		cons[v] = v.Destroying:Connect(function()
			bondFarm.Collected += 1
		end)
	end
end

workspace.RuntimeItems.ChildAdded:Connect(function(v)
	if v.Name == "Bond" and not cons[v] then
		cons[v] = v.Destroying:Connect(function()
			bondFarm.Collected += 1
		end)
	end
end)

-- Start loop
task.spawn(function()
	while task.wait(0.075) do
		if bondFarm.Active then
			local finalPlate = workspace:FindFirstChild("Baseplates") and workspace.Baseplates:FindFirstChild("FinalBasePlate")
			if finalPlate then
				local bond = bondFarm.GetClosestBond()
				if not bond then
					bondFarm.Finished = true
					break
				end
				bondFarm.BondStep(bond)
			else
				bondFarm.BondStep(bondFarm.GetClosestBond())
			end
		end
	end
end)

return bondFarm
