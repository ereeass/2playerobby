--=====================================================================
-- Gifting   (server)
--
-- A Robux skin bought for someone else in the server. The Skins menu's gift button
-- (ScootersUI.Gift) lists the players here; picking one asks GiftRequest, and the
-- server - never the client - checks the gift can go (the skin is sold, the receiver
-- is here, isn't the buyer and doesn't own it), remembers who it's for, then opens
-- Roblox's purchase prompt for that skin's GIFT product (Shared.Scooters:
-- Unlock.GiftProductId - a product of its own, so a gift can never be mistaken for a
-- buy for yourself, and the dashboard counts gifts apart).
--
-- The receipt (DonationHandler -> ProcessReceipt) delivers it:
--   receiver here      ScooterSelection.GrantSkin (saved before it says yes)
--   receiver left      added straight to their save (PlayerSettings_v1, OwnedScooters is
--                      only ever added to, so no other server's write can lose it): it's
--                      theirs when they next join
--   receiver owns it   (bought it meanwhile) it goes to the buyer instead, if they lack it
--   nobody remembered  (a receipt Roblox offers again much later and the note is gone)
--                      the buyer gets it themselves
-- Who a gift is for is noted in a DataStore (ScooterGifts_v1) BEFORE the prompt opens,
-- so a receipt that comes later - another server, after a rejoin - still finds it.
-- Then both are told (GiftResult): the buyer "sent", the receiver "received".
--
-- Studio: a skin with no GiftProductId yet still shows its gift button there, and a
-- gift goes through at once without a purchase prompt (nothing is paid, the webhook
-- says [Studio test]). Live servers never show or allow a gift without the product.
--=====================================================================

local Players            = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService   = game:GetService("DataStoreService")
local RunService         = game:GetService("RunService")
local HttpService        = game:GetService("HttpService")
local RS                 = game:GetService("ReplicatedStorage")
local SSS                = game:GetService("ServerScriptService")

local Root     = RS:WaitForChild("ScooterSystem")
local Remotes  = Root:WaitForChild("Remotes")
local Scooters = require(Root:WaitForChild("Shared"):WaitForChild("Scooters"))
local ScooterSelection = require(SSS:WaitForChild("ScooterSystem"):WaitForChild("ScooterSelection"))
local ScooterWebhook   = require(SSS:WaitForChild("ScooterSystem"):WaitForChild("ScooterWebhook"))

local SAVE_STORE   = "PlayerSettings_v1"   -- the players' own save (SettingsServer)
local GIFT_STORE   = "ScooterGifts_v1"     -- who each gift is for, noted before its prompt
local REQUEST_GAP  = 1.5                   -- seconds between gift requests from one player
local LIST_GAP     = 0.4                   -- between player-list asks
local STUDIO       = RunService:IsStudio()

local Gifting = {}

local function log(...) print("[Gift]", ...) end

--------------------------------------------------------------------- products
local giftProduct = {}   -- [gift product id] = definition
for _, def in ipairs(Scooters.List) do
	local u = def.Unlock
	if u and u.Type == "Product" and type(u.GiftProductId) == "number" and u.GiftProductId > 0 then
		giftProduct[u.GiftProductId] = def
	end
end
-- archived skins can't be gifted any more, but a gift Roblox still owes a receipt for is delivered
for _, def in ipairs(Scooters.Archived or {}) do
	local u = def.Unlock
	if u and type(u.LegacyGiftProductId) == "number" and u.LegacyGiftProductId > 0 then
		giftProduct[u.LegacyGiftProductId] = def
	end
end

-- can this skin be gifted here? (Studio also allows one whose gift product isn't made yet)
function Gifting.CanGift(def)
	local u = def and def.Unlock
	if not (u and u.Type == "Product") then return false end
	return (type(u.GiftProductId) == "number" and u.GiftProductId > 0) or STUDIO
end

function Gifting.IsProduct(productId)
	return giftProduct[productId] ~= nil
end

--------------------------------------------------------------------- stores
local function getStore(name)
	local ok, s = pcall(DataStoreService.GetDataStore, DataStoreService, name)
	return ok and s or nil
end
local saveStore, giftStore = getStore(SAVE_STORE), getStore(GIFT_STORE)

-- Studio without API access: notes live in memory only (and a receiver is always here)
local function noAccess(err)
	err = tostring(err)
	return err:find("StudioAccessToApisNotAllowed") or err:find("Studio access") or err:find("403")
end

local notes = {}   -- [buyerId .. ":" .. skinId] = { to, toName, at }  (this server's copy)

local function noteKey(buyerId, skinId) return ("p_%d_%s"):format(buyerId, skinId) end

local function writeNote(buyerId, skinId, note)
	notes[buyerId .. ":" .. skinId] = note
	if not giftStore then return STUDIO end
	local ok, err = pcall(giftStore.SetAsync, giftStore, noteKey(buyerId, skinId), note)
	if ok then return true end
	if STUDIO and noAccess(err) then return true end
	warn("[Gift] couldn't note a gift: " .. tostring(err))
	return false
end

-- the note for this buyer's gift of this skin: note, or nil, plus false if it couldn't be read
local function readNote(buyerId, skinId)
	local mine = notes[buyerId .. ":" .. skinId]
	if mine then return mine, true end
	if not giftStore then return nil, true end
	local ok, result = pcall(giftStore.GetAsync, giftStore, noteKey(buyerId, skinId))
	if ok then return type(result) == "table" and result or nil, true end
	if STUDIO and noAccess(result) then return nil, true end
	warn("[Gift] couldn't read a gift note: " .. tostring(result))
	return nil, false
end

-- A gift paid for but not delivered yet (its receipt still to come, or being retried) keeps its
-- note: a new gift of the same skin by the same buyer would write over it, and the paid one
-- would then go to the NEW receiver. So the purchase window closing with a purchase marks the
-- note paid (Token: only the note this server wrote for that prompt, never one delivered or
-- replaced since), and a new gift of that skin waits until it is delivered (request, "pending").
-- PAID_HOLD: an older paid mark no longer blocks, so a note whose "done" was never written
-- can't stop that skin being gifted for ever.
local PAID_HOLD = 24 * 3600

local function awaitingDelivery(note)
	return type(note) == "table" and type(note.to) == "number" and note.paid == true and note.done == nil
		and os.time() - (tonumber(note.paidAt) or 0) < PAID_HOLD
end

local function markPaid(buyerId, skinId)
	local note = notes[buyerId .. ":" .. skinId]
	if not (type(note) == "table" and type(note.to) == "number" and note.token and note.done == nil) then return end
	local token, at = note.token, os.time()
	note.paid, note.paidAt = true, at
	if not giftStore then return end
	local ok, err = pcall(giftStore.UpdateAsync, giftStore, noteKey(buyerId, skinId), function(old)
		if type(old) ~= "table" or old.token ~= token or old.done ~= nil then return nil end   -- not that note any more
		old.paid, old.paidAt = true, at
		return old
	end)
	if not ok and not (STUDIO and noAccess(err)) then warn("[Gift] couldn't mark a gift as paid: " .. tostring(err)) end
end

-- Is this buyer's last gift of this skin paid for and still waiting to be delivered? Read from
-- the store (another server may have delivered it since this one's copy was made); this
-- server's copy also counts while the store still holds that same undelivered note (its paid
-- mark may not have been written). (answer, read ok) - not ok: the store couldn't be read.
local function stillPaidFor(buyerId, skinId)
	local mine = notes[buyerId .. ":" .. skinId]
	if not giftStore then return awaitingDelivery(mine), true end
	local ok, stored = pcall(giftStore.GetAsync, giftStore, noteKey(buyerId, skinId))
	if not ok then
		if STUDIO and noAccess(stored) then return awaitingDelivery(mine), true end
		warn("[Gift] couldn't read a gift note: " .. tostring(stored))
		return false, false
	end
	stored = type(stored) == "table" and stored or nil
	if awaitingDelivery(stored) then return true, true end
	return awaitingDelivery(mine) and stored ~= nil and stored.token == mine.token and stored.done == nil, true
end

-- delivered: the note now only says which purchase it was, so a receipt Roblox offers
-- again (on any server) is recognised and never delivered twice
local function markDone(buyerId, skinId, purchaseId)
	local note = { done = purchaseId }
	notes[buyerId .. ":" .. skinId] = note
	if giftStore then pcall(giftStore.SetAsync, giftStore, noteKey(buyerId, skinId), note) end
end

-- a skin added to the save of someone not in this server. OwnedScooters only ever grows
-- (every server merges its list into what is stored), so this can't be lost or undone.
-- True once stored, and whether it was new to them.
local function grantOffline(userId, skinId)
	if not saveStore then return false, false end
	local isNew = false
	local ok, err = pcall(saveStore.UpdateAsync, saveStore, "u_" .. userId, function(old)
		isNew = false
		local data = type(old) == "table" and old or {}
		local list = type(data.OwnedScooters) == "table" and data.OwnedScooters or {}
		for _, id in ipairs(list) do
			if id == skinId then return nil end            -- already theirs: nothing to write
		end
		isNew = true
		local new = table.clone(list)
		table.insert(new, skinId)
		table.sort(new)
		data.OwnedScooters = new
		return data
	end)
	if not ok then warn("[Gift] couldn't add " .. skinId .. " to " .. userId .. "'s save: " .. tostring(err)) end
	return ok, ok and isNew
end

-- give a skin to this user wherever they are: true once saved, and whether it was new
local function give(userId, skinId)
	local player = Players:GetPlayerByUserId(userId)
	if player then return ScooterSelection.GrantSkin(player, skinId) end
	return grantOffline(userId, skinId)
end

local function nameOf(userId, fallback)
	local p = Players:GetPlayerByUserId(userId)
	if p then return p.DisplayName end
	if fallback then return fallback end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	return ok and name or "someone"
end

local function tell(userId, kind, otherName, skinId, extra)
	local p = Players:GetPlayerByUserId(userId)
	if p then Remotes.GiftResult:FireClient(p, kind, otherName, skinId, extra) end
end

--------------------------------------------------------------------- delivery
local done = {}   -- purchase ids delivered in this server (a receipt offered twice)

-- the gift itself, once paid for (or straight away in a Studio test)
local function deliver(buyerId, def, purchaseId, paid)
	if done[purchaseId] then return true end
	local note, readOk = readNote(buyerId, def.Id)
	if not readOk then return false end                          -- try again later
	if note and note.done == purchaseId then                     -- delivered already
		done[purchaseId] = true
		return true
	end
	local buyerName = nameOf(buyerId)

	if not note or type(note.to) ~= "number" then
		-- nobody to give it to any more: the buyer gets what they paid for
		local ok = give(buyerId, def.Id)
		if not ok then return false end
		tell(buyerId, "self", nil, def.Id)
		log(buyerName, "gift of", def.Id, "had no receiver noted: given to the buyer")
	else
		local toName = nameOf(note.to, note.toName)
		local ok, isNew = give(note.to, def.Id)
		if not ok then return false end
		if isNew then
			tell(buyerId, "sent", toName, def.Id)
			tell(note.to, "received", buyerName, def.Id)
			log(buyerName, "gave", toName, def.Id)
		else
			-- they got it some other way meanwhile: the buyer has it instead, if they lack it
			local ok2, newToBuyer = give(buyerId, def.Id)
			if not ok2 then return false end
			tell(buyerId, newToBuyer and "instead" or "had", toName, def.Id)
			log(buyerName, "gift of", def.Id, "- receiver", toName, "already had it; buyer got it:", newToBuyer)
		end
	end
	done[purchaseId] = true
	markDone(buyerId, def.Id, purchaseId)
	if paid then ScooterWebhook.LogGift(paid, def, note and note.to) end
	return true
end

-- DonationHandler's ProcessReceipt, for a gift product
function Gifting.ProcessReceipt(receipt)
	local def = giftProduct[receipt.ProductId]
	if not def then return Enum.ProductPurchaseDecision.NotProcessedYet end
	local ok, result = pcall(deliver, receipt.PlayerId, def, receipt.PurchaseId, receipt)
	if ok and result then return Enum.ProductPurchaseDecision.PurchaseGranted end
	if not ok then warn("[Gift] delivering a gift failed: " .. tostring(result)) end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

--------------------------------------------------------------------- requests
local lastRequest, lastList = {}, {}
local busy = {}   -- [player] = true while their gift prompt is being set up

-- the players a gift could go to, and whether each already owns this skin
local function targets(player, skinId)
	local now = os.clock()
	if now - (lastList[player] or -math.huge) < LIST_GAP then return nil end
	lastList[player] = now
	local def = Scooters.Get(skinId)
	if not Gifting.CanGift(def) then return nil end
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then
			local owns = ScooterSelection.Owns(p, def.Id)
			table.insert(list, { UserId = p.UserId, Owns = owns == true, Loading = owns == nil })
		end
	end
	return list
end

-- "prompt"  the purchase prompt is open      "studio"  a Studio test gift went through
-- "owned"   they already have it             "gone"    they left
-- "self"    can't gift yourself              "busy"    too soon / still loading
-- "pending" their last gift of this skin is paid but not delivered yet (see markPaid)
-- "failed"  couldn't note it: nothing was charged, try again
local function request(player, skinId, toUserId)
	local def = Scooters.Get(skinId)
	if not Gifting.CanGift(def) or type(toUserId) ~= "number" then return "failed" end
	if busy[player] then return "busy" end
	local now = os.clock()
	if now - (lastRequest[player] or -math.huge) < REQUEST_GAP then return "busy" end
	lastRequest[player] = now
	if toUserId == player.UserId then return "self" end
	local target = Players:GetPlayerByUserId(toUserId)
	if not target then return "gone" end
	local owns = ScooterSelection.Owns(target, def.Id, true)
	if owns == nil then return "busy" end
	if owns then return "owned" end

	busy[player] = true
	-- their last gift of this skin is paid for but not delivered yet: its note stays (see markPaid)
	local waiting, readOk = stillPaidFor(player.UserId, def.Id)
	if not readOk then busy[player] = nil return "failed" end
	if waiting then busy[player] = nil return "pending" end
	local ok = writeNote(player.UserId, def.Id, { to = toUserId, toName = target.DisplayName, at = os.time(),
		token = HttpService:GenerateGUID(false) })
	busy[player] = nil
	if not ok then return "failed" end
	if player.Parent ~= Players then return "failed" end

	local productId = def.Unlock.GiftProductId
	if type(productId) == "number" and productId > 0 then
		local okPrompt, err = pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, player, productId)
		if not okPrompt then
			warn("[Gift] purchase prompt failed: " .. tostring(err))
			return "failed"
		end
		return "prompt"
	end
	-- Studio, no gift product yet: the gift goes through at once, nothing paid
	if STUDIO then
		local delivered = deliver(player.UserId, def, "studio-" .. HttpService:GenerateGUID(false), nil)
		return delivered and "studio" or "failed"
	end
	return "failed"
end

--------------------------------------------------------------------- start
local function remote(className, name)
	local r = Remotes:FindFirstChild(name)
	if not r then
		r = Instance.new(className)
		r.Name = name
		r.Parent = Remotes
	end
	return r
end
remote("RemoteEvent", "GiftResult")
local GiftTargets = remote("RemoteFunction", "GiftTargets")
local GiftRequest = remote("RemoteFunction", "GiftRequest")

if not GiftRequest:GetAttribute("Bound") then
	GiftRequest:SetAttribute("Bound", true)
	GiftTargets.OnServerInvoke = function(player, skinId)
		if type(skinId) ~= "string" then return nil end
		return targets(player, skinId)
	end
	GiftRequest.OnServerInvoke = function(player, skinId, toUserId)
		if type(skinId) ~= "string" then return "failed" end
		return request(player, skinId, toUserId)
	end
	Players.PlayerRemoving:Connect(function(p)
		lastRequest[p], lastList[p], busy[p] = nil, nil, nil
	end)
	-- a gift's purchase window closed WITH a purchase: its note is marked paid (see markPaid)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(who, productId, purchased)
		local def = purchased and giftProduct[productId]
		if not def then return end
		local userId = (typeof(who) == "Instance" and who.UserId) or tonumber(who)
		if userId then task.spawn(markPaid, userId, def.Id) end
	end)
	if STUDIO then
		-- the gift path without a purchase, from the command bar (Server):
		--   game.ServerStorage.GiftStudioTest:Invoke(buyerUserId, "Galaxy", receiverUserId)
		local hook = game:GetService("ServerStorage"):FindFirstChild("GiftStudioTest") or Instance.new("BindableFunction")
		hook.Name = "GiftStudioTest"
		hook.OnInvoke = function(buyerId, skinId, toUserId)
			local def = Scooters.Get(skinId)
			if not def then return "no such skin" end
			if toUserId then writeNote(buyerId, def.Id, { to = toUserId, toName = nameOf(toUserId), at = os.time() }) end
			return deliver(buyerId, def, "studio-" .. HttpService:GenerateGUID(false), nil)
		end
		hook.Parent = game:GetService("ServerStorage")
		-- Studio only: the insides, for tests from the command bar (never in a live server):
		--   GiftStudioInternals:Invoke("deliver", buyerId, skinId, purchaseId)   a receipt, as if paid
		--   GiftStudioInternals:Invoke("note", buyerId, skinId, toUserId)        note who it's for
		--   GiftStudioInternals:Invoke("read", buyerId, skinId)                  the note
		--   GiftStudioInternals:Invoke("forget")                                 like another server
		local inside = game:GetService("ServerStorage"):FindFirstChild("GiftStudioInternals") or Instance.new("BindableFunction")
		inside.Name = "GiftStudioInternals"
		inside.OnInvoke = function(cmd, a, b, c)
			local def = type(b) == "string" and Scooters.Get(b)
			if cmd == "deliver" then return deliver(a, def, c, nil) end
			if cmd == "note" then return writeNote(a, def.Id, { to = c, toName = "Test" .. tostring(c), at = os.time() }) end
			if cmd == "read" then return readNote(a, def.Id) end
			if cmd == "forget" then table.clear(notes) table.clear(done) return true end
			return nil
		end
		inside.Parent = game:GetService("ServerStorage")
	end
end

return Gifting
