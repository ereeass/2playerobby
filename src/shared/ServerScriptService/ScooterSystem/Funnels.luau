--=====================================================================
-- Funnels   (ScooterSystem, server)   *** ANALYTICS ONLY ***
--
-- Reports five Roblox funnels (AnalyticsService Funnel Events: Creator Hub > Analytics >
-- Funnels), and the "LaunchCancelled" custom event (a launch called off after START). It only WATCHES what the game has already decided: nothing here changes, waits
-- on or answers anything for gameplay. The game's scripts tell it what happened through
-- one-line hooks (funnel(...)), each run in its own protected thread, so an error in here can
-- never reach them. No client can reach it: there are no remotes, and every funnel name, step
-- number and session id is decided here.
--
--   New Players – World 1  (World 1 only; LogFunnelStepEvent) - once per visit:
--     1 Player Joined    2 Loaded In (their first character spawned)
--     3 Got Through Cutscene (the first-join intro ended, watched or skipped: IntroCinematicServer;
--       a player who doesn't get the intro this visit counts it when they enter a booth)
--     4 Entered Booth    5 Partner Joined   6 Pressed START (the pair's START, so both riders get it)
--     7 Ride Started     8 Reached Checkpoint 2
--     Who: players who haven't reached this world's checkpoint 2 yet (CheckpointProgress's
--     own save). Session id: a new GUID for each visit (server join).
--     It replaced Roblox's single Onboarding funnel (2026-10-06): that one kept the FIRST name
--     it ever saw for each step number, so inserting step 3 left two "Entered Booth" rows.
--     NEVER RENUMBER OR INSERT STEPS in any funnel here: Roblox keeps old names per number.
--     A new step goes in a new funnel (a new name).
--   Ride – World 1 / Ride – World 2  (WorldConfig.Id; LogFunnelStepEvent) - every ride:
--     1 Entered Booth    2 Partner Joined    3 Ride Started    4 Next Checkpoint    5 Finished
--     Session id: a new GUID every time a player walks into a booth (Funnels.BoothEntered).
--     When the ride starts it becomes that ride's (ride.FunnelSessions[player]) for the rest
--     of the ride; it goes when the ride ends (RideManager.End) or when they leave the booth
--     without riding. Never reused, never the UserId, never from a client.
--     Next Checkpoint: the ride's riders reaching the next checkpoint together
--     (CheckpointProgress.Reached). Finished: the ride's chassis crossing the finish gate
--     (WorldUnlock) while the ride is still live - a ride ended any other way (left, reset,
--     died without a revive, ...) never gets it.
--   Course – World 1 / Course – World 2  (LogFunnelStepEvent) - each ride from checkpoint 1:
--     1 Ride Started   2.. Reached <checkpoint 2, 3, ...> (Shared.Checkpoints' names)   last Finished
--     Only rides that start at checkpoint 1 (a later start would make Roblox count the
--     checkpoints before it as reached). Same session id as the ride's Ride funnel. A Skip
--     Stage (SkipStage sets ride.SkipMoving while it moves the scooter) ends the ride's course
--     tracking for good, so the funnel only ever shows stages that were actually driven.
--   Each step is sent at most once per session (Roblox only counts the first anyway, but a
--   repeat would still use up the event rate limit).
--   Studio: nothing is sent (Roblox ignores Studio events too); each event is printed as
--   "[Funnels] (Studio, not sent) ..." so it can be checked.
--=====================================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local HttpService      = game:GetService("HttpService")
local AnalyticsService = game:GetService("AnalyticsService")
local RS               = game:GetService("ReplicatedStorage")

local World              = require(RS:WaitForChild("WorldConfig"))
local RideManager        = require(script.Parent:WaitForChild("RideManager"))
local CheckpointProgress = require(script.Parent:WaitForChild("CheckpointProgress"))
local Checkpoints        = require(RS:WaitForChild("ScooterSystem"):WaitForChild("Shared"):WaitForChild("Checkpoints"))

local LIVE          = not RunService:IsStudio()
local ONBOARDING    = World.Id == 1
local NEW_FUNNEL    = "New Players – World 1"   -- never rename: a new name starts a new funnel
local RIDE_FUNNEL   = ({ [1] = "Ride – World 1", [2] = "Ride – World 2" })[World.Id]
local COURSE_FUNNEL = ({ [1] = "Course – World 1", [2] = "Course – World 2" })[World.Id]
local FIRST_ID      = Checkpoints.ByOrder(1) and Checkpoints.ByOrder(1).Id
local LAST_ORDER    = Checkpoints.MaxOrder()
local LOAD_WAIT     = 30   -- seconds to wait for a player's checkpoint save before deciding onboarding

local OB = {
	Joined      = { 1, "Player Joined" },
	Loaded      = { 2, "Loaded In" },
	Intro       = { 3, "Got Through Cutscene" },
	Booth       = { 4, "Entered Booth" },
	Partner     = { 5, "Partner Joined" },
	Start       = { 6, "Pressed START" },
	Ride        = { 7, "Ride Started" },
	Checkpoint2 = { 8, "Reached Checkpoint 2" },
}
local RIDE = {
	Booth      = { 1, "Entered Booth" },
	Partner    = { 2, "Partner Joined" },
	Started    = { 3, "Ride Started" },
	Checkpoint = { 4, "Next Checkpoint" },
	Finished   = { 5, "Finished" },
}

local Funnels = {}
local onboarding = {}   -- [player] = { id, logged = {} } while onboarding; false = not (yet, or done)
local attempts   = {}   -- [player] = { Id, Logged = {}, Ride } : their current booth entry / ride
local introDone  = {}   -- [player] = true: their first-join intro ended (kept until onboarding is decided)

local function here(plr)
	return typeof(plr) == "Instance" and plr:IsA("Player") and plr.Parent == Players
end

---------------------------------------------------------------- sending
local function onboard(plr, step)
	if not ONBOARDING or not here(plr) then return end
	local st = onboarding[plr]
	if not st or st.logged[step[1]] then return end
	st.logged[step[1]] = true
	if LIVE then
		local ok, err = pcall(AnalyticsService.LogFunnelStepEvent, AnalyticsService, plr, NEW_FUNNEL, st.id, step[1], step[2])
		if not ok then warn("[Funnels] new-player step " .. step[1] .. " not sent: " .. tostring(err)) end
	else
		print(("[Funnels] (Studio, not sent) %s %d %s - %s [%s]"):format(NEW_FUNNEL, step[1], step[2], plr.Name, st.id))
	end
	if step == OB.Checkpoint2 then onboarding[plr] = false end   -- done for good
end

local function rideStep(plr, attempt, step)
	if not RIDE_FUNNEL or not here(plr) or not attempt or attempt.Logged[step[1]] then return end
	attempt.Logged[step[1]] = true
	if LIVE then
		local ok, err = pcall(AnalyticsService.LogFunnelStepEvent, AnalyticsService, plr, RIDE_FUNNEL, attempt.Id, step[1], step[2])
		if not ok then warn("[Funnels] ride step " .. step[1] .. " not sent: " .. tostring(err)) end
	else
		print(("[Funnels] (Studio, not sent) %s %d %s - %s [%s]"):format(RIDE_FUNNEL, step[1], step[2], plr.Name, attempt.Id))
	end
end

-- Course funnel: step 1 Ride Started, checkpoint `order` is step `order`, Finished is the step
-- after the last checkpoint. Only for a ride from checkpoint 1 that hasn't been skipped.
local function courseStep(plr, attempt, n, name)
	local c = attempt and attempt.Course
	if not COURSE_FUNNEL or not here(plr) or not c or c.off or c.logged[n] then return end
	if attempt.Ride and attempt.Ride.SkipMoving then c.off = true return end
	c.logged[n] = true
	if LIVE then
		local ok, err = pcall(AnalyticsService.LogFunnelStepEvent, AnalyticsService, plr, COURSE_FUNNEL, attempt.Id, n, name)
		if not ok then warn("[Funnels] course step " .. n .. " not sent: " .. tostring(err)) end
	else
		print(("[Funnels] (Studio, not sent) %s %d %s - %s [%s]"):format(COURSE_FUNNEL, n, name, plr.Name, attempt.Id))
	end
end

-- a skip ends course tracking for that ride (checked every frame: SkipMoving is set before the
-- scooter moves, so it is always seen before the checkpoint it lands on counts)
RunService.Heartbeat:Connect(function()
	for _, a in pairs(attempts) do
		local c = a.Course
		if c and not c.off and a.Ride and a.Ride.SkipMoving then c.off = true end
	end
end)

---------------------------------------------------------------- onboarding: who
-- Onboarding is for players who haven't reached checkpoint 2 here yet. Their checkpoint
-- save is waited for (it loads after they join); a player who already has it is never in it.
local function startOnboarding(plr)
	if not ONBOARDING or onboarding[plr] ~= nil then return end
	onboarding[plr] = false
	local t0 = os.clock()
	local highest, loaded = CheckpointProgress.Get(plr)
	while here(plr) and not loaded and os.clock() - t0 < LOAD_WAIT do
		task.wait(0.5)
		highest, loaded = CheckpointProgress.Get(plr)
	end
	if not (here(plr) and loaded) or highest >= 2 then return end
	onboarding[plr] = { id = HttpService:GenerateGUID(false), logged = {} }
	onboard(plr, OB.Joined)
	if plr.Character then onboard(plr, OB.Loaded) end   -- else when it arrives (below)
	if introDone[plr] then onboard(plr, OB.Intro) end   -- a skip can beat the save load
end

local function onPlayer(plr)
	plr.CharacterAdded:Connect(function() onboard(plr, OB.Loaded) end)   -- only the first counts
	task.spawn(startOnboarding, plr)
end
Players.PlayerAdded:Connect(onPlayer)
for _, plr in ipairs(Players:GetPlayers()) do onPlayer(plr) end
Players.PlayerRemoving:Connect(function(plr)
	onboarding[plr], attempts[plr], introDone[plr] = nil, nil, nil
end)

---------------------------------------------------------------- hooks (the game calls these)
-- IntroCinematicServer: this player's first-join intro ended, watched or skipped (once each).
function Funnels.IntroDone(plr)
	if not ONBOARDING or not here(plr) then return end
	introDone[plr] = true
	onboard(plr, OB.Intro)
end

-- TeamManager.Enter: this player has just taken a booth slot. A new session every time.
function Funnels.BoothEntered(plr)
	if not here(plr) then return end
	local attempt = { Id = HttpService:GenerateGUID(false), Logged = {} }
	attempts[plr] = attempt
	rideStep(plr, attempt, RIDE.Booth)
	-- no intro this visit (seen on an earlier one): they are past that point all the same
	local st = onboarding[plr]
	if st and not st.logged[OB.Intro[1]] then onboard(plr, OB.Intro) end
	onboard(plr, OB.Booth)
end

-- TeamManager.Exit: out of the booth. A session that never became a ride is dropped.
function Funnels.BoothLeft(plr)
	local a = attempts[plr]
	if a and not a.Ride then attempts[plr] = nil end
end

-- TeamManager.Recompute: both players are inside the same station.
function Funnels.PartnerJoined(driver, passenger)
	if not (here(driver) and here(passenger)) or driver == passenger then return end
	for _, plr in ipairs({ driver, passenger }) do
		local a = attempts[plr]
		if a and not a.Ride then rideStep(plr, a, RIDE.Partner) end
		onboard(plr, OB.Partner)
	end
end

-- TeamManager.ReadyUp: the server accepted the pair's START.
function Funnels.PressedStart(driver, passenger)
	if not (here(driver) and here(passenger)) or driver == passenger then return end
	onboard(driver, OB.Start)
	onboard(passenger, OB.Start)
end

-- RideManager.Begin: the ride exists and both riders are on it.
function Funnels.RideStarted(ride)
	if type(ride) ~= "table" or ride._ended or ride.FunnelSessions then return end
	if not ride.Scooter or RideManager.Rides[ride.Scooter] ~= ride then return end
	ride.FunnelSessions = {}
	for _, plr in ipairs({ ride.Driver or false, ride.Passenger or false }) do
		local a = plr and attempts[plr]
		if a and not a.Ride then
			a.Ride = ride
			ride.FunnelSessions[plr] = a.Id
			rideStep(plr, a, RIDE.Started)
			if FIRST_ID and ride.CheckpointId == FIRST_ID then
				a.Course = { logged = {} }
				courseStep(plr, a, 1, "Ride Started")
			end
		end
		if plr then onboard(plr, OB.Ride) end
	end
end

-- TeamManager: a launch was called off after the pair's START (someone pressed EXIT, left the
-- game or died during the countdown, a rider couldn't be put on the scooter, or the ride
-- couldn't start). A "LaunchCancelled" custom event, once per launch:
--   CustomField01  why    CustomField02  "New player" / "Returning" (whoever it is logged on)
--   CustomField03  the world
local CANCEL_WHY = {
	button  = "Pressed EXIT",
	leaving = "Left the game",
	respawn = "Died or reset",
	missing = "Rider missing at launch",
	failed  = "Ride failed to start",
}
function Funnels.LaunchCancelled(why, a, b)
	local plr = (here(a) and a) or (here(b) and b) or nil
	if not plr then return end
	local reason = CANCEL_WHY[why] or tostring(why)
	local kind = (type(onboarding[plr]) == "table") and "New player" or "Returning"
	if LIVE then
		local ok, err = pcall(AnalyticsService.LogCustomEvent, AnalyticsService, plr, "LaunchCancelled", 1, {
			[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = reason,
			[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = kind,
			[Enum.AnalyticsCustomFieldKeys.CustomField03.Name] = tostring(World.Name or World.Id),
		})
		if not ok then warn("[Funnels] LaunchCancelled not sent: " .. tostring(err)) end
	else
		print(("[Funnels] (Studio, not sent) LaunchCancelled: %s / %s / %s"):format(reason, kind, tostring(World.Name or World.Id)))
	end
end

-- this live ride's riders whose session is still this ride's: [player] = attempt
local function liveSessions(ride)
	local out = {}
	if type(ride) ~= "table" or ride._ended or not ride.FunnelSessions then return out end
	if not ride.Scooter or RideManager.Rides[ride.Scooter] ~= ride then return out end
	for plr, id in pairs(ride.FunnelSessions) do
		local a = attempts[plr]
		if a and a.Ride == ride and a.Id == id then out[plr] = a end
	end
	return out
end

-- WorldUnlock: this ride's chassis crossed the finish gate.
function Funnels.RideFinished(ride)
	for plr, a in pairs(liveSessions(ride)) do
		rideStep(plr, a, RIDE.Finished)
		courseStep(plr, a, LAST_ORDER + 1, "Finished")
	end
end

-- RideManager.End: the ride is over, whatever the reason. Its sessions close for good.
function Funnels.RideEnded(ride)
	if type(ride) ~= "table" or not ride.FunnelSessions then return end
	for plr, id in pairs(ride.FunnelSessions) do
		local a = attempts[plr]
		if a and a.Ride == ride and a.Id == id then attempts[plr] = nil end
	end
	ride.FunnelSessions = nil
end

-- the ride's riders reached the next checkpoint together (an existing event: no hook needed)
CheckpointProgress.Reached:Connect(function(scooter, order)
	local ride = RideManager.Rides[scooter]
	if type(ride) ~= "table" or ride._ended then return end
	local cp = type(order) == "number" and order >= 2 and order <= LAST_ORDER and Checkpoints.ByOrder(order)
	for plr, a in pairs(liveSessions(ride)) do
		rideStep(plr, a, RIDE.Checkpoint)
		if cp then courseStep(plr, a, order, "Reached " .. tostring(cp.DisplayName or ("Checkpoint " .. order))) end
	end
	if order == 2 then
		for _, plr in ipairs({ ride.Driver or false, ride.Passenger or false }) do
			if plr then onboard(plr, OB.Checkpoint2) end
		end
	end
end)

return Funnels
