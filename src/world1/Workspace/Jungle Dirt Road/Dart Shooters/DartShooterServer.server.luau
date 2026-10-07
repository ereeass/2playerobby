-- Jungle Dirt Road dart shooters: each tiki blows a dart across the road on a fixed beat.
-- Everything runs off the shared server clock (workspace:GetServerTimeNow()), so nothing is
-- replicated per shot: this script works out where every dart is and does the hit checks,
-- and StarterPlayerScripts.DartFx draws the same darts smoothly on each player's screen.
--   Run    a dart hitting a rider or their scooter ends the run (DeathManager: SKIP / REVIVE).
--   Home   a dart hitting someone NOT in a run sends them back to the lobby, like KillZones.
-- Tuning: attributes on each DartShooterN model
--   Interval  seconds between shots        Phase  offset, so the four don't fire together
--   Speed     studs/s of the dart          Range  studs from the pipe to the target

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local ScooterSystem = game:GetService("ServerScriptService"):WaitForChild("ScooterSystem")
local RideManager   = require(ScooterSystem:WaitForChild("RideManager"))
local DeathManager  = require(ScooterSystem:WaitForChild("DeathManager"))

local DART_LEN   = 2.4     -- studs, tip to fletching
local DART_THICK = 1.2     -- hit box width (a little fatter than the dart itself)
local HOME_AGAIN = 3
local homeSent   = {}

local folder = script.Parent
local shooters = {}
for _, m in ipairs(folder:GetChildren()) do
	local muzzle = m:IsA("Model") and m:FindFirstChild("Muzzle")
	if muzzle then
		table.insert(shooters, { model = m, muzzle = muzzle, shot = -1, hitThisShot = {} })
	end
end

local params = OverlapParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = { folder.Parent }

local function characterOf(part)
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		if model:FindFirstChildOfClass("Humanoid") then return Players:GetPlayerFromCharacter(model) end
		model = model:FindFirstAncestorOfClass("Model")
	end
end

local function rideOfScooterPart(part)
	for scooter, ride in pairs(RideManager.Rides) do
		if part:IsDescendantOf(scooter) then return ride end
	end
end

local function hit(part, seen)
	local player = characterOf(part)
	if player then
		if seen[player] then return end
		seen[player] = true
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
	local ride = rideOfScooterPart(part)
	if ride and not seen[ride] then
		seen[ride] = true
		DeathManager.Hit(ride)
	end
end

RunService.Heartbeat:Connect(function(dt)
	local now = workspace:GetServerTimeNow()
	for _, s in ipairs(shooters) do
		local m = s.model
		local interval = m:GetAttribute("Interval") or 2.4
		local phase    = m:GetAttribute("Phase") or 0
		local speed    = m:GetAttribute("Speed") or 40
		local range    = m:GetAttribute("Range") or 13
		local t = now - phase
		local shot = math.floor(t / interval)
		local into = t - shot * interval
		if shot ~= s.shot then s.shot = shot; s.hitThisShot = {} end
		if into <= range / speed then
			-- the stretch the dart covered since last frame, so fast darts can't skip past anyone
			local head = math.min(into * speed, range)
			local tail = math.max(0, head - DART_LEN - speed * dt)
			local cf = s.muzzle.CFrame * CFrame.new(0, 0, -(head + tail) / 2)
			local parts = workspace:GetPartBoundsInBox(cf, Vector3.new(DART_THICK, DART_THICK, head - tail + 0.4), params)
			for _, p in ipairs(parts) do hit(p, s.hitThisShot) end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player) homeSent[player] = nil end)
