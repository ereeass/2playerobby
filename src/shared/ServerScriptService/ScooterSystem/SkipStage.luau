--=====================================================================
-- SkipStage   (ScooterSystem, server)
--
-- The Skip Stage button (StarterGui.SkipStageGui): a Developer Product
-- (Shared.Config.SkipStageProductId) that moves a ride on to the next stage of the course.
--
--   Where to     from the ride's own progress (CheckpointProgress.RideReached: the last
--                checkpoint it reached, or where it started): the NEXT checkpoint, into the
--                bay a booth start there would use (StartManager.ResolveSpawnPart). From the
--                last checkpoint: onto the road FINISH_BACK studs before the finish gate,
--                facing it, and the motor drives it over the line, so the finish cutscene
--                (StarterPlayerScripts.FinishCutscene) plays as it always does. Never
--                backwards, never more than one stage at a time.
--   The ride     the scooter is moved with both riders still welded on (one rigid body), so
--                the Driver and the Motor keep their places and nothing is left behind. The
--                server holds the physics for the move and hands it back to the Driver.
--                Arriving on the next lot counts as reaching it, as ever (CheckpointProgress:
--                the unlock for both riders, the popup, the area music, the progress bar).
--   Hazards      while a skip moves a scooter (from the poof to the hand-back) ride.SkipMoving
--                is set: a push already running on it (the Stone Sweeper's shove) stops and no
--                new one starts, so nothing carries on shoving it at the new spot and flings
--                it. The server holds it perfectly still every frame of the hand-back.
--   The run      ended for good BEFORE anything moves (RunTimer.Invalidate): this ride gets
--                no time, no finish and no Fastest Duos record, however many more skips.
--                Records already saved are never touched.
--   Buying       the client only ASKS (Remotes.SkipStage); the server checks the ride and
--                opens the prompt itself, one prompt at a time per scooter. The skip happens
--                only in ProcessReceipt (DonationHandler), once Roblox confirms the purchase;
--                a cancelled or failed prompt changes nothing. A purchase that can't be used
--                any more (the ride ended, went into the water or reached the finish
--                meanwhile, or they left) is kept as a free skip on their account
--                (SkipCredits), spent on their next Skip Stage without a prompt.
--   The button   follows each rider's attributes: SkipStageTo (where a skip would take this
--                ride now: a checkpoint's name or "Finish"; nil when it can't),
--                SkipStageBusy (a prompt is open on this scooter) and SkipCredits.
--=====================================================================

local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local HttpService        = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local CollectionService  = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage      = game:GetService("ServerStorage")
local RS                 = game:GetService("ReplicatedStorage")

local Root        = RS:WaitForChild("ScooterSystem")
local Remotes     = Root:WaitForChild("Remotes")
local Shared      = Root:WaitForChild("Shared")
local Config      = require(Shared:WaitForChild("Config"))
local Checkpoints = require(Shared:WaitForChild("Checkpoints"))

local RideManager        = require(script.Parent:WaitForChild("RideManager"))
local CheckpointProgress = require(script.Parent:WaitForChild("CheckpointProgress"))
local RunTimer           = require(script.Parent:WaitForChild("RunTimer"))
local StartManager       = require(script.Parent:WaitForChild("StartManager"))
local RiderAttach        = require(script.Parent:WaitForChild("RiderAttach"))
local SkipStageWebhook   = require(script.Parent:WaitForChild("SkipStageWebhook"))   -- the team's Discord log of sales

local PRODUCT      = tonumber(Config.SkipStageProductId) or 0
local ATTR_TO      = "SkipStageTo"
local ATTR_BUSY    = "SkipStageBusy"
local ATTR_CREDITS = "SkipCredits"
local CREDITS_KEY  = "SkipCredits"      -- in the player's save (SettingsServer's PlayerData)
local FINISH_TAG   = "FinishLine"       -- the finish gate (as RunTimer and the cutscene use)
local FINISH_BACK  = 18     -- studs before the gate a last-stage skip puts the scooter (the straight run-in)
local FINISH_NEAR  = 32     -- nearer the line than this, or past it: nothing left to skip
local FINISH_DRIVE = 5      -- seconds the motor drives a last-stage skip on for, at most
local LEAD         = 0.45   -- the poof builds this long before the move (StarterPlayerScripts.TeleportFx)
local HAND_BACK    = 0.35   -- seconds the server holds the physics after the move
local PROMPT_WAIT  = 30     -- an unanswered prompt stops blocking the scooter after this (a
                             -- purchase finished later still counts: ProcessReceipt never needs it)
local BUSY_AFTER   = 3      -- after a purchase, the scooter's next skip waits this long
local UPDATE_EVERY = 0.2

local INVALID_NOTE = " This run won't count for Fastest Duos."
local SAVED_NOTE   = "Your skip couldn't be used, so it's saved: your next Skip Stage is free."

local SkipStage = {}

local function log(...) if Config.DebugLogging then print("[SkipStage]", ...) end end

-- per ride: skippedTo (order), toFinish, finished, pending = { player, at }, busyUntil,
-- moving, lastPos
local state = setmetatable({}, { __mode = "k" })
local function stateOf(ride)
	local st = state[ride]
	if not st then
		st = {}
		state[ride] = st
	end
	return st
end

local function riders(ride)
	local list = {}
	for _, plr in ipairs({ ride.Driver or false, ride.Passenger or false }) do
		if plr and plr.Parent == Players then table.insert(list, plr) end
	end
	return list
end

-- both riders on the scooter and alive (as CheckpointProgress and RunTimer count it)
local function bothAboard(ride)
	for _, role in ipairs({ "Driver", "Passenger" }) do
		local h = ride.Riders and ride.Riders[role]
		local plr = h and h.Player
		if not h or h.Released or not plr or plr.Parent ~= Players then return false end
		if h.Humanoid and h.Humanoid.Health <= 0 then return false end
	end
	return true
end

local function finishGate()
	for _, g in ipairs(CollectionService:GetTagged(FINISH_TAG)) do
		if g:IsA("BasePart") and g.Parent then return g end
	end
	return nil
end

---------------------------------------------------------------- free skips (credits)
local credits = {}   -- [player] = number, once loaded

local dataApi
local function data()
	if dataApi and dataApi.Parent then return dataApi end
	local settings = ServerScriptService:FindFirstChild("SettingsServer")
	dataApi = settings and settings:WaitForChild("PlayerData", 10)
	return dataApi
end

local function creditsOf(player)
	if credits[player] == nil then
		local api = data()
		local ok, value, state = false, nil, nil
		if api then ok, value, state = pcall(api.Get.Invoke, api.Get, player, CREDITS_KEY) end
		-- their save didn't load: the real count is unknown, so it isn't guessed (a 0 saved over
		-- it would wipe what they have). Nothing is written; it's read again next time.
		if not ok or state == "failed" or state == "invalid" then return 0, false end
		if credits[player] == nil and player.Parent == Players then
			credits[player] = math.max(0, math.floor(tonumber(value) or 0))
			player:SetAttribute(ATTR_CREDITS, credits[player])
		end
	end
	return credits[player] or 0, credits[player] ~= nil
end

local locks = {}   -- [player] = true while their count is being changed

-- The count changed by `by` and saved at once: true only once it is stored. One change at a
-- time per player (as DeathManager's revives and TrollEffects' trolls do it), each worked out
-- from the count as it is when its turn comes, so two at once can never overwrite each other.
local function changeCredits(player, by)
	while locks[player] do task.wait() end
	locks[player] = true
	local ok, stored = pcall(function()
		local api = data()
		if not api or player.Parent ~= Players then return false end
		local have, known = creditsOf(player)
		if not known then return false end   -- (their save didn't load: never written over)
		local n = have + by
		if n < 0 then return false end
		if not api.SaveNow:Invoke(player, CREDITS_KEY, n) then return false end
		if player.Parent == Players then
			credits[player] = n
			player:SetAttribute(ATTR_CREDITS, n)
		end
		return true
	end)
	locks[player] = nil
	if not ok then warn("[SkipStage] saved skips: " .. tostring(stored)) end
	return ok and stored == true
end

---------------------------------------------------------------- where a skip goes
-- Where a skip would take this ride now: { Order, Checkpoint } for the next checkpoint,
-- { Finish = true } from the last one - or nil and why not.
local function targetOf(ride)
	if not ride or ride._ended or ride.Down then return nil, "You need to be riding." end
	-- an obstacle or a troll has the ride (it is about to go down): nothing to skip
	if ride.Doomed then return nil, "You can't skip right now." end
	if not bothAboard(ride) then return nil, "Both riders need to be on the scooter." end
	local st = stateOf(ride)
	if not st.finished then
		local run = ride.Driver and RunTimer.GetRunForPlayer(ride.Driver)
		if run and run.Status == "Completed" then st.finished = true end
	end
	if st.finished or st.toFinish then return nil, "You're already at the finish." end

	local reached = CheckpointProgress.RideReached(ride) or Checkpoints.OrderOf(ride.CheckpointId) or 1
	local current = math.max(reached, st.skippedTo or 0)
	local cp = Checkpoints.ByOrder(current + 1)
	if cp and cp.Unlocked then return { Order = cp.Order, Checkpoint = cp } end

	-- the last stage: on to the finish line, unless it's (nearly) there or already past it
	local gate = finishGate()
	local chassis = ride.Scooter and ride.Scooter.PrimaryPart
	if not (gate and chassis) then return nil, "There's no stage left to skip." end
	local p = gate.CFrame:PointToObjectSpace(chassis.Position)
	if p.Z < FINISH_NEAR and math.abs(p.X) < gate.Size.X / 2 + FINISH_NEAR and math.abs(p.Y) < 60 then
		return nil, "You're almost at the finish!"
	end
	return { Finish = true }
end

local function labelOf(target)
	return target and (target.Finish and "Finish" or target.Checkpoint.DisplayName) or nil
end

-- the chassis CFrame the scooter goes to (as RideManager.Begin places a new one)
local function destinationFor(ride, target)
	if target.Finish then
		local gate = finishGate()
		if not gate then return nil end
		local fwd = gate.CFrame.LookVector * Vector3.new(1, 0, 1)   -- the way riders cross it
		fwd = fwd.Magnitude > 1e-3 and fwd.Unit or Vector3.new(0, 0, -1)
		local spot = gate.CFrame * Vector3.new(0, 0, FINISH_BACK)    -- +Z: the road side
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.RespectCanCollide = true
		params.IgnoreWater = true
		local ignore = { gate }
		local sys = workspace:FindFirstChild("RideSystem")
		if sys then table.insert(ignore, sys) end
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr.Character then table.insert(ignore, plr.Character) end
		end
		params.FilterDescendantsInstances = ignore
		local hit = workspace:Raycast(spot + Vector3.new(0, 6, 0), Vector3.new(0, -30, 0), params)
		if not hit then return nil end
		local pos = hit.Position + Vector3.new(0, Config.ScooterLift, 0)
		return CFrame.lookAt(pos, pos + fwd)
	end
	local part = StartManager.ResolveSpawnPart(target.Checkpoint.Id, ride.StationId)
	if not part then return nil end
	local a = part:FindFirstChild("ScooterSpawn")
	local base = a and a.WorldCFrame or part.CFrame
	return CFrame.new(base.Position + Vector3.new(0, Config.ScooterLift, 0)) * base.Rotation
end

---------------------------------------------------------------- the move
local function holdStill(chassis)
	chassis.AssemblyLinearVelocity = Vector3.zero
	chassis.AssemblyAngularVelocity = Vector3.zero
end

-- back to the Driver's machine, which simulates the scooter (as RiderAttach set it up)
local function handBack(ride)
	local chassis = not ride._ended and ride.Scooter and ride.Scooter.PrimaryPart
	if not chassis then return end
	holdStill(chassis)
	local driver = ride.Driver
	if driver and driver.Parent == Players then
		pcall(function() chassis:SetNetworkOwner(driver) end)
		local ph = ride.Riders and ride.Riders.Passenger
		if ph then RiderAttach.SetSimulationOwner(ph, driver) end
	else
		pcall(function() chassis:SetNetworkOwnershipAuto() end)
	end
end

-- From the last checkpoint: the motor takes it over the line (the cutscene then brakes it
-- through the Motor's own controls). Either rider's own input takes over as usual.
local function driveThrough(ride, st)
	local c = ride.Controller
	if not c or ride._ended then return end
	c:SetSteer(0)
	c:SetThrottle("forward")
	local t0 = os.clock()
	while not ride._ended and not ride.Down and not st.finished and os.clock() - t0 < FINISH_DRIVE do
		task.wait(0.1)
	end
	if st.finished then task.wait(0.5) end
	if not ride._ended and c.Mode == "forward" then c:SetThrottle("coast") end
end

-- Skips this ride to `target`. The caller has claimed it (st.moving = true); this lets go.
-- True once the scooter has been moved.
local function apply(ride, target)
	local st = stateOf(ride)
	local cf = destinationFor(ride, target)
	if not cf then
		st.moving = false
		warn("[SkipStage] no spot to skip to (" .. tostring(labelOf(target)) .. ")")
		return false
	end

	-- no hazard shoves it from here until it's handed back (see the header)
	ride.SkipMoving = true

	-- the mist gathers round both riders and at the spot, and bursts as they go
	local poofs = {}
	for _, role in ipairs({ "Driver", "Passenger" }) do
		local h = ride.Riders and ride.Riders[role]
		if h and h.Root and h.Root.Parent then table.insert(poofs, h.Root.Position) end
	end
	table.insert(poofs, cf.Position + Vector3.new(0, 3, 0))
	pcall(function() Remotes.TeleportFx:FireAllClients(poofs, LEAD) end)
	task.wait(LEAD)

	local chassis = ride.Scooter and ride.Scooter.PrimaryPart
	if ride._ended or ride.Down or ride.Doomed or not chassis or not bothAboard(ride) then
		st.moving = false
		ride.SkipMoving = nil
		return false
	end
	-- the skip is going ahead: the run is over first, before anything moves (never timed again,
	-- RunTimer), and the ride remembers where it skipped to. Only now, so a skip called off
	-- above leaves the run and the ride's next skip exactly as they were.
	local hadRun = RunTimer.Invalidate(ride, "skipped a stage")
	if target.Finish then st.toFinish = true else st.skippedTo = target.Order end
	if ride.Controller then pcall(function() ride.Controller:Stop() end) end
	pcall(function() chassis:SetNetworkOwner(nil) end)   -- the server holds it for the move
	holdStill(chassis)
	ride.Scooter:PivotTo(cf)
	holdStill(chassis)
	st.lastPos = nil
	ride.Trail = nil   -- DeathManager's revive spots were on the road it left

	local where = labelOf(target)
	local note = (target.Finish and "Skipped to the finish!" or "Stage skipped!") .. (hadRun and INVALID_NOTE or "")
	for _, plr in ipairs(riders(ride)) do Remotes.Notice:FireClient(plr, note) end
	log(ride.Driver and ride.Driver.Name, "+", ride.Passenger and ride.Passenger.Name, "skipped to", where,
		hadRun and "(run invalidated)" or "")

	-- held perfectly still at the new spot until it's handed back: nothing left over from the
	-- road it left (a hazard's shove, the speed it had) can move it
	local held = 0
	local hold
	hold = RunService.Heartbeat:Connect(function(dt)
		held += dt
		if ride._ended or not chassis.Parent or held >= HAND_BACK then hold:Disconnect() return end
		holdStill(chassis)
	end)
	task.delay(HAND_BACK, function()
		if hold.Connected then hold:Disconnect() end
		handBack(ride)
		ride.SkipMoving = nil
		st.moving = false
		if target.Finish then driveThrough(ride, st) end
	end)
	return true
end

---------------------------------------------------------------- buying
local function setBusy(ride, on)
	for _, plr in ipairs(riders(ride)) do
		if plr:GetAttribute(ATTR_BUSY) ~= (on or nil) then plr:SetAttribute(ATTR_BUSY, on or nil) end
	end
end

-- Saved skips from elsewhere (the Daily Rewards calendar): the same count the button spends
-- and shows. True once saved.
function SkipStage.GiveSkips(player, n)
	return changeCredits(player, n)   -- (their save didn't load: never written over)
end

function SkipStage.IsProduct(productId)
	return PRODUCT ~= 0 and productId == PRODUCT
end

-- A confirmed purchase (DonationHandler's ProcessReceipt). Skips the buyer's ride now if it
-- still can; otherwise keeps it as a free skip. Granted only once it is used or saved.
local granted = {}   -- [PurchaseId] = true: handled on this server
function SkipStage.ProcessReceipt(receipt)
	if granted[receipt.PurchaseId] then return Enum.ProductPurchaseDecision.PurchaseGranted end
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end   -- offered again when they're back

	local ride = RideManager.PlayerRide[player]
	local st = ride and stateOf(ride)
	if st and st.pending and st.pending.player == player then
		st.pending = nil
		setBusy(ride, false)
	end

	local used, where = false, nil
	if st and not st.moving then
		local target = targetOf(ride)
		if target then
			st.moving = true
			used = apply(ride, target)
			where = labelOf(target)
		end
	end
	if not used then
		if not changeCredits(player, 1) then
			return Enum.ProductPurchaseDecision.NotProcessedYet   -- nothing given yet: Roblox offers it again
		end
		Remotes.Notice:FireClient(player, SAVED_NOTE)
		log(player.Name, "bought a skip that couldn't be used; saved as a free skip")
	end
	if st then st.busyUntil = os.clock() + BUSY_AFTER end
	granted[receipt.PurchaseId] = true
	SkipStageWebhook.Log(receipt, used and ("Skipped to " .. tostring(where)) or "Couldn't be used, saved as a free skip")   -- in the background
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- The button asks. Never grants anything itself: it checks, then either spends a free skip
-- or opens Roblox's prompt from here. Returns ok, and what happened (or why not).
local function request(player)
	local ride = RideManager.PlayerRide[player]
	if not ride then return false, "You need to be riding." end
	local st = stateOf(ride)
	local now = os.clock()
	if st.moving or now < (st.busyUntil or 0) then return false, "Skipping..." end
	local p = st.pending
	if p and p.player ~= player and p.player.Parent == Players and now - p.at < PROMPT_WAIT then
		return false, "Your partner is buying a skip."
	end
	local target, why = targetOf(ride)
	if not target then return false, why end

	-- a free skip saved on their account: spent now, no prompt
	if creditsOf(player) > 0 then
		st.moving = true
		if not changeCredits(player, -1) then
			st.moving = false
			return false, "Couldn't use your free skip, try again."
		end
		target = targetOf(ride)
		if target and apply(ride, target) then return true, "free" end
		st.moving = false
		-- not used after all: it's theirs again
		if not changeCredits(player, 1) then
			warn("[SkipStage] couldn't give " .. player.Name .. " back their free skip")
		end
		return false, "Couldn't skip right now."
	end

	if PRODUCT == 0 then return false, "Skip Stage isn't set up yet." end
	st.pending = { player = player, at = now }
	setBusy(ride, true)
	MarketplaceService:PromptProductPurchase(player, PRODUCT)
	return true, "prompt"
end

Remotes:WaitForChild("SkipStage").OnServerInvoke = function(player)
	local ok, a, b = pcall(request, player)
	if not ok then
		warn("[SkipStage] " .. tostring(a))
		return false, "Couldn't skip right now."
	end
	return a, b
end

-- the prompt closed (bought or not): the scooter's other rider may ask again. Never grants.
MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
	if not SkipStage.IsProduct(productId) then return end
	local player = Players:GetPlayerByUserId(userId)
	local ride = player and RideManager.PlayerRide[player]
	local st = ride and state[ride]
	if st and st.pending and st.pending.player == player then
		st.pending = nil
		setBusy(ride, false)
		if purchased then st.busyUntil = math.max(st.busyUntil or 0, os.clock() + BUSY_AFTER) end
	end
end)

---------------------------------------------------------------- every frame
-- Over the finish line (any ride on the last stage): nothing is left to skip after that.
local function watchFinish(ride, st, gate)
	local chassis = ride.Scooter and ride.Scooter.PrimaryPart
	if not chassis then return end
	local pos, prev = chassis.Position, st.lastPos
	st.lastPos = pos
	if not prev or (pos - prev).Magnitude > 60 then return end   -- a teleport is never a crossing
	local a, b = gate.CFrame:PointToObjectSpace(prev), gate.CFrame:PointToObjectSpace(pos)
	if a.Z > 0 and b.Z <= 0 then
		local at = a:Lerp(b, a.Z / (a.Z - b.Z))
		if math.abs(at.X) <= gate.Size.X / 2 and math.abs(at.Y) <= gate.Size.Y / 2 then
			st.finished = true
		end
	end
end

local sinceUpdate = 0
local MAX_ORDER = Checkpoints.MaxOrder()
RunService.Heartbeat:Connect(function(dt)
	local gate = finishGate()
	if gate then
		for _, ride in pairs(RideManager.Rides) do
			local st = state[ride]
			if not ride._ended and not (st and st.finished)
				and ((CheckpointProgress.RideReached(ride) or 0) >= MAX_ORDER or (st and st.toFinish)) then
				watchFinish(ride, stateOf(ride), gate)
			end
		end
	end

	sinceUpdate += dt
	if sinceUpdate < UPDATE_EVERY then return end
	sinceUpdate = 0
	-- each rider's button: where a skip would take their ride now (nil: no button)
	local seen, now = {}, os.clock()
	for _, ride in pairs(RideManager.Rides) do
		local st = stateOf(ride)
		local p = st.pending
		if p and (p.player.Parent ~= Players or now - p.at >= PROMPT_WAIT) then
			st.pending = nil
			setBusy(ride, false)
		end
		local label = nil
		if not st.moving then label = labelOf((targetOf(ride))) end
		for _, plr in ipairs(riders(ride)) do
			seen[plr] = true
			if plr:GetAttribute(ATTR_TO) ~= label then plr:SetAttribute(ATTR_TO, label) end
		end
	end
	for _, plr in ipairs(Players:GetPlayers()) do
		if not seen[plr] then
			if plr:GetAttribute(ATTR_TO) ~= nil then plr:SetAttribute(ATTR_TO, nil) end
			if plr:GetAttribute(ATTR_BUSY) ~= nil then plr:SetAttribute(ATTR_BUSY, nil) end
		end
	end
end)

---------------------------------------------------------------- players
Players.PlayerAdded:Connect(function(player) task.spawn(creditsOf, player) end)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(creditsOf, player) end
Players.PlayerRemoving:Connect(function(player) credits[player] = nil end)

---------------------------------------------------------------- studio
-- Studio only: a confirmed purchase for this player, exactly as ProcessReceipt gets it
-- (Command bar, Server):  game.ServerStorage.SkipStageStudioTest:Invoke(player)
if RunService:IsStudio() then
	local hook = Instance.new("BindableFunction")
	hook.Name = "SkipStageStudioTest"
	hook.OnInvoke = function(player)
		return SkipStage.ProcessReceipt({
			PlayerId = player.UserId, ProductId = PRODUCT, CurrencySpent = 0,
			PurchaseId = "studio-" .. HttpService:GenerateGUID(false),
		})
	end
	hook.Parent = ServerStorage
end

return SkipStage
