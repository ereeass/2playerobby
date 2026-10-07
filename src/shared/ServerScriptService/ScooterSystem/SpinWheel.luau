--=====================================================================
-- SpinWheel   (ScooterSystem, server)
--
-- The Daily Wheel by the lobby fountain (Workspace["Spin the Wheel"], StarterGui.
-- SpinWheelWindow). Everything is decided here; the client only ASKS to spin
-- (Remotes.SpinWheel).
--   Balance  ONE count of spins (Spins in the save): bought, earned and given all go on it.
--   Free     a spin EARNED by time in the game: every Shared.SpinWheel.Interval (15 min) of
--            playing adds 1 to the balance (saved at once) and the clock starts over. The
--            clock only runs while the player is in the server. How far along it is (Played,
--            seconds) is saved, so leaving at 7 minutes and rejoining carries on from 7
--            minutes - time away never counts, so it can't be farmed offline. While they play,
--            FreeAt is the server time the next one lands (never saved: worked out from Played
--            on join), which is what the countdown shows.
--   Spinning takes one from the balance. The SERVER rolls the slot
--            (Shared.SpinWheel.Slots Chance, a real percentage - the client never picks),
--            gives its reward (grant) and only then answers which slot, for the wheel to
--            land on. The spin and the reward are saved together before the answer, so
--            leaving mid-spin loses nothing and nothing can be won twice.
--   Rewards  Skin: ScooterSelection.GrantSkin (the Skins system's own OwnedScooters).
--            Revive: DeathManager.GiveRevives - Skip: SkipStage.GiveSkips (the same counts
--            REVIVE and Skip Stage spend and show, as the Daily Rewards give them).
--   Result   the slot, and what the client shows: { Text = Shared.SpinWheel.RewardText,
--            Chance = that slot's configured chance } - so the REWARD banner and the
--            confetti (Chance <= ConfettiChance) come from the server's own roll.
--            Already theirs: never a second copy; onDuplicate is where compensation goes
--            once it is decided (nothing yet), and the client is told it was a duplicate.
--   Buying   Shared.SpinWheel.Products. DonationHandler hands their receipts here
--            (IsProduct / ProcessReceipt); the spins go on the same balance.
--   Policy   bought spins are a PAID RANDOM ITEM, so Roblox's rule applies: each player's
--            PolicyService:GetPolicyInfoForPlayerAsync is checked on join, and where
--            ArePaidRandomItemsRestricted is true (or the check can't be made at all) they
--            can't buy spins. The purchase window is only ever opened HERE, after that check
--            (the client asks with Remotes.SpinWheel "buy"). The player's PaidSpinsBlocked
--            attribute tells the window (true = the buy buttons go, a note says why; missing
--            = not known yet, the buttons stay hidden). Free spins (played time) are for
--            everyone. A purchase that still arrives from a blocked player is honoured.
--   Saved    "SpinWheel" in the player's save (SettingsServer's PlayerData):
--            { Spins = the balance, Played = seconds played toward the next free spin }
--            (kept up to date in the save every few seconds, so leaving keeps the progress).
--            An older save ({ Spins, FreeAt }, the daily spin) is carried over once: a daily
--            spin that was ready goes on the balance.
--   Client   the player's SpinBalance and SpinFreeAt attributes; missing = not loaded yet.
-- Studio: ServerStorage.SpinWheelStudioTest:Invoke(player, "forward", seconds) moves the
-- free-spin clock on; (player, "add", n) adds spins; (player, "reset") = a new player;
-- (player, "rig", slot) makes their NEXT spin land on that slot (to test a prize);
-- (player, "odds", n) rolls n times and returns how often each slot came up;
-- (player, "policy", true/false) pretends their paid-random-items policy is restricted / allowed.
--=====================================================================

local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage       = game:GetService("ServerStorage")
local RS                  = game:GetService("ReplicatedStorage")
local MarketplaceService  = game:GetService("MarketplaceService")
local PolicyService       = game:GetService("PolicyService")

local Root    = RS:WaitForChild("ScooterSystem")
local Remotes = Root:WaitForChild("Remotes")
local Wheel   = require(Root:WaitForChild("Shared"):WaitForChild("SpinWheel"))
local Config  = require(Root:WaitForChild("Shared"):WaitForChild("Config"))
local ScooterSelection = require(script.Parent:WaitForChild("ScooterSelection"))

local KEY          = "SpinWheel"
local ATTR_BALANCE = "SpinBalance"
local ATTR_FREE    = "SpinFreeAt"
local ASK_GAP      = 0.5      -- seconds between one player's spin requests
local LOAD_WAIT    = 20       -- seconds a receipt waits for the player's save to load
local KEEP_EVERY   = 30       -- seconds between writing the play-time progress into the save
                              -- (leaving and the server closing write it too, so only a crash loses any)

local SpinWheel = {}
local states  = {}            -- [player] = { Spins, FreeAt }, once loaded
local busy    = {}
local lastAsk = {}
local rng     = Random.new()
local rigged  = {}            -- Studio only: [player] = the slot their next spin lands on
local ATTR_BLOCKED = "PaidSpinsBlocked"
local policy  = {}            -- [player] = true (may buy) / false (blocked); nil = not checked yet
local lastBuy = {}
local BLOCKED_TEXT = "Extra spins aren't available in your region."

local function log(...) if Config.DebugLogging then print("[SpinWheel]", ...) end end
local function now() return workspace:GetServerTimeNow() end

-- seconds played toward the next free spin, and what goes in the save
local function playedOf(st)
	return math.clamp(Wheel.Interval - (st.FreeAt - now()), 0, Wheel.Interval)
end
local function saved(st)
	return { Spins = st.Spins, Played = math.floor(playedOf(st)) }
end

local function dataApi()
	local settings = ServerScriptService:WaitForChild("SettingsServer", 10)
	return settings and settings:WaitForChild("PlayerData", 10)
end

local function show(player)
	local st = states[player]
	if not st or not player.Parent then return end
	player:SetAttribute(ATTR_BALANCE, st.Spins)
	player:SetAttribute(ATTR_FREE, st.FreeAt)
end

local function load(player)
	local api = dataApi()
	if not api then return end
	local ok, value, loadState = pcall(api.Get.Invoke, api.Get, player, KEY)
	if states[player] or player.Parent ~= Players then return end
	if not ok or loadState == "failed" then
		warn("[SpinWheel] couldn't load " .. player.Name .. "'s spins")
		return
	end
	local spins, played = 0, 0
	if type(value) == "table" then
		spins = math.max(math.floor(tonumber(value.Spins) or 0), 0)
		played = math.clamp(tonumber(value.Played) or 0, 0, Wheel.Interval)
		-- an older save (the daily spin): a daily spin that was ready is kept, on the balance
		if value.Played == nil and tonumber(value.FreeAt) and tonumber(value.FreeAt) <= now() then
			spins += 1
		end
	else
		spins = 0   -- a new player: no starter spin; their first comes after 15 minutes of play
	end
	-- the clock carries on from where they left it
	states[player] = { Spins = spins, FreeAt = now() + Wheel.Interval - played }
	pcall(api.Set.Invoke, api.Set, player, KEY, saved(states[player]))
	show(player)
end

local function loaded(player)
	local t0 = os.clock()
	while player.Parent == Players and not states[player] and os.clock() - t0 < LOAD_WAIT do task.wait(0.2) end
	return states[player]
end

-- a slot's real chance (percent)
local function chanceOf(s)
	return math.max(tonumber(s.Chance or s.Weight) or 0, 0)
end

-- the roll: slot i comes up Chance / (sum of Chances) of the time
local function roll()
	local total = 0
	for _, s in ipairs(Wheel.Slots) do total += chanceOf(s) end
	local r = rng:NextNumber() * total
	for i, s in ipairs(Wheel.Slots) do
		r -= chanceOf(s)
		if r < 0 then return i end
	end
	return #Wheel.Slots
end

local function pick(player)
	if RunService:IsStudio() and rigged[player] then   -- Studio test only (see the header)
		local slot = rigged[player]
		rigged[player] = nil
		return slot
	end
	return roll()
end

-- A prize they already own (e.g. the Rainbow Scooter again). Nothing extra yet: when the
-- compensation is decided, give it here and return true once it is saved.
local function onDuplicate(player, slot)
	return true
end

-- the slot's reward, through the system that owns it: true once theirs and saved, and
-- whether it was one they already had
local function grant(player, slot)
	local reward = Wheel.Slots[slot] and Wheel.Slots[slot].Reward
	if not reward then return true, false end               -- no reward set for this slot yet
	if reward.Kind == "Skin" then
		local ok, isNew = ScooterSelection.GrantSkin(player, reward.Skin)
		if not ok then return false, false end
		if not isNew then return onDuplicate(player, slot), true end
		return true, false
	end
	if reward.Kind == "Revive" then
		return require(script.Parent:WaitForChild("DeathManager")).GiveRevives(player, reward.Amount or 1) == true, false
	end
	if reward.Kind == "Skip" then
		return require(script.Parent:WaitForChild("SkipStage")).GiveSkips(player, reward.Amount or 1) == true, false
	end
	warn("[SpinWheel] slot " .. slot .. " has an unknown reward kind: " .. tostring(reward.Kind))
	return false, false
end

-- Uses one spin (the free one first) and lands on a slot:
-- true, slot, usedFree, alreadyOwned, { Text, Chance } - or false, why
function SpinWheel.Spin(player)
	local st = states[player]
	if not st then return false, "Still loading - try again in a moment." end
	if busy[player] then return false, nil end
	if st.Spins <= 0 then return false, "No spins left!" end
	local free = false   -- (free spins are earned onto the balance: see the header)
	local api = dataApi()
	if not api then return false, "Couldn't spin - try again." end
	busy[player] = true
	local slot = pick(player)
	local after = { Spins = st.Spins - 1, FreeAt = st.FreeAt }
	-- the spin is spent in the save first (kept in memory), so the reward's own save writes both
	pcall(api.Set.Invoke, api.Set, player, KEY, saved(after))
	local ok, given, duplicate = pcall(grant, player, slot)
	if not (ok and given) then
		pcall(api.Set.Invoke, api.Set, player, KEY, saved(st))
		busy[player] = nil
		warn("[SpinWheel] couldn't give slot " .. slot .. " to " .. player.Name .. ": " .. tostring(given))
		return false, "Couldn't spin - try again."
	end
	after.FreeAt = states[player].FreeAt   -- (the clock kept running meanwhile)
	after.Spins = states[player].Spins - 1  -- (and a spin it earned meanwhile is kept)
	states[player] = after
	-- A new reward's own save already stored the spent spin with it, so this only brings the
	-- clock up to date and goes with the next regular write (no second write right now). A
	-- duplicate saved nothing, so then the spent spin is written at once.
	if duplicate then
		pcall(api.SaveNow.Invoke, api.SaveNow, player, KEY, saved(after))
	else
		pcall(api.Set.Invoke, api.Set, player, KEY, saved(after))
	end
	show(player)
	busy[player] = nil
	log(player.Name, "spun", free and "(free)" or "", "->", slot, Wheel.Slots[slot].Name, duplicate and "(already owned)" or "")
	return true, slot, free, duplicate == true, { Text = Wheel.RewardText(slot), Chance = chanceOf(Wheel.Slots[slot]) }
end

---------------------------------------------------------------- bought spins
-- how many spins a Developer Product gives (nil: not one of the wheel's)
local function spinsFor(productId)
	for _, p in ipairs(Wheel.Products) do
		if p.ProductId and p.ProductId ~= 0 and p.ProductId == productId then return p.Spins end
	end
	return nil
end

function SpinWheel.IsProduct(productId)
	return spinsFor(productId) ~= nil
end

-- DonationHandler's ProcessReceipt: the spins go on the balance; granted only once saved.
-- One change to the balance at a time: a spin in progress (or another purchase being saved)
-- is waited for, then the balance is held (busy: no spin, no earned spin, no other purchase)
-- from reading it to saving it, so nothing can change it in between and be overwritten.
local granted = {}   -- [PurchaseId] = true: handled on this server
local BUSY_WAIT = 20 -- seconds a receipt waits for a spin in progress; then Roblox offers it again
function SpinWheel.ProcessReceipt(receipt)
	if granted[receipt.PurchaseId] then return Enum.ProductPurchaseDecision.PurchaseGranted end
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local st = player and loaded(player)
	local api = st and dataApi()
	if not (st and api) then return Enum.ProductPurchaseDecision.NotProcessedYet end
	local t0 = os.clock()
	while busy[player] and player.Parent == Players and os.clock() - t0 < BUSY_WAIT do task.wait(0.1) end
	if granted[receipt.PurchaseId] then return Enum.ProductPurchaseDecision.PurchaseGranted end   -- (handled meanwhile)
	st = states[player]   -- the balance as it is now, after whatever was in progress
	if busy[player] or not st or player.Parent ~= Players then return Enum.ProductPurchaseDecision.NotProcessedYet end
	busy[player] = true
	local after = { Spins = st.Spins + (spinsFor(receipt.ProductId) or 0), FreeAt = st.FreeAt }
	local ok, stored = pcall(api.SaveNow.Invoke, api.SaveNow, player, KEY, saved(after))
	if not (ok and stored) then
		-- not stored: the save goes back to what it was, so Roblox's retry can't add them twice
		pcall(api.Set.Invoke, api.Set, player, KEY, saved(st))
		busy[player] = nil
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if player.Parent == Players then
		states[player] = after
		show(player)
	end
	busy[player] = nil
	granted[receipt.PurchaseId] = true
	log(player.Name, "bought", spinsFor(receipt.ProductId), "spins")
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

---------------------------------------------------------------- the paid random items policy
-- Roblox's GetPolicyInfoForPlayerAsync, a few tries; if it never answers the player counts as
-- blocked (safe side: a Roblox outage never lets a restricted player buy)
local function checkPolicy(player)
	local allowed = false
	for attempt = 1, 4 do
		local ok, info = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
		if ok and type(info) == "table" then
			allowed = info.ArePaidRandomItemsRestricted == false
			break
		end
		if player.Parent ~= Players then return end
		task.wait(attempt * 2)
	end
	if player.Parent ~= Players then return end
	policy[player] = allowed
	player:SetAttribute(ATTR_BLOCKED, not allowed)
	log(player.Name, allowed and "may buy spins" or "can't buy spins (paid random items restricted)")
end

-- may this player buy spins? waits a little for the check if it's still running
local function mayBuy(player)
	local t0 = os.clock()
	while policy[player] == nil and player.Parent == Players and os.clock() - t0 < 10 do task.wait(0.2) end
	return policy[player] == true
end

-- the buy buttons ask here; only an allowed player ever gets the purchase window
local function buy(player, index)
	local p = type(index) == "number" and Wheel.Products[index]
	if not p then return false, nil end
	if not p.ProductId or p.ProductId == 0 then return false, "Coming soon!" end
	local t = os.clock()
	if t - (lastBuy[player] or 0) < ASK_GAP then return false, nil end
	lastBuy[player] = t
	if not mayBuy(player) then
		Remotes.Notice:FireClient(player, BLOCKED_TEXT)   -- the red notice; no purchase window
		return false, BLOCKED_TEXT
	end
	local ok, err = pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, player, p.ProductId)
	if not ok then warn("[SpinWheel] purchase prompt failed: " .. tostring(err)) return false, "Couldn't open the purchase - try again." end
	return true, nil
end

---------------------------------------------------------------- remote
Remotes:WaitForChild("SpinWheel").OnServerInvoke = function(player, what, arg)
	if what == "buy" then return buy(player, arg) end
	if what ~= "spin" then return false, nil end
	local t = os.clock()
	if t - (lastAsk[player] or 0) < ASK_GAP then return false, nil end
	lastAsk[player] = t
	return SpinWheel.Spin(player)
end

Players.PlayerAdded:Connect(function(player) task.spawn(load, player); task.spawn(checkPolicy, player) end)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(load, player); task.spawn(checkPolicy, player) end
Players.PlayerRemoving:Connect(function(player)
	policy[player], lastBuy[player] = nil, nil
	-- the clock's progress goes in the save as they leave (it is kept there every few seconds too) -
	-- unless a spin or a purchase is being saved right now: that save already holds the balance
	-- (and the clock), and this older copy written over it would undo it (as on shutdown, below)
	local st, api = states[player], states[player] and dataApi()
	if st and api and not busy[player] then pcall(api.Set.Invoke, api.Set, player, KEY, saved(st)) end
	states[player], busy[player], lastAsk[player] = nil, nil, nil
end)

-- the server closing: everyone's progress goes in the save (SettingsServer writes it out)
game:BindToClose(function()
	local api = dataApi()
	if not api then return end
	for player, st in pairs(states) do
		if not busy[player] then pcall(api.Set.Invoke, api.Set, player, KEY, saved(st)) end
	end
end)

---------------------------------------------------------------- the play-time clock
-- Every second: a player whose 15 minutes are up gets their spin (saved at once) and the
-- clock starts over. Every KEEP_EVERY seconds the progress is written into the save, so
-- leaving (or the server closing) keeps it.
task.spawn(function()
	local lastKeep = os.clock()
	while true do
		task.wait(1)
		local api = dataApi()
		local keep = os.clock() - lastKeep >= KEEP_EVERY
		if keep then lastKeep = os.clock() end
		for player, st in pairs(states) do
			if player.Parent == Players and api and not busy[player] then
				if now() >= st.FreeAt then
					local after = { Spins = st.Spins + 1, FreeAt = now() + Wheel.Interval }
					states[player] = after
					pcall(api.SaveNow.Invoke, api.SaveNow, player, KEY, saved(after))
					show(player)
					log(player.Name, "earned a spin by playing")
				elseif keep then
					pcall(api.Set.Invoke, api.Set, player, KEY, saved(st))
				end
			end
		end
	end
end)

-- Studio only (see the header)
if RunService:IsStudio() then
	local hook = Instance.new("BindableFunction")
	hook.Name = "SpinWheelStudioTest"
	hook.OnInvoke = function(player, what, n)
		if what == "policy" then   -- (player, "policy", true) = pretend they're restricted; false = allowed
			policy[player] = not n
			player:SetAttribute(ATTR_BLOCKED, n == true)
			return "PaidSpinsBlocked = " .. tostring(n == true)
		end
		local st = states[player]
		local api = dataApi()
		if not st or not api then return "not loaded" end
		if what == "reset" then
			states[player] = { Spins = 0, FreeAt = now() + Wheel.Interval }
		elseif what == "forward" then
			states[player] = { Spins = st.Spins, FreeAt = st.FreeAt - (tonumber(n) or Wheel.Interval) }
		elseif what == "add" then
			states[player] = { Spins = st.Spins + (tonumber(n) or 1), FreeAt = st.FreeAt }
		elseif what == "rig" then
			rigged[player] = tonumber(n)
			return "next spin lands on slot " .. tostring(n)
		elseif what == "odds" then
			local counts = {}
			for _ = 1, tonumber(n) or 100000 do
				local s = roll()
				counts[s] = (counts[s] or 0) + 1
			end
			return counts
		end
		api.SaveNow:Invoke(player, KEY, saved(states[player]))
		show(player)
		return states[player]
	end
	hook.Parent = ServerStorage
end

return SpinWheel
