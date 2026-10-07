-- Heart hammers (see ReplicatedStorage.HammerSlam): as a hammer's head comes down onto the road,
-- anything under it - a scooter or its riders - ends that run in the death popup
-- (ScooterSystem.DeathManager: SKIP / REVIVE), like the laser gates; a player on foot just dies.
-- Only at the end of the slam: a hammer resting on the road is just in the way.
local CollectionService   = game:GetService("CollectionService")
local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ScooterSystem = ServerScriptService:WaitForChild("ScooterSystem")
local RideManager   = require(ScooterSystem:WaitForChild("RideManager"))
local DeathManager  = require(ScooterSystem:WaitForChild("DeathManager"))
local HammerSlam    = require(game:GetService("ReplicatedStorage"):WaitForChild("HammerSlam"))
local scooters      = workspace:WaitForChild("RideSystem"):WaitForChild("Scooters")

local DANGER_ANGLE = math.rad(35)   -- the head is over the road and low below this
local TALL = 8                      -- studs above the road that count as "under the head"

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
	for _, hammer in ipairs(CollectionService:GetTagged("HeartHammer")) do
		local fp = hammer:FindFirstChild("Footprint")
		if not fp then continue end
		local angle, phase = HammerSlam.State(hammer, now)
		if phase ~= "slam" or angle > DANGER_ANGLE then continue end
		local bottom = fp.Position.Y - fp.Size.Y / 2
		local box = CFrame.new(fp.Position.X, bottom + TALL / 2, fp.Position.Z)
		for _, hit in ipairs(workspace:GetPartBoundsInBox(box, Vector3.new(fp.Size.X, TALL, fp.Size.Z), params)) do
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
