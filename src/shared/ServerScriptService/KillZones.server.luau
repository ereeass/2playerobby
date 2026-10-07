-- Kill zones: every Model tagged "KillZone" (the TropicalIsland and the StiltHut; tag any
-- other model to add it) is lethal like the water (ServerScriptService.WaterHazard):
--   Run    a rider in a scooter run, or their scooter, touching any part of it ends
--          that run in the death popup (ScooterSystem.DeathManager: SKIP / REVIVE).
--   Home   anyone NOT in a run who gets onto it is sent back to the lobby (no death,
--          no popup), exactly as the water does.

local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")

local ScooterSystem = game:GetService("ServerScriptService"):WaitForChild("ScooterSystem")
local RideManager   = require(ScooterSystem:WaitForChild("RideManager"))
local DeathManager  = require(ScooterSystem:WaitForChild("DeathManager"))

local TAG        = "KillZone"
local HOME_AGAIN = 3        -- seconds before a player on foot is sent home again
local homeSent   = {}       -- [player] = os.clock() of the last send home
local wired      = setmetatable({}, { __mode = "k" })

local function characterOf(part)
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		if model:FindFirstChildOfClass("Humanoid") then
			return Players:GetPlayerFromCharacter(model)
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local function rideOfScooterPart(part)
	for scooter, ride in pairs(RideManager.Rides) do
		if part:IsDescendantOf(scooter) then return ride end
	end
	return nil
end

local function onTouched(hit)
	local player = characterOf(hit)
	if player then
		if RideManager.PlayerRide[player] then
			DeathManager.HitPlayer(player)
		elseif os.clock() - (homeSent[player] or 0) > HOME_AGAIN then
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				homeSent[player] = os.clock()
				RideManager.SendHome(player)
			end
		end
		return
	end
	local ride = rideOfScooterPart(hit)
	if ride then DeathManager.Hit(ride) end
end

local function wire(part)
	if wired[part] or not part:IsA("BasePart") then return end
	wired[part] = true
	part.Touched:Connect(onTouched)
end

local function addZone(model)
	for _, d in ipairs(model:GetDescendants()) do wire(d) end
	model.DescendantAdded:Connect(wire)
end

for _, m in ipairs(CollectionService:GetTagged(TAG)) do addZone(m) end
CollectionService:GetInstanceAddedSignal(TAG):Connect(addZone)
Players.PlayerRemoving:Connect(function(player) homeSent[player] = nil end)
