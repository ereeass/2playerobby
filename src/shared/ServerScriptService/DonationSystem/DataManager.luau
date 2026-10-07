--=====================================================================
-- DonationSystem / DataManager
--
-- Persistence for donations. Three stores, written in this order so a
-- retried receipt can never be counted twice:
--
--   1. Donors  (DataStore)         "u_<userId>" -> { total, receipts, name }
--      The purchase id is checked and the total bumped in ONE
--      UpdateAsync. That single atomic write is what makes each
--      donation count exactly once.
--   2. AllTimeRanked (OrderedDataStore)  "<userId>" -> rank key
--      The donor's absolute total AND when they reached it, packed into
--      one number (Encode): equal totals sort by who got there FIRST, so a
--      newer donor never jumps a tie. Never lowered, so a repeat, or two
--      quick donations finishing out of order, is harmless. (AllTime, the
--      plain totals it replaced, is still written as a backup.)
--   3. Board   (DataStore)         "board" -> { rev, days, names, last, ids }
--      Per-day totals for the rolling 30-day tab plus the recent feed.
--      Skips any purchase id it has already seen; rev counts every write,
--      so a reader can tell which of two copies is newer.
--
-- If step 2 or 3 fails the receipt goes back to Roblox as unprocessed
-- and is retried; step 1 recognises it, so the retry only redoes the
-- idempotent writes.
--
-- In Studio (unless Config.UseDataStoresInStudio) the same code runs
-- against an in-memory backend, so test purchases never touch live data.
-- A live server NEVER falls back to memory: if data stores cannot be
-- reached, recording fails and Roblox keeps the receipt for later.
--=====================================================================

local DataStoreService  = game:GetService("DataStoreService")
local HttpService       = game:GetService("HttpService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("DonationSystem"):WaitForChild("Config"))

local DataManager = {}

local BOARD_KEY     = "board"
local KEEP_RECEIPTS = 100   -- per donor; retries arrive long before this rolls over
local KEEP_IDS      = 250   -- purchase ids remembered by the shared board record
local KEEP_LAST     = 12    -- recent feed length (the board shows Config.MaxLastDonators)
local DAY           = 86400

-- rank key = total * SLOT + (SLOT - 1 - seconds since EPOCH it was reached): a higher total
-- always wins, and on a tie the earlier second does. Kept under 2^53 (exact in Luau) for
-- totals up to 9 million Robux per donor, and good for 31 years (to 2057).
local SLOT  = 1e9
local EPOCH = 1767225600    -- 2026-01-01 UTC
local MAX_TOTAL = 9e6
-- The one-off copy of the old AllTime list into AllTimeRanked (Backfill) is finished: every
-- server started since the switch ran it, so it no longer runs on each server start. (Was
-- 1791072000 = 2026-10-04 UTC; a later date here would turn it back on. Nothing it copied is
-- touched, and the old AllTime list is still kept as a backup.)
local BACKFILL_UNTIL = 0

local function dayNumber(t)
	return t // DAY
end
DataManager.DayNumber = dayNumber

local function encode(total, t)
	local second = math.clamp(math.floor((t or EPOCH) - EPOCH), 0, SLOT - 1)
	return math.clamp(math.floor(total), 0, MAX_TOTAL) * SLOT + (SLOT - 1 - second)
end
DataManager.Encode = encode
function DataManager.Decode(key)
	return key // SLOT
end

--------------------------------------------------------------------- backends
local function dataStoreBackend()
	local prefix = Config.DataStorePrefix
	local stores = {
		Donors = DataStoreService:GetDataStore(prefix .. "_Donors"),
		Board  = DataStoreService:GetDataStore(prefix .. "_Board"),
	}
	local plain = DataStoreService:GetOrderedDataStore(prefix .. "_AllTime")         -- backup: plain totals
	local allTime = DataStoreService:GetOrderedDataStore(prefix .. "_AllTimeRanked") -- what the board reads

	return {
		Kind = "DataStore",
		Update = function(store, key, transform)
			stores[store]:UpdateAsync(key, transform)
		end,
		Get = function(store, key)
			return stores[store]:GetAsync(key)
		end,
		SetTotal = function(userId, total, reachedAt)
			-- never lower: two quick donations can finish out of order, and a retried
			-- receipt (same total, a later time) keeps the time it was first reached
			local key = encode(total, reachedAt)
			allTime:UpdateAsync(tostring(userId), function(old)
				if type(old) == "number" and old >= key then return nil end
				return key
			end)
			pcall(plain.UpdateAsync, plain, tostring(userId), function(old)
				if type(old) == "number" and old >= total then return nil end
				return total
			end)
		end,
		-- the old plain list into the ranked one (a total only, never over a ranked
		-- entry that already has it); reachedAt(userId) -> when they got there, if known
		Backfill = function(reachedAt)
			local pages = plain:GetSortedAsync(false, 100)
			local n = 0
			while true do
				for _, e in ipairs(pages:GetCurrentPage()) do
					local uid, total = tonumber(e.key), e.value
					if uid and type(total) == "number" and total > 0 then
						allTime:UpdateAsync(e.key, function(old)
							if type(old) == "number" and old // SLOT >= total then return nil end
							n += 1
							return encode(total, reachedAt(uid))
						end)
					end
				end
				if pages.IsFinished then break end
				pages:AdvanceToNextPageAsync()
			end
			return n
		end,
		Top = function(count)
			-- out of read budget in a very busy spell: skip this read (the board
			-- keeps its last copy) rather than queue up and spam warnings
			if DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetSortedAsync) < 1 then
				return nil
			end
			local out = {}
			-- one page holds at most 100 entries
			for _, e in ipairs(allTime:GetSortedAsync(false, math.min(count, 100)):GetCurrentPage()) do
				local uid = tonumber(e.key)
				if uid then table.insert(out, { UserId = uid, Amount = e.value // SLOT, Key = e.value }) end
			end
			return out
		end,
		-- a cursor over the WHOLE all-time list, `size` per page, highest first
		-- (the board's deeper pages: LeaderboardManager walks it as people scroll)
		OpenTop = function(size)
			local function budget()
				if DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetSortedAsync) < 1 then
					error("out of GetSortedAsync budget")
				end
			end
			budget()
			local pages = allTime:GetSortedAsync(false, size)
			return {
				Page = function()
					local out = {}
					for _, e in ipairs(pages:GetCurrentPage()) do
						local uid = tonumber(e.key)
						if uid then table.insert(out, { UserId = uid, Amount = e.value // SLOT, Key = e.value }) end
					end
					return out
				end,
				Finished = function() return pages.IsFinished end,
				Next = function()
					budget()
					pages:AdvanceToNextPageAsync()
				end,
			}
		end,
	}
end

-- Same interface, held in this server's memory. The JSON round trip
-- mimics what a real data store does to stored values.
local function memoryBackend()
	local data   = { Donors = {}, Board = {} }
	local totals = {}

	local function copy(v)
		if v == nil then return nil end
		return HttpService:JSONDecode(HttpService:JSONEncode(v))
	end

	return {
		Kind = "Memory",
		Update = function(store, key, transform)
			local new = transform(copy(data[store][key]))
			if new ~= nil then data[store][key] = copy(new) end
		end,
		Get = function(store, key)
			return copy(data[store][key])
		end,
		SetTotal = function(userId, total, reachedAt)
			totals[userId] = math.max(totals[userId] or 0, encode(total, reachedAt))
		end,
		Backfill = function() return 0 end,
		Top = function(count)
			local out = {}
			for uid, key in pairs(totals) do
				table.insert(out, { UserId = uid, Amount = key // SLOT, Key = key })
			end
			table.sort(out, function(a, b)
				if a.Key ~= b.Key then return a.Key > b.Key end
				return a.UserId < b.UserId
			end)
			for i = #out, count + 1, -1 do out[i] = nil end
			return out
		end,
		OpenTop = function(size)
			local all, page = {}, 1
			for uid, key in pairs(totals) do table.insert(all, { UserId = uid, Amount = key // SLOT, Key = key }) end
			table.sort(all, function(a, b)
				if a.Key ~= b.Key then return a.Key > b.Key end
				return a.UserId < b.UserId
			end)
			return {
				Page = function() return table.move(all, (page - 1) * size + 1, math.min(page * size, #all), 1, {}) end,
				Finished = function() return page * size >= #all end,
				Next = function() page += 1 end,
			}
		end,
	}
end

-- Every call fails, so ProcessReceipt answers NotProcessedYet and Roblox
-- keeps the receipt instead of the donation being granted and forgotten.
local function unavailableBackend(reason)
	local function fail() error("data stores unavailable: " .. tostring(reason)) end
	return { Kind = "Unavailable", Update = fail, Get = fail, SetTotal = fail, Top = fail, OpenTop = fail, Backfill = fail }
end

local backend
if RunService:IsStudio() and not Config.UseDataStoresInStudio then
	backend = memoryBackend()
else
	local ok, result = pcall(dataStoreBackend)
	if ok then
		backend = result
	else
		warn("[Donations] Data stores unavailable; donations stay pending until they are: " .. tostring(result))
		backend = unavailableBackend(result)
	end
end
DataManager.Backend = backend.Kind

--------------------------------------------------------------------- helpers
local function attempt(fn, ...)
	local ok, result
	for i = 1, 3 do
		ok, result = pcall(fn, ...)
		if ok then return true, result end
		if i < 3 then task.wait(i) end
	end
	return false, result
end

local function normaliseBoard(b)
	b = type(b) == "table" and b or {}
	b.days  = type(b.days)  == "table" and b.days  or {}
	b.names = type(b.names) == "table" and b.names or {}
	b.last  = type(b.last)  == "table" and b.last  or {}
	b.ids   = type(b.ids)   == "table" and b.ids   or {}
	b.at    = type(b.at)    == "table" and b.at    or {}   -- [uid] = their latest donation (30-day ties)
	b.rev   = tonumber(b.rev) or 0
	return b
end

-- Drops days that have left the window, and names nobody refers to any more.
local function prune(b, today)
	local oldest = today - Config.RecentDays
	for uid, days in pairs(b.days) do
		for key in pairs(days) do
			local d = tonumber(string.sub(key, 2))
			if not d or d < oldest then days[key] = nil end
		end
		if next(days) == nil then b.days[uid] = nil end
	end

	for uid in pairs(b.at) do
		if not b.days[uid] then b.at[uid] = nil end
	end

	local keep = {}
	for uid in pairs(b.days) do keep[uid] = true end
	for _, e in ipairs(b.last) do keep[tostring(e.u)] = true end
	for uid in pairs(b.names) do
		if not keep[uid] then b.names[uid] = nil end
	end
end

--------------------------------------------------------------------- api
-- Returns ok, newTotalForDonor, boardRecord, fresh
-- fresh is false when this receipt had already been counted (a retry).
function DataManager.RecordDonation(userId, amount, purchaseId, name)
	-- 1. exactly-once: receipt id and total move together
	local total, fresh
	local ok, err = attempt(backend.Update, "Donors", "u_" .. userId, function(rec)
		rec = type(rec) == "table" and rec or {}
		rec.total = rec.total or 0
		rec.receipts = rec.receipts or {}
		if table.find(rec.receipts, purchaseId) then
			total, fresh = rec.total, false
			return nil                              -- already counted, nothing to write
		end
		fresh = true
		rec.total += amount
		table.insert(rec.receipts, purchaseId)
		while #rec.receipts > KEEP_RECEIPTS do table.remove(rec.receipts, 1) end
		rec.name = name
		total = rec.total
		return rec
	end)
	if not ok or not total then
		warn("[Donations] Could not save donor total: " .. tostring(err))
		return false
	end

	-- 2. all-time leaderboard (absolute value, safe to repeat; a retry keeps the first time)
	ok, err = attempt(backend.SetTotal, userId, total, os.time())
	if not ok then
		warn("[Donations] Could not update all-time board: " .. tostring(err))
		return false
	end

	-- 3. rolling 30-day totals and the recent feed
	local board
	ok, err = attempt(backend.Update, "Board", BOARD_KEY, function(b)
		b = normaliseBoard(b)
		if table.find(b.ids, purchaseId) then
			board = b
			return nil
		end
		local now = os.time()
		local today = dayNumber(now)
		local uid = tostring(userId)
		local days = b.days[uid] or {}
		days["d" .. today] = (days["d" .. today] or 0) + amount
		b.days[uid] = days
		b.names[uid] = name
		b.at[uid] = now

		table.insert(b.last, 1, { u = userId, n = name, a = amount, t = now })
		while #b.last > KEEP_LAST do table.remove(b.last) end

		table.insert(b.ids, purchaseId)
		while #b.ids > KEEP_IDS do table.remove(b.ids, 1) end

		prune(b, today)
		b.rev += 1
		board = b
		return b
	end)
	if not ok then
		warn("[Donations] Could not update recent donations: " .. tostring(err))
		return false
	end

	return true, total, board, fresh
end

-- { {UserId, Amount}, ... } highest first, or nil on failure
function DataManager.GetTop(count)
	local ok, result = attempt(backend.Top, count)
	if not ok then
		warn("[Donations] Could not read all-time board: " .. tostring(result))
		return nil
	end
	return result
end

-- Copies the old plain AllTime list into AllTimeRanked (only until BACKFILL_UNTIL: done,
-- see the top). A donor's time comes from the board's feed when it
-- is still there, else they count as having got there before anyone new.
-- Returns how many entries it wrote, or nil when it didn't run.
function DataManager.Backfill()
	if os.time() > BACKFILL_UNTIL then return nil end
	local ok, board = attempt(backend.Get, "Board", BOARD_KEY)
	local when = {}
	if ok and type(board) == "table" and type(board.last) == "table" then
		for _, e in ipairs(board.last) do                -- newest first: keep each donor's latest
			if type(e) == "table" and e.u and not when[e.u] then when[e.u] = tonumber(e.t) end
		end
	end
	return backend.Backfill(function(uid) return when[uid] end)
end

-- A cursor over every all-time donor, `size` per page: Page() -> { {UserId, Amount} },
-- Finished() -> bool, Next() moves on a page. Page, Next and opening it may error
-- (out of budget, data stores down); the caller catches that.
function DataManager.OpenTop(size)
	return backend.OpenTop(size)
end

-- The shared board record, or nil on failure
function DataManager.GetBoard()
	local ok, result = attempt(backend.Get, "Board", BOARD_KEY)
	if not ok then
		warn("[Donations] Could not read recent donations: " .. tostring(result))
		return nil
	end
	return normaliseBoard(result)
end

-- A single donor's all-time total, or nil on failure
function DataManager.GetTotal(userId)
	local ok, result = attempt(backend.Get, "Donors", "u_" .. userId)
	if not ok then return nil end
	return type(result) == "table" and result.total or 0
end

return DataManager
