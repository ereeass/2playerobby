-- Volcano (see ReplicatedStorage.VolcanoCycle): while the lava is on the road, anything in it - a
-- scooter or its riders - ends that run in the death popup (ScooterSystem.DeathManager: SKIP /
-- REVIVE), like the laser gates; a player on foot just dies. Only the part of the road the lava
-- has reached counts, and nothing once it starts to fade.
local CollectionService   = game:GetService("CollectionService")
local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ScooterSystem = ServerScriptService:WaitForChild("ScooterSystem")
local RideManager   = require(ScooterSystem:WaitForChild("RideManager"))
local DeathManager  = require(ScooterSystem:WaitForChild("DeathManager"))
local VolcanoCycle  = require(game:GetService("ReplicatedStorage"):WaitForChild("VolcanoCycle"))
local scooters      = workspace:WaitForChild("RideSystem"):WaitForChild("Scooters")

local TALL = 4     -- studs above the road that count as "in the lava"

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
	for _, v in ipairs(CollectionService:GetTagged("Volcano")) do
		local pool = v:FindFirstChild("Pool")
		if not pool then continue end
		local s = VolcanoCycle.State(v, now)
		if not s.deadly or s.spread <= 0 then continue end
		local full = pool.Size
		local w, d = full.X * s.spread, full.Z * s.spread
		local arrive = pool.CFrame:PointToObjectSpace(Vector3.new(pool:GetAttribute("ArriveX") or pool.Position.X, pool.Position.Y, pool.Position.Z)).X
		local cx = math.clamp(arrive, -full.X / 2 + w / 2, full.X / 2 - w / 2)
		local box = pool.CFrame * CFrame.new(cx, TALL / 2 - full.Y / 2, full.Z / 2 - d / 2)
		for _, hit in ipairs(workspace:GetPartBoundsInBox(box, Vector3.new(w, TALL, d), params)) do
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
