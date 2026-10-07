--=====================================================================
-- Spectate   (ScooterSystem, server)
--
-- The Troll window's spectate camera (StarterGui.TrollGui.TrollUI.Spectate) needs to know
-- which players ride together. RideManager is the only record of that, and it lives here
-- on the server, so this script READS it (it never changes a ride) and publishes it:
--
--   on each scooter model (workspace.RideSystem.Scooters, streamed to every client):
--     SpectateDriver / SpectateMotor   the two riders' UserIds, while the duo can be watched
--   A duo can be watched while its ride is live: not ended, not down (the death popup), not
--   being revived, and BOTH riders are still in the game and still held on the scooter - or
--   while a troll bought onto it is still playing (ScooterSystem.DuoState, one rule for this
--   and the Troll effects). The moment that stops being true the two attributes go, so no
--   client ever watches a finished, dead, half-empty or destroyed ride.
--
-- Streaming is on, so a scooter far down the course would have no road round it on the
-- watcher's machine. Remotes.Spectate(scooter | nil) points the watcher's ReplicationFocus
-- at the scooter they are watching (only a watchable one, and never for a player who is
-- riding: their own ride needs streaming round them), and nil gives it back. It is also
-- given back when they start riding, when the duo stops being watchable, or when they leave.
--=====================================================================

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")

local Remotes     = RS:WaitForChild("ScooterSystem"):WaitForChild("Remotes")
local RideManager = require(script.Parent:WaitForChild("RideManager"))
local DuoState    = require(script.Parent:WaitForChild("DuoState"))

local ATTR_DRIVER, ATTR_MOTOR = "SpectateDriver", "SpectateMotor"
local STEP       = 0.25   -- seconds between looks at the rides (a handful of tables)
local PER_SECOND = 10     -- a watcher's requests past this many in a second are dropped

local remote = Remotes:WaitForChild("Spectate")

local watchable = DuoState.Watchable

local function mark(scooter, driverId, motorId)
	if not scooter.Parent then return end
	-- the Motor first: a client only lists a scooter once BOTH are there
	if scooter:GetAttribute(ATTR_MOTOR) ~= motorId then scooter:SetAttribute(ATTR_MOTOR, motorId) end
	if scooter:GetAttribute(ATTR_DRIVER) ~= driverId then scooter:SetAttribute(ATTR_DRIVER, driverId) end
end

---------------------------------------------------------------- the watchers' streaming
local focus  = {}   -- [player] = the scooter they are watching
local asks   = {}   -- [player] = { n = requests this second, at = when that second began }

-- Every request is taken as it comes (so a watcher's streaming is always on the duo their
-- camera shows, however fast they switch), up to PER_SECOND of them a second.
local function allowed(player)
	local now = os.clock()
	local a = asks[player]
	if not a or now - a.at >= 1 then
		a = { n = 0, at = now }
		asks[player] = a
	end
	a.n += 1
	return a.n <= PER_SECOND
end

-- While the watcher's streaming follows the duo, the lobby round their own character is
-- asked to stay loaded (every KEEP_HOME seconds, and once more as they stop watching), so
-- closing the Troll window doesn't show it popping back in.
local KEEP_HOME = 5
local keptAt = {}   -- [player] = os.clock() of the last ask
local function keepHome(player)
	keptAt[player] = os.clock()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local at = root.Position
	task.spawn(function() pcall(player.RequestStreamAroundAsync, player, at, 3) end)
end

local function release(player)
	if focus[player] == nil then return end
	focus[player] = nil
	keptAt[player] = nil
	if player.Parent then
		player.ReplicationFocus = nil   -- back to their own character
		keepHome(player)
	end
end

remote.OnServerEvent:Connect(function(player, scooter)
	-- letting go is never dropped, however soon it comes
	if scooter == nil then release(player) return end
	if not allowed(player) then return end
	if typeof(scooter) ~= "Instance" then return end
	local ride = RideManager.Rides[scooter]
	if RideManager.PlayerRide[player] or not watchable(ride) then return end
	focus[player] = scooter
	player.ReplicationFocus = scooter.PrimaryPart
	if not keptAt[player] then keepHome(player) end
end)

Players.PlayerRemoving:Connect(function(player)
	focus[player], asks[player], keptAt[player] = nil, nil, nil
end)

---------------------------------------------------------------- the loop
task.spawn(function()
	while true do
		for scooter, ride in pairs(RideManager.Rides) do
			local d, p = ride.Driver, ride.Passenger
			if watchable(ride) and d and p then
				mark(scooter, d.UserId, p.UserId)
			else
				mark(scooter, nil, nil)
			end
		end
		for player, scooter in pairs(focus) do
			local ride = RideManager.Rides[scooter]
			if not player.Parent or RideManager.PlayerRide[player] or not watchable(ride) then
				release(player)
			else
				if player.ReplicationFocus ~= scooter.PrimaryPart then
					player.ReplicationFocus = scooter.PrimaryPart
				end
				if os.clock() - (keptAt[player] or 0) >= KEEP_HOME then keepHome(player) end
			end
		end
		task.wait(STEP)
	end
end)
