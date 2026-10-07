-- Octopus tentacles (see ReplicatedStorage.TentacleCycle): whatever is on a tentacle's red strip
-- as it smacks down - a scooter or its riders - ends that run in the death popup
-- (ScooterSystem.DeathManager: SKIP / REVIVE), like the laser gates; a player on foot just dies.
-- Only the smack itself: a tentacle lying on the road is harmless.
local CollectionService   = game:GetService("CollectionService")
local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ScooterSystem = ServerScriptService:WaitForChild("ScooterSystem")
local RideManager   = require(ScooterSystem:WaitForChild("RideManager"))
local DeathManager  = require(ScooterSystem:WaitForChild("DeathManager"))
local TentacleCycle = require(game:GetService("ReplicatedStorage"):WaitForChild("TentacleCycle"))
local scooters      = workspace:WaitForChild("RideSystem"):WaitForChild("Scooters")

local DANGER = math.rad(30)   -- below this the arm is coming down onto the road
local TALL   = 7              -- studs above the strip that count as "under it"

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
	local now = workspace:GetServerTimeNow()
	local watch = { scooters }
	for _, plr in ipairs(Players:GetPlayers()) do if plr.Character then table.insert(watch, plr.Character) end end
	params.FilterDescendantsInstances = watch
	for _, t in ipairs(CollectionService:GetTagged("Tentacle")) do
		local zone = t:FindFirstChild("Zone")
		if not zone then continue end
		local a, phase, k = TentacleCycle.State(t, now)
		local hitting = (phase == "slam" and a < DANGER) or (phase == "down" and k < 0.12)
		if not hitting then continue end
		local box = zone.CFrame * CFrame.new(0, TALL / 2, 0)
		for _, hit in ipairs(workspace:GetPartBoundsInBox(box, Vector3.new(zone.Size.X, TALL, zone.Size.Z), params)) do
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
