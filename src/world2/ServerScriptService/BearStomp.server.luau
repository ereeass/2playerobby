-- Stomp bears (see ReplicatedStorage.BearStomp): while a bear slams down, anything under it -
-- a scooter or its riders - ends that run in the death popup (ScooterSystem.DeathManager:
-- SKIP / REVIVE), like the laser gates; a player on foot just dies. Only while it's coming
-- down: a bear sitting on the road is just in the way, and one in the air is safe to pass under.
local CollectionService   = game:GetService("CollectionService")
local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ScooterSystem = ServerScriptService:WaitForChild("ScooterSystem")
local RideManager   = require(ScooterSystem:WaitForChild("RideManager"))
local DeathManager  = require(ScooterSystem:WaitForChild("DeathManager"))
local BearStomp     = require(game:GetService("ReplicatedStorage"):WaitForChild("BearStomp"))
local scooters      = workspace:WaitForChild("RideSystem"):WaitForChild("Scooters")

local DANGER = 8     -- studs above the road: below this a falling bear is on top of whatever's there

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
	local bears = CollectionService:GetTagged("StompBear")
	local watch = { scooters }
	for _, plr in ipairs(Players:GetPlayers()) do if plr.Character then table.insert(watch, plr.Character) end end
	params.FilterDescendantsInstances = watch
	for _, bear in ipairs(bears) do
		local fp = bear:FindFirstChild("Footprint")
		if not fp then continue end
		local h, phase = BearStomp.State(bear, now)
		if phase ~= "drop" or h > DANGER then continue end
		local bottom = fp.Position.Y - fp.Size.Y / 2
		local tall = math.max(h, 1)
		local box = CFrame.new(fp.Position.X, bottom + tall / 2, fp.Position.Z)
		for _, hit in ipairs(workspace:GetPartBoundsInBox(box, Vector3.new(fp.Size.X, tall, fp.Size.Z), params)) do
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
