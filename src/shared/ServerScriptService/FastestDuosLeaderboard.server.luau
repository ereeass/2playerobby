--=====================================================================
-- FastestDuosLeaderboard   (server)
--
-- The fastest full-course times, one record per DUO, ranked worldwide (top 100) on
-- the lobby's "Fastest Finish Leaderboard" board (titled Fastest Duos). The board is
-- drawn by the Robux board's own code (DonationBoardClient / BoardUI.newDuo); this
-- script only records, reads and publishes the snapshot
-- (ReplicatedStorage.FastestDuosSystem.BoardData).
--
-- Where times come from: ScooterSystem.RunTimer, the server's own course stopwatch.
-- It alone starts and finishes a run (the scooter crossing the start / finish gates
-- with both riders aboard), knows the two riders from the ride itself (Driver and
-- Passenger), and marks a run Valid only when every checkpoint was reached in order
-- and the scooter never moved impossibly fast. Only such runs are recorded here; no
-- client can send a time.
--
--   Top (OrderedDataStore)  "<lowId>_<highId>" -> ms * 2 + (driver was highId and 1 or 0)
--     one key per duo whatever their roles, so a duo is never listed twice; only a
--     FASTER time replaces it (UpdateAsync), and it replaces the roles with it. The low
--     bit is saved with the time, so the Driver and the Motor of THAT run survive
--     restarts and reloads; it never changes the order by time.
--   Roles: RunTimer reads them off the ride in the frame the finish gate is crossed
--   (Player Role "Driver" / "Passenger" = the motor). Each board entry: a = the Driver,
--   b = the Motor.
--   under its own name (PREFIX): nothing here touches the other boards' stores.
--
-- The board reloads every REFRESH_EVERY seconds on every server (the same ordered
-- store, so all servers show one board); BoardData's NextRefresh attribute is the
-- server time of the next reload, which the board counts down to. A write that fails
-- is kept and tried again at every reload, and meanwhile still shows on this server.
--
-- Studio: kept in this server's memory only (like the other boards), so Studio play
-- never reaches the real board. Preview from the command bar (Server):
--   game.ServerStorage.FastestDuosStudioTest:Invoke(userId1, userId2, seconds)
--=====================================================================

local Players             = game:GetService("Players")
local DataStoreService    = game:GetService("DataStoreService")
local HttpService         = game:GetService("HttpService")
local RunService          = game:GetService("RunService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerStorage       = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- usernames and verified badges: the Robux board's own lookup and cache
local Names    = require(ServerScriptService:WaitForChild("DonationSystem"):WaitForChild("LeaderboardManager"))
-- the course stopwatch (the same module ScooterSystem.Main runs)
local RunTimer = require(ServerScriptService:WaitForChild("ScooterSystem"):WaitForChild("RunTimer"))

-- !! The saved times live under this name: changing it starts an EMPTY board (the old times
-- stay in their old store, untouched). v1 -> v2 on 2026-09-29: the board was cleared on the
-- owner's request; setting it back to "FastestDuos_v1" would bring the old times back.
-- (each world has its own board: WorldConfig.FastestDuosStore - World 1's is "FastestDuos_v2")
local PREFIX        = require(ReplicatedStorage:WaitForChild("WorldConfig")).FastestDuosStore or "FastestDuos_v2"
local REFRESH_EVERY = 30      -- seconds between board reloads (the board counts down to it)
local TOP           = 100
local MIN_TIME      = 5       -- seconds: no real run is faster (a guard against broken data)
local MAX_TIME      = 3 * 3600

local system = ReplicatedStorage:FindFirstChild("FastestDuosSystem")
if not system then
	system = Instance.new("Folder")
	system.Name = "FastestDuosSystem"
	system.Parent = ReplicatedStorage
end
local boardData = system:FindFirstChild("BoardData")
if not boardData then
	boardData = Instance.new("StringValue")
	boardData.Name = "BoardData"
	boardData.Parent = system
end

--------------------------------------------------------------------- records
-- one duo, whatever their roles: the key always has the lower UserId first
local function duoKey(a, b)
	local lo, hi = math.min(a, b), math.max(a, b)
	return lo .. "_" .. hi, lo, hi
end

local function encode(ms, driverIsHigh)
	return ms * 2 + (driverIsHigh and 1 or 0)
end

-- a stored entry back into { Key, Lo, Hi, Ms, Driver, Other }, or nil if it is not valid
local function decode(key, value)
	if type(key) ~= "string" or type(value) ~= "number" or value ~= value then return nil end
	local lo, hi = key:match("^(%d+)_(%d+)$")
	lo, hi = tonumber(lo), tonumber(hi)
	if not (lo and hi) or lo <= 0 or hi <= 0 or lo == hi then return nil end
	value = math.floor(value)
	local ms = value // 2
	if ms < MIN_TIME * 1000 or ms > MAX_TIME * 1000 then return nil end
	local driverIsHigh = value % 2 == 1
	return {
		Key = key, Lo = lo, Hi = hi, Ms = ms, Value = value,
		Driver = driverIsHigh and hi or lo, Other = driverIsHigh and lo or hi,
	}
end

--------------------------------------------------------------------- backends
local function dataStoreBackend()
	local top = DataStoreService:GetOrderedDataStore(PREFIX .. "_Top")
	return {
		Kind = "DataStore",
		-- keeps the faster of the saved time and this one
		Submit = function(key, value)
			top:UpdateAsync(key, function(old)
				if type(old) == "number" and old // 2 <= value // 2 then return nil end
				return value
			end)
		end,
		Top = function(count)
			-- out of read budget: skip this reload (the board keeps its last copy)
			if DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetSortedAsync) < 1 then
				return nil
			end
			local out = {}
			for _, e in ipairs(top:GetSortedAsync(true, math.min(count, 100)):GetCurrentPage()) do
				table.insert(out, { Key = e.key, Value = e.value })
			end
			return out
		end,
	}
end

-- Studio: the same interface in this server's memory
local function memoryBackend()
	local top = {}
	return {
		Kind = "Memory",
		Submit = function(key, value)
			local old = top[key]
			if old and old // 2 <= value // 2 then return end
			top[key] = value
		end,
		Top = function(count)
			local out = {}
			for key, value in pairs(top) do table.insert(out, { Key = key, Value = value }) end
			table.sort(out, function(a, b) return a.Value < b.Value end)
			for i = #out, count + 1, -1 do out[i] = nil end
			return out
		end,
	}
end

local backend
if RunService:IsStudio() then
	backend = memoryBackend()
	print("[FastestDuos] Studio test: times are kept in memory and never reach the real leaderboard")
else
	local ok, result = pcall(dataStoreBackend)
	if ok then
		backend = result
	else
		warn("[FastestDuos] Data stores unavailable; times are not saved this server: " .. tostring(result))
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

--------------------------------------------------------------------- recording
local publish        -- (below) rebuilds and re-ranks the board from what is known
local known   = {}   -- [key] = best value finished on THIS server (shown even before the store has it)
local pending = {}   -- [key] = value whose write failed; tried again at every reload
local seenRun = {}   -- [runId] = true: a run is only ever recorded once

local function write(key, value)
	if not backend then return end
	local ok, err = attempt(backend.Submit, key, value)
	if ok then
		if pending[key] == value then pending[key] = nil end
		print(("[FastestDuos] saved pair %s: %.3fs"):format(key, (value // 2) / 1000))
	else
		-- keep the better of what was already waiting and this one
		if not pending[key] or pending[key] // 2 > value // 2 then pending[key] = value end
		warn(("[FastestDuos] Could not save %s's time (will retry): %s"):format(key, tostring(err)))
	end
end

-- one duo finished together in `seconds`; driverId drove, passengerId was the motor
local function submit(driverId, passengerId, seconds)
	driverId, passengerId, seconds = tonumber(driverId), tonumber(passengerId), tonumber(seconds)
	if not (driverId and passengerId and seconds) then return false end
	driverId, passengerId = math.floor(driverId), math.floor(passengerId)
	if driverId <= 0 or passengerId <= 0 or driverId == passengerId then return false end
	if seconds ~= seconds or seconds < MIN_TIME or seconds > MAX_TIME then return false end

	local key, _, hi = duoKey(driverId, passengerId)
	local value = encode(math.floor(seconds * 1000 + 0.5), driverId == hi)
	if known[key] and known[key] // 2 <= value // 2 then return true end   -- not a new best: nothing to save
	known[key] = value
	task.spawn(write, key, value)
	task.spawn(publish)   -- a pair's best changed: re-rank the board now, not at the next reload
	return true
end

RunTimer.RunCompleted:Connect(function(record)
	if type(record) ~= "table" or record.Status ~= "Completed" then return end
	if record.RunId then
		if seenRun[record.RunId] then return end   -- a repeated finish event
		seenRun[record.RunId] = true
	end
	if record.Valid ~= true then return end        -- skipped a checkpoint, or moved impossibly fast
	-- the roles RunTimer read off the ride as it crossed the finish: by role, never by order
	local driver, motor
	for _, p in ipairs({ record.Player1, record.Player2 }) do
		if type(p) == "table" then
			if p.Role == "Driver" then driver = p elseif p.Role == "Passenger" then motor = p end
		end
	end
	if not (driver and motor) then return end
	submit(driver.UserId, motor.UserId, record.CompletionTime)
end)

game:BindToClose(function()
	local waiting = 0
	for key, value in pairs(pending) do
		waiting += 1
		task.spawn(function()
			write(key, value)
			waiting -= 1
		end)
	end
	local t0 = os.clock()
	while waiting > 0 and os.clock() - t0 < 25 do task.wait(0.1) end
end)

--------------------------------------------------------------------- board
local top = {}   -- the last worldwide top list read: { {Key, Value} }

local function build()
	-- the store's list, with this server's own (maybe not yet saved) bests merged in
	local best = {}
	local function consider(key, value)
		local e = decode(key, value)
		if e and (not best[key] or e.Ms < best[key].Ms) then best[key] = e end
	end
	for _, e in ipairs(top) do consider(e.Key, e.Value) end
	for key, value in pairs(known) do consider(key, value) end

	local list = {}
	for _, e in pairs(best) do table.insert(list, e) end
	table.sort(list, function(a, b)
		if a.Ms ~= b.Ms then return a.Ms < b.Ms end
		return a.Key < b.Key
	end)
	for i = #list, TOP + 1, -1 do list[i] = nil end

	local ids, seen = {}, {}
	for _, e in ipairs(list) do
		for _, uid in ipairs({ e.Driver, e.Other }) do
			if not seen[uid] then seen[uid] = true; table.insert(ids, uid) end
		end
	end
	local ok, users = pcall(Names.ResolveNames, ids)
	if not ok then users = {} end

	local out = {}
	for _, e in ipairs(list) do
		local a, b = users[e.Driver], users[e.Other]
		table.insert(out, {
			a = e.Driver, an = (a and a.n) or "Player", av = (a and a.v) or nil,
			b = e.Other,  bn = (b and b.n) or "Player", bv = (b and b.v) or nil,
			t = e.Ms / 1000,
		})
	end
	local encoded, json = pcall(HttpService.JSONEncode, HttpService, { duos = out })
	if encoded and json ~= boardData.Value then boardData.Value = json end
end

-- One build at a time (the name lookup waits on the web): a change that lands while one
-- is running asks for one more pass, so an older snapshot can never overwrite a newer one
-- and a burst of finishes costs two builds, not one each.
local building, again = false, false
function publish()
	if building then again = true return end
	building = true
	repeat
		again = false
		local ok, err = pcall(build)
		if not ok then warn("[FastestDuos] Could not build the board: " .. tostring(err)) end
	until not again
	building = false
end

local function refresh()
	if backend then
		for key, value in pairs(pending) do task.spawn(write, key, value) end
		local ok, result = attempt(backend.Top, TOP)
		if ok and result then
			top = result
		elseif not ok then
			warn("[FastestDuos] Could not read the top list (showing the last one): " .. tostring(result))
		end
	end
	publish()
end

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
	hook.Name = "FastestDuosStudioTest"
	hook.OnInvoke = function(userId1, userId2, seconds)
		local ok = submit(userId1, userId2, seconds)
		task.wait()   -- let the write land
		if ok then refresh() end
		return ok
	end
	hook.Parent = ServerStorage
end
