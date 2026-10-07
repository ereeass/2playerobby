-- Saves each player's settings (SFX volume, music volume, shadows) to their account.
--
-- The client applies a setting the moment it changes and then tells this script
-- with SaveSetting(key, value). Writes happen a couple of seconds after the player
-- stops changing things, and when they leave, so dragging a slider never spends
-- DataStore budget. Only the keys the player actually changed are written, on top
-- of whatever is stored, so a failed load can never wipe their other settings.
--
-- The client is told how saving went (SaveSetting fired back with "saved",
-- "failed" or "offline"), which the Settings window shows at the bottom.
--
-- The same save also holds a few server-owned values for other systems (the
-- selected scooter, scooters bought with Robux, checkpoint progress). They go through the PlayerData
-- bindables at the bottom, never through SaveSetting, so no client can write them.
--
-- In Studio this uses the real DataStore when Game Settings > Security >
-- "Enable Studio Access to API Services" is on; otherwise settings last for the
-- play session only.

local DataStoreService  = game:GetService("DataStoreService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local system      = ReplicatedStorage:WaitForChild("SettingsSystem")
local Schema      = require(system:WaitForChild("Defaults"))
local remotes     = system:WaitForChild("Remotes")
local GetSettings = remotes:WaitForChild("GetSettings")
local SaveSetting = remotes:WaitForChild("SaveSetting")

local STORE_NAME  = "PlayerSettings_v1"
local SAVE_DELAY  = 2     -- seconds without changes before writing
local WRITE_GAP   = 6.5   -- DataStores allow one write per key every 6 seconds
local RETRY_DELAY = 15    -- after a failed write
local LOAD_TRIES  = 3
local LOAD_WAIT   = 20    -- GetSettings waits at most this long for the load
local MAX_EVENTS  = 40    -- SaveSetting calls allowed per player per 10 s

local store
local online = true
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		online = false
		warn("[Settings] DataStore unavailable; settings last for this session only: " .. tostring(result))
	end
end

local sessions = {}   -- [player] = session

-- Server-owned numbers that may only ever go UP: when written, the higher of the stored
-- and the new value is kept, so a failed load or a stale write can never lower them
-- (each world's checkpoint progress: ScooterSystem.CheckpointProgress, under that world's
-- WorldConfig.CheckpointSaveKey - World 1 "CheckpointProgress", World 2 "CheckpointProgress_W2").
local HIGHEST_WINS = { CheckpointProgress = true, CheckpointProgress_W2 = true }
do
	-- and whatever key this world's checkpoints are saved under (a new world is covered too)
	local wc = ReplicatedStorage:FindFirstChild("WorldConfig")
	local ok, cfg = pcall(function() return wc and require(wc) end)
	local key = ok and type(cfg) == "table" and cfg.CheckpointSaveKey
	if type(key) == "string" and key ~= "" then HIGHEST_WINS[key] = true end
end

-- Server-owned lists that may only ever GROW: when written, every entry already stored is
-- kept alongside the new ones, so a failed or slow load (this server's copy empty or
-- missing some) can never wipe what is stored (OwnedScooters: ScooterSystem.ScooterSelection).
-- Only a SaveNow asked with replace = true (the Studio-only reward reset) writes as given.
local LIST_UNION = { OwnedScooters = true }

local function union(stored, value)
	local seen, out = {}, {}
	for _, list in ipairs({ stored, value }) do
		for _, item in ipairs(list) do
			if not seen[item] then seen[item] = true; table.insert(out, item) end
		end
	end
	if #out > 0 and type(out[1]) == "string" then pcall(table.sort, out) end
	return out
end

-- settings live in session.Values; server-owned values (PlayerData) in session.Extra
local isSetting = {}
for _, key in ipairs(Schema.Keys) do isSetting[key] = true end

local function valueOf(s, key)
	if isSetting[key] then return s.Values[key] end
	return s.Extra[key]
end

local function keyFor(player)
	return "u_" .. player.UserId
end

-- Studio without API access, or a place that may not use DataStores at all
local function isAccessError(err)
	err = tostring(err)
	return err:find("StudioAccessToApisNotAllowed") ~= nil
		or err:find("Studio access") ~= nil
		or err:find("403") ~= nil
end

local function goOffline()
	if online then
		online = false
		warn("[Settings] no DataStore access (in Studio: Game Settings > Security > Enable Studio Access to API Services); settings last for this session only")
	end
end

local function notify(player, s)
	if player.Parent == Players then
		SaveSetting:FireClient(player, s.State)
	end
end

---------------------------------------------------------------- load
local function load(player, s)
	if not online then
		s.State, s.Loaded = "offline", true
		return
	end
	for attempt = 1, LOAD_TRIES do
		local ok, result = pcall(store.GetAsync, store, keyFor(player))
		if ok then
			local stored = Schema.Normalize(result)
			for _, key in ipairs(Schema.Keys) do
				-- a change that arrived while loading wins over the stored value
				if not s.Dirty[key] then s.Values[key] = stored[key] end
			end
			-- server-owned values are kept exactly as stored
			if type(result) == "table" then
				for key, value in pairs(result) do
					if not isSetting[key] and not s.Dirty[key] then s.Extra[key] = value end
				end
			end
			s.State, s.Loaded = "saved", true
			return
		end
		if isAccessError(result) then
			goOffline()
			s.State, s.Loaded = "offline", true
			return
		end
		warn(("[Settings] loading %s's settings failed (try %d): %s"):format(player.Name, attempt, tostring(result)))
		if attempt < LOAD_TRIES then task.wait(attempt * 2) end
	end
	-- defaults for now; whatever they have stored stays untouched
	s.State, s.Loaded = "failed", true
end

local function sessionFor(player)
	local s = sessions[player]
	if s or player.Parent ~= Players then return s end
	s = {
		Values = Schema.Normalize(nil), Extra = {}, Dirty = {}, Replace = {}, State = "loading", Loaded = false,
		Active = true, Scheduled = false, LastChange = 0, LastWrite = -math.huge, RetryAt = 0,
		WindowStart = 0, Events = 0,
	}
	sessions[player] = s
	task.spawn(load, player, s)
	return s
end

---------------------------------------------------------------- save
-- Writes the changed keys on top of what is stored. Returns true on success.
local function flush(player, s)
	if not next(s.Dirty) then return true end
	if not online then
		s.State = "offline"
		notify(player, s)
		return false
	end

	local changes, replace = {}, {}
	for key in pairs(s.Dirty) do
		changes[key] = valueOf(s, key)
		replace[key] = s.Replace[key]
	end
	s.LastWrite = os.clock()   -- from the start: no other write to this key begins meanwhile
	local ok, err = pcall(store.UpdateAsync, store, keyFor(player), function(old)
		local data = type(old) == "table" and old or {}
		for key, value in pairs(changes) do
			if HIGHEST_WINS[key] and type(data[key]) == "number" and type(value) == "number" then
				data[key] = math.max(data[key], value)
			elseif LIST_UNION[key] and not replace[key] and type(data[key]) == "table" and type(value) == "table" then
				data[key] = union(data[key], value)
			else
				data[key] = value
			end
		end
		return data, { player.UserId }
	end)
	s.LastWrite = os.clock()

	if ok then
		for key, value in pairs(changes) do
			if valueOf(s, key) == value then s.Dirty[key] = nil; s.Replace[key] = nil end   -- unless it changed again meanwhile
		end
		if next(s.Dirty) then return true end                     -- more to write: stay "saving"
		s.State = "saved"
	elseif isAccessError(err) then
		goOffline()
		s.State = "offline"
	else
		warn(("[Settings] saving %s's settings failed: %s"):format(player.Name, tostring(err)))
		s.State = "failed"
	end
	notify(player, s)
	return ok
end

local function schedule(player, s)
	if s.Scheduled then return end
	s.Scheduled = true
	task.spawn(function()
		while s.Active and next(s.Dirty) do
			local now = os.clock()
			local wait = math.max(SAVE_DELAY - (now - s.LastChange), WRITE_GAP - (now - s.LastWrite), s.RetryAt - now)
			if wait > 0 then
				task.wait(wait)
			elseif not flush(player, s) then
				if not online then break end
				s.RetryAt = os.clock() + RETRY_DELAY
			end
		end
		s.Scheduled = false
	end)
end

---------------------------------------------------------------- remotes
GetSettings.OnServerInvoke = function(player)
	local s = sessionFor(player)
	local t0 = os.clock()
	while s and not s.Loaded and os.clock() - t0 < LOAD_WAIT do task.wait(0.1) end
	if not s then return nil end
	return { Values = table.clone(s.Values), State = s.Loaded and s.State or "failed" }
end

SaveSetting.OnServerEvent:Connect(function(player, key, value)
	if type(key) ~= "string" then return end
	local clean = Schema.Sanitize(key, value)
	if clean == nil then return end
	local s = sessionFor(player)
	if not s then return end

	local now = os.clock()
	if now - s.WindowStart > 10 then s.WindowStart, s.Events = now, 0 end
	s.Events += 1
	-- past the limit the latest value is still kept (writes are spaced out by schedule()
	-- anyway, so spamming can't cost more saves); only the extra replies are dropped. The
	-- change is written and the client told "saved" once it is - never left "saving..."
	local flooding = s.Events > MAX_EVENTS

	if s.Values[key] == clean and not s.Dirty[key] then
		if not flooding then notify(player, s) end   -- nothing to write; tell the client where things stand
		return
	end
	s.Values[key] = clean
	s.Dirty[key] = true
	s.LastChange = now
	if not online then
		s.State = "offline"
		if not flooding then notify(player, s) end
		return
	end
	schedule(player, s)
end)

---------------------------------------------------------------- server-owned values
-- Other server scripts keep a few per-player values in this same save:
--   PlayerData.Get:Invoke(player, key)            -> value, load state ("saved", "failed", "offline", ...)
--   PlayerData.Set:Invoke(player, key, value)     -> true; written like the settings (soon after,
--                                                    on leaving, on shutdown)
--   PlayerData.SaveNow:Invoke(player, key, value) -> true only once it is safely stored (purchases)
--   PlayerData.SaveNow:Invoke(player, key, value, true) -> the same, written exactly as given
--                                                    (not merged with a LIST_UNION key's stored list)
-- Keys that are settings are refused, so neither side can overwrite the other.
local PlayerData = Instance.new("Folder")
PlayerData.Name = "PlayerData"
local apiGet, apiSet, apiSaveNow = Instance.new("BindableFunction"), Instance.new("BindableFunction"), Instance.new("BindableFunction")
apiGet.Name, apiSet.Name, apiSaveNow.Name = "Get", "Set", "SaveNow"

local function serverKey(key)
	return type(key) == "string" and not isSetting[key]
end

local function loadedSession(player)
	local s = sessionFor(player)
	local t0 = os.clock()
	while s and not s.Loaded and os.clock() - t0 < LOAD_WAIT do task.wait(0.1) end
	return s
end

apiGet.OnInvoke = function(player, key)
	if not serverKey(key) then return nil, "invalid" end
	local s = loadedSession(player)
	if not s then return nil, "failed" end
	return s.Extra[key], s.Loaded and s.State or "failed"
end

apiSet.OnInvoke = function(player, key, value)
	if not serverKey(key) then return false end
	local s = sessionFor(player)
	if not s then return false end
	s.Extra[key] = value
	s.Dirty[key] = true
	s.Replace[key] = nil
	s.LastChange = os.clock()
	if online then schedule(player, s) end   -- offline: kept for this session
	return true
end

apiSaveNow.OnInvoke = function(player, key, value, replace)
	if not serverKey(key) then return false end
	local s = loadedSession(player)
	if not s then return false end
	s.Extra[key] = value
	s.Dirty[key] = true
	s.Replace[key] = replace == true or nil
	s.LastChange = os.clock()
	if not online then return true end       -- Studio without API access: this session only
	-- Roblox takes one write per key every 6 seconds; one sooner is queued and logged as a
	-- warning ("DataStore request was added to queue"). So it waits its turn (a few seconds
	-- at most); a write that lands meanwhile may already have stored this value.
	while s.Dirty[key] and os.clock() - s.LastWrite < WRITE_GAP do task.wait(0.2) end
	if not s.Dirty[key] then return true end
	local ok = flush(player, s)
	if next(s.Dirty) then schedule(player, s) end
	return ok and not s.Dirty[key]
end

apiGet.Parent, apiSet.Parent, apiSaveNow.Parent = PlayerData, PlayerData, PlayerData
PlayerData.Parent = script

---------------------------------------------------------------- players
Players.PlayerAdded:Connect(sessionFor)
for _, player in ipairs(Players:GetPlayers()) do sessionFor(player) end

Players.PlayerRemoving:Connect(function(player)
	local s = sessions[player]
	if not s then return end
	task.wait()   -- other scripts' last values for this player (SpinWheel's progress) land first
	s.Active = false
	if next(s.Dirty) and online then flush(player, s) end
	sessions[player] = nil
end)

game:BindToClose(function()
	task.wait()   -- other scripts' last values (SpinWheel's progress) land first
	local pending = 0
	for player, s in pairs(sessions) do
		if next(s.Dirty) and online then
			pending += 1
			task.spawn(function()
				s.Active = false
				flush(player, s)
				pending -= 1
			end)
		end
	end
	local t0 = os.clock()
	while pending > 0 and os.clock() - t0 < 25 do task.wait(0.1) end
end)
