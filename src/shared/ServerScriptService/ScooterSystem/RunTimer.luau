--=====================================================================
-- RunTimer   (ScooterSystem, server)
--
-- The course stopwatch, for a DUO: one run per ride (RideManager), shared by both of
-- its riders. The server alone decides everything that matters - when a run starts,
-- who is in it, when it finishes and its time. Clients only draw it
-- (StarterGui.RunTimerGui) from what they are told; nothing a client sends can start,
-- stop or time a run.
--
--   Which rides  a ride that starts at the first checkpoint (Checkpoint 1's parking
--                lot). It is "Waiting" (0:00.00, not counting) until it drives out.
--   Start        its chassis crossing the start gate - any part tagged START_TAG
--                (Workspace["Checkpoint 1 Parking Lot"].StartGate.Gate, on the painted
--                StartLine) from its back to its front, with BOTH riders still on board.
--                Walking past it does nothing: only a ride's scooter counts.
--   Finish       the chassis crossing a finish gate - any part tagged FINISH_TAG
--                (Workspace["Finish Area"].FinishGate.Gate, on the finish line) - the
--                same way. Once: the run is marked Completed before anything is told.
--   Timing       server clock (os.clock), the crossing moment worked out WITHIN the
--                frame from where the chassis was before and after it, so a time is
--                good to about a millisecond of the scooter's replicated position.
--   Ending       the run lives exactly as long as its ride, by the game's own rules: a
--                rider leaving, resetting, a run ending in the water - whatever ends the
--                ride (RideManager.End) - ends an unfinished run as "Abandoned". Nothing
--                new is decided here.
--   Checks       for a leaderboard to trust it later: the checkpoints the ride reached
--                on the way (CheckpointProgress.Reached) are kept as splits, and a run
--                that skipped one is kept but marked Valid = false with why (Flags), and a
--                warning says so in the server log. Speed is only LOGGED (never flags a run):
--                a legit duo can be flung by physics or by someone else, and the owners'
--                rule is that a legit run is never lost to a guess. Clear cheating is
--                handled by AntiCheat (RunTimer.Invalidate) on hard evidence only.
--   Route        the scooter's position is kept at the start line, each checkpoint and the
--                finish. Between any two of them the time must allow the STRAIGHT-LINE
--                sideways distance at no more than ROUTE_SPEED (about 2x the scooter's top
--                speed): the straight line is the shortest way there, so no legit duo can
--                average that, while flying or teleporting through the course can't avoid
--                it. Not a minimum time: it only measures how far apart the positions were.
--                Such a run is kept off the leaderboard (Valid = false) and reported to
--                the team (AntiCheatWebhook); the riders' game is not touched.
--   Skipping     a ride that skips part of the course (SkipStage) loses its run for good:
--                RunTimer.Invalidate flags it, ends it as "Abandoned" and leaves the ride
--                untimed (like a ride that started further along), so it can never start
--                again, finish or reach a leaderboard. Records already saved are untouched.
--
-- For a leaderboard (nothing is stored permanently here):
--   RunTimer.RunCompleted:Connect(function(record) end)   every finished run
--   RunTimer.RunStarted / RunTimer.RunAbandoned           the same record, as it happens
--   RunTimer.GetRun(runId), RunTimer.GetRunForPlayer(player), RunTimer.GetCompletedRuns()
-- or, from any server Script without requiring this: ScooterSystem.RunTimer.RunCompleted
-- (a BindableEvent). A record is plain data (DataStore-safe):
--   { RunId, Status = "Waiting"|"Running"|"Completed"|"Abandoned",
--     Player1 = { UserId, Name, DisplayName, Role = "Driver" },      (at the finish, once Completed)
--     Player2 = { UserId, Name, DisplayName, Role = "Passenger" },   (the motor rider)
--     StartCheckpointId, StationId,
--     StartedAt, CompletedAt (unix seconds, ms precision), Timestamp (= CompletedAt),
--     CompletionTime (seconds, 3 decimals), Splits = { { Order, CheckpointId, Time } },
--     Valid, Flags, EndReason }
-- Times are written with Shared.RunTime.Format.
--=====================================================================

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local HttpService       = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local RS                = game:GetService("ReplicatedStorage")

local Root        = RS:WaitForChild("ScooterSystem")
local Remotes     = Root:WaitForChild("Remotes")
local Shared      = Root:WaitForChild("Shared")
local Config      = require(Shared:WaitForChild("Config"))
local Checkpoints = require(Shared:WaitForChild("Checkpoints"))

local RideManager        = require(script.Parent:WaitForChild("RideManager"))
local AntiCheatWebhook   = require(script.Parent:WaitForChild("AntiCheatWebhook"))
local CheckpointProgress = require(script.Parent:WaitForChild("CheckpointProgress"))

local START_TAG      = "RunStartLine"
local FINISH_TAG     = "FinishLine"
local MAX_SPEED      = 300   -- studs/s: faster than any ride (or thrown scooter) goes (top speed ~21); faster is flagged
local SPEED_WINDOW   = 0.5   -- seconds the speed is measured over (see the note at "every frame")
local STEP_SLACK     = 5     -- studs a crossing move may exceed MAX_SPEED x its time by
local KEEP_COMPLETED = 200   -- finished runs kept for GetCompletedRuns (this server)
local ROUTE_SPEED    = 45    -- studs/s: the fastest straight-line average between two route points (top speed ~21)
local ROUTE_MIN      = 80    -- studs: shorter legs aren't judged (their timing is too fine)
-- Owners' rule (2026-09-30): reaching one checkpoint and then the next in under this many
-- seconds is impossible by driving (measured: every checkpoint-to-checkpoint road takes ~15s+
-- flat out at top speed, in both worlds), so such a run is kept off the leaderboard.
local MIN_CHECKPOINT_GAP = 10

local remote = Remotes:WaitForChild("RunTimer")   -- server -> client only

local RunTimer = {}

local function signal(name)
	local e = Instance.new("BindableEvent")
	e.Name = name
	e.Parent = script
	return e
end
local startedEvent   = signal("RunStarted")
local completedEvent = signal("RunCompleted")
local abandonedEvent = signal("RunAbandoned")
RunTimer.RunStarted   = startedEvent.Event
RunTimer.RunCompleted = completedEvent.Event
RunTimer.RunAbandoned = abandonedEvent.Event

local byRide    = {}   -- [ride] = run, or false (a ride that isn't timed)
local byId      = {}   -- [runId] = run
local completed = {}   -- finished runs' records, oldest first

local function log(...) if Config.DebugLogging then print("[RunTimer]", ...) end end

local function firstCheckpointId()
	local cp = Checkpoints.ByOrder(1)
	return cp and cp.Id
end

local function unixNow()
	return DateTime.now().UnixTimestampMillis / 1000
end

---------------------------------------------------------------- records
local function copy(t)
	if type(t) ~= "table" then return t end
	local c = {}
	for k, v in pairs(t) do c[k] = copy(v) end
	return c
end

-- the run as plain data (no Instances): what every event and getter hands out
function RunTimer.Record(run)
	return {
		RunId = run.RunId, Status = run.Status,
		Player1 = copy(run.Player1), Player2 = copy(run.Player2),
		StartCheckpointId = run.StartCheckpointId, StationId = run.StationId,
		StartedAt = run.StartedAt, CompletedAt = run.CompletedAt, Timestamp = run.CompletedAt,
		CompletionTime = run.CompletionTime,
		Splits = copy(run.Splits), Valid = run.Valid, Flags = copy(run.Flags),
		EndReason = run.EndReason,
	}
end

local function who(plr, role)
	if typeof(plr) ~= "Instance" then return nil end
	return { UserId = plr.UserId, Name = plr.Name, DisplayName = plr.DisplayName, Role = role }
end

-- both riders' stopwatches, for those still in the game
local function tell(run, message)
	for _, plr in ipairs({ run.Ride.Driver or false, run.Ride.Passenger or false }) do
		if plr and plr.Parent == Players then remote:FireClient(plr, message) end
	end
end

local function flag(run, why)
	for _, f in ipairs(run.Flags) do if f == why then return end end
	table.insert(run.Flags, why)
end

-- both riders on the scooter and alive (as CheckpointProgress counts it)
local function bothAboard(ride)
	for _, role in ipairs({ "Driver", "Passenger" }) do
		local h = ride.Riders and ride.Riders[role]
		local plr = h and h.Player
		if not h or h.Released or not plr or not plr.Parent then return false end
		if h.Humanoid and h.Humanoid.Health <= 0 then return false end
	end
	return true
end

---------------------------------------------------------------- lifecycle
local function track(ride)
	if ride.CheckpointId ~= firstCheckpointId() or not (ride.Driver and ride.Passenger) then
		byRide[ride] = false   -- started further along: not a full run
		return
	end
	local run = {
		RunId = HttpService:GenerateGUID(false), Status = "Waiting", Ride = ride,
		Player1 = who(ride.Driver, "Driver"), Player2 = who(ride.Passenger, "Passenger"),
		StartCheckpointId = ride.CheckpointId, StationId = ride.StationId,
		Splits = {}, Flags = {},
	}
	byRide[ride], byId[run.RunId] = run, run
	tell(run, { State = "Ready", RunId = run.RunId })
end

-- where the scooter is now, for the route check
local function routePoint(run, at, label)
	local chassis = run.Ride and run.Ride.Scooter and run.Ride.Scooter.PrimaryPart
	if chassis then table.insert(run.Route, { Pos = chassis.Position, At = at, Label = label }) end
end

-- The route's legs that no scooter could cover that fast (see the header): a list of reasons
function RunTimer.CheckRoute(route)
	local bad = {}
	for i = 2, #route do
		local a, b = route[i - 1], route[i]
		local gap = b.Pos - a.Pos
		local dist = Vector3.new(gap.X, 0, gap.Z).Magnitude
		local secs = math.max(b.At - a.At, 1 / 60)
		if dist >= ROUTE_MIN and dist / secs > ROUTE_SPEED then
			table.insert(bad, ("impossibly fast from %s to %s (%d studs in %.1fs = %d studs/s; top speed ~21)")
				:format(a.Label, b.Label, dist, secs, dist / secs))
		elseif a.Label:sub(1, 10) == "checkpoint" and b.Label:sub(1, 10) == "checkpoint"
			and b.At - a.At < MIN_CHECKPOINT_GAP then
			table.insert(bad, ("%s to %s in %.1fs (under %ds between checkpoints is impossible by driving)")
				:format(a.Label, b.Label, b.At - a.At, MIN_CHECKPOINT_GAP))
		end
	end
	return bad
end

local function start(run, at)
	run.Status = "Running"
	run.StartClock = at
	run.Route = {}
	pcall(routePoint, run, at, "the start")
	run.StartedAt = unixNow() - (os.clock() - at)
	-- the clients count from the server's clock (GetServerTimeNow), so both riders agree
	local serverStart = workspace:GetServerTimeNow() - (os.clock() - at)
	tell(run, { State = "Running", RunId = run.RunId, StartedAt = serverStart })
	log(run.Player1.Name, "+", run.Player2.Name, "started run", run.RunId)
	startedEvent:Fire(RunTimer.Record(run))
end

local function complete(run, at)
	if run.Status ~= "Running" then return end
	run.Status = "Completed"   -- first: nothing below can finish it twice
	-- The roles AS THEY ARE at the finish, read from the ride (the same record the server
	-- trusts for who may steer and who drives the motor) in the frame the gate is crossed,
	-- before anything is told: no cutscene, portal or cleanup has started yet. Player1 is
	-- always the Driver and Player2 the Passenger (the motor), whoever held them earlier.
	local ride = run.Ride
	run.Player1 = who(ride.Driver, "Driver") or run.Player1
	run.Player2 = who(ride.Passenger, "Passenger") or run.Player2
	if not (ride.Driver and ride.Passenger) or ride.Driver == ride.Passenger then
		flag(run, "riders missing at the finish")
	end
	run.CompletionTime = math.floor((at - run.StartClock) * 1000 + 0.5) / 1000
	run.CompletedAt = unixNow() - (os.clock() - at)
	run.EndReason = "finished"
	-- every released checkpoint between the start and the finish, reached in order
	local want = 2
	for _, split in ipairs(run.Splits) do
		if split.Order == want then want += 1 end
	end
	for _, cp in ipairs(Checkpoints.List) do
		if cp.Unlocked and cp.Order >= want then flag(run, "missed checkpoint " .. cp.Order) end
	end
	-- the route: no leg covered faster than any scooter can (see the header)
	-- (protected: nothing here can ever stop a finish from being recorded)
	pcall(function()
		routePoint(run, at, "the finish")
		local bad = RunTimer.CheckRoute(run.Route or {})
		for _, why in ipairs(bad) do flag(run, why) end
		if bad[1] and ride.Driver then
			local partner = ride.Passenger
			AntiCheatWebhook.Report(ride.Driver, {
				What = "Impossible run time", Detail = bad[1] .. ("\nRun time %.3fs"):format(run.CompletionTime),
				Certainty = 99, Action = "Time kept off the leaderboard (their game was not touched)",
				Partner = partner and partner ~= ride.Driver and ("%s (@%s) - UserId %d"):format(partner.DisplayName, partner.Name, partner.UserId) or nil,
			})
		end
	end)
	run.Valid = #run.Flags == 0
	local record = RunTimer.Record(run)
	table.insert(completed, record)
	if #completed > KEEP_COMPLETED then table.remove(completed, 1) end
	tell(run, { State = "Finished", RunId = run.RunId, Time = run.CompletionTime })
	log(run.Player1.Name, "+", run.Player2.Name, "finished in", run.CompletionTime, run.Valid and "" or ("(" .. table.concat(run.Flags, ", ") .. ")"))
	if not run.Valid then
		-- always shown (live: Developer Console, F9 -> Server), so a run left off the board is never a mystery
		warn(("[RunTimer] %s + %s finished in %.3fs but the run is not valid for the leaderboard: %s")
			:format(run.Player1.Name, run.Player2.Name, run.CompletionTime, table.concat(run.Flags, ", ")))
	end
	completedEvent:Fire(record)
end

-- the ride is over (RideManager ended it, for whatever reason)
local function drop(ride, run)
	byRide[ride] = nil
	if not run then return end
	byId[run.RunId] = nil
	if run.Status == "Waiting" or run.Status == "Running" then
		local wasRunning = run.Status == "Running"
		run.Status, run.EndReason = "Abandoned", "ride ended"
		if wasRunning then abandonedEvent:Fire(RunTimer.Record(run)) end
	end
	tell(run, { State = "None" })
end

-- where a gate was crossed between a and b (0..1 along the move), or nil
local function crossing(gate, a, b)
	local cf, size = gate.CFrame, gate.Size
	local pa, pb = cf:PointToObjectSpace(a), cf:PointToObjectSpace(b)
	if pa.Z > 0 and pb.Z <= 0 then   -- +Z is a gate's back: the side riders come from
		local k = pa.Z / (pa.Z - pb.Z)
		local at = pa:Lerp(pb, k)
		if math.abs(at.X) <= size.X / 2 and math.abs(at.Y) <= size.Y / 2 then return k end
	end
	return nil
end

local function crossedAny(tag, a, b)
	for _, gate in ipairs(CollectionService:GetTagged(tag)) do
		if gate:IsA("BasePart") then
			local k = crossing(gate, a, b)
			if k then return k end
		end
	end
	return nil
end

---------------------------------------------------------------- every frame
-- One Heartbeat for all rides; it does nothing at all while nobody is riding.
--
-- The Driver's machine simulates the scooter, so the server only sees its position when
-- an update arrives over the network - in bunches, not every frame. After a hitch it
-- stands still for a few frames and then jumps the whole way at once. So nothing here is
-- judged frame by frame:
--   a MOVE    is from the last position that was actually different (Moved*), over the
--             whole time since then - a crossing is timed within that span;
--   SPEED     is the distance covered over at least SPEED_WINDOW seconds, so a hitch
--             averages out to the real speed while a teleport or speed hack still shows;
--   a JUMP    too far for the time it covered (faster than MAX_SPEED) never counts as
--             crossing a gate.
-- (Judging each frame alone flagged real runs as "moved impossibly fast" on live servers,
-- where Studio's lag-free play never did.)
local function speedCheck(run, pos, now)
	local w = run.Window
	if not w then
		w = {}
		run.Window = w
	end
	table.insert(w, { pos, now })
	-- keep one sample at least SPEED_WINDOW old as the far end
	while #w > 2 and now - w[2][2] >= SPEED_WINDOW do table.remove(w, 1) end
	local first = w[1]
	local span = now - first[2]
	if span >= SPEED_WINDOW then
		local speed = (pos - first[1]).Magnitude / span
		if speed > MAX_SPEED and not run.SpeedNoted then
			run.SpeedNoted = true   -- observation only (see the header): the run stays valid
			log("run", run.RunId, "moved very fast", math.floor(speed), "studs/s (noted, not flagged)")
		end
	end
end

RunService.Heartbeat:Connect(function()
	if next(RideManager.Rides) == nil and next(byRide) == nil then return end
	local now = os.clock()
	for _, ride in pairs(RideManager.Rides) do
		if byRide[ride] == nil and not ride._ended then track(ride) end
	end
	for ride, run in pairs(byRide) do
		if ride._ended or RideManager.Rides[ride.Scooter] ~= ride then
			drop(ride, run or nil)
		elseif run and (run.Status == "Waiting" or run.Status == "Running") then
			local chassis = ride.Scooter and ride.Scooter.PrimaryPart
			if chassis then
				local pos = chassis.Position
				local prev, prevT = run.MovedPos, run.MovedClock
				if not prev then
					run.MovedPos, run.MovedClock = pos, now
				elseif pos ~= prev then   -- a new position arrived
					run.MovedPos, run.MovedClock = pos, now
					local span = math.max(now - prevT, 1 / 240)
					local step = (pos - prev).Magnitude
					if run.Status == "Running" then speedCheck(run, pos, now) end
					if step <= MAX_SPEED * span + STEP_SLACK then
						if run.Status == "Waiting" then
							local k = crossedAny(START_TAG, prev, pos)
							if k and bothAboard(ride) then start(run, prevT + k * (now - prevT)) end
						else
							local k = crossedAny(FINISH_TAG, prev, pos)
							if k then complete(run, prevT + k * (now - prevT)) end
						end
					else
						log("ignored a jump of", math.floor(step), "studs in", ("%.2f"):format(span), "s")
					end
				end
			end
		end
	end
end)

-- splits: the checkpoints this ride's riders reached together, on the run's clock
-- (it names the scooter: RideManager.Rides gives its ride, the same table this keys runs by)
CheckpointProgress.Reached:Connect(function(scooter, order)
	local ride = RideManager.Rides[scooter]
	local run = ride and byRide[ride]
	if not (run and run.Status == "Running") then return end
	local cp = Checkpoints.ByOrder(order)
	pcall(routePoint, run, os.clock(), "checkpoint " .. order)
	table.insert(run.Splits, {
		Order = order, CheckpointId = cp and cp.Id,
		Time = math.floor((os.clock() - run.StartClock) * 1000 + 0.5) / 1000,
	})
end)

---------------------------------------------------------------- skipping
-- This ride skipped part of the course (SkipStage): its run - waiting or running - is over
-- for good. Flagged (so even a copy of its record is never Valid), ended as "Abandoned",
-- dropped, and the ride left untimed for the rest of its life (byRide = false, the same as
-- a ride that started further along), so nothing can start, time or finish it again. Both
-- riders' stopwatches hide. A finished run is left as it is. True if a run was ended.
function RunTimer.Invalidate(ride, why)
	if not ride then return false end
	why = why or "invalidated"
	local run = byRide[ride]
	if not run then
		byRide[ride] = false   -- not tracked yet (or already untimed): it never will be
		return false
	end
	if run.Status == "Completed" then return false end
	flag(run, why)
	run.Valid = false
	byRide[ride], byId[run.RunId] = false, nil
	if run.Status == "Waiting" or run.Status == "Running" then
		local wasRunning = run.Status == "Running"
		run.Status, run.EndReason = "Abandoned", why
		if wasRunning then abandonedEvent:Fire(RunTimer.Record(run)) end
	end
	tell(run, { State = "None" })
	log(run.Player1.Name, "+", run.Player2.Name, "run", run.RunId, "invalidated:", why)
	return true
end

-- A revive (RideManager.Relaunch) put the ride on a new scooter a way back along the course:
-- that jump isn't driving, so the next position starts afresh - no gate crossed on the way,
-- no speed flagged. The clock keeps running (the time spent down counts, as it always did).
RideManager.Relaunched:Connect(function(scooter)
	local ride = RideManager.Rides[scooter]
	local run = ride and byRide[ride]
	if run then run.MovedPos, run.MovedClock, run.Window = nil, nil, nil end
end)

---------------------------------------------------------------- queries
function RunTimer.GetRun(runId)
	local run = byId[runId]
	if run then return RunTimer.Record(run) end
	for i = #completed, 1, -1 do
		if completed[i].RunId == runId then return copy(completed[i]) end
	end
	return nil
end

-- the run this player is in now (waiting, running or just finished), or nil
function RunTimer.GetRunForPlayer(player)
	local ride = RideManager.PlayerRide[player]
	local run = ride and byRide[ride]
	return run and RunTimer.Record(run) or nil
end

-- every run finished on this server (newest last), at most KEEP_COMPLETED
function RunTimer.GetCompletedRuns()
	return copy(completed)
end

return RunTimer
