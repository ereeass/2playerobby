--=====================================================================
-- DailyRewards   (ScooterSystem, server)
--
-- The Daily Rewards calendar (StarterGui.DailyGui / DailyWindow). Everything is decided
-- here; the client only ASKS to claim (Remotes.DailyClaim).
--   Days     Shared.DailyRewards: what each day gives. A day with nothing set yet can't
--            be claimed.
--   Saved    "DailyReward" in the player's save (SettingsServer's PlayerData):
--            { Day = the last day claimed (0: none yet), At = when (server time) }
--   Rule     Day 1 is ready at once. Each next day is ready Interval (24 h) after the
--            previous one was CLAIMED: the clock only starts on a claim. Joining,
--            opening the calendar or leaving a ready reward unclaimed never moves it,
--            and missed days are never skipped - the next day waits for this one.
--            Time counts from the saved claim, so it runs on while they're offline and
--            a rejoin can't reset it.
--   Rewards  through the systems that own them, so they are the same counts:
--            Revive  DeathManager.GiveRevives     (ReviveCredits: REVIVE's red count)
--            Skip    SkipStage.GiveSkips          (SkipCredits: Skip Stage's red count)
--            Skin    ScooterSelection.GrantDaily  (OwnedScooters; already theirs: kept)
--            The claim is written into the save before the reward's own save, so the
--            two are stored together; a reward that can't be given undoes the claim.
--   Client   the player's DailyDay (last day claimed) and DailyNextAt (server time the
--            next day is ready; 0 = now) attributes. The calendar and the DAILY tile's
--            notification are drawn from them; missing = not loaded yet.
-- Studio: ServerStorage.DailyStudioTest:Invoke(player, "forward", seconds) moves the
-- last claim back in time; (player, "reset") = never claimed. Live servers have neither.
--=====================================================================

local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage       = game:GetService("ServerStorage")
local RS                  = game:GetService("ReplicatedStorage")

local Root    = RS:WaitForChild("ScooterSystem")
local Remotes = Root:WaitForChild("Remotes")
local Days    = require(Root:WaitForChild("Shared"):WaitForChild("DailyRewards"))
local Config  = require(Root:WaitForChild("Shared"):WaitForChild("Config"))

local DeathManager     = require(script.Parent:WaitForChild("DeathManager"))
local SkipStage        = require(script.Parent:WaitForChild("SkipStage"))
local ScooterSelection = require(script.Parent:WaitForChild("ScooterSelection"))

local KEY       = "DailyReward"
local ATTR_DAY  = "DailyDay"
local ATTR_NEXT = "DailyNextAt"
local ASK_GAP   = 0.5      -- seconds between one player's claim requests

local DailyRewards = {}
local states  = {}         -- [player] = { Day, At }, once loaded
local busy    = {}         -- [player] = true while a claim is being done
local lastAsk = {}

local function log(...) if Config.DebugLogging then print("[Daily]", ...) end end
local function now() return workspace:GetServerTimeNow() end

local function dataApi()
	local settings = ServerScriptService:WaitForChild("SettingsServer", 10)
	return settings and settings:WaitForChild("PlayerData", 10)
end

-- when the day after `st.Day` is ready (server time)
local function readyAt(st)
	return st.Day == 0 and 0 or st.At + Days.Interval
end

local function show(player)
	local st = states[player]
	if not st or not player.Parent then return end
	player:SetAttribute(ATTR_DAY, st.Day)
	player:SetAttribute(ATTR_NEXT, readyAt(st))
end

local function load(player)
	local api = dataApi()
	if not api then return end
	local ok, value, loadState = pcall(api.Get.Invoke, api.Get, player, KEY)
	if states[player] or player.Parent ~= Players then return end
	if not ok or loadState == "failed" then
		warn("[Daily] couldn't load " .. player.Name .. "'s daily rewards")
		return                                   -- nothing to show or claim this session
	end
	local day, at = 0, 0
	if type(value) == "table" then
		day = math.max(math.floor(tonumber(value.Day) or 0), 0)
		at = tonumber(value.At) or 0
	end
	states[player] = { Day = day, At = at }
	show(player)
end

-- the reward, through the system that owns it; true once it is theirs and saved
local function grant(player, reward)
	if reward.Kind == "Revive" then return DeathManager.GiveRevives(player, reward.Amount) end
	if reward.Kind == "Skip" then return SkipStage.GiveSkips(player, reward.Amount) end
	if reward.Kind == "Skin" then return ScooterSelection.GrantDaily(player, reward.Skin) end
	return false
end

-- Claims the day that is ready, if one is: true, or false and why not
function DailyRewards.Claim(player)
	local st = states[player]
	if not st then return false, "Still loading - try again in a moment." end
	if busy[player] then return false, nil end
	local day = st.Day + 1
	local reward = Days.Get(day)
	if not reward then return false, "More rewards are coming soon!" end
	if now() < readyAt(st) then return false, "Not ready yet!" end
	local api = dataApi()
	if not api then return false, "Couldn't claim - try again." end
	busy[player] = true
	local claimed = { Day = day, At = now() }
	-- the claim goes into the save first (kept in memory), so the reward's own save writes
	-- both at once; a reward that can't be given puts the old state back
	local given = false
	if pcall(api.Set.Invoke, api.Set, player, KEY, claimed) then
		local ok, result = pcall(grant, player, reward)
		if not ok then warn("[Daily] granting day " .. day .. " to " .. player.Name .. " failed: " .. tostring(result)) end
		given = ok and result == true
	end
	if given then
		states[player] = claimed
		-- (the reward's own save already stored the claim with it: no second write right now)
		pcall(api.Set.Invoke, api.Set, player, KEY, claimed)
		show(player)
		log(player.Name, "claimed day", day, reward.Kind)
	else
		pcall(api.Set.Invoke, api.Set, player, KEY, { Day = st.Day, At = st.At })
	end
	busy[player] = nil
	return given, (not given) and "Couldn't claim - try again." or nil
end

Remotes:WaitForChild("DailyClaim").OnServerInvoke = function(player)
	local t = os.clock()
	if t - (lastAsk[player] or 0) < ASK_GAP then return false, nil end
	lastAsk[player] = t
	return DailyRewards.Claim(player)
end

Players.PlayerAdded:Connect(function(player) task.spawn(load, player) end)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(load, player) end
Players.PlayerRemoving:Connect(function(player)
	states[player], busy[player], lastAsk[player] = nil, nil, nil
end)

-- Studio only: move the last claim back in time ("forward", seconds), or forget every claim ("reset")
if RunService:IsStudio() then
	local hook = Instance.new("BindableFunction")
	hook.Name = "DailyStudioTest"
	hook.OnInvoke = function(player, what, seconds)
		local st = states[player]
		local api = dataApi()
		if not st or not api then return "not loaded" end
		if what == "reset" then
			states[player] = { Day = 0, At = 0 }
		elseif what == "forward" then
			states[player] = { Day = st.Day, At = st.At - (tonumber(seconds) or Days.Interval) }
		end
		api.SaveNow:Invoke(player, KEY, states[player])
		show(player)
		return states[player]
	end
	hook.Parent = ServerStorage
end

return DailyRewards
