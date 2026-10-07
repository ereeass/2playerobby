-- Single source of truth for every capsule station.
-- Remotes only ever ask this module to act; nothing mutates state directly.
--
-- Roles are Driver (steers) and Passenger (works the electric motor).

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")

local Root        = RS:WaitForChild("ScooterSystem")
local Remotes     = Root:WaitForChild("Remotes")
local Shared      = Root:WaitForChild("Shared")
local Config      = require(Shared:WaitForChild("Config"))
local Checkpoints = require(Shared:WaitForChild("Checkpoints"))

local StartManager    = require(script.Parent:WaitForChild("StartManager"))
local RideManager     = require(script.Parent:WaitForChild("RideManager"))
local CapsuleGeometry = require(script.Parent:WaitForChild("CapsuleGeometry"))
local CapsuleEntry    = require(script.Parent:WaitForChild("CapsuleEntry"))
-- each player's saved checkpoints: the pair may start up to the lower of the two
local CheckpointProgress = require(script.Parent:WaitForChild("CheckpointProgress"))

-- Analytics only (ScooterSystem.Funnels): funnel(...) reports what already happened, in its
-- own protected thread, so it can never change or stop anything here.
local okFunnels, Funnels = pcall(require, script.Parent:FindFirstChild("Funnels"))
local function funnel(name, ...)
	if okFunnels and type(Funnels) == "table" and type(Funnels[name]) == "function" then
		task.spawn(pcall, Funnels[name], ...)
	end
end

local TeamManager = {}
TeamManager.Stations   = {}   -- [id]     = station
TeamManager.PartMap    = {}   -- [part]   = { station = st, role = "Driver" }
TeamManager.PlayerSlot = {}   -- [player] = { station = st, role = "Driver" }

local function log(...)
	if Config.DebugLogging then print("[Scooter]", ...) end
end

-- PHASES: Empty -> Waiting -> Countdown -> Launched. With Config.CheckpointPicker
-- on, the Driver picks the start first: Waiting -> Selecting -> Ready -> Countdown.
local function otherRole(role)
	return role == "Driver" and "Passenger" or "Driver"
end

function TeamManager.Init()
	TeamManager.Stations, TeamManager.PartMap, TeamManager.PlayerSlot = {}, {}, {}
	CapsuleEntry.SetSlotLookup(function(plr) return TeamManager.PlayerSlot[plr] end)

	local sys    = workspace:WaitForChild("RideSystem")
	local folder = sys:WaitForChild("CapsuleStations")
	local measured, missing = 0, 0

	for _, m in ipairs(folder:GetChildren()) do
		if m:IsA("Model") then
			local idv = m:FindFirstChild("StationId")
			local dp  = m:FindFirstChild("DriverCapsule")
			local pp  = m:FindFirstChild("MotorCapsule")
			if not (idv and dp and pp) then
				warn("[Scooter] station " .. m.Name .. " is malformed - skipped")
			else
				local st = {
					Id = idv.Value, Model = m,
					Parts     = { Driver = dp, Passenger = pp },
					FloorY    = {},
					Occupants = { Driver = nil, Passenger = nil },
					Arriving  = {},   -- [player] = entry ticket: in a slot, still walking into the booth
					Phase = "Empty", CheckpointId = nil, Countdown = nil, Token = 0,
				}
				for role, part in pairs(st.Parts) do
					local ref = part:FindFirstChild("CapsuleModel")
					local y = CapsuleGeometry.FindFloorY(part, ref and ref.Value)
					st.FloorY[role] = y
					if y then measured += 1 else missing += 1 end
					TeamManager.PartMap[part] = { station = st, role = role }
				end
				TeamManager.Stations[st.Id] = st
			end
		end
	end

	-- a booth's menu follows its occupants' progress (their saves load after they join)
	CheckpointProgress.Changed:Connect(function(player)
		local st = TeamManager.FindSlot(player)
		if st and st.Phase ~= "Countdown" and st.Phase ~= "Launched" then TeamManager.PushState(st) end
	end)

	local n = 0
	for _ in pairs(TeamManager.Stations) do n += 1 end
	log(("initialised %d stations; floors measured %d, unmeasured %d"):format(n, measured, missing))
	if missing > 0 then
		warn("[Scooter] " .. missing .. " capsule(s) had no measurable floor - players will fall back to trigger height")
	end
end

function TeamManager.FindSlot(player)
	local s = TeamManager.PlayerSlot[player]
	if s then return s.station, s.role end
	return nil, nil
end

---------------------------------------------------------------- state push
-- A booth's bottom lights go back to normal as soon as its role is free again.
local function syncBooths(st)
	for role, part in pairs(st.Parts) do
		if not st.Occupants[role] then CapsuleEntry.SetOccupied(part, false) end
	end
end

local function buildState(st, role)
	local partner = st.Occupants[otherRole(role)]
	return {
		Phase        = st.Phase,
		StationId    = st.Id,
		Role         = role,
		PartnerName  = partner and partner.DisplayName or nil,
		CanPick      = (role == Config.CheckpointPickerRole),
		-- this pair's list: past the lower of their two progresses shows LOCKED
		Menu         = CheckpointProgress.MenuFor(st.Occupants.Driver, st.Occupants.Passenger),
		CheckpointId = st.CheckpointId,
		Countdown    = st.Countdown,
	}
end

-- A player still walking in to join a partner hears nothing yet: their booth UI
-- (the checkpoint window) comes up once they are inside. Walking in alone they
-- get "Waiting for partner.." straight away, as always.
function TeamManager.PushState(st)
	syncBooths(st)
	for role, plr in pairs(st.Occupants) do
		if plr and plr.Parent and not (st.Arriving[plr] and st.Occupants[otherRole(role)]) then
			Remotes.StateChanged:FireClient(plr, buildState(st, role))
		end
	end
end

function TeamManager.PushNone(player)
	if player and player.Parent then
		Remotes.StateChanged:FireClient(player, { Phase = "None" })
	end
end

---------------------------------------------------------------- phase logic
local function cancelCountdown(st)
	st.Token += 1          -- invalidates any running countdown coroutine
	st.Countdown = nil
end

-- The Driver gets Config.PickTimeoutSeconds from the checkpoint window opening to press
-- START. If this same pair is still choosing then, both go back to the lobby spawn
-- through Exit, and each is told why (the game's notice, Remotes.Notice). A new pair,
-- or the window closing (someone left, or START), drops the ticket and the timer does
-- nothing.
local PICK_TIMEOUT_NOTICE = "You were in the booth too long without starting, so you've been sent back!"
local function startPickTimer(st)
	local d, p = st.Occupants.Driver, st.Occupants.Passenger
	local ticket = {}
	st.PickTicket = ticket
	task.delay(Config.PickTimeoutSeconds or 60, function()
		if st.PickTicket ~= ticket then return end
		st.PickTicket = nil
		if st.Phase ~= "Selecting" and st.Phase ~= "Ready" then return end
		if st.Occupants.Driver ~= d or st.Occupants.Passenger ~= p then return end
		log("station", st.Id, "checkpoint not picked in time - both back to spawn")
		TeamManager.Exit(d, "pick timeout")
		TeamManager.Exit(p, "pick timeout")
		-- after Exit's state push, so the lobby HUD is back when it shows
		for _, plr in ipairs({ d, p }) do
			if plr and plr.Parent then Remotes.Notice:FireClient(plr, PICK_TIMEOUT_NOTICE) end
		end
	end)
end

-- still in the game with a living character: can be moved onto a scooter
local function inBooth(plr)
	local ch  = plr and plr.Parent and plr.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

-- 3, 2, 1 - each step pushed to both players, so both panels count together - then
-- GO! and the ride. Anyone leaving on the way (EXIT, the game, a respawn) goes
-- through Exit, whose Recompute bumps st.Token, and the count stops where it is.
local function startCountdown(st)
	st.PickTicket = nil
	st.Phase = "Countdown"
	st.Token += 1
	local token = st.Token
	log("station", st.Id, "countdown started")

	task.spawn(function()
		for i = Config.CountdownSeconds, 1, -1 do
			if st.Token ~= token then return end
			st.Countdown = i
			TeamManager.PushState(st)
			task.wait(1)
		end
		if st.Token ~= token then return end
		if not (st.Occupants.Driver and st.Occupants.Passenger) then return end

		st.Countdown, st.Phase = 0, "Launched"
		TeamManager.PushState(st)

		local d, p = st.Occupants.Driver, st.Occupants.Passenger
		-- the same two, both still here and alive, right up to the teleport
		local function bothAboard()
			return st.Occupants.Driver == d and st.Occupants.Passenger == p and inBooth(d) and inBooth(p)
		end
		local spawnPart = StartManager.ResolveSpawnPart(st.CheckpointId, st.Id)   -- this station's bay
		local ride, err = RideManager.Begin(st.Id, d, p, st.CheckpointId, spawnPart, bothAboard)
		if not ride and not bothAboard() then
			-- Someone left, reset or died between GO! and the teleport: no ride. Anyone
			-- who cannot ride is let go; whoever is left stays in their booth and
			-- waits for a new partner, exactly as if they had been alone all along.
			log("station", st.Id, "launch called off:", tostring(err))
			funnel("LaunchCancelled", "missing", d, p)   -- analytics only
			for _, plr in pairs(st.Occupants) do
				if plr and not inBooth(plr) then TeamManager.Exit(plr, "launch called off") end
			end
			st.Phase, st.Countdown = "Waiting", nil   -- out of Launched, so Recompute decides afresh
			TeamManager.Recompute(st)
			return
		end
		if not ride then
			-- Never leave a team sealed in its capsules (e.g. the start marker was
			-- deleted): free the station and send both players back to the lobby.
			warn("[Scooter] ride start failed at station " .. tostring(st.Id) .. ": " .. tostring(err))
			funnel("LaunchCancelled", "failed", d, p)   -- analytics only
			st.Occupants.Driver, st.Occupants.Passenger = nil, nil
			TeamManager.PlayerSlot[d] = nil
			TeamManager.PlayerSlot[p] = nil
			st.CheckpointId, st.Countdown = nil, nil
			st.Phase = "Empty"
			syncBooths(st)
			for _, plr in ipairs({ d, p }) do
				if plr.Parent then
					StartManager.ReturnToLobby(plr)
					TeamManager.PushNone(plr)
				end
			end
			return
		end
		log("station", st.Id, "launched ->", tostring(st.CheckpointId))

		task.wait(0.8)
		st.Occupants.Driver, st.Occupants.Passenger = nil, nil
		TeamManager.PlayerSlot[d] = nil
		TeamManager.PlayerSlot[p] = nil
		st.CheckpointId, st.Countdown = nil, nil
		st.Phase = "Empty"
		TeamManager.PushState(st)   -- riders keep the Riding state RideManager gave them
	end)
end

function TeamManager.Recompute(st)
	local count = (st.Occupants.Driver and 1 or 0) + (st.Occupants.Passenger and 1 or 0)
	if count == 0 then
		cancelCountdown(st); st.Phase, st.CheckpointId, st.PickTicket = "Empty", nil, nil
	elseif count == 1 or next(st.Arriving) ~= nil then
		-- alone, or the partner is still walking in: the pair starts once both are inside
		cancelCountdown(st); st.Phase, st.CheckpointId, st.PickTicket = "Waiting", nil, nil
	elseif st.Phase ~= "Countdown" and st.Phase ~= "Launched" then
		funnel("PartnerJoined", st.Occupants.Driver, st.Occupants.Passenger)   -- analytics only
		if Config.CheckpointPicker then
			if not st.PickTicket then startPickTimer(st) end   -- the window just opened
			st.Phase = st.CheckpointId and "Ready" or "Selecting"
		else
			-- nothing to pick: a full station counts straight down, from the first open checkpoint
			local cp = Checkpoints.GetDefault()
			st.CheckpointId = cp and cp.Id or nil
			startCountdown(st)   -- pushes its first step itself
			return
		end
	end
	TeamManager.PushState(st)
end

---------------------------------------------------------------- actions
function TeamManager.Enter(player, capsulePart)
	local entry = TeamManager.PartMap[capsulePart]
	if not entry then return end
	local st, role = entry.station, entry.role

	if TeamManager.PlayerSlot[player] then return end      -- already in a capsule
	if st.Occupants[role] then return end                  -- taken
	if st.Phase == "Countdown" or st.Phase == "Launched" then return end

	local ch = player.Character
	if not ch or not ch:FindFirstChild("HumanoidRootPart") then return end
	-- only through the glass door: never from behind or beside the booth
	if not CapsuleEntry.CanEnterFrom(capsulePart, ch.HumanoidRootPart.Position) then
		log(player.Name, "is not at the front of station", st.Id, role, "- entry ignored")
		return
	end

	st.Occupants[role] = player
	TeamManager.PlayerSlot[player] = { station = st, role = role }
	local ticket = {}   -- this entry's own: a leave-and-re-enter makes a new one
	st.Arriving[player] = ticket
	funnel("BoothEntered", player)   -- analytics only

	-- Inside and facing out: now the pair can go on to the checkpoint window. Runs
	-- once, and only for this entry (never a previous one's late fallback).
	local function arrived()
		if st.Arriving[player] ~= ticket then return end
		st.Arriving[player] = nil
		log(player.Name, "is inside station", st.Id)
		TeamManager.Recompute(st)
	end
	-- a normal walk-in takes about a second; a slow or blocked one never holds the
	-- pair up for more than 3 s
	task.delay(3, arrived)

	-- Stand on the measured floor. No anchoring: the character keeps full physics
	-- and normal movement while it waits; the capsule walls keep it inside.
	-- The glass door lifts and the character walks in; if the way in is blocked
	-- they are placed on the floor exactly as before.
	local hrp = ch:FindFirstChild("HumanoidRootPart")
	hrp.Anchored = false
	CapsuleEntry.WalkIn(player, capsulePart, CapsuleGeometry.StandCFrame(ch, capsulePart, st.FloorY[role]), function()
		local s = TeamManager.PlayerSlot[player]
		return s ~= nil and s.station == st and s.role == role and st.Phase ~= "Launched"
	end, arrived)

	log(player.Name, "entered station", st.Id, "as", role)
	TeamManager.Recompute(st)
end

-- Leaving never takes the partner along: whoever is left in the station goes back
-- to waiting for a new partner, and a countdown under way is called off.
function TeamManager.Exit(player, reason)
	local st, role = TeamManager.FindSlot(player)
	-- EXIT is gone from GO! on (the ride is being put together); a late press is ignored
	if st and reason == "button" and st.Phase == "Launched" then return end
	TeamManager.PlayerSlot[player] = nil
	funnel("BoothLeft", player)   -- analytics only
	if not st then TeamManager.PushNone(player); return end

	st.Occupants[role] = nil
	st.Arriving[player] = nil
	StartManager.ReleaseCharacter(player)
	if reason ~= "leaving" then StartManager.ReturnToLobby(player) end
	TeamManager.PushNone(player)
	log(player.Name, "exited station", st.Id, "(" .. tostring(reason) .. ")")

	-- between GO! and the teleport the launch owns the station: it sees who is
	-- missing and sorts the station out itself (startCountdown)
	if st.Phase == "Launched" then return end
	if st.Phase == "Countdown" then
		log("countdown cancelled at station", st.Id, "-", player.Name, "left")
		funnel("LaunchCancelled", reason, player, st.Occupants.Driver or st.Occupants.Passenger)   -- analytics only
	end
	TeamManager.Recompute(st)   -- cancels any countdown; a partner left behind waits again
end

function TeamManager.SelectCheckpoint(player, id)
	local st, role = TeamManager.FindSlot(player)
	if not st then return end
	if role ~= Config.CheckpointPickerRole then return end
	if st.Phase ~= "Selecting" and st.Phase ~= "Ready" then return end
	-- only a checkpoint BOTH of them have unlocked (and that is released)
	if not CheckpointProgress.CanStart(st.Occupants.Driver, st.Occupants.Passenger, id) then return end

	st.CheckpointId = id
	st.Phase = "Ready"
	log("station", st.Id, "selected", id)
	TeamManager.PushState(st)
end

-- The Driver's START in the checkpoint window (Config.CheckpointPicker only).
function TeamManager.ReadyUp(player)
	local st, role = TeamManager.FindSlot(player)
	if not st then return end
	if role ~= Config.CheckpointPickerRole then return end
	if st.Phase ~= "Ready" then return end
	if not (st.Occupants.Driver and st.Occupants.Passenger) then return end
	-- checked again at START: it must still be open to this pair
	if not CheckpointProgress.CanStart(st.Occupants.Driver, st.Occupants.Passenger, st.CheckpointId) then
		st.CheckpointId, st.Phase = nil, "Selecting"
		TeamManager.PushState(st)
		return
	end
	funnel("PressedStart", st.Occupants.Driver, st.Occupants.Passenger)   -- analytics only
	startCountdown(st)
end

return TeamManager
