-- Chemical spills (Workspace > Chemical Spills, Models tagged "ChemSpill"): a scooter whose tyre
-- (or any part) touches a spill ends that run in the death popup (ScooterSystem.DeathManager:
-- SKIP / REVIVE), like the laser gates; a player on foot who steps in one just dies. Each spill's
-- invisible Zone part is the deadly area (a little inside the glowing puddle, up to tyre height).
local CollectionService   = game:GetService("CollectionService")
local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ScooterSystem = ServerScriptService:WaitForChild("ScooterSystem")
local RideManager   = require(ScooterSystem:WaitForChild("RideManager"))
local DeathManager  = require(ScooterSystem:WaitForChild("DeathManager"))
local scooters      = workspace:WaitForChild("RideSystem"):WaitForChild("Scooters")

local function whoHit(hit)
	local model = hit:FindFirstAncestorOfClass("Model")
	while model do
		if model.Parent == scooters then return RideManager.Rides[model], nil end
		local plr = Players:GetPlayerFromCharacter(model)
		if plr then return RideManager.PlayerRide[plr], plr end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil, nil
end

local params = OverlapParams.new()
params.FilterType = Enum.RaycastFilterType.Include

RunService.Heartbeat:Connect(function()
	local watch = { scooters }
	for _, plr in ipairs(Players:GetPlayers()) do if plr.Character then table.insert(watch, plr.Character) end end
	params.FilterDescendantsInstances = watch
	for _, spill in ipairs(CollectionService:GetTagged("ChemSpill")) do
		local zone = spill:FindFirstChild("Zone")
		if not zone then continue end
		for _, hit in ipairs(workspace:GetPartBoundsInBox(zone.CFrame, zone.Size, params)) do
			local ride, plr = whoHit(hit)
			if ride then
				if not ride._ended and not ride.Down then DeathManager.Hit(ride) end
			elseif plr and plr.Character then
				local hum = plr.Character:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 then hum.Health = 0 end
			end
		end
	end
end)
