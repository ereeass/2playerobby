--=====================================================================
-- ScooterSelection   (server)
--
-- Which scooter each player rides, and whether they may. The client only ever
-- ASKS (Remotes.GetScooters / Remotes.EquipScooter); every answer is decided here.
--
--   Registry  ReplicatedStorage.ScooterSystem.Shared.Scooters
--   Models    ServerStorage.ScooterModels: the working scooters, server only.
--             The menu gets visual-only copies (ReplicatedStorage.ScooterSystem.
--             ScooterPreviews), made here at start: visible parts, anchored, with
--             no hitboxes, joints, sounds or tuning.
--   Saved     in the player's save, through SettingsServer's PlayerData bindables:
--             SelectedScooter (an Id) and OwnedScooters (Ids bought with products, or
--             claimed from the Daily Rewards calendar: GrantDaily).
--   Limited   a DailyReward scooter (the Bee) is only ever had from its calendar day;
--             its card's LIMITED pill asks RewardAction, which says where it comes from.
--   Rides     RideManager.Begin spawns TemplateFor(driver): the team rides the
--             DRIVER's scooter, whatever the passenger picked.
--   Groups    a group's scooter offers Roblox's join prompt on its card (ScootersUI.Menu);
--             when that says they joined, the server looks afresh (GroupService), so the
--             scooter unlocks without a rejoin.
--   Rewards   a GroupReward scooter (the Ice Scooter): "join the group, like the game,
--             rejoin". Roblox can't tell a game whether someone liked it, so the server
--             checks what it can: they are in the group AND this is a later session than
--             the one in which they were ASKED to like the game and rejoin (GroupAsked,
--             saved): their card / the podium, tapped while in the group, shows that ask.
--             Only that ask counts - just being seen in the group never does - so nobody
--             gets it without being told to like and rejoin first. Whether they are in the group counts ONLY as
--             it was when the session started (member, asked afresh then): joining
--             during a session never unlocks or grants anything - not even a reward
--             they already own (someone who left and came back rejoins for it too).
--             It is granted in ONE place only, grantReward, and only when a session
--             starts (the rejoin) - never by a button, a remote, or opening the menu.
--             The lobby podium and the scooter's card both use RewardAction
--             (Remotes.RewardAction), which can't grant anything: it looks the player
--             up and says so (join the group / rejoin / already yours). A grant is
--             saved in OwnedScooters for good; riding it also needs them in the group
--             when the session started, and still in it (looked at every GROUP_WATCH s:
--             leaving mid-game locks it at once). GroupAsked is forgotten when they are seen
--             outside the group, so an old ask can't stand in for a new join.
--   Studio    the SimulateNotInGroup attribute on this module plays everyone as outside
--             the group until that prompt says they joined (untick it for the rejoin).
--             StudioResetReward: set it to any new text and the next session in Studio
--             forgets the tester's group rewards and GroupAsked ONCE, like an account
--             that never tried them (the text is remembered, so rejoins keep them).
--             Live servers ignore both.
--   Testers   the UserIds in TESTERS may ride EVERY scooter in the registry (every card
--             says SELECT), new ones included, for testing in game. Nothing is saved for
--             it: take someone off the list and they're back to what they really own.
--
-- A selection is always a scooter the player may ride: a missing, unknown or
-- no-longer-unlocked pick becomes Scooters.DefaultId, and the save is corrected
-- (unless loading it failed, when the stored value is left alone).
--=====================================================================

local Players             = game:GetService("Players")
local MarketplaceService  = game:GetService("MarketplaceService")
local GroupService        = game:GetService("GroupService")
local RunService          = game:GetService("RunService")
local BadgeService        = game:GetService("BadgeService")
local ServerStorage       = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService         = game:GetService("HttpService")
local RS                  = game:GetService("ReplicatedStorage")

local Root     = RS:WaitForChild("ScooterSystem")
local Remotes  = Root:WaitForChild("Remotes")
local Shared   = Root:WaitForChild("Shared")
local Scooters = require(Shared:WaitForChild("Scooters"))
local Config   = require(Shared:WaitForChild("Config"))

local RECHECK_AFTER = 30     -- seconds an unlock answer is trusted before asking Roblox again
local EQUIP_GAP     = 0.35   -- seconds between equip requests from one player
local LOAD_WAIT     = 20     -- seconds a request waits for the player's save to load
local JOIN_GAP      = 1      -- seconds between fresh group looks for one player

local OWNED_NOTICE  = "You already own this item"
local JOINED_NOTICE = "Joined! Now like the game and rejoin to get your Ice Scooter."
local REJOIN_NOTICE = "Like the game, then rejoin to get your Ice Scooter!"
local BACK_NOTICE   = "Welcome back to the group! Rejoin to ride your Ice Scooter again."
local GROUP_WATCH   = 60     -- seconds between looks at whether an Ice owner is still in its group
local DAILY_NOTICE  = "This item can be obtained from the Daily Rewards."

-- the owners, testing skins in game: every scooter is theirs to ride (see the header)
local TESTERS = {
	[476180958]  = true,   -- Vexerixx
	[7415418006] = true,   -- Ereeass
}

local ScooterSelection = {}

function ScooterSelection.IsTester(player)
	return TESTERS[player.UserId] == true
end

local function log(...) if Config.DebugLogging then print("[Scooter]", ...) end end

--------------------------------------------------------------------- unlocks
-- The future progress system (checkpoints reached, worlds completed) plugs in here.
ScooterSelection.Progress = {
	HasCheckpoint     = function(player, checkpoint) return false end,
	HasCompletedWorld = function(player, world) return false end,
}

-- Studio only (see the header): does this player play as outside the group?
local function studioGuest(st)
	return RunService:IsStudio() and script:GetAttribute("SimulateNotInGroup") == true
		and not (st and st.simJoined)
end

-- Player:GetRankInGroup keeps its answer for a minute, so someone who has just joined
-- through the prompt can still read as a guest. Once they have joined this session,
-- GroupService is asked afresh (at most once a JOIN_GAP; 0 otherwise).
local function freshRank(player, st, groupId)
	if not (st and st.joined[groupId]) or os.clock() - st.freshAt < JOIN_GAP then return 0 end
	st.freshAt = os.clock()
	for _, g in ipairs(GroupService:GetGroupsAsync(player.UserId)) do
		if g.Id == groupId then return g.Rank end
	end
	return 0
end

local function inGroup(p, u, st)
	if studioGuest(st) then return false end
	-- seen leaving this session (watchGroups): GetRankInGroup still keeps "member", so they
	-- count as outside until the join prompt says they joined again
	if st and st.left[u.GroupId] and not st.joined[u.GroupId] then return false end
	local min = u.MinRank or 1
	return p:GetRankInGroup(u.GroupId) >= min or freshRank(p, st, u.GroupId) >= min
end

-- Was this player in a reward's group when their session started? Asked once, from
-- load, and afresh (GroupService) rather than from GetRankInGroup's kept answer, so
-- someone back on the same server after joining is seen as they are now. Nothing later
-- in the session changes the answer.
local function memberAtStart(player, st, u)
	if studioGuest(st) then return false end
	local min = u.MinRank or 1
	local ok, groups = pcall(GroupService.GetGroupsAsync, GroupService, player.UserId)
	if ok and type(groups) == "table" then
		for _, g in ipairs(groups) do
			if g.Id == u.GroupId then return g.Rank >= min end
		end
		return false
	end
	local ok2, rank = pcall(player.GetRankInGroup, player, u.GroupId)
	if ok2 then return rank >= min end
	warn(("[Scooter] couldn't look up %s in group %d: %s"):format(player.Name, u.GroupId, tostring(rank)))
	return false
end

-- (player, unlock, session, definition) -> true when the player may ride it
local Checks = {
	Free       = function() return true end,
	Group      = inGroup,
	GroupReward = function(p, u, st, def) return st.owned[def.Id] == true and st.member[tostring(u.GroupId)] == true end,
	GamePass   = function(p, u) return MarketplaceService:UserOwnsGamePassAsync(p.UserId, u.GamePassId) end,
	Badge      = function(p, u) return BadgeService:UserHasBadgeAsync(p.UserId, u.BadgeId) end,
	Product    = function(_, _, st, def) return st.owned[def.Id] == true end,
	DailyReward = function(_, _, st, def) return st.owned[def.Id] == true end,
	Limited    = function(_, _, st, def) return st.owned[def.Id] == true end,
	Archived   = function(_, _, st, def) return st.owned[def.Id] == true end,   -- no longer sold: owners keep it
	Checkpoint = function(p, u) return ScooterSelection.Progress.HasCheckpoint(p, u.Checkpoint) == true end,
	World      = function(p, u) return ScooterSelection.Progress.HasCompletedWorld(p, u.World) == true end,
}
ScooterSelection.Checks = Checks

local productScooter = {}   -- [developer product id] = definition
for _, def in ipairs(Scooters.List) do
	local u = def.Unlock
	if u and u.Type == "Product" and u.ProductId then productScooter[u.ProductId] = def end
	-- a scooter no longer sold: a purchase Roblox still owes a receipt for is still granted
	if u and u.LegacyProductId then productScooter[u.LegacyProductId] = def end
end
-- archived scooters (Scooters.Archived): a purchase Roblox still owes a receipt for is granted
for _, def in ipairs(Scooters.Archived or {}) do
	local u = def.Unlock
	if u and u.LegacyProductId then productScooter[u.LegacyProductId] = def end
end

--------------------------------------------------------------------- player data
local dataApi
local function data()
	if dataApi and dataApi.Parent then return dataApi end
	local settings = ServerScriptService:FindFirstChild("SettingsServer")
	dataApi = settings and settings:WaitForChild("PlayerData", 10)
	return dataApi
end

local function readData(player, key)
	local api = data()
	if not api then return nil, "failed" end
	return api.Get:Invoke(player, key)
end

local function writeData(player, key, value, now, replace)
	local api = data()
	if not api then return false end
	if now then return api.SaveNow:Invoke(player, key, value, replace) end
	return api.Set:Invoke(player, key, value)
end

-- the owned list is a set, saved sorted: a scooter can never be in it twice. The save only
-- ever ADDS to what is stored (SettingsServer's LIST_UNION), so a save that failed or was
-- slow to load never wipes it; replace (the Studio reward reset only) writes it as given.
local function saveOwned(player, st, replace)
	local list = {}
	for id in pairs(st.owned) do table.insert(list, id) end
	table.sort(list)
	return writeData(player, "OwnedScooters", list, true, replace)
end

--------------------------------------------------------------------- sessions
local sessions = {}   -- [player] = { selected, unlocked, owned, checkedAt, ready, lastEquip, joined,
                      --              freshAt, simJoined, session, groupSeen, member, claim, lastAction, left }

-- The session in which this player, in the group, was asked to like the game and rejoin
-- is remembered (GroupAsked); a later session (the rejoin) is what earns its reward.
-- Saved at once, so a quick rejoin (or a hop to the other world) already finds it.
local function markSeen(player, st, groupId)
	local key = tostring(groupId)
	if st.groupSeen[key] then return end
	st.groupSeen[key] = st.session
	if not writeData(player, "GroupAsked", table.clone(st.groupSeen), true) then
		st.groupSeen[key] = nil                           -- not saved: the next tap asks again
	end
end

-- Seen outside the group: what was remembered is out of date (they left since), so a
-- join from here on starts again (seen now, rewarded on a later session).
local function clearSeen(player, st, groupId)
	local key = tostring(groupId)
	if not st.groupSeen[key] then return end
	st.groupSeen[key] = nil
	writeData(player, "GroupAsked", table.clone(st.groupSeen))
end

-- A GroupReward scooter for this player right now. "Member" is whether they were in
-- the group when this session started (memberAtStart); joining since never counts.
--   "owned"    theirs, and a member: theirs to ride
--   "join"     not in the group
--   "rejoin"   in the group, but not asked to like and rejoin in an earlier session (they
--              joined during this one, were asked this session, or were never asked yet)
--   "eligible" a member, asked in an earlier session: grantReward gives it when a session
--              starts (load); mid-session it waits for the next one like "rejoin"
-- asked: this look IS the ask (RewardAction: the card / podium, which shows the notice)
local function rewardStatus(player, st, def, asked)
	local u = def.Unlock
	local key = tostring(u.GroupId)
	local member = st.member[key] == true
	if member and st.owned[def.Id] then return "owned" end
	if not (member or inGroup(player, u, st)) then
		clearSeen(player, st, u.GroupId)
		return "join"
	end
	if asked then markSeen(player, st, u.GroupId) end
	if member and not st.owned[def.Id] and st.groupSeen[key] and st.groupSeen[key] ~= st.session then return "eligible" end
	return "rejoin"
end

local function check(player, st, def)
	if ScooterSelection.IsTester(player) then return true end
	local unlock = def.Unlock or { Type = "Free" }
	local fn = Checks[unlock.Type]
	if not fn then return false end
	local ok, result = pcall(fn, player, unlock, st, def)
	if not ok then
		warn(("[Scooter] unlock check for %s (%s) failed: %s"):format(def.Id, unlock.Type, tostring(result)))
		return st.unlocked[def.Id] == true   -- keep the last known answer
	end
	return result == true
end

-- one GroupReward scooter's status into the session (unlocked + what its card offers)
local function refreshReward(player, st, def, asked)
	if ScooterSelection.IsTester(player) then   -- theirs to ride; nothing granted or saved
		st.unlocked[def.Id], st.claim[def.Id] = true, nil
		return "owned"
	end
	local ok, status = pcall(rewardStatus, player, st, def, asked)
	if not ok then
		warn(("[Scooter] reward check for %s failed: %s"):format(def.Id, tostring(status)))
		return st.claim[def.Id] or (st.unlocked[def.Id] and "owned" or "join")   -- keep the last known answer
	end
	st.unlocked[def.Id] = status == "owned"
	-- what its card offers: JOIN GROUP; UNLOCK (in the group, not asked yet: tapping it is the
	-- like + rejoin ask); or REJOIN once asked (the grant only ever comes with a new session)
	local asked = st.owned[def.Id] or st.groupSeen[tostring(def.Unlock.GroupId)] ~= nil   -- an owner is never asked
	st.claim[def.Id] = (status == "join" and "join") or (status ~= "owned" and (asked and "rejoin" or "ask")) or nil
	return status
end

local function refresh(player, st, force)
	if not force and os.clock() - st.checkedAt < RECHECK_AFTER then return end
	st.checkedAt = os.clock()
	for _, def in ipairs(Scooters.List) do
		if def.Unlock and def.Unlock.Type == "GroupReward" then
			refreshReward(player, st, def)
		else
			st.unlocked[def.Id] = check(player, st, def)
		end
	end
	-- archived scooters: still theirs to ride if they own one (not on the menu)
	for _, def in ipairs(Scooters.Archived or {}) do
		st.unlocked[def.Id] = check(player, st, def)
	end
end

-- THE one place a GroupReward scooter becomes someone's. Only load() calls it, when a
-- session starts, for a player rewardStatus calls "eligible" (in the group, and
-- rejoined since the server first saw them there). No remote can reach it.
local function grantReward(player, st, def)
	if st.owned[def.Id] then return true end
	st.owned[def.Id] = true
	if not saveOwned(player, st) then
		st.owned[def.Id] = nil                            -- not saved: the next session tries again
		return false
	end
	st.unlocked[def.Id], st.claim[def.Id] = true, nil
	log(player.Name, "earned", def.Id)
	return true
end

local function snapshot(st)
	local unlocked = {}
	for id, yes in pairs(st.unlocked) do if yes then unlocked[id] = true end end
	return { Selected = st.selected, Unlocked = unlocked, Claim = table.clone(st.claim) }
end

-- the pick must be a scooter they may ride; anything else becomes the default
local function settle(player, st, saveIfChanged)
	if Scooters.Get(st.selected) and st.unlocked[st.selected] then return end
	st.selected = Scooters.DefaultId
	if saveIfChanged and not studioGuest(st) then   -- a simulated guest's save is left alone
		writeData(player, "SelectedScooter", st.selected)
	end
end

-- Left a reward's group during the session: no longer a member, so the scooter locks now
-- (a ride already going finishes; the pick goes back to the default) and the ask is
-- forgotten. Only players it matters to are looked up: members who own the reward.
local function stillInGroup(player, u)            -- nil when Roblox couldn't say
	local ok, groups = pcall(GroupService.GetGroupsAsync, GroupService, player.UserId)
	if not ok or type(groups) ~= "table" then return nil end
	for _, g in ipairs(groups) do
		if g.Id == u.GroupId then return g.Rank >= (u.MinRank or 1) end
	end
	return false
end
local function watchGroups(player, st)
	while sessions[player] == st do
		task.wait(GROUP_WATCH)
		if sessions[player] ~= st then break end
		if not ScooterSelection.IsTester(player) and not studioGuest(st) then
			for _, def in ipairs(Scooters.List) do
				local u = def.Unlock
				local key = u and u.Type == "GroupReward" and tostring(u.GroupId)
				if key and st.member[key] and st.owned[def.Id] and stillInGroup(player, u) == false
					and sessions[player] == st then
					st.member[key] = false
					st.joined[u.GroupId] = nil
					st.left[u.GroupId] = true
					clearSeen(player, st, u.GroupId)
					refreshReward(player, st, def)
					settle(player, st, true)
					log(player.Name, "left group", u.GroupId, "-", def.Id, "locked")
				end
			end
		end
	end
end

local function load(player)
	local st = { selected = Scooters.DefaultId, unlocked = {}, owned = {}, checkedAt = -math.huge,
		ready = false, lastEquip = 0, joined = {}, freshAt = -math.huge, simJoined = false,
		session = HttpService:GenerateGUID(false), groupSeen = {}, member = {}, claim = {}, lastAction = 0, left = {} }
	sessions[player] = st
	if studioGuest(st) then
		warn("[Scooter] Studio: " .. player.Name .. " plays as NOT in the group (ScooterSelection attribute SimulateNotInGroup)")
	end
	local owned = readData(player, "OwnedScooters")
	if type(owned) == "table" then
		for _, id in ipairs(owned) do
			if type(id) == "string" then st.owned[id] = true end
		end
	end
	local seen = readData(player, "GroupAsked")
	if type(seen) == "table" then
		for group, session in pairs(seen) do
			if type(session) == "string" then st.groupSeen[tostring(group)] = session end
		end
	end
	-- Studio only (see the header): forget this tester's group rewards once per new
	-- StudioResetReward text, as if the account had never tried them
	local reset = RunService:IsStudio() and script:GetAttribute("StudioResetReward")
	if type(reset) == "string" and reset ~= "" and readData(player, "StudioRewardReset") ~= reset then
		for _, def in ipairs(Scooters.List) do
			if def.Unlock and def.Unlock.Type == "GroupReward" then st.owned[def.Id] = nil end
		end
		st.groupSeen = {}
		saveOwned(player, st, true)
		writeData(player, "GroupAsked", {}, true)
		writeData(player, "StudioRewardReset", reset, true)
		warn("[Scooter] Studio: " .. player.Name .. "'s group rewards were reset (StudioResetReward = " .. reset .. ")")
	end
	-- in each reward's group as this session starts: the only membership rewards count
	for _, def in ipairs(Scooters.List) do
		local u = def.Unlock
		if u and u.Type == "GroupReward" then st.member[tostring(u.GroupId)] = memberAtStart(player, st, u) end
	end
	local saved, loadState = readData(player, "SelectedScooter")
	if sessions[player] ~= st then return end            -- left while loading
	refresh(player, st, true)
	-- a new session is the "rejoin": group rewards they've earned since are granted now
	for _, def in ipairs(Scooters.List) do
		if def.Unlock and def.Unlock.Type == "GroupReward" and refreshReward(player, st, def) == "eligible" then
			grantReward(player, st, def)
		end
	end
	st.selected = saved
	-- a new player (nothing saved) just gets the default; a stored pick that is
	-- unknown or no longer theirs is corrected, unless the save failed to load
	settle(player, st, saved ~= nil and loadState ~= "failed")
	st.ready = true
	log(player.Name, "rides", st.selected)
	task.spawn(watchGroups, player, st)
end

local function sessionOf(player)
	local st = sessions[player]
	local t0 = os.clock()
	while st and not st.ready and os.clock() - t0 < LOAD_WAIT do task.wait(0.1) end
	return (st and st.ready) and st or nil
end

--------------------------------------------------------------------- api
-- Never yields. The default until the player's save has loaded.
function ScooterSelection.GetSelected(player)
	local st = player and sessions[player]
	if st and st.ready and st.unlocked[st.selected] then return st.selected end
	return Scooters.DefaultId
end

-- The working model a ride with this DRIVER spawns, and its scooter id.
function ScooterSelection.TemplateFor(driver)
	local models = ServerStorage:FindFirstChild("ScooterModels")
	if not models then return nil end
	local def = Scooters.Get(ScooterSelection.GetSelected(driver)) or Scooters.Default()
	local model = models:FindFirstChild(def.Model)
	if not model then
		def = Scooters.Default()
		model = models:FindFirstChild(def.Model)
	end
	return model, def.Id
end

-- Does this player own this skin (bought, given, claimed - not a tester's free ride)?
-- nil while their save is still loading; wait = true waits for it (up to LOAD_WAIT).
function ScooterSelection.Owns(player, id, wait)
	local st = player and (wait and sessionOf(player) or sessions[player])
	if not (st and st.ready) then return nil end
	return st.owned[id] == true
end

function ScooterSelection.IsScooterProduct(productId)
	return productScooter[productId] ~= nil
end

-- DonationHandler's ProcessReceipt calls this for a scooter product. True only once
-- the unlock is safely saved; otherwise Roblox offers the receipt again later.
function ScooterSelection.GrantProduct(userId, productId)
	local def = productScooter[productId]
	local player = Players:GetPlayerByUserId(userId)
	if not def or not player then return false end
	local st = sessionOf(player)
	if not st then return false end
	local had = st.owned[def.Id]                     -- already theirs: saved again, never twice
	st.owned[def.Id] = true
	if not saveOwned(player, st) then
		if not had then st.owned[def.Id] = nil end    -- not saved: not theirs until the receipt comes again
		return false
	end
	st.unlocked[def.Id] = true
	log(player.Name, "bought", def.Id)
	return true
end

-- A skin given by a game feature (a Daily Rewards day, a Daily Wheel prize): true once it
-- is theirs and saved, and whether it is new to them. One they already own is never added
-- twice (OwnedScooters is a set) - the second value says so, for the feature to decide.
function ScooterSelection.GrantSkin(player, id)
	local def = Scooters.Get(id)
	local st = def and sessionOf(player)
	if not st then return false, false end
	local isNew = not st.owned[def.Id]
	if isNew then
		st.owned[def.Id] = true
		if not saveOwned(player, st) then
			st.owned[def.Id] = nil
			return false, false
		end
		log(player.Name, "was given", def.Id)
	end
	st.unlocked[def.Id] = true
	return true, isNew
end

-- A Daily Rewards skin (DailyRewards, when its day is claimed)
function ScooterSelection.GrantDaily(player, id)
	return (ScooterSelection.GrantSkin(player, id))
end

-- What the podium's prompt and the scooter's card do (Remotes.RewardAction). It can
-- NOT grant or unlock anything (only grantReward can, at session start): it looks the
-- player up afresh and says where they stand. joinPrompt is only what Roblox's join
-- prompt answered, never proof: a reason to look at the group afresh - and a join
-- found that way still waits for the rejoin. Returns the status ("owned", "join",
-- "rejoin" or "busy") and the player's state:
--   owned   "You already own this item"
--   rejoin  "You've joined the group! Rejoin the game to receive your Ice Scooter."
--   join    the client opens Roblox's join prompt, then asks again with its answer
function ScooterSelection.RewardAction(player, id, joinPrompt)
	local st = sessionOf(player)
	if not st then return "busy", nil end
	local def = Scooters.Get(id)
	local u = def and def.Unlock
	if not (u and (u.Type == "GroupReward" or u.Type == "DailyReward" or u.Type == "Limited" or u.Type == "Product")) then return "busy", snapshot(st) end
	local now = os.clock()
	if now - st.lastAction < EQUIP_GAP then return "busy", snapshot(st) end
	st.lastAction = now
	-- a Robux skin's shop stand: already theirs, say so; otherwise the client opens the
	-- purchase (the receipt grants it, GrantProduct - never this)
	if u.Type == "Product" then
		if st.unlocked[def.Id] then
			Remotes.Notice:FireClient(player, OWNED_NOTICE)
			return "owned", snapshot(st)
		end
		return "buy", snapshot(st)
	end
	-- a LIMITED skin's card: where it comes from (already theirs: say so)
	if u.Type == "DailyReward" or u.Type == "Limited" then
		if st.owned[def.Id] then
			Remotes.Notice:FireClient(player, OWNED_NOTICE)
			return "owned", snapshot(st)
		end
		local text = u.Type == "DailyReward" and DAILY_NOTICE or u.Notice
		if type(text) == "string" then Remotes.Notice:FireClient(player, text) end
		return "limited", snapshot(st)
	end
	local joining = joinPrompt == "Joined" or joinPrompt == "AlreadyMember"
	if joining then
		st.joined[u.GroupId] = true
		st.simJoined = true
	end
	local status = refreshReward(player, st, def, true)   -- in the group: this is the ask
	if status == "eligible" then status = "rejoin" end   -- granted when their next session starts
	if status == "owned" then
		Remotes.Notice:FireClient(player, OWNED_NOTICE)
	elseif status == "rejoin" then
		-- already theirs (they had left the group): no ask, the rejoin is all it takes
		local text = (st.owned[def.Id] and BACK_NOTICE) or (joinPrompt == "Joined" and JOINED_NOTICE) or REJOIN_NOTICE
		Remotes.Notice:FireClient(player, text)
	end
	settle(player, st, true)
	return status, snapshot(st)
end

--------------------------------------------------------------------- previews
-- Visual-only copies of the working models, for the menu's ViewportFrames.
-- Lighter copies, so each spinning card has less to draw (the ridden scooters are never
-- affected). These copies are also what the lobby podiums and the Spin the Wheel window
-- show. To undo either, set it to false (the copies then hold every visible part, as before).
--   LITE_PREVIEWS  leave out parts hidden inside the tyres (no visible change anywhere)
--   LITE_SPECKS    also leave out tiny specks (sprinkles, deck stars, grass tufts...): unseen
--                  on a card, but they'd also go from the big lobby podium displays
local LITE_PREVIEWS = true
local LITE_SPECKS   = false
local HIDDEN_PARTS = { WheelCore = true, TreadCore = true }   -- only while the tyre is solid
local SPECK_PARTS  = { Sprinkle = true, ConstellationLine = true, MossPatch = true, GrassBlade = true }
local function skipInPreview(d)
	if LITE_PREVIEWS and HIDDEN_PARTS[d.Name] and d.Transparency == 0 then return true end
	if LITE_SPECKS and SPECK_PARTS[d.Name] then return true end
	return false
end
local function buildPreviews()
	local models = ServerStorage:FindFirstChild("ScooterModels")
	local folder = Root:FindFirstChild("ScooterPreviews")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "ScooterPreviews"
	end
	folder:ClearAllChildren()
	-- archived skins too: their owners still get a card for them (ScootersUI.Cards)
	local all = table.clone(Scooters.List)
	for _, def in ipairs(Scooters.Archived or {}) do table.insert(all, def) end
	for _, def in ipairs(all) do
		local src = models and models:FindFirstChild(def.Model)
		if src then
			local copy = Instance.new("Model")
			copy.Name = def.Id
			for _, d in ipairs(src:GetDescendants()) do
				if d:IsA("BasePart") and d.Transparency < 0.99 and not skipInPreview(d) then
					local p = d:Clone()
					for _, c in ipairs(p:GetChildren()) do
						if not (c:IsA("DataModelMesh") or c:IsA("Decal") or c:IsA("SurfaceAppearance")) then c:Destroy() end
					end
					p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
					p.Parent = copy
				end
			end
			copy.WorldPivot = src:GetPivot()
			copy.Parent = folder
		else
			warn("[Scooter] no model '" .. tostring(def.Model) .. "' in ServerStorage.ScooterModels for " .. def.Id)
		end
	end
	folder.Parent = Root
end

--------------------------------------------------------------------- start
-- Bound once per server (a second copy of this module, e.g. from a test, leaves them be)
if not Remotes.EquipScooter:GetAttribute("Bound") then
	Remotes.EquipScooter:SetAttribute("Bound", true)
	buildPreviews()

	Remotes.GetScooters.OnServerInvoke = function(player)
		local st = sessionOf(player)
		if not st then return nil end
		refresh(player, st, false)
		settle(player, st, true)                          -- lost an unlock since? back to the default
		return snapshot(st)
	end

	-- joinPrompt: what the menu's join prompt answered, for a group's scooter. Never proof,
	-- only a reason to ask Roblox afresh (and, in Studio, the end of SimulateNotInGroup).
	Remotes.EquipScooter.OnServerInvoke = function(player, id, joinPrompt)
		local st = sessionOf(player)
		if not st then return false, nil end
		local now = os.clock()
		if now - st.lastEquip < EQUIP_GAP then return false, snapshot(st) end
		st.lastEquip = now
		local def = Scooters.Get(id)
		if not def then return false, snapshot(st) end
		local unlock = def.Unlock
		if unlock and (unlock.Type == "Group" or unlock.Type == "GroupReward") and (joinPrompt == "Joined" or joinPrompt == "AlreadyMember") then
			st.joined[unlock.GroupId] = true
			st.simJoined = true
		end
		if unlock and unlock.Type == "GroupReward" then  -- always a fresh answer for the one asked for
			refreshReward(player, st, def)
		else
			st.unlocked[def.Id] = check(player, st, def)
		end
		if not st.unlocked[def.Id] then return false, snapshot(st) end
		if st.selected ~= def.Id then
			st.selected = def.Id
			writeData(player, "SelectedScooter", def.Id)
			log(player.Name, "picked", def.Id)
		end
		return true, snapshot(st)
	end

	-- the podium and the card: a look-up (and join follow-up), never a grant
	Remotes.RewardAction.OnServerInvoke = function(player, id, joinPrompt)
		if type(id) ~= "string" then return "busy", nil end
		if type(joinPrompt) ~= "string" then joinPrompt = nil end
		return ScooterSelection.RewardAction(player, id, joinPrompt)
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, _, bought)
		local st = sessions[player]
		if bought and st then st.checkedAt = -math.huge end   -- ask again on the next look
	end)
end

Players.PlayerAdded:Connect(function(p) task.spawn(load, p) end)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(load, p) end
Players.PlayerRemoving:Connect(function(p) sessions[p] = nil end)

return ScooterSelection
