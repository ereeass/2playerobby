--=====================================================================
-- PlaytimeLeaderboard   (server)
--
-- Time played in the live game, saved per player and ranked worldwide (top 100) on
-- the lobby's "playtime leaderboard" board. The board is drawn by the Robux board's
-- own code (DonationBoardClient / BoardUI.newTop); this script only counts, saves
-- and publishes the snapshot (ReplicatedStorage.PlaytimeSystem.BoardData) every
-- REFRESH_EVERY seconds, stamping its NextRefresh attribute for the board's countdown.
--
--   Players (DataStore)         "u_<userId>" -> { seconds = total }   the real total
--   Top     (OrderedDataStore)  "<userId>"   -> whole seconds (raised, never lowered)
--   under their own names (PREFIX): nothing here touches the donation stores.
--
-- Counting: each player's unsaved seconds build up in this server and are ADDED to
-- their saved total every SAVE_EVERY seconds, when they leave and when the server
-- shuts down. UpdateAsync adds to whatever is saved, so nothing is ever set back to
-- zero or overwritten; a failed save keeps its seconds and tries again later.
-- Every server reads the same ordered store, so all servers fill one board; players
-- in this server show their live time on it straight away.
--
-- Studio: counts in this server's memory only (like the donation board), so Studio
-- play never reaches the real stores or the worldwide board. Preview from the command
-- bar (Server): game.ServerStorage.PlaytimeStudioTest:Invoke(userId, seconds)
--=====================================================================

local Players           = game:GetService("Players")
local DataStoreService  = game:GetService("DataStoreService")
local HttpService       = game:GetService("HttpService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- usernames and verified badges: the Robux board's own lookup and cache
local Names = require(ServerScriptService:WaitForChild("DonationSystem"):WaitForChild("LeaderboardManager"))

-- !! DO NOT CHANGE once live: the saved playtime lives under this name
-- Each world counts its own time: WorldConfig.PlaytimeStore (World 2: "Playtime_W2").
-- A world without one uses "Playtime_v1" (World 1's board, as it always was).
local PREFIX        = require(ReplicatedStorage:WaitForChild("WorldConfig")).PlaytimeStore or "Playtime_v1"
local SAVE_EVERY    = 120    -- seconds between saves of each player's new time
local REFRESH_EVERY = 30     -- seconds between board reloads (the board counts down to it)
local TOP           = 100

-- Players the owners took off this board: their time isn't counted or saved and they're
-- never shown (everyone below moves up). Their old saved time is left untouched, so taking
-- an id out of this list brings them straight back.
local HIDDEN = {
	[476180958]  = true,   -- Vexerixx
	[7415418006] = true,   -- Ereeass
	[7229646209] = true,   -- Giving_rbx1
}

local system = ReplicatedStorage:FindFirstChild("PlaytimeSystem")
if not system then
	system = Instance.new("Folder")
	system.Name = "PlaytimeSystem"
	system.Parent = ReplicatedStorage
end
local boardData = system:FindFirstChild("BoardData")
if not boardData then
	boardData = Instance.new("StringValue")
	boardData.Name = "BoardData"
	boardData.Parent = system
end

--------------------------------------------------------------------- backends
local function dataStoreBackend()
	local players = DataStoreService:GetDataStore(PREFIX .. "_Players")
	local top = DataStoreService:GetOrderedDataStore(PREFIX .. "_Top")
	return {
		Kind = "DataStore",
		-- adds seconds to the saved total; returns the new total. token names this one chunk:
		-- a chunk already added (a retry after a write that worked but reported an error) is
		-- never added twice (rec.lastAdd; the saved seconds are never changed in any other way)
		Add = function(userId, seconds, token)
			local total
			players:UpdateAsync("u_" .. userId, function(rec)
				rec = type(rec) == "table" and rec or {}
				if token and rec.lastAdd == token then
					total = tonumber(rec.seconds) or 0
					return nil                            -- already in: nothing to write
				end
				rec.seconds = (tonumber(rec.seconds) or 0) + seconds
				rec.lastAdd = token
				total = rec.seconds
				return rec
			end)
			return total
		end,
		Get = function(userId)
			local rec = players:GetAsync("u_" .. userId)
			return type(rec) == "table" and tonumber(rec.seconds) or 0
		end,
		SetTop = function(userId, total)
			top:UpdateAsync(tostring(userId), function(old)
				if type(old) == "number" and old >= total then return nil end
				return total
			end)
		end,
		Top = function(count)
			-- out of read budget: skip this reload (the board keeps its last copy)
			if DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetSortedAsync) < 1 then
				return nil
			end
			local out = {}
			for _, e in ipairs(top:GetSortedAsync(false, math.min(count, 100)):GetCurrentPage()) do
				local uid = tonumber(e.key)
				if uid then table.insert(out, { UserId = uid, Seconds = e.value }) end
			end
			return out
		end,
	}
end

-- Studio: the same interface in this server's memory
local function memoryBackend()
	local totals, top = {}, {}
	return {
		Kind = "Memory",
		Add = function(userId, seconds)
			totals[userId] = (totals[userId] or 0) + seconds
			return totals[userId]
		end,
		Get = function(userId) return totals[userId] or 0 end,
		SetTop = function(userId, total) top[userId] = math.max(top[userId] or 0, total) end,
		Top = function(count)
			local out = {}
			for uid, s in pairs(top) do table.insert(out, { UserId = uid, Seconds = s }) end
			table.sort(out, function(a, b) return a.Seconds > b.Seconds end)
			for i = #out, count + 1, -1 do out[i] = nil end
			return out
		end,
	}
end

local backend
if RunService:IsStudio() then
	backend = memoryBackend()
	print("[Playtime] Studio test: playtime is kept in memory and never reaches the real leaderboard")
else
	local ok, result = pcall(dataStoreBackend)
	if ok then
		backend = result
	else
		warn("[Playtime] Data stores unavailable; playtime is not saved this server: " .. tostring(result))
	end
end

local function attempt(fn, ...)
	local ok, result
	for i = 1, 3 do
		ok, result = pcall(fn, ...)
		if ok then return true, result end
		if i < 3 then task.wait(i) end
	end
	return false, result
end

--------------------------------------------------------------------- counting
local sessions = {}   -- [player] = { since, unsaved, total (saved total, once known), saving,
                      --              chunk = { add, token } (a chunk not yet confirmed saved) }

local function collect(s)
	local now = os.clock()
	s.unsaved += now - s.since
	s.since = now
end

-- adds this player's unsaved whole seconds to their saved total
local function save(player, s)
	if not backend or s.saving then return end
	collect(s)
	-- a chunk whose save wasn't confirmed goes again exactly as it was (same seconds, same
	-- token), so if it did reach the store after all it isn't counted twice
	local chunk = s.chunk
	if not chunk then
		local add = math.floor(s.unsaved)
		if add < 1 then return end
		chunk = { add = add, token = HttpService:GenerateGUID(false) }
		s.chunk = chunk
	end
	local add = chunk.add
	s.saving = true
	local ok, total = attempt(backend.Add, player.UserId, add, chunk.token)
	if ok and total then
		s.chunk = nil
		s.unsaved -= add
		s.total = total
		local okTop, err = attempt(backend.SetTop, player.UserId, math.floor(total))
		if not okTop then warn("[Playtime] Could not update the top list for " .. player.Name .. ": " .. tostring(err)) end
	else
		warn("[Playtime] Could not save " .. player.Name .. "'s playtime (kept for the next save): " .. tostring(total))
	end
	s.saving = false
end

local function onJoin(player)
	if HIDDEN[player.UserId] then return end   -- off the board: nothing counted
	local s = { since = os.clock(), unsaved = 0, total = nil, saving = false }
	sessions[player] = s
	if backend then
		-- only to show their live time on the board; saving never needs it
		local ok, total = attempt(backend.Get, player.UserId)
		if ok and sessions[player] == s and s.total == nil then s.total = total end
	end
end

local function onLeave(player)
	local s = sessions[player]
	if not s then return end
	save(player, s)
	sessions[player] = nil
end

Players.PlayerAdded:Connect(onJoin)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(onJoin, p) end
Players.PlayerRemoving:Connect(onLeave)

game:BindToClose(function()
	local pending = 0
	for player, s in pairs(sessions) do
		pending += 1
		task.spawn(function()
			save(player, s)
			pending -= 1
		end)
	end
	local t0 = os.clock()
	while pending > 0 and os.clock() - t0 < 25 do task.wait(0.1) end
end)

task.spawn(function()
	while true do
		task.wait(SAVE_EVERY)
		for player, s in pairs(sessions) do
			task.spawn(save, player, s)
			task.wait(0.5)                              -- spread the writes out
		end
	end
end)

--------------------------------------------------------------------- board
local top = {}   -- the last worldwide top list read

local function publish()
	local totals = {}
	for _, e in ipairs(top) do totals[e.UserId] = e.Seconds end
	-- players here: their live time (saved + this session), fresher than the store
	for player, s in pairs(sessions) do
		if s.total then
			collect(s)
			local live = math.floor(s.total + s.unsaved)
			if (totals[player.UserId] or 0) < live then totals[player.UserId] = live end
		end
	end
	local list = {}
	for uid, sec in pairs(totals) do
		if sec >= 60 and not HIDDEN[uid] then table.insert(list, { u = uid, a = sec }) end
	end
	table.sort(list, function(a, b)
		if a.a ~= b.a then return a.a > b.a end
		return a.u < b.u
	end)
	for i = #list, TOP + 1, -1 do list[i] = nil end

	local ids = {}
	for _, e in ipairs(list) do table.insert(ids, e.u) end
	local ok, users = pcall(Names.ResolveNames, ids)
	for _, e in ipairs(list) do
		local info = ok and users[e.u]
		e.n = (info and info.n) or "Player"
		e.v = (info and info.v) or nil
	end
	local encoded, json = pcall(HttpService.JSONEncode, HttpService, { allTime = list })
	if encoded and json ~= boardData.Value then boardData.Value = json end
end

local function refresh()
	if backend then
		local ok, result = attempt(backend.Top, TOP)
		if ok and result then
			top = result
		elseif not ok then
			warn("[Playtime] Could not read the top list (showing the last one): " .. tostring(result))
		end
	end
	publish()
end

-- BoardData's NextRefresh attribute is the server time of the next reload: the board's
-- "Refreshes in Ns" footer counts down to it (as on the Fastest Duos board)
task.spawn(function()
	while true do
		refresh()
		local nextAt = workspace:GetServerTimeNow() + REFRESH_EVERY
		boardData:SetAttribute("NextRefresh", nextAt)
		task.wait(math.max(nextAt - workspace:GetServerTimeNow(), 1))
	end
end)

--------------------------------------------------------------------- studio
if backend and backend.Kind == "Memory" then
	local hook = Instance.new("BindableFunction")
	hook.Name = "PlaytimeStudioTest"
	hook.OnInvoke = function(userId, seconds)
		local total = backend.Add(userId, seconds)
		backend.SetTop(userId, math.floor(total))
		refresh()
		return total
	end
	hook.Parent = ServerStorage
end
