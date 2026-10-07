-- Entry point. Requires the managers, hooks remotes and player lifecycle.

local Players            = game:GetService("Players")
local RS                 = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local Remotes        = RS:WaitForChild("ScooterSystem"):WaitForChild("Remotes")
local TeamManager    = require(script.Parent:WaitForChild("TeamManager"))
local CapsuleManager = require(script.Parent:WaitForChild("CapsuleManager"))
local RideManager    = require(script.Parent:WaitForChild("RideManager"))
local CollisionGroups = require(script.Parent:WaitForChild("CollisionGroups"))
local DeathManager   = require(script.Parent:WaitForChild("DeathManager"))
require(script.Parent:WaitForChild("RunTimer"))   -- the duo's course stopwatch: runs by itself from here
require(script.Parent:WaitForChild("SkipStage"))  -- the Skip Stage button's server side: runs by itself from here
require(script.Parent:WaitForChild("TrollEffects"))  -- the Troll window's effects: run by themselves from here
require(script.Parent:WaitForChild("DailyRewards"))  -- the Daily Rewards calendar's server side: runs by itself from here
require(script.Parent:WaitForChild("SpinWheel"))     -- the Daily Wheel's server side: runs by itself from here
require(script.Parent:WaitForChild("AntiCheat"))     -- ride movement checks (lenient; never kicks): runs by itself from here
local Config         = require(RS:WaitForChild("ScooterSystem"):WaitForChild("Shared"):WaitForChild("Config"))

TeamManager.Init()
CapsuleManager.Init()

Remotes.ExitCapsule.OnServerEvent:Connect(function(player)
	TeamManager.Exit(player, "button")
end)

Remotes.SelectCheckpoint.OnServerEvent:Connect(function(player, id)
	if typeof(id) ~= "string" then return end
	TeamManager.SelectCheckpoint(player, id)
end)

Remotes.ReadyUp.OnServerEvent:Connect(function(player)
	TeamManager.ReadyUp(player)
end)

Remotes.EnterCapsule.OnServerEvent:Connect(function(player, capsulePart)
	if typeof(capsulePart) == "Instance" and capsulePart:IsA("BasePart") then
		TeamManager.Enter(player, capsulePart)
	end
end)

-- Ride input. The payload is a table so one remote can carry either role's
-- controls; RideManager decides which field the sender is actually allowed to use.
Remotes.DriveInput.OnServerEvent:Connect(function(player, payload)
	if typeof(payload) ~= "table" then return end
	RideManager.ApplyInput(player, payload)
end)

-- The Respawn button (StarterGui.RespawnGui): either rider brings the ride down for BOTH of
-- them, just as an obstacle would (DeathManager.Hit): the SKIP / REVIVE popup, and from
-- there back to the lobby or revived. Not while the ride is already down.
local lastRespawn = {}
Remotes.Respawn.OnServerEvent:Connect(function(player)
	local now = os.clock()
	if now - (lastRespawn[player] or 0) < 2 then return end
	lastRespawn[player] = now
	local ride = RideManager.PlayerRide[player]
	if not ride or ride._ended or ride.Down then return end
	DeathManager.Hit(ride)
end)
Players.PlayerRemoving:Connect(function(player) lastRespawn[player] = nil end)

-- The death popup (DeathManager): a SKIP vote; REVIVE asked for (the server opens the
-- purchase itself), or the rider's own screen saying the purchase window closed. The revive
-- itself only ever comes from Roblox's receipt (DonationHandler's ProcessReceipt).
Remotes.DeathSkip.OnServerEvent:Connect(function(player)
	DeathManager.Skip(player)
end)

Remotes.ReviveRequest.OnServerEvent:Connect(function(player, action)
	if action == "closed" then
		DeathManager.PromptClosed(player)
	elseif action == "five" or action == "infinite" then
		DeathManager.RequestRevive(player, action)   -- 5x REVIVES / INFINITE REVIVES under the popup
	else
		DeathManager.RequestRevive(player)
	end
end)

MarketplaceService.PromptProductPurchaseFinished:Connect(function(who, productId, purchased)
	local player = (typeof(who) == "Instance" and who) or Players:GetPlayerByUserId(tonumber(who) or 0)
	if player then DeathManager.OnPromptFinished(player, productId, purchased) end
end)

-- Joining: Roblox spawns every player itself, as in any other game (Players.CharacterAutoLoads
-- is on - set in the place, see default.project.json / world2.project.json).
-- Respawning after a death is done here rather than by Roblox: a rider who dies in the water
-- must stay down, visibly, for the whole death countdown (DeathManager), and a Roblox respawn
-- would bring them back mid-countdown and end the run. So Roblox's own respawn is pushed out
-- of reach (Players.RespawnTime is enormous) and:
--   * died during a run: respawn as soon as the run is over (AFTER_RUN after
--     dying at the earliest), at the lobby spawn - that is their way home
--   * died anywhere else: respawn RESPAWN_DELAY after dying
--   * character gone altogether (e.g. fell out of the world and was deleted): respawn at once
local AFTER_RUN     = 1
local RESPAWN_DELAY = 3
Players.RespawnTime = 1e6   -- Roblox's own respawn never comes; this script does every respawn

-- Streaming is on, and a player's own device runs their character's physics. A character
-- spawned where that device hasn't loaded the ground yet falls straight through it, drops out
-- of the world and is deleted - and the next spawn lands in the same hole, over and over
-- (slow phones and big maps: many seconds of it; the loading screen can't finish meanwhile).
-- So every lobby spawn first has the ground round the spawn streamed to that player (up to
-- SPAWN_STREAM_WAIT seconds), then creates the character on it.
local SPAWN_STREAM_WAIT = 10
local spawnLocation = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
local function loadAtSpawn(player)
	if spawnLocation and spawnLocation.Parent then
		pcall(player.RequestStreamAroundAsync, player, spawnLocation.Position, SPAWN_STREAM_WAIT)
	end
	if not player.Parent then return end
	player:LoadCharacter()
end

local function respawnWhenDue(player, character)
	local diedAt   = os.clock()
	local wasInRun = RideManager.PlayerRide[player] ~= nil
	-- A rider whose body is gone altogether (removed, not just dead) still waits for the run to
	-- end like any dead rider; if nothing has brought the ride down yet, that is done now, so the
	-- duo still gets the SKIP / REVIVE popup.
	while player.Parent and (player.Character == character
		or (player.Character == nil and RideManager.PlayerRide[player])) do
		local ride = RideManager.PlayerRide[player]
		if ride and player.Character == nil and not ride.Down and not ride._ended then
			DeathManager.HitPlayer(player)
		end
		if not ride
			and os.clock() - diedAt >= (wasInRun and AFTER_RUN or RESPAWN_DELAY) then
			break
		end
		task.wait(0.1)
	end
	-- still that dead character, or no character at all now (it was removed): spawn them.
	-- A new character means someone else (a revive, a respawn) already did.
	if player.Parent and (player.Character == character or player.Character == nil)
		and not RideManager.IsReviving(player) then
		pcall(loadAtSpawn, player)
	end
end

local function watchDeath(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then return end
	humanoid.Died:Once(function() respawnWhenDue(player, character) end)
end

-- Per-player connections are tracked so they are released on leave.
local perPlayer = {}

-- A spawn made sure of, for the safety net below only (Roblox does the join spawn):
-- LoadCharacter can fail, so it is retried until they have one. Only the first try waits for
-- the map round the spawn (at most FIRST_STREAM_WAIT), and only one runs per player.
local FIRST_STREAM_WAIT = 3
local function spawnFirst(player)
	if player:GetAttribute("FirstSpawning") then return end
	player:SetAttribute("FirstSpawning", true)
	-- [Spawn] lines time each step
	local t0, mapWait = os.clock(), 0
	for attempt = 1, 20 do
		if not player.Parent or player.Character then break end
		local loadStart
		local ok, err = pcall(function()
			if attempt == 1 and spawnLocation and spawnLocation.Parent then
				local ts = os.clock()
				pcall(player.RequestStreamAroundAsync, player, spawnLocation.Position, FIRST_STREAM_WAIT)
				mapWait = os.clock() - ts
			end
			loadStart = os.clock()
			if player.Parent and not player.Character then player:LoadCharacter() end
		end)
		if ok and player.Character then
			print(string.format("[Spawn] %s spawned by Main %.1fs after it started (try %d: map wait %.1fs, character load %.1fs)",
				player.Name, os.clock() - t0, attempt, mapWait, os.clock() - (loadStart or t0)))
			break
		end
		if not ok then warn("[Scooter] first spawn for " .. player.Name .. " failed (try " .. attempt .. "): " .. tostring(err)) end
		task.wait(math.min(0.5 * attempt, 3))
	end
	if player.Parent then player:SetAttribute("FirstSpawning", nil) end
end

local function onCharacterAdded(player)
	-- a revive gave them this character to carry on the SAME ride (RideManager.Relaunch)
	if RideManager.IsReviving(player) then return end
	RideManager.EndForPlayer(player, "respawn")
	-- dying or respawning inside a capsule must free the slot
	task.wait(0.2)
	if TeamManager.FindSlot(player) then
		TeamManager.Exit(player, "respawn")
	end
	TeamManager.PushNone(player)
end

local function hookPlayer(player)
	if perPlayer[player] then return end
	local seenAt, firstLogged = os.clock(), player.Character ~= nil
	perPlayer[player] = player.CharacterAdded:Connect(function(char)
		if not firstLogged then
			firstLogged = true
			print(string.format("[Spawn] %s's first character arrived %.1fs after the server saw them join", player.Name, os.clock() - seenAt))
		end
		-- bystanders pass through scooters instead of shoving them
		CollisionGroups.TrackCharacter(char)
		task.spawn(watchDeath, player, char)
		onCharacterAdded(player)
	end)
	if player.Character then
		CollisionGroups.TrackCharacter(player.Character)
		task.spawn(watchDeath, player, player.Character)
	end
	-- (no first spawn here: Roblox spawns joining players itself)
	TeamManager.PushNone(player)
end

-- players already present when this script runs must be hooked too
for _, p in ipairs(Players:GetPlayers()) do hookPlayer(p) end
Players.PlayerAdded:Connect(hookPlayer)

Players.PlayerRemoving:Connect(function(player)
	RideManager.EndForPlayer(player, "player left", true)
	TeamManager.Exit(player, "leaving")
	local c = perPlayer[player]
	if c then c:Disconnect(); perPlayer[player] = nil end
end)

-- Safety net: anyone in the server with NO character at all (not a dead one waiting out a
-- death countdown - that one still exists) for a while is spawned. Nothing should ever leave
-- a player like that; if something does, they never stay stuck. The grace is long enough
-- that a slow Roblox join spawn (the avatar still downloading) is never doubled up.
local NO_CHAR_GRACE = 15
local BROKEN_GRACE  = 10   -- a dead character normally respawns in RESPAWN_DELAY (3s); this is the backstop
task.spawn(function()
	local since = {}
	local broken_ = {}   -- [player] = when their character was first seen not working
	while true do
		task.wait(1)
		for _, player in ipairs(Players:GetPlayers()) do
			local char = player.Character
			if char and not RideManager.IsReviving(player) and not RideManager.PlayerRide[player] then
				-- a character that exists but isn't working (no Humanoid, no root part, or
				-- dead) with no ride holding it down: respawned after BROKEN_GRACE
				local hum = char:FindFirstChildOfClass("Humanoid")
				local broken = not hum or not char:FindFirstChild("HumanoidRootPart") or hum.Health <= 0
				if broken then
					broken_[player] = broken_[player] or os.clock()
					if os.clock() - broken_[player] >= BROKEN_GRACE then
						broken_[player] = nil
						warn("[Scooter] " .. player.Name .. "'s character wasn't working - respawning them")
						task.spawn(function() pcall(loadAtSpawn, player) end)
					end
				else
					broken_[player] = nil
				end
			else
				broken_[player] = nil
			end
			-- (a rider in a run is left to respawnWhenDue: they come back when the run is over)
			if player.Character or RideManager.IsReviving(player) or RideManager.PlayerRide[player] then
				since[player] = nil
			else
				since[player] = since[player] or os.clock()
				if os.clock() - since[player] >= NO_CHAR_GRACE then
					since[player] = nil
					print("[Scooter] " .. player.Name .. " had no character - spawning them"
						.. (player:GetAttribute("FirstSpawning") and " (a first spawn is still running for them)" or ""))
					task.spawn(spawnFirst, player)
				end
			end
		end
		for p in pairs(since) do if not p.Parent then since[p] = nil end end
		for p in pairs(broken_) do if not p.Parent then broken_[p] = nil end end
	end
end)

print("[Scooter] server ready")
