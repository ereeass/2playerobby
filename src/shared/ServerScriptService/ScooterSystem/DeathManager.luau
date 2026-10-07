--=====================================================================
-- DeathManager   (ScooterSystem)
--
-- A ride "goes down" when an obstacle or the water catches it (Hit): both riders die for
-- real (Roblox's own death: the character falls apart, the death sound plays), and both
-- get the death popup (StarterGui.DeathGui) over it. Everything that matters is decided
-- HERE, so no client can stretch the timer, vote twice or revive for free:
--
--   Timer   Config.DeathSeconds, run on the server. Runs out -> the run ends. It stands
--           still while a revive is being bought or done (see REVIVE).
--   SKIP    each rider votes once (Remotes.DeathSkip); both see the same count. Every
--           rider voted -> the run ends (once a purchase still open is given up).
--   Ending  RideManager.End (scooter gone, ride cleared, lobby HUD back); the dead riders
--           respawn at the lobby spawn (Main), and anyone still alive is sent there.
--   REVIVE  Config.ReviveProductId, a Developer Product one rider buys for the pair:
--             asked    REVIVE on the popup (Remotes.ReviveRequest). One purchase per ride
--                      at a time: the server opens Roblox's purchase window for that
--                      rider, holds the countdown and tells both riders (the other one
--                      sees "Your friend is buying a revive..."). Asking again, or both at
--                      once, opens nothing more.
--             closed   PromptProductPurchaseFinished (or the buyer's own screen saying it
--                      closed): not bought -> the message goes at once and the countdown
--                      carries on (at least RESUME_MIN s left); bought -> it waits for
--                      Roblox's receipt. Left open, the countdown carries on after
--                      Config.ReviveHoldSeconds anyway.
--             receipt  Roblox's receipt (DonationHandler's ProcessReceipt hands revives
--                      here) is the ONLY thing that revives. A receipt with nothing to
--                      revive any more (the run ended, a rider left, the buyer came back
--                      later) is never lost: it is saved as a free revive for that
--                      player's next REVIVE (ReviveCredits in their save), which then
--                      revives at once without a purchase. How many they have is also
--                      their ReviveCredits attribute: REVIVE's red count.
--             revive   both riders get new characters on a new scooter at a safe spot a
--                      little way BACK along the course (ReviveSpot), GRACE seconds of
--                      protection, and the popup closes. The run, its stopwatch and its
--                      checkpoints carry on. If it can't be done the run ends as it would
--                      have, and the buyer keeps the revive for next time.
--   Obstacles that throw the scooter before it dies (landmines, hammers, sliding blocks)
--   claim the ride first (Claim) and pass the life they claimed to Hit, so a Hit that
--   comes late can never land on the ride after a revive.
--
-- A rider leaving (or the ride ending any other way) also closes the popup:
-- RideManager.End sends Phase "None", which the popup listens for.
--
-- 5x REVIVES / INFINITE REVIVES: two more Developer Products, offered under the popup's box on
-- a death with no revenge (DeathClient). Asked for exactly like REVIVE (Remotes.ReviveRequest
-- "five" / "infinite": one purchase per ride at a time, the countdown held), and only their
-- receipt (DonationHandler -> ProcessPackReceipt) rewards, ONLY the player who bought it:
--   5x        the ride revived now (that's one of the five) + 4 saved revives (ReviveCredits);
--             with nothing to revive any more, all 5 are saved
--   infinite  InfiniteRevives = true in their save, for good (every world: the save is shared),
--             and the ride revived now. From then on their REVIVE is free and spends nothing -
--             saved revives they have are kept (InfiniteRevives attribute: the popup says so).
-- Each reward is saved in the same write as the receipt's PurchaseId (ReviveReceipts), so a
-- receipt Roblox offers again - in any server, any world - is recognised and never pays twice.
--
-- REVENGE: a ride brought down by another riding duo's EXPLODE PLAYERS (the E prompt on a
-- scooter, TrollEffects "ride" mode) is Hit with a cause { Kind = "RideExplode", AttackerRide,
-- ByName, ByUserId }. Only that death gets down.Revenge, and with it the EXPLODE BACK (REVENGE)
-- section of the popup. Everything about buying and doing the revenge is TrollEffects'; this
-- keeps the countdown (held while it is bought or played, exactly as for a revive) and tells
-- both riders its state. The revenge's own explosion is Hit with { Kind = "Revenge" }: never a
-- revenge of its own, and logged as "Revenge".
--=====================================================================

local Players             = game:GetService("Players")
local MarketplaceService  = game:GetService("MarketplaceService")
local ServerScriptService = game:GetService("ServerScriptService")
local RS                  = game:GetService("ReplicatedStorage")

local Root    = RS:WaitForChild("ScooterSystem")
local Remotes = Root:WaitForChild("Remotes")
local Config  = require(Root:WaitForChild("Shared"):WaitForChild("Config"))

local RideManager = require(script.Parent:WaitForChild("RideManager"))
local ReviveSpot  = require(script.Parent:WaitForChild("ReviveSpot"))
local ReviveWebhook = require(script.Parent:WaitForChild("ReviveWebhook"))   -- the team's Discord log of sales
local AnalyticsService = game:GetService("AnalyticsService")

local SECONDS       = Config.DeathSeconds or 10
local PRODUCT       = Config.ReviveProductId or 0
local HOLD_MAX      = Config.ReviveHoldSeconds or 45   -- the countdown waits at most this long for a purchase
local RESUME_MIN    = 5      -- a purchase given up leaves at least this many seconds to choose
local RECEIPT_WAIT  = 20     -- after "bought", how long the countdown waits for Roblox's receipt
local GRACE         = 2      -- seconds after a revive in which nothing can bring the ride down
local ASK_GAP       = 1      -- seconds between one rider's REVIVE requests
local CREDIT_KEY    = "ReviveCredits"
local CREDIT_ATTR   = "ReviveCredits"   -- on the player: REVIVE's red count (UITemplates.CountBadge)
local FIVE_PRODUCT  = Config.ReviveFiveProductId or 0       -- 5x REVIVES
local INF_PRODUCT   = Config.ReviveInfiniteProductId or 0   -- INFINITE REVIVES
local FIVE_SAVED    = 4      -- 5x: one revive now and this many saved (all five saved if nothing to revive)
local INF_KEY       = "InfiniteRevives"   -- true in their save: REVIVE free for good
local INF_ATTR      = "InfiniteRevives"   -- on the player, for the popup
local RECEIPTS_KEY  = "ReviveReceipts"    -- the PurchaseIds of 5x / infinite receipts already rewarded
local RECEIPTS_MAX  = 50
local INF_NOTICE    = "Infinite Revives unlocked - your REVIVE is free forever!"
local FIVE_NOTICE   = "4 more revives saved - your next REVIVE is free!"
local FIVE_SAVED_NOTICE = "5 revives saved - your next REVIVE is free!"
local SAVED_NOTICE  = "Your revive was saved - your next REVIVE is free!"
local FAILED_NOTICE = "The revive couldn't be placed - it's saved for your next REVIVE."

local DeathManager = {}

local function log(...) if Config.DebugLogging then print("[Scooter]", ...) end end

-- the ride's riders, either of which can be missing
local function riders(ride)
	local list = {}
	for _, plr in ipairs({ ride.Driver or false, ride.Passenger or false }) do
		if plr then table.insert(list, plr) end
	end
	return list
end

local function present(plr)
	return typeof(plr) == "Instance" and plr.Parent ~= nil
end

local function votesOf(down)
	local n = 0
	for _ in pairs(down.Votes) do n += 1 end
	return n
end

-- a revenge being bought or played on this down (TrollEffects): the countdown stays held
local function revengeBusy(down)
	local rv = down and down.Revenge
	return rv ~= nil and (rv.Status == "buying" or rv.Status == "playing")
end

-- set by TrollEffects: can this down's revenge be bought right now? (the attackers still riding
-- and explodable, nothing else under way)
DeathManager.RevengeOpen = nil

---------------------------------------------------------------- saved revives
-- A revive bought but not used (see REVIVE) is kept in the player's save, through
-- SettingsServer's PlayerData (server only), and spent by their next REVIVE.
local credits = {}   -- [player] = count, once read
local locks   = {}   -- [player] = true while their count is being changed

local function dataApi()
	local settings = ServerScriptService:FindFirstChild("SettingsServer")
	return settings and settings:FindFirstChild("PlayerData")
end

local function show(player)
	if player.Parent then player:SetAttribute(CREDIT_ATTR, credits[player]) end
end

local function creditsOf(player)
	if credits[player] == nil then
		local api = dataApi()
		local ok, value, state = false, nil, nil
		if api then ok, value, state = pcall(api.Get.Invoke, api.Get, player, CREDIT_KEY) end
		-- their save didn't load: the real count is unknown, so it isn't guessed (a 0 saved over
		-- it would wipe what they have). Nothing is written; it's read again next time.
		if not ok or state == "failed" or state == "invalid" then return 0, false end
		-- (read by someone else while this one waited: that one stands)
		if credits[player] == nil and player.Parent then
			credits[player] = math.max(0, math.floor(tonumber(ok and value or nil) or 0))
			show(player)
		end
	end
	return credits[player] or 0, credits[player] ~= nil
end

-- the count changed by `by` and saved at once: true only once it is stored
local function changeCredits(player, by)
	while locks[player] do task.wait() end
	locks[player] = true
	local ok, stored = pcall(function()
		local api = dataApi()
		if not api then return false end
		local have, known = creditsOf(player)
		if not known then return false end   -- (their save didn't load: never written over)
		local n = have + by
		if n < 0 then return false end
		local saved = api.SaveNow:Invoke(player, CREDIT_KEY, n)
		if saved then credits[player] = n; show(player) end
		return saved
	end)
	locks[player] = nil
	if not ok then warn("[Scooter] revive credits: " .. tostring(stored)) end
	return ok and stored == true
end

Players.PlayerRemoving:Connect(function(player) credits[player] = nil end)

---------------------------------------------------------------- infinite revives
local infinite = {}   -- [player] = true / false, once read

local function infiniteOf(player)
	if infinite[player] == nil then
		local api = dataApi()
		local ok, value, state = false, nil, nil
		if api then ok, value, state = pcall(api.Get.Invoke, api.Get, player, INF_KEY) end
		if not ok or state == "failed" or state == "invalid" then return false, false end   -- unknown: read again next time
		if infinite[player] == nil and player.Parent then
			infinite[player] = value == true
			player:SetAttribute(INF_ATTR, infinite[player] or nil)
		end
	end
	return infinite[player] == true, infinite[player] ~= nil
end
Players.PlayerRemoving:Connect(function(player) infinite[player] = nil end)

-- A 5x / infinite reward: `key` set to `value` in the SAME write as the receipt's PurchaseId
-- (the Set marks the list to go with the SaveNow that follows), so a receipt offered again
-- finds its id and is never rewarded twice. "granted", "duplicate", or false (not stored:
-- both put back as they were, and Roblox offers the receipt again). Called holding the lock.
local function grantOnce(player, receiptId, key, value, before)
	local api = dataApi()
	if not api then return false end
	local ok, list, state = pcall(api.Get.Invoke, api.Get, player, RECEIPTS_KEY)
	if not ok or state == "failed" or state == "invalid" then return false end
	local old = type(list) == "table" and table.clone(list) or {}
	if table.find(old, receiptId) then return "duplicate" end
	local new = table.clone(old)
	table.insert(new, receiptId)
	while #new > RECEIPTS_MAX do table.remove(new, 1) end
	api.Set:Invoke(player, RECEIPTS_KEY, new)
	if api.SaveNow:Invoke(player, key, value) then return "granted" end
	api.Set:Invoke(player, RECEIPTS_KEY, old)   -- not stored: nothing half-written later
	api.Set:Invoke(player, key, before)
	return false
end

-- `n` saved revives for this receipt (5x)
local function creditsForReceipt(player, n, receiptId)
	while locks[player] do task.wait() end
	locks[player] = true
	local ok, result = pcall(function()
		local have, known = creditsOf(player)
		if not known then return false end
		local r = grantOnce(player, receiptId, CREDIT_KEY, have + n, have)
		if r == "granted" then credits[player] = have + n; show(player) end
		return r
	end)
	locks[player] = nil
	if not ok then warn("[Scooter] 5x revives: " .. tostring(result)) return false end
	return result
end

-- infinite revives for this receipt
local function infiniteForReceipt(player, receiptId)
	while locks[player] do task.wait() end
	locks[player] = true
	local ok, result = pcall(function()
		local had = infiniteOf(player)
		local r = grantOnce(player, receiptId, INF_KEY, true, had or nil)
		if r == "granted" or r == "duplicate" then
			infinite[player] = true
			if player.Parent then player:SetAttribute(INF_ATTR, true) end
		end
		return r
	end)
	locks[player] = nil
	if not ok then warn("[Scooter] infinite revives: " .. tostring(result)) return false end
	return result
end

-- Saved revives from elsewhere (the Daily Rewards calendar): the same count REVIVE spends
-- and shows. True once saved.
function DeathManager.GiveRevives(player, n)
	return changeCredits(player, n)
end

-- read on joining, so REVIVE's count is right from the first death
local function preload(player)
	local settings = ServerScriptService:WaitForChild("SettingsServer", 10)
	if settings then settings:WaitForChild("PlayerData", 10) end
	creditsOf(player)
	infiniteOf(player)
end
Players.PlayerAdded:Connect(function(player) task.spawn(preload, player) end)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(preload, player) end

---------------------------------------------------------------- telling the riders
-- Both riders get the same state: the countdown (running: when it ends; held: what is left),
-- the SKIP votes and the revive - who is buying it (them or their partner), whether it is
-- being done, and whether REVIVE is free for them.
local function send(ride)
	local down, list = ride.Down, riders(ride)
	if not down then return end
	local rv = down.Revenge
	local revStatus
	if rv then
		revStatus = rv.Status
		if revStatus == "ready" then
			local ok, open = pcall(function() return DeathManager.RevengeOpen and DeathManager.RevengeOpen(ride, down) end)
			if not (ok and open) then revStatus = "unavailable" end
			rv.LastOpen = revStatus == "ready"
		end
	end
	for _, plr in ipairs(list) do
		if present(plr) then
			Remotes.DeathState:FireClient(plr, {
				Revenge  = rv and {
					By     = rv.By,
					UserId = rv.UserId,
					Status = revStatus,   -- ready | unavailable | buying | playing | used
					Buying = rv.Status == "buying" and ((rv.Buyer == plr and "self") or "partner") or nil,
					Watch  = rv.Status == "playing" and rv.Watch or nil,
				} or nil,
				Active   = true,
				EndsAt   = down.EndsAt,
				Left     = down.Left,
				Skips    = votesOf(down),
				Needed   = #list,
				Voted    = down.Votes[plr] == true,
				Buying   = (down.Buyer == plr and "self") or (down.Buyer and "partner") or nil,
				BuyingKind = down.Buyer and down.Kind or nil,   -- revive | five | infinite
				Reviving = down.Reviving or nil,
				Free     = ((credits[plr] or 0) > 0 or infinite[plr] == true) or nil,
				Infinite = infinite[plr] == true or nil,
			})
		end
	end
end

---------------------------------------------------------------- the countdown
local function arm(ride, down)
	down.Gen += 1
	local gen = down.Gen
	task.delay(math.max(down.EndsAt - workspace:GetServerTimeNow(), 0), function()
		if ride.Down == down and down.Gen == gen and not ride._ended then
			DeathManager.Finish(ride, "death timer ran out")
		end
	end)
end

-- it stands still (a revive is being bought or done)...
local function hold(down)
	if not down.EndsAt then return end
	down.Left = math.max(down.EndsAt - workspace:GetServerTimeNow(), 0)
	down.EndsAt = nil
	down.Gen += 1                          -- the running timer is called off
end

-- ...and carries on, with at least RESUME_MIN s left to choose
local function resume(ride, down)
	if down.EndsAt or ride.Down ~= down or ride._ended or down.Reviving or revengeBusy(down) then return end
	down.EndsAt = workspace:GetServerTimeNow() + math.max(down.Left or 0, RESUME_MIN)
	down.Left = nil
	arm(ride, down)
end

-- The purchase under way is over without a revive: the message goes, the countdown carries
-- on. `token` names that purchase, so a late call about an older one does nothing.
local function giveUp(ride, down, token)
	if ride.Down ~= down or ride._ended or down.Reviving or down.Token ~= token then return end
	down.Buyer, down.Paid, down.Kind = nil, false, nil
	down.Token += 1
	resume(ride, down)
	send(ride)
	-- everyone had voted to skip meanwhile
	if votesOf(down) >= #riders(ride) and not revengeBusy(down) then DeathManager.Finish(ride, "both riders skipped") end
end

---------------------------------------------------------------- the revive
local function revive(ride, down)
	local placed
	local ok, err = pcall(function()
		local cf, info = ReviveSpot.Find(ride, down.Incident)
		if not cf then error("no safe spot found") end
		if ride._ended or ride.Down ~= down then error("the ride ended") end
		RideManager.Relaunch(ride, function()
			-- the last look before the scooter appears: still clear? (someone may have driven in)
			local safe, why = ReviveSpot.StillSafe(cf, ride)
			if not safe then
				log("revive spot taken meanwhile (" .. tostring(why) .. "): looking again")
				local again, info2 = ReviveSpot.Find(ride, down.Incident)
				if again then cf, info = again, info2 end
			end
			return cf
		end)
		placed = info
	end)
	if ride._ended then return false end         -- a rider left meanwhile: the ride is over anyway
	if not ok then
		warn("[Scooter] revive failed: " .. tostring(err))
		DeathManager.Finish(ride, "revive failed")
		return false
	end
	ReviveSpot.Relaunched(ride, placed and placed.s)
	ride.Down = nil
	ride.Doomed = nil
	ride.Life = (ride.Life or 0) + 1
	ride.GraceUntil = os.clock() + GRACE
	for _, plr in ipairs(riders(ride)) do
		if present(plr) then Remotes.DeathState:FireClient(plr, { Active = false, Revived = true }) end
	end
	if placed then
		log(("ride at station %s revived %s"):format(tostring(ride.StationId),
			placed.lot and ("in checkpoint " .. placed.lot .. "'s lot")
				or ("%.0f studs back (%.0f studs along the course)"):format(placed.back or 0, placed.s or 0)))
	end
	return true
end

-- `buyer`: who paid for it (they keep it for next time if it can't be done; not when
-- `noRefund`: an infinite revive, which cost nothing)
local function startRevive(ride, down, buyer, why, noRefund)
	if down.Reviving then return end
	down.Reviving = true
	down.Buyer, down.Paid, down.Kind = nil, false, nil
	down.Token += 1
	hold(down)
	send(ride)
	log(buyer and buyer.Name or "?", "revives the ride at station", ride.StationId, "(" .. why .. ")")
	task.spawn(function()
		if not revive(ride, down) and buyer and buyer.Parent and not noRefund then
			if changeCredits(buyer, 1) then
				Remotes.Notice:FireClient(buyer, FAILED_NOTICE)
			else
				warn("[Scooter] a revive " .. buyer.Name .. " paid for failed and couldn't be saved for later")
			end
		end
	end)
end

---------------------------------------------------------------- death log
-- Every ride that goes down is logged as a "Death" custom event (Creator Hub -> Analytics ->
-- Custom Events), so the obstacles that end the most runs can be found:
--   CustomField01  what brought it down: the obstacle's script (its folder in Workspace),
--                  plus `source` when one is passed
--   CustomField02  the area under the scooter (its model in Workspace). Over nothing (it went
--                  over the edge, e.g. into the water): the last area it was on, sampled every
--                  AREA_EVERY s while the ride is up; "Fell off" only if it was never on one.
--   CustomField03  the world (WorldConfig.Name)
-- Only live servers report. It never affects the ride.
local okWorld, WorldConfig = pcall(function() return require(RS:WaitForChild("WorldConfig", 5)) end)
local WORLD = (okWorld and type(WorldConfig) == "table" and WorldConfig.Name) or "?"
local SCRIPT_NAMES = { Main = "Respawn button", TrollShow = "Troll effect" }

-- the script that called Hit (`level`: Hit's caller; HitPlayer and engine frames are looked past)
local function killerOf(level, source)
	local path
	for l = level, level + 4 do
		local s = debug.info(l, "s")
		if not s then break end
		if s ~= "[C]" and not s:find("DeathManager$") then path = s break end
	end
	local parts = string.split(path or "?", ".")
	local name = parts[#parts]
	if parts[1] == "Workspace" and #parts >= 3 then name = parts[#parts - 1] end
	name = SCRIPT_NAMES[name] or name
	if typeof(source) == "Instance" then name ..= " - " .. source.Name end
	return name
end

-- the model the scooter is over (a folder in Workspace, e.g. Roads, gives its child instead)
local function areaOf(ride)
	local scooter = ride.Scooter
	if typeof(scooter) ~= "Instance" or not scooter.Parent then return "?" end
	local exclude = { scooter }
	for _, plr in ipairs(riders(ride)) do
		if present(plr) and plr.Character then table.insert(exclude, plr.Character) end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.RespectCanCollide = true
	local hit = workspace:Raycast(scooter:GetPivot().Position + Vector3.new(0, 5, 0), Vector3.new(0, -80, 0), params)
	if not hit then return "Fell off" end
	if hit.Instance == workspace.Terrain then return "Terrain" end
	local below, top = nil, hit.Instance
	while top.Parent and top.Parent ~= workspace do below, top = top, top.Parent end
	if top.Parent ~= workspace then return "?" end
	if top:IsA("Folder") and below then top = below end
	return top.Name
end

-- where each ride last was ON something (ride.LastArea), for deaths over nothing
local AREA_EVERY = 0.5
task.spawn(function()
	while true do
		task.wait(AREA_EVERY)
		for _, ride in pairs(RideManager.Rides) do
			if type(ride) == "table" and not ride.Down and not ride._ended then
				local ok, area = pcall(areaOf, ride)
				if ok and area ~= "Fell off" and area ~= "?" then ride.LastArea = area end
			end
		end
	end
end)

local function logDeath(ride, killer)
	local okArea, area = pcall(areaOf, ride)
	area = okArea and area or "?"
	if (area == "Fell off" or area == "?") and type(ride.LastArea) == "string" then area = ride.LastArea end
	local player = riders(ride)[1]
	if not present(player) then return end
	task.spawn(pcall, AnalyticsService.LogCustomEvent, AnalyticsService, player, "Death", 1, {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = tostring(killer),
		[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = tostring(area),
		[Enum.AnalyticsCustomFieldKeys.CustomField03.Name] = tostring(WORLD),
	})
	log("death logged:", killer, "/", area, "/", WORLD)
end

---------------------------------------------------------------- the run
-- The water or an obstacle caught this ride (or one of its riders). Once per life of the
-- ride. `source` (optional): the obstacle - a new one is learned by ReviveSpot, so revives
-- keep clear of it. `life` (optional): the life Claim returned; a Hit for an earlier life
-- (the ride has been revived since) does nothing.
-- `cause` (optional, TrollShow): { Kind = "RideExplode", AttackerRide, ByName, ByUserId } when
-- another riding duo exploded them (it offers REVENGE), or { Kind = "Revenge" } for a revenge.
function DeathManager.Hit(ride, source, life, cause)
	if not ride or ride._ended or ride.Down then return end
	if life ~= nil and life ~= (ride.Life or 0) then return end
	if ride.GraceUntil and os.clock() < ride.GraceUntil then return end   -- just revived
	pcall(ReviveSpot.Learn, source)
	local down = {
		EndsAt   = workspace:GetServerTimeNow() + SECONDS,
		Votes    = {},
		Late     = {},      -- [player] = true: a receipt of theirs still revives this down
		Gen      = 0,       -- the countdown's current timer
		Token    = 0,       -- the purchase under way
		Incident = ReviveSpot.Incident(ride),   -- studs along the course where the trouble started
		Cause    = type(cause) == "table" and cause or nil,
	}
	if down.Cause and down.Cause.Kind == "RideExplode" and type(down.Cause.AttackerRide) == "table" then
		down.Revenge = {
			Status = "ready",                 -- ready | buying | playing | used (TrollEffects)
			By     = down.Cause.ByName,       -- the player who bought the explode
			UserId = down.Cause.ByUserId,
			Target = down.Cause.AttackerRide, -- their ride: the duo the revenge goes to
			Token  = 0,
		}
	end
	ride.Down = down
	ride.Doomed = true
	logDeath(ride, (down.Cause and down.Cause.Kind == "Revenge") and "Revenge" or killerOf(3, source))
	-- no more driving; the scooter sinks where it went in
	if ride.Controller then
		pcall(function() ride.Controller:SetSteer(0); ride.Controller:SetThrottle("coast") end)
	end
	RideManager.SilenceHorn(ride)   -- and no horn
	-- both riders die for real, together (ride.Down is set first, so Main keeps
	-- them down until the run ends)
	for _, plr in ipairs(riders(ride)) do
		local ch  = present(plr) and plr.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then hum.Health = 0 end
	end
	log("ride at station", ride.StationId, "went down", typeof(source) == "Instance" and ("(" .. source.Name .. ")") or "")
	send(ride)
	arm(ride, down)
	-- is REVIVE free for them? (read once from their save)
	for _, plr in ipairs(riders(ride)) do
		if present(plr) and credits[plr] == nil then
			task.spawn(function()
				creditsOf(plr)
				if ride.Down == down and (credits[plr] or 0) > 0 then send(ride) end
			end)
		end
	end
end

function DeathManager.HitPlayer(player, source)
	DeathManager.Hit(RideManager.PlayerRide[player], source)
end

-- for TrollEffects' REVENGE: tell both riders, hold / carry on the countdown, and end the run
-- if both had voted to skip while it was being bought
function DeathManager.Send(ride) if ride then send(ride) end end
function DeathManager.HoldDown(ride) if ride and ride.Down then hold(ride.Down) end end
function DeathManager.ResumeDown(ride) if ride and ride.Down then resume(ride, ride.Down) end end
function DeathManager.CheckSkips(ride)
	local down = ride and ride.Down
	if down and not ride._ended and not down.Buyer and not down.Reviving and not revengeBusy(down)
		and votesOf(down) >= #riders(ride) then
		DeathManager.Finish(ride, "both riders skipped")
	end
end

-- An obstacle that will bring this ride down in a moment (it throws the scooter first)
-- takes it now: the life number to hand to Hit later, or nil if the ride is not there to
-- take (down, already taken, just revived). Once per life of the ride.
function DeathManager.Claim(ride)
	if not ride or ride._ended or ride.Down or ride.Doomed then return nil end
	if ride.GraceUntil and os.clock() < ride.GraceUntil then return nil end
	ride.Doomed = true
	return ride.Life or 0
end

-- one vote per rider; the run ends once every rider has voted
function DeathManager.Skip(player)
	local ride = RideManager.PlayerRide[player]
	local down = ride and ride.Down
	if not down or ride._ended or down.Votes[player] or down.Reviving then return end
	if down.Revenge and down.Revenge.Status == "playing" then return end   -- watching it: no votes
	down.Votes[player] = true
	send(ride)
	-- a purchase still open (a revive or a revenge) is let run: if it is given up, the run ends
	-- then (giveUp / TrollEffects)
	if votesOf(down) >= #riders(ride) and not down.Buyer and not revengeBusy(down) then
		DeathManager.Finish(ride, "both riders skipped")
	end
end

function DeathManager.Finish(ride, reason)
	if not ride or ride._ended then return end
	local list = riders(ride)
	RideManager.End(ride, reason)
	for _, plr in ipairs(list) do
		if present(plr) then
			Remotes.DeathState:FireClient(plr, { Active = false })
			-- the dead respawn in the lobby now that the run is over (Main); anyone
			-- still alive is sent there
			local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then RideManager.SendHome(plr) end
		end
	end
end

---------------------------------------------------------------- REVIVE
local lastAsk = {}
Players.PlayerRemoving:Connect(function(player) lastAsk[player] = nil end)

-- the Developer Product a purchase of this kind opens
local function productOf(kind)
	return (kind == "five" and FIVE_PRODUCT) or (kind == "infinite" and INF_PRODUCT) or PRODUCT
end

-- REVIVE pressed on the popup (Remotes.ReviveRequest), or (`kind` "five" / "infinite") one
-- of the two offers under it.
function DeathManager.RequestRevive(player, kind)
	if kind ~= nil and kind ~= "five" and kind ~= "infinite" then return end
	local ride = RideManager.PlayerRide[player]
	local down = ride and ride.Down
	if not down or ride._ended or down.Reviving then return end
	if player ~= ride.Driver and player ~= ride.Passenger then return end
	local now = os.clock()
	if now - (lastAsk[player] or 0) < ASK_GAP then return end
	lastAsk[player] = now
	-- one purchase per ride at a time (the popup shows who is buying); none while a revenge is
	-- being bought or played
	if down.Buyer or revengeBusy(down) then send(ride) return end
	-- the offers only come with a death that has no revenge, and not for someone who already
	-- has infinite revives (their REVIVE is free)
	if kind and (down.Revenge or infinite[player] == true) then send(ride) return end
	down.Votes[player] = nil                 -- asking for a revive takes back their SKIP
	down.Buyer = player
	down.Kind = kind or "revive"
	down.Token += 1
	local token = down.Token
	hold(down)
	send(ride)

	if not kind then
		-- infinite revives: free, and nothing spent (any saved revives are kept)
		if infiniteOf(player) then
			if ride.Down == down and not ride._ended and down.Token == token then
				startRevive(ride, down, player, "infinite revives", true)
			end
			return
		end
		-- a revive they bought earlier and couldn't use: spent now, no purchase
		if creditsOf(player) > 0 and changeCredits(player, -1) then
			if ride.Down == down and not ride._ended and down.Token == token then
				startRevive(ride, down, player, "a saved revive")
			else
				changeCredits(player, 1)         -- nothing to use it on after all: kept
			end
			return
		end
	end
	if ride.Down ~= down or ride._ended or down.Token ~= token then return end
	local product = productOf(kind)
	if product == 0 then
		warn("[Death] REVIVE: set Config's revive Developer Product ids (" .. tostring(kind or "revive") .. ")")
		giveUp(ride, down, token)
		return
	end
	local ok, err = pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, player, product)
	if not ok then
		warn("[Scooter] couldn't open the revive purchase for " .. player.Name .. ": " .. tostring(err))
		giveUp(ride, down, token)
		return
	end
	-- left open, the countdown doesn't wait for ever. A receipt that still comes while the
	-- ride is down revives it; after that it is kept for next time.
	task.delay(HOLD_MAX, function()
		if down.Token == token then
			down.Late[player] = true
			giveUp(ride, down, token)
		end
	end)
end

-- The purchase window closed (MarketplaceService.PromptProductPurchaseFinished). Bought:
-- Roblox's receipt is on its way (it revives) and the countdown keeps waiting for it; not
-- bought, or it errored: the countdown carries on.
function DeathManager.OnPromptFinished(player, productId, purchased)
	local ride = RideManager.PlayerRide[player]
	local down = ride and ride.Down
	if not down or ride._ended or down.Reviving or down.Buyer ~= player then return end
	local product = productOf(down.Kind)
	if product == 0 or productId ~= product then return end   -- (another product's window)
	local token = down.Token
	-- the window can close and the purchase still go through: its receipt still revives
	down.Late[player] = true
	if purchased then
		if down.Paid then return end
		down.Paid = true
		send(ride)
		task.delay(RECEIPT_WAIT, function()
			if down.Token == token then giveUp(ride, down, token) end
		end)
	else
		giveUp(ride, down, token)
	end
end

-- the buyer's own screen saying the window closed without a purchase (a backup for the
-- server's event: a client can only ever give up its own purchase with it)
function DeathManager.PromptClosed(player)
	local ride = RideManager.PlayerRide[player]
	local down = ride and ride.Down
	DeathManager.OnPromptFinished(player, productOf(down and down.Kind), false)
end

local handled = {}   -- [PurchaseId] = true: receipts this server has dealt with already

-- Roblox's receipt for a revive (DonationHandler's ProcessReceipt hands these here). It
-- revives the buyer's ride if that is down and waiting for this purchase; otherwise the
-- revive is saved for their next REVIVE. PurchaseGranted once one of those has happened.
function DeathManager.ProcessReviveReceipt(receipt)
	local id = tostring(receipt.PurchaseId)
	if handled[id] then return Enum.ProductPurchaseDecision.PurchaseGranted end
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end   -- offered again when they're back
	local ride = RideManager.PlayerRide[player]
	local down = ride and ride.Down
	-- the other rider, for the log
	local partner
	if ride then
		local other = ride.Driver == player and ride.Passenger or ride.Driver
		if typeof(other) == "Instance" and other:IsA("Player") then
			partner = ("%s (@%s)"):format(other.DisplayName, other.Name)
		end
	end
	if down and not ride._ended and not down.Reviving and (down.Buyer == player or down.Late[player]) then
		handled[id] = true
		startRevive(ride, down, player, "bought")
		ReviveWebhook.Log(receipt, "Revived the ride", partner)   -- in the background
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	if changeCredits(player, 1) then
		handled[id] = true
		ReviveWebhook.Log(receipt, "Nothing to revive - saved as a free revive", partner)
		log(player.Name, "bought a revive with nothing to revive: saved for their next REVIVE")
		Remotes.Notice:FireClient(player, SAVED_NOTICE)
		if ride and ride.Down then send(ride) end   -- REVIVE is free for them now
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

function DeathManager.IsRevivePack(productId)
	return productId ~= 0 and (productId == FIVE_PRODUCT or productId == INF_PRODUCT)
end

-- Roblox's receipt for 5x REVIVES or INFINITE REVIVES (DonationHandler hands these here).
-- The reward is the BUYER's alone and is saved with the receipt's id first (a receipt offered
-- again is recognised: "duplicate", nothing more given); then, if their ride is still down
-- and waiting for this purchase, it is revived. PurchaseGranted only once the reward is stored.
function DeathManager.ProcessPackReceipt(receipt)
	local id = tostring(receipt.PurchaseId)
	if handled[id] then return Enum.ProductPurchaseDecision.PurchaseGranted end
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end   -- offered again when they're back
	local five = receipt.ProductId == FIVE_PRODUCT
	local ride = RideManager.PlayerRide[player]
	local down = ride and ride.Down
	local function waiting()
		return ride ~= nil and down ~= nil and ride.Down == down and not ride._ended and not down.Reviving
			and (down.Buyer == player or down.Late[player] == true)
	end
	local partner
	if ride then
		local other = ride.Driver == player and ride.Passenger or ride.Driver
		if typeof(other) == "Instance" and other:IsA("Player") then
			partner = ("%s (@%s)"):format(other.DisplayName, other.Name)
		end
	end

	-- 5x: four saved and one used now - or all five saved when there's nothing to revive
	local reviveNow = waiting()
	local result
	if five then
		result = creditsForReceipt(player, reviveNow and FIVE_SAVED or FIVE_SAVED + 1, id)
	else
		result = infiniteForReceipt(player, id)
	end
	if result == "duplicate" then
		handled[id] = true
		log(player.Name, "'s", five and "5x" or "infinite", "revives receipt was rewarded already")
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	if result ~= "granted" then return Enum.ProductPurchaseDecision.NotProcessedYet end
	handled[id] = true

	local notice = five and FIVE_NOTICE or INF_NOTICE
	local function report(outcome) if not receipt.StudioTest then ReviveWebhook.Log(receipt, outcome, partner) end end
	if reviveNow and waiting() then
		startRevive(ride, down, player, five and "5x revives" or "infinite revives")
		report(five and "5x Revives: revived the ride + 4 saved" or "Infinite Revives: revived the ride")
	else
		-- nothing to revive (any more): the reward alone. A 5x that counted on reviving now and
		-- lost the ride while it was being saved gets its fifth saved too.
		if five and reviveNow and not changeCredits(player, 1) then
			warn("[Scooter] " .. player.Name .. "'s 5x revives: the fifth couldn't be saved")
		end
		if five then notice = FIVE_SAVED_NOTICE end
		report(five and "5x Revives: nothing to revive - 5 saved" or "Infinite Revives: unlocked (nothing to revive)")
		if ride and ride.Down then send(ride) end   -- REVIVE is free for them now
	end
	Remotes.Notice:FireClient(player, notice)
	log(player.Name, "bought", five and "5x revives" or "infinite revives")
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Studio only (never in a live server): ServerStorage.ReviveStudioTest:Invoke(action, ...) from
-- the command bar (Server view) while testing the popup and its offers alone:
--   "ride", player, at              a solo ride for them at the CFrame `at`
--   "hit", player, revenge?         their ride goes down (with a revenge section if true)
--   "receipt", player, kind, id     a 5x / infinite receipt (kind "five" / "infinite") with
--                                   PurchaseId `id` - give the same id twice to try a retry
--   "state", player                 { credits, infinite, down, reviving }
--   "reset", player                 saved revives 0, infinite off, no receipts (the tester's real
--                                   save when Studio has API access: note theirs first)
if game:GetService("RunService"):IsStudio() and not game:GetService("ServerStorage"):FindFirstChild("ReviveStudioTest") then
	local hook = Instance.new("BindableFunction")
	hook.Name = "ReviveStudioTest"
	hook.OnInvoke = function(action, player, a, b)
		if action == "ride" then
			local pad = Instance.new("Part")
			pad.Name, pad.Anchored, pad.Transparency, pad.CanCollide = "ReviveTestPad", true, 1, false
			pad.CFrame = a
			pad.Parent = workspace
			local ride, err = RideManager.Begin("ReviveTest", player, nil, nil, pad)
			pad:Destroy()
			return ride ~= nil, err
		elseif action == "hit" then
			local ride = RideManager.PlayerRide[player]
			DeathManager.Hit(ride, nil, nil, a and { Kind = "RideExplode", AttackerRide = {}, ByName = "Tester", ByUserId = 1 } or nil)
			return ride ~= nil and ride.Down ~= nil
		elseif action == "receipt" then
			local decision = DeathManager.ProcessPackReceipt({ PurchaseId = b, PlayerId = player.UserId, StudioTest = true,
				ProductId = a == "five" and FIVE_PRODUCT or INF_PRODUCT })
			return decision.Name
		elseif action == "state" then
			local ride = RideManager.PlayerRide[player]
			return { credits = creditsOf(player), infinite = infiniteOf(player), down = ride ~= nil and ride.Down ~= nil,
				reviving = ride ~= nil and ride.Down ~= nil and ride.Down.Reviving == true }
		elseif action == "reset" then
			local api = dataApi()
			credits[player], infinite[player] = 0, false   -- (first: a long save can outlast the caller)
			api.Set:Invoke(player, CREDIT_KEY, 0)
			api.Set:Invoke(player, RECEIPTS_KEY, {})
			api.SaveNow:Invoke(player, INF_KEY, false)   -- (nil is never written: false is "none")
			show(player)
			player:SetAttribute(INF_ATTR, nil)
			return true
		end
	end
	hook.Parent = game:GetService("ServerStorage")
end

return DeathManager
