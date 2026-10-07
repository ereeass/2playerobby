--=====================================================================
-- DonationSystem / LeaderboardManager
--
-- Builds the board snapshot (all-time top 100, rolling 30-day top 100,
-- latest donations) and publishes it as JSON in
-- ReplicatedStorage.DonationSystem.BoardData. Clients only ever READ
-- that value.
--
-- Everyone who ever donated is listed, not just the top 100: as a player
-- scrolls a tab near its end the board asks for the next 100
-- (DonorPage, a read-only RemoteFunction: tab + page number in, rows out;
-- nothing a client sends is ever written). All-time pages are walked
-- through the ordered store and kept for DEEP_TTL, shared by everyone in
-- the server; 30-day pages come from the board record already in memory.
--
-- Other servers are told about new donations over MessagingService and
-- reload a few seconds later; every server also reloads on a timer.
--=====================================================================

local Players           = game:GetService("Players")
local HttpService       = game:GetService("HttpService")
local UserService       = game:GetService("UserService")
local MessagingService  = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local system      = ReplicatedStorage:WaitForChild("DonationSystem")
local Config      = require(system:WaitForChild("Config"))
local DataManager = require(script.Parent.DataManager)

local LeaderboardManager = {}

local TOPIC       = Config.DataStorePrefix .. "_Board"
local NAME_RETRY  = 300    -- seconds before a failed name lookup is tried again
local PAGE        = math.clamp(Config.MaxLeaderboardEntries, 1, 100)   -- rows per page; page 1 is the snapshot
local DEEP_TTL    = 300    -- seconds the deeper all-time pages are kept before being read again
local MAX_PAGE    = 1000   -- 100 000 donors deep
local ASK_GAP     = 0.4    -- seconds a player must leave between page requests

local boardData = system:FindFirstChild("BoardData")
if not boardData then
	boardData = Instance.new("StringValue")
	boardData.Name = "BoardData"
	boardData.Parent = system
end

-- Server -> clients only: "a donation just went through here", which
-- plays the coin burst. Nothing listens to it on the server.
local celebrate = system:FindFirstChild("DonationCelebrate")
if not celebrate then
	celebrate = Instance.new("RemoteEvent")
	celebrate.Name = "DonationCelebrate"
	celebrate.Parent = system
end

-- Client -> server, read only: the next page of a tab (see the top)
local donorPage = system:FindFirstChild("DonorPage")
if not donorPage then
	donorPage = Instance.new("RemoteFunction")
	donorPage.Name = "DonorPage"
	donorPage.Parent = system
end

local state = {
	top   = {},    -- last all-time page read: { {UserId, Amount} }
	recentAll = {},  -- every 30-day donor, highest first (the snapshot shows the first PAGE)
	board = nil,   -- last board record read or written
	-- Totals this server wrote itself. Ordered stores are eventually
	-- consistent, so a reload right after a donation can still return the
	-- old value; taking the max stops the board from briefly rolling back.
	known = {},
}
local users = {}   -- userId -> { n = username, v = verified, retry = clock }

-- A reload can race a donation this server just wrote and bring back the
-- copy from before it; only ever move forward to a newer revision.
local function adoptBoard(board)
	if board and (not state.board or (board.rev or 0) >= (state.board.rev or 0)) then
		state.board = board
	end
end

--------------------------------------------------------------------- names
local function resolveUsers(ids)
	local now = os.clock()
	local missing = {}
	for _, uid in ipairs(ids) do
		local info = users[uid]
		if uid > 0 and (not info or (info.retry and info.retry < now)) then
			local plr = Players:GetPlayerByUserId(uid)
			if plr then
				users[uid] = { n = plr.Name, v = plr.HasVerifiedBadge }
			else
				table.insert(missing, uid)
			end
		end
	end

	for i = 1, #missing, 100 do
		local batch = table.move(missing, i, math.min(i + 99, #missing), 1, {})
		local ok, infos = pcall(UserService.GetUserInfosByUserIdsAsync, UserService, batch)
		if ok and infos then
			for _, info in ipairs(infos) do
				users[info.Id] = { n = info.Username, v = info.HasVerifiedBadge }
			end
		end
	end

	-- whatever the batch lookup could not answer
	for _, uid in ipairs(missing) do
		local info = users[uid]
		if not info or info.retry then
			local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, uid)
			if ok and name then
				users[uid] = { n = name, v = false }
			else
				users[uid] = { n = info and info.n, v = false, retry = now + NAME_RETRY }
			end
		end
	end
end

--------------------------------------------------------------------- snapshot
-- map: [uid] = rank key (DataManager.Encode: the total, then who reached it first)
local function sortedEntries(map, limit)
	local list, keys = {}, {}
	for uid, key in pairs(map) do
		local amount = DataManager.Decode(key)
		if amount > 0 then
			local e = { u = uid, a = amount }
			keys[e] = key
			table.insert(list, e)
		end
	end
	table.sort(list, function(a, b)
		if keys[a] ~= keys[b] then return keys[a] > keys[b] end
		return a.u < b.u
	end)
	for i = #list, limit + 1, -1 do list[i] = nil end
	return list
end

local function build()
	local limit = Config.MaxLeaderboardEntries

	local totals = {}
	for _, e in ipairs(state.top) do totals[e.UserId] = e.Key or DataManager.Encode(e.Amount) end
	for uid, key in pairs(state.known) do
		if (totals[uid] or 0) < key then totals[uid] = key end
	end
	local allTime = sortedEntries(totals, limit)

	local board = state.board or { days = {}, names = {}, last = {}, at = {} }
	-- when each 30-day donor last gave (ties go to whoever got there first); older records
	-- without it fall back on the feed, else count as earliest
	local at = {}
	for _, e in ipairs(board.last) do
		local k = tostring(e.u)
		if not at[k] then at[k] = tonumber(e.t) end
	end
	for k, t in pairs(board.at or {}) do at[k] = tonumber(t) end
	local fromDay = DataManager.DayNumber(os.time()) - (Config.RecentDays - 1)
	local recentTotals = {}
	for uidStr, days in pairs(board.days) do
		local uid, sum = tonumber(uidStr), 0
		for key, amount in pairs(days) do
			local d = tonumber(string.sub(key, 2))
			if d and d >= fromDay then sum += amount end
		end
		if uid and sum > 0 then recentTotals[uid] = DataManager.Encode(sum, at[uidStr]) end
	end
	local recentAll = sortedEntries(recentTotals, math.huge)
	state.recentAll = recentAll
	local recent = table.move(recentAll, 1, math.min(limit, #recentAll), 1, {})

	local last = {}
	for i = 1, math.min(#board.last, Config.MaxLastDonators) do
		local e = board.last[i]
		table.insert(last, { u = e.u, a = e.a, t = e.t, n = e.n })
	end

	local ids, seen = {}, {}
	for _, list in ipairs({ allTime, recent, last }) do
		for _, e in ipairs(list) do
			if not seen[e.u] then
				seen[e.u] = true
				table.insert(ids, e.u)
			end
		end
	end
	resolveUsers(ids)

	for _, list in ipairs({ allTime, recent, last }) do
		for _, e in ipairs(list) do
			local info = users[e.u]
			e.n = (info and info.n) or e.n or board.names[tostring(e.u)] or "Player"
			e.v = (info and info.v) or nil
		end
	end

	-- whether a tab goes on past its first page (the board then loads more as it's scrolled)
	local more = { allTime = #allTime >= limit, recent = #recentAll > limit }
	return { allTime = allTime, recent = recent, last = last, more = more }
end

local function publish()
	local ok, snapshot = pcall(build)
	if not ok then
		warn("[Donations] Could not build board: " .. tostring(snapshot))
		return
	end
	local encoded, json = pcall(HttpService.JSONEncode, HttpService, snapshot)
	if encoded and json ~= boardData.Value then
		boardData.Value = json
	end
end

--------------------------------------------------------------------- refresh
local refreshing, again = false, false

function LeaderboardManager.Refresh()
	if refreshing then
		again = true
		return
	end
	refreshing = true
	repeat
		again = false
		local top = DataManager.GetTop(Config.MaxLeaderboardEntries)
		if top then state.top = top end
		adoptBoard(DataManager.GetBoard())
		publish()
	until not again
	refreshing = false
end

--------------------------------------------------------------------- deeper pages
local deep = { pages = {}, cursor = nil, finished = false, at = 0, busy = false }

-- all-time page n (2+): { {u, a} }, more   or nil when it can't be read right now
local function allTimePage(n)
	while deep.busy do task.wait(0.1) end        -- one walk at a time; the rest share it
	deep.busy = true
	local ok, err = pcall(function()
		if os.clock() - deep.at > DEEP_TTL then
			deep.pages, deep.cursor, deep.finished = {}, nil, false
		end
		while #deep.pages < n and not deep.finished do
			if deep.cursor then
				deep.cursor.Next()
			else
				deep.cursor = DataManager.OpenTop(PAGE)
				deep.at = os.clock()
			end
			local rows = {}
			for _, e in ipairs(deep.cursor.Page()) do table.insert(rows, { u = e.UserId, a = e.Amount }) end
			table.insert(deep.pages, rows)
			deep.finished = deep.cursor.Finished()
		end
	end)
	deep.busy = false
	if not ok then
		warn("[Donations] Could not read all-time page " .. n .. ": " .. tostring(err))
		return nil
	end
	return deep.pages[n] or {}, #deep.pages > n or not deep.finished
end

local function recentPage(n)
	local all = state.recentAll
	return table.move(all, (n - 1) * PAGE + 1, math.min(n * PAGE, #all), 1, {}), #all > n * PAGE
end

local lastAsk = {}
donorPage.OnServerInvoke = function(plr, tab, n)
	if tab ~= "allTime" and tab ~= "recent" then return nil end
	if type(n) ~= "number" or n ~= n or n % 1 ~= 0 or n < 2 or n > MAX_PAGE then return nil end
	local now = os.clock()
	if lastAsk[plr] and now - lastAsk[plr] < ASK_GAP then return nil end
	lastAsk[plr] = now

	local rows, more
	if tab == "allTime" then rows, more = allTimePage(n) else rows, more = recentPage(n) end
	if not rows then return nil end

	local ids, out = {}, {}
	for _, e in ipairs(rows) do table.insert(ids, e.u) end
	resolveUsers(ids)
	local names = state.board and state.board.names or {}
	for _, e in ipairs(rows) do
		local info = users[e.u]
		table.insert(out, { u = e.u, a = e.a, n = (info and info.n) or names[tostring(e.u)] or "Player", v = (info and info.v) or nil })
	end
	return { list = out, more = more }
end
Players.PlayerRemoving:Connect(function(plr) lastAsk[plr] = nil end)

local pendingRemote = false
local function onRemoteDonation(message)
	if message.Data == game.JobId or pendingRemote then return end
	pendingRemote = true
	deep.at = 0                             -- the order changed: deeper pages are read afresh
	-- give the ordered store a moment to catch up before reading it
	task.delay(5, function()
		pendingRemote = false
		LeaderboardManager.Refresh()
	end)
end

--------------------------------------------------------------------- api
-- Usernames (and verified badges) for other boards (PlaytimeLeaderboard), from the
-- same cache: { [userId] = { n = name, v = verified } }
function LeaderboardManager.ResolveNames(ids)
	resolveUsers(ids)
	return users
end

-- Called by DonationHandler once Roblox has confirmed the purchase.
function LeaderboardManager.RecordDonation(userId, amount, purchaseId)
	resolveUsers({ userId })
	local info = users[userId]
	local name = (info and info.n) or ("Player" .. userId)

	local ok, total, board, fresh = DataManager.RecordDonation(userId, amount, purchaseId, name)
	if not ok then return false end

	-- a retried receipt was already celebrated the first time
	if fresh then celebrate:FireAllClients(userId, amount) end

	state.known[userId] = math.max(state.known[userId] or 0, DataManager.Encode(total, os.time()))
	deep.at = 0                             -- the order changed: deeper pages are read afresh
	adoptBoard(board)

	local plr = Players:GetPlayerByUserId(userId)
	if plr then plr:SetAttribute("DonatedRobux", total) end

	task.spawn(function()
		publish()
		if DataManager.Backend == "DataStore" then
			pcall(MessagingService.PublishAsync, MessagingService, TOPIC, game.JobId)
		end
	end)
	return true
end

-- Shows a joining player their own all-time total on the Donate board.
function LeaderboardManager.LoadPlayer(plr)
	local total = DataManager.GetTotal(plr.UserId)
	if total and plr.Parent then
		-- a donation may have landed while this was loading; keep the higher
		plr:SetAttribute("DonatedRobux", math.max(total, plr:GetAttribute("DonatedRobux") or 0))
	end
end

function LeaderboardManager.Start()
	publish()                               -- empty board straight away, filled below
	task.spawn(function()
		-- the old plain totals into the ranked list first (only for a few days after the switch)
		local ok, n = pcall(DataManager.Backfill)
		if not ok then warn("[Donations] Could not copy the old all-time list: " .. tostring(n)) end
		if ok and n and n > 0 then print("[Donations] copied " .. n .. " donor(s) into the ranked all-time list") end
		LeaderboardManager.Refresh()
	end)

	task.spawn(function()
		while true do
			task.wait(Config.RefreshInterval)
			LeaderboardManager.Refresh()
		end
	end)

	if DataManager.Backend == "DataStore" then
		local ok, err = pcall(MessagingService.SubscribeAsync, MessagingService, TOPIC, onRemoteDonation)
		if not ok then
			warn("[Donations] Cross-server updates off, boards still reload every "
				.. Config.RefreshInterval .. "s: " .. tostring(err))
		end
	end
end

return LeaderboardManager
