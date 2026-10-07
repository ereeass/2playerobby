--=====================================================================
-- Crates   (ScooterSystem, server)
--
-- The Shop's crates (Shared.Crates). Everything is decided here; the client only ASKS to buy
-- (Remotes.CrateBuy) and plays what it is told (Remotes.CrateOpened).
--   Buying    the BUY button asks CrateBuy; the purchase window is only ever opened HERE,
--             after the paid random items check: a crate is a PAID RANDOM ITEM, so where
--             Roblox's ArePaidRandomItemsRestricted is true (the player's PaidSpinsBlocked
--             attribute, checked on join by ScooterSystem.SpinWheel) it can't be bought.
--   Receipt   DonationHandler hands a crate's receipt here (IsProduct / ProcessReceipt). The
--             SERVER rolls the prize (each Prize's Chance, a real percentage), gives it and
--             saves it together with the receipt's PurchaseId (CrateReceipts in the save,
--             the last KEEP_RECEIPTS) in ONE write - so a receipt Roblox sends again, on any
--             server, is recognised and never opens a second crate, and leaving or a crash
--             mid-opening loses nothing. Only then is the purchase confirmed.
--   Prize     a new scooter: ScooterSelection.GrantSkin (OwnedScooters - it shows as owned in
--             Skins). One they already own: the crate's Duplicate instead (revives / skips).
--   Opening   Remotes.CrateOpened to the owner (see announce): once it plays for them, every
--             player near them sees the crate drop and open
--             (StarterPlayerScripts.CrateOpenFx); the prize is already theirs by then.
--   Log       the team's Discord (ScooterWebhook.LogCrate).
-- Gifts     see "gifts" below (GiftProductId; the skin gifts' rules, ScooterSystem.Gifting).
-- Studio: ServerStorage.CrateStudioTest:Invoke(player, "open", crateId[, skin]) plays an
-- opening for them WITHOUT giving or saving anything (skin = force that prize);
-- (player, "odds", crateId, n) rolls n times and returns how often each prize came up.
--=====================================================================

local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage       = game:GetService("ServerStorage")
local RS                  = game:GetService("ReplicatedStorage")
local MarketplaceService  = game:GetService("MarketplaceService")

local Root      = RS:WaitForChild("ScooterSystem")
local Remotes   = Root:WaitForChild("Remotes")
local Shared    = require(Root:WaitForChild("Shared"):WaitForChild("Crates"))
local Scooters  = require(Root:WaitForChild("Shared"):WaitForChild("Scooters"))
local Config    = require(Root:WaitForChild("Shared"):WaitForChild("Config"))
local ScooterSelection = require(script.Parent:WaitForChild("ScooterSelection"))

local KEY           = "CrateReceipts"   -- the save: the last purchases opened (their PurchaseIds)
local KEEP_RECEIPTS = 100
local ASK_GAP       = 0.6               -- seconds between one player's buy requests
local POLICY_WAIT   = 10                -- seconds a buy waits for the paid random items check
local LOAD_WAIT     = 20                -- seconds a receipt waits for the player's save
local ATTR_BLOCKED  = "PaidSpinsBlocked"
local BLOCKED_TEXT  = "Crates aren't available in your region."

local Crates  = {}
local rng     = Random.new()
local lastBuy = {}
local locks   = {}

local function log(...) if Config.DebugLogging then print("[Crates]", ...) end end

local function dataApi()
	local settings = ServerScriptService:WaitForChild("SettingsServer", 10)
	return settings and settings:WaitForChild("PlayerData", 10)
end

-- the roll: prize i comes up Chance / (sum of Chances) of the time
local function roll(c)
	local total = 0
	for _, p in ipairs(c.Prizes) do total += math.max(tonumber(p.Chance) or 0, 0) end
	local r = rng:NextNumber() * total
	for _, p in ipairs(c.Prizes) do
		r -= math.max(tonumber(p.Chance) or 0, 0)
		if r < 0 then return p end
	end
	return c.Prizes[#c.Prizes]
end

-- the duplicate's bonus, through the system that owns it: true once saved
local function giveBonus(player, d)
	if not d then return true end
	if d.Kind == "Revive" then
		return require(script.Parent:WaitForChild("DeathManager")).GiveRevives(player, d.Amount or 1) == true
	end
	if d.Kind == "Skip" then
		return require(script.Parent:WaitForChild("SkipStage")).GiveSkips(player, d.Amount or 1) == true
	end
	warn("[Crates] unknown duplicate kind: " .. tostring(d.Kind))
	return false
end

-- An opening is sent to its owner ONLY. Their game plays it once they're free in the lobby
-- (CrateOpenFx) and only then says so (Remotes.CrateShow, with the token): that is when everyone
-- else is shown it - so nobody sees someone's crate open before they do themselves.
local Http  = game:GetService("HttpService")
local shows = {}   -- [player] = { [token] = { crateId, skin, bonus, from } }
local function announce(player, crateId, skin, bonus, from)
	local token = Http:GenerateGUID(false)
	shows[player] = shows[player] or {}
	shows[player][token] = { crateId, skin, bonus, from }
	Remotes.CrateOpened:FireClient(player, player, crateId, skin, bonus, from, token)
end
Remotes:WaitForChild("CrateShow").OnServerEvent:Connect(function(player, token)
	local list = shows[player]
	local e = type(token) == "string" and list and list[token]
	if not e then return end
	list[token] = nil
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then Remotes.CrateOpened:FireClient(other, player, e[1], e[2], e[3], e[4]) end
	end
end)
Players.PlayerRemoving:Connect(function(player) shows[player] = nil end)

function Crates.IsProduct(productId)
	return Shared.ForProduct(productId) ~= nil
end

-- Opens a crate for this player (in this server): rolls the prize, gives it and saves it with
-- the purchase id in ONE write, then everyone near them sees it open. from = the gifter's name
-- (a gift). "granted" / "later" (couldn't save: Roblox offers the receipt again).
local function openFor(player, crateId, c, purchaseId, receipt, from, giftFrom)
	-- their Skins save must be loaded (Owns waits for it; nil = it never loaded)
	if ScooterSelection.Owns(player, c.Prizes[1].Skin, true) == nil then return "later" end
	local api = dataApi()
	if not api then return "later" end

	-- one at a time per player
	local t0 = os.clock()
	while locks[player] and os.clock() - t0 < LOAD_WAIT do task.wait(0.1) end
	if locks[player] then return "later" end
	locks[player] = true
	local function done(r) locks[player] = nil return r end

	local ok, list, loadState = pcall(api.Get.Invoke, api.Get, player, KEY)
	if not ok or loadState == "failed" then return done("later") end
	list = type(list) == "table" and list or {}
	if table.find(list, purchaseId) then return done("granted") end   -- opened already

	local prize = roll(c)
	local owned = ScooterSelection.Owns(player, prize.Skin) == true
	-- the receipt goes in the save with the prize: the prize's own save writes both at once
	local after = table.clone(list)
	table.insert(after, purchaseId)
	while #after > KEEP_RECEIPTS do table.remove(after, 1) end
	pcall(api.Set.Invoke, api.Set, player, KEY, after)
	local given
	if owned then
		given = giveBonus(player, c.Duplicate)
	else
		local okG, isNew = ScooterSelection.GrantSkin(player, prize.Skin)
		given = okG == true
		if given and not isNew then given = giveBonus(player, c.Duplicate); owned = true end   -- (owned meanwhile)
	end
	if not given then
		pcall(api.Set.Invoke, api.Set, player, KEY, list)        -- not saved: Roblox offers it again
		warn("[Crates] couldn't give " .. player.Name .. " their crate prize (" .. prize.Skin .. ") - it will be offered again")
		return done("later")
	end
	local bonus = owned and c.Duplicate and c.Duplicate.Text or nil
	announce(player, crateId, prize.Skin, bonus, from)
	log(player.Name, "opened", crateId, from and ("(gift from " .. from .. ")") or "", "->", prize.Skin, bonus and ("(duplicate: " .. bonus .. ")") or "")
	if receipt then
		pcall(function()
			require(script.Parent:WaitForChild("ScooterWebhook")).LogCrate(receipt, Scooters.Get(prize.Skin), c, bonus, giftFrom and player.UserId or nil)
		end)
	end
	return done("granted")
end

---------------------------------------------------------------- gifts
-- A crate bought for someone else in the server: the Shop's gift button (ShopUI.Menu's gift
-- page) lists the players here; GIFT asks CrateGiftRequest. The server notes who it's for in
-- ScooterGifts_v1 ("c_<buyer>_<crate>") BEFORE the purchase window opens (so a receipt that
-- arrives later, on any server, still finds it), then opens the crate's GiftProductId.
--   receiver here     openFor(receiver): their prize, their save; their opening waits until
--                     they're free in the lobby (CrateOpenFx): "GIFT FROM <buyer>!"
--   receiver left     the prize is rolled and added to their save straight away (OwnedScooters
--                     only ever grows), with the opening kept in CratePending: it plays when
--                     they next join (a duplicate's bonus is given then too)
--   nobody noted      the buyer opens it themselves
-- The note then only says which purchase it was, so a receipt offered again is never opened twice.
local DataStoreService = game:GetService("DataStoreService")
local HttpService      = game:GetService("HttpService")
local STUDIO = RunService:IsStudio()
local SAVE_STORE, GIFT_STORE = "PlayerSettings_v1", "ScooterGifts_v1"
local PENDING_KEY = "CratePending"
local function getStore(name)
	local ok, st = pcall(DataStoreService.GetDataStore, DataStoreService, name)
	return ok and st or nil
end
local saveStore, giftStore = getStore(SAVE_STORE), getStore(GIFT_STORE)
local function noAccess(err)
	err = tostring(err)
	return err:find("StudioAccessToApisNotAllowed") or err:find("Studio access") or err:find("403")
end
local notes = {}
local function noteKey(buyerId, crateId) return ("c_%d_%s"):format(buyerId, crateId) end
local function writeNote(buyerId, crateId, note)
	notes[buyerId .. ":" .. crateId] = note
	if not giftStore then return STUDIO end
	local ok, err = pcall(giftStore.SetAsync, giftStore, noteKey(buyerId, crateId), note)
	if ok then return true end
	if STUDIO and noAccess(err) then return true end
	warn("[Crates] couldn't note a crate gift: " .. tostring(err))
	return false
end
local function readNote(buyerId, crateId)
	local mine = notes[buyerId .. ":" .. crateId]
	if mine then return mine, true end
	if not giftStore then return nil, true end
	local ok, result = pcall(giftStore.GetAsync, giftStore, noteKey(buyerId, crateId))
	if ok then return type(result) == "table" and result or nil, true end
	if STUDIO and noAccess(result) then return nil, true end
	warn("[Crates] couldn't read a crate gift note: " .. tostring(result))
	return nil, false
end
local function markDone(buyerId, crateId, purchaseId)
	local note = { done = purchaseId }
	notes[buyerId .. ":" .. crateId] = note
	if giftStore then pcall(giftStore.SetAsync, giftStore, noteKey(buyerId, crateId), note) end
end
-- A crate gift paid for but not delivered yet keeps its note: a new gift of the same crate by the
-- same buyer would write over it and the paid one would go to the NEW receiver. So the purchase
-- window closing with a purchase marks the note paid (Token: only the note written for that
-- prompt, never one delivered or replaced since), and a new gift of that crate waits until it is
-- delivered (giftRequest, "pending"). An older paid mark than PAID_HOLD no longer blocks, so a note
-- whose "done" was never written can't stop that crate being gifted for ever.
local PAID_HOLD = 24 * 3600
local function awaitingDelivery(note)
	return type(note) == "table" and type(note.to) == "number" and note.paid == true and note.done == nil
		and os.time() - (tonumber(note.paidAt) or 0) < PAID_HOLD
end
local function markPaid(buyerId, crateId)
	local note = notes[buyerId .. ":" .. crateId]
	if not (type(note) == "table" and type(note.to) == "number" and note.token and note.done == nil) then return end
	local token, at = note.token, os.time()
	note.paid, note.paidAt = true, at
	if not giftStore then return end
	local ok, err = pcall(giftStore.UpdateAsync, giftStore, noteKey(buyerId, crateId), function(old)
		if type(old) ~= "table" or old.token ~= token or old.done ~= nil then return nil end   -- not that note any more
		old.paid, old.paidAt = true, at
		return old
	end)
	if not ok and not (STUDIO and noAccess(err)) then warn("[Crates] couldn't mark a crate gift as paid: " .. tostring(err)) end
end
-- Is this buyer's last gift of this crate paid for and still waiting to be delivered? Read from
-- the store (another server may have delivered it since this one's copy was made); this server's
-- copy also counts while the store still holds that same undelivered note (its paid mark may not
-- have been written). (answer, read ok) - not ok: the store couldn't be read.
local function stillPaidFor(buyerId, crateId)
	local mine = notes[buyerId .. ":" .. crateId]
	if not giftStore then return awaitingDelivery(mine), true end
	local ok, stored = pcall(giftStore.GetAsync, giftStore, noteKey(buyerId, crateId))
	if not ok then
		if STUDIO and noAccess(stored) then return awaitingDelivery(mine), true end
		warn("[Crates] couldn't read a crate gift note: " .. tostring(stored))
		return false, false
	end
	stored = type(stored) == "table" and stored or nil
	if awaitingDelivery(stored) then return true, true end
	return awaitingDelivery(mine) and stored ~= nil and stored.token == mine.token and stored.done == nil, true
end
MarketplaceService.PromptProductPurchaseFinished:Connect(function(who, productId, purchased)
	if not purchased then return end
	local crateId, _, isGift = Shared.ForProduct(productId)
	if not (crateId and isGift) then return end
	local userId = (typeof(who) == "Instance" and who.UserId) or tonumber(who)
	if userId then task.spawn(markPaid, userId, crateId) end
end)
local function nameOf(userId, fallback)
	local p = Players:GetPlayerByUserId(userId)
	if p then return p.DisplayName end
	if fallback then return fallback end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	return ok and name or "someone"
end
local function tellBuyer(buyerId, kind, toName)
	local p = Players:GetPlayerByUserId(buyerId)
	if p then Remotes.CrateGiftResult:FireClient(p, kind, toName) end
end

-- the receiver isn't in this server: the prize goes straight into their save with the purchase
-- id (so it is never opened twice) and the opening waits in CratePending for their next join.
-- A duplicate's bonus is given on that join (revives aren't merged across servers like skins).
local function openOffline(userId, crateId, c, purchaseId, from)
	if not saveStore then return false end
	local prize = roll(c)
	local ok, err = pcall(saveStore.UpdateAsync, saveStore, "u_" .. userId, function(old)
		local data = type(old) == "table" and old or {}
		local list = type(data[KEY]) == "table" and table.clone(data[KEY]) or {}
		if table.find(list, purchaseId) then return nil end                 -- done already
		table.insert(list, purchaseId)
		while #list > KEEP_RECEIPTS do table.remove(list, 1) end
		data[KEY] = list
		local owned = type(data.OwnedScooters) == "table" and table.clone(data.OwnedScooters) or {}
		local dup = table.find(owned, prize.Skin) ~= nil
		if not dup then
			table.insert(owned, prize.Skin)
			table.sort(owned)
			data.OwnedScooters = owned
		end
		local pending = type(data[PENDING_KEY]) == "table" and table.clone(data[PENDING_KEY]) or {}
		table.insert(pending, { Crate = crateId, Skin = prize.Skin, Dup = dup, From = from })
		data[PENDING_KEY] = pending
		return data
	end)
	if not ok then warn("[Crates] couldn't save a crate gift for " .. userId .. ": " .. tostring(err)) end
	return ok
end

local giftsDone = {}
local function deliverGift(receipt, crateId, c)
	local buyerId, purchaseId = receipt.PlayerId, receipt.PurchaseId
	if giftsDone[purchaseId] then return true end
	local note, readOk = readNote(buyerId, crateId)
	if not readOk then return false end
	if note and note.done == purchaseId then giftsDone[purchaseId] = true return true end
	local buyerName = nameOf(buyerId)
	local to = note and type(note.to) == "number" and note.to or nil
	if to == buyerId then to = nil end
	if not to then
		-- nobody to give it to any more: the buyer opens it themselves
		local buyer = Players:GetPlayerByUserId(buyerId)
		if not buyer then return false end                                  -- when they're back
		if openFor(buyer, crateId, c, purchaseId, receipt, nil, nil) ~= "granted" then return false end
		tellBuyer(buyerId, "self", nil)
	else
		local toName = nameOf(to, note.toName)
		local target = Players:GetPlayerByUserId(to)
		if target then
			if openFor(target, crateId, c, purchaseId, receipt, buyerName, buyerId) ~= "granted" then return false end
		else
			if not openOffline(to, crateId, c, purchaseId, buyerName) then return false end
			pcall(function() require(script.Parent:WaitForChild("ScooterWebhook")).LogCrate(receipt, nil, c, nil, to) end)
		end
		tellBuyer(buyerId, "sent", toName)
	end
	giftsDone[purchaseId] = true
	markDone(buyerId, crateId, purchaseId)
	return true
end

-- DonationHandler's ProcessReceipt for a crate or a crate gift (see the header)
function Crates.ProcessReceipt(receipt)
	local crateId, c, isGift = Shared.ForProduct(receipt.ProductId)
	if not c then return Enum.ProductPurchaseDecision.NotProcessedYet end
	if isGift then
		local ok, result = pcall(deliverGift, receipt, crateId, c)
		if not ok then warn("[Crates] delivering a crate gift failed: " .. tostring(result)) end
		return (ok and result) and Enum.ProductPurchaseDecision.PurchaseGranted or Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end   -- offered again when they're back
	local r = openFor(player, crateId, c, receipt.PurchaseId, receipt, nil, nil)
	return r == "granted" and Enum.ProductPurchaseDecision.PurchaseGranted or Enum.ProductPurchaseDecision.NotProcessedYet
end

-- a crate gift opened for them while they were away: it plays now (and a duplicate's bonus is given)
local function openPending(player)
	local api = dataApi()
	if not api or player.Parent ~= Players then return end
	local ok, pending, loadState = pcall(api.Get.Invoke, api.Get, player, PENDING_KEY)
	if not ok or loadState == "failed" or type(pending) ~= "table" or #pending == 0 then return end
	if ScooterSelection.Owns(player, "Red", true) == nil then return end   -- Skins save loaded (it has the prize)
	-- cleared in the save in the same write as any bonus (GiveRevives saves at once)
	pcall(api.Set.Invoke, api.Set, player, PENDING_KEY, {})
	local bonusGiven = true
	for _, e in ipairs(pending) do
		local c = Shared.Get(e.Crate)
		if c and e.Dup then bonusGiven = giveBonus(player, c.Duplicate) and bonusGiven end
	end
	if not bonusGiven then
		pcall(api.Set.Invoke, api.Set, player, PENDING_KEY, pending)         -- the next join tries again
		return
	end
	pcall(api.SaveNow.Invoke, api.SaveNow, player, PENDING_KEY, {})
	for _, e in ipairs(pending) do
		local c = Shared.Get(e.Crate)
		if c then
			announce(player, e.Crate, e.Skin, e.Dup and c.Duplicate and c.Duplicate.Text or nil, e.From)
		end
	end
end
Players.PlayerAdded:Connect(function(p) task.delay(3, openPending, p) end)
for _, p in ipairs(Players:GetPlayers()) do task.delay(3, openPending, p) end

-- who a crate could be gifted to (everyone else here; a crate can always be given)
local lastList, lastGift, giftBusy = {}, {}, {}
local function giftTargets(player, crateId)
	if not Shared.Get(crateId) then return nil end
	local t = os.clock()
	if t - (lastList[player] or -math.huge) < 0.4 then return nil end
	lastList[player] = t
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then table.insert(list, { UserId = p.UserId, Owns = false }) end
	end
	return list
end

-- "prompt" / "gone" / "self" / "busy" / "blocked" / "pending" / "failed" (as the skin gifts', ScooterSystem.Gifting)
local function giftRequest(player, crateId, toUserId)
	local c = Shared.Get(crateId)
	if not c or type(toUserId) ~= "number" then return "failed" end
	if not c.GiftProductId or c.GiftProductId == 0 then return "failed" end
	if giftBusy[player] then return "busy" end
	local t = os.clock()
	if t - (lastGift[player] or -math.huge) < 1.5 then return "busy" end
	lastGift[player] = t
	if toUserId == player.UserId then return "self" end
	local target = Players:GetPlayerByUserId(toUserId)
	if not target then return "gone" end
	-- a crate is a paid random item: the buyer must be allowed to buy one
	local t0 = os.clock()
	while player:GetAttribute(ATTR_BLOCKED) == nil and player.Parent == Players and os.clock() - t0 < POLICY_WAIT do task.wait(0.2) end
	if not Shared.Allowed(player) then return "blocked" end
	giftBusy[player] = true
	-- their last gift of this crate is paid for but not delivered yet: its note stays (see markPaid)
	local waiting, readOk = stillPaidFor(player.UserId, crateId)
	if not readOk then giftBusy[player] = nil return "failed" end
	if waiting then giftBusy[player] = nil return "pending" end
	local ok = writeNote(player.UserId, crateId, { to = toUserId, toName = target.DisplayName, at = os.time(),
		token = HttpService:GenerateGUID(false) })
	giftBusy[player] = nil
	if not ok or player.Parent ~= Players then return "failed" end
	local okP, err = pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, player, c.GiftProductId)
	if not okP then warn("[Crates] gift purchase prompt failed: " .. tostring(err)) return "failed" end
	return "prompt"
end

-- the BUY button asks here; only an allowed player ever gets the purchase window
local function buy(player, crateId, check)
	local c = type(crateId) == "string" and Shared.Get(crateId)
	if not c then return false, nil end
	if not c.ProductId or c.ProductId == 0 then return false, "Coming soon!" end
	local t = os.clock()
	if t - (lastBuy[player] or 0) < ASK_GAP then return false, nil end
	lastBuy[player] = t
	local t0 = os.clock()
	while player:GetAttribute(ATTR_BLOCKED) == nil and player.Parent == Players and os.clock() - t0 < POLICY_WAIT do task.wait(0.2) end
	if not Shared.Allowed(player) then
		Remotes.Notice:FireClient(player, BLOCKED_TEXT)   -- the red notice; no purchase window
		return false, BLOCKED_TEXT
	end
	if check then return true, nil end                    -- (the gift button only asked: allowed)
	local ok, err = pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, player, c.ProductId)
	if not ok then warn("[Crates] purchase prompt failed: " .. tostring(err)) return false, "Couldn't open the purchase - try again." end
	return true, nil
end

Remotes:WaitForChild("CrateBuy").OnServerInvoke = function(player, crateId, check)
	return buy(player, crateId, check == "check")
end
Remotes:WaitForChild("CrateGiftTargets").OnServerInvoke = function(player, crateId)
	if type(crateId) ~= "string" then return nil end
	return giftTargets(player, crateId)
end
Remotes:WaitForChild("CrateGiftRequest").OnServerInvoke = function(player, crateId, toUserId)
	if type(crateId) ~= "string" then return "failed" end
	return giftRequest(player, crateId, toUserId)
end
Players.PlayerRemoving:Connect(function(player)
	lastBuy[player], locks[player], lastList[player], lastGift[player], giftBusy[player] = nil, nil, nil, nil, nil
end)

-- Studio only (see the header): an opening that gives and saves NOTHING
if RunService:IsStudio() and not ServerStorage:FindFirstChild("CrateStudioTest") then
	local hook = Instance.new("BindableFunction")
	hook.Name = "CrateStudioTest"
	hook.OnInvoke = function(player, what, crateId, arg)
		local c = Shared.Get(crateId or "Premium")
		if not c then return "no crate " .. tostring(crateId) end
		if what == "odds" then
			local counts = {}
			for _ = 1, tonumber(arg) or 100000 do
				local p = roll(c)
				counts[p.Skin] = (counts[p.Skin] or 0) + 1
			end
			return counts
		end
		if what == "receipt" then   -- (player, "receipt", crateId, giftToUserId): a REAL receipt, as if paid
			-- (Studio only, and it gives and saves for real: use test accounts)
			local cc = Shared.Get(crateId or "Premium")
			if arg then writeNote(player.UserId, crateId or "Premium", { to = arg, toName = nameOf(arg), at = os.time() }) end
			local r = { PlayerId = player.UserId, ProductId = arg and cc.GiftProductId or cc.ProductId,
				PurchaseId = "studio-" .. HttpService:GenerateGUID(false), CurrencySpent = 0 }
			return tostring(Crates.ProcessReceipt(r))
		end
		if what == "open" then
			local prize = arg and Shared.PrizeOf(crateId or "Premium", arg) or roll(c)
			local owned = ScooterSelection.Owns(player, prize.Skin) == true
			local bonus = owned and c.Duplicate and c.Duplicate.Text or nil
			announce(player, crateId or "Premium", prize.Skin, bonus, nil)
			return prize.Skin .. (bonus and (" (duplicate: " .. bonus .. ")") or "") .. " - test only, nothing given"
		end
		return "unknown"
	end
	hook.Parent = ServerStorage
end

return Crates
