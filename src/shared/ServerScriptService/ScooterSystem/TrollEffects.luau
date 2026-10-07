--=====================================================================
-- TrollEffects   (ScooterSystem, server)
--
-- The Troll window's effects: buying one onto the duo you are watching, and what happens then.
-- Everything that matters is decided HERE - the Troll window only asks.
--
--   Asking     Remotes.TrollRequest(effectId, scooter). Checked: the effect exists and is on
--              sale; the asker is in the lobby (not riding, not queued in a booth) and is
--              WATCHING that scooter (their spectate streaming is on it - ScooterSystem.Spectate
--              only points it at a duo they asked to watch); the scooter is an active ride whose
--              duo can be trolled right now (DuoState.Trollable: both riders on, nothing else
--              has it), not mid-skip and not just over the finish. The asker is never one of its
--              riders. Then:
--                a saved free one  spent at once and the effect starts - no purchase
--                otherwise         the order is remembered and the server opens Roblox's
--                                  purchase window for that effect's Developer Product
--              Not watching anyone (scooter nil): buying one for later. Only the lobby check
--              applies; the purchase window opens and the receipt saves it as a free one.
--   Buying     Roblox's receipt (DonationHandler's ProcessReceipt hands Troll products here)
--              is the ONLY thing that starts a bought effect, and each purchase is handled
--              once. The order is checked again: still there and still trollable -> it starts;
--              otherwise (they finished, died, left, someone else got them first) the purchase
--              is saved as a free one for the buyer's next go - their save (SettingsServer's
--              PlayerData) and the red count on its button - and they are told. Nothing is lost.
--   Playing    the effect gets ONE ride - its scooter and its two riders - and nothing else in
--              the game: no other player, scooter or ride, and never the buyer. While it plays
--              the ride is ride.Troll (no second troll) and ride.TrollShow (still listed for
--              spectators, DuoState).
--   Cut short  a rider leaves (or the ride ends any other way) before the effect has done its
--              job: the buyer gets it back as a free one and is told why.
--   The log    every purchase goes to the team's Discord (TrollWebhook).
--   From a ride  the same effects asked for from ON a scooter, at another duo riding close by
--              (StarterPlayerScripts.RideTrollPrompt: an E prompt on their scooter, only while
--              the asker is riding too): Remotes.TrollRequest(effectId, scooter, "ride"). Only
--              the effects in RIDE_EFFECTS (Explode). Checked instead of the lobby/watching rule:
--              the asker is riding, the target is another ride, within RIDE_RANGE of the asker's
--              scooter. Everything after that - the saved free one, the purchase, the receipt,
--              saving it if they get away - is exactly the Troll window's (one system).
--
--   REVENGE    a duo exploded FROM A RIDE (above) gets EXPLODE BACK (REVENGE) on its death popup
--              (DeathManager: the death's cause names the attacking ride and who bought it). One
--              rider presses it (Remotes.RevengeRequest): checked and locked at once on the
--              server, so only one revenge per death; the countdown holds as for a revive and
--              Roblox's purchase window opens for Config.RevengeProductId. Its receipt explodes
--              that same attacking duo (the same Explode show) while both victims watch it
--              (their streaming focus and camera on it), then the popup carries on. If the
--              attackers can't be exploded by then, the buyer alone gets a free Explode Players.
--              If they leave mid-explosion it stops and the victims go back to the lobby. Never a
--              revenge of a revenge. Logged to the Troll webhook as REVENGE.
--
-- A new troll: an entry in ReplicatedStorage.TrollFx.Effects (its button), its product id in
-- Shared.Config.TrollProducts, and a ModuleScript under this one named after its Id with
-- Run(ctx) -> true once it has done its job (see Rocket; a show that ends in the explosion is
-- just ScooterSystem.TrollShow.Play with its own clock, as Rocket and Explode are). Nothing
-- else changes here.
--=====================================================================

local Players             = game:GetService("Players")
local MarketplaceService  = game:GetService("MarketplaceService")
local RunService          = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage       = game:GetService("ServerStorage")
local HttpService         = game:GetService("HttpService")
local RS                  = game:GetService("ReplicatedStorage")

local Root       = RS:WaitForChild("ScooterSystem")
local Remotes    = Root:WaitForChild("Remotes")
local Config     = require(Root:WaitForChild("Shared"):WaitForChild("Config"))
local EffectList = require(RS:WaitForChild("TrollFx"):WaitForChild("Effects"))

local RideManager  = require(script.Parent:WaitForChild("RideManager"))
local TeamManager  = require(script.Parent:WaitForChild("TeamManager"))
local DeathManager = require(script.Parent:WaitForChild("DeathManager"))
local DuoState     = require(script.Parent:WaitForChild("DuoState"))
local TrollWebhook = require(script.Parent:WaitForChild("TrollWebhook"))

local ORDER_TTL = 180    -- seconds an order waits for its receipt
local ASK_GAP   = 0.4    -- seconds between one player's requests
local RIDE_EFFECTS = { Explode = true }   -- what can be asked for from a scooter (see the header)
local RIDE_RANGE   = 30   -- studs, scooter to scooter, for asking from a ride (the prompt's own range is shorter)
local REVENGE_PRODUCT = Config.RevengeProductId or 0   -- "Get Revenge!" (see REVENGE in the header)

local SAVED_NOTE = "They got away before your %s landed - it's saved, your next one is FREE!"
local LEFT_NOTE  = "They left before your %s finished - your next one is FREE!"
local STOCK_NOTE = "Your %s is saved! Watch a duo and press it to use it FREE!"
local FAILED_ASK = "Couldn't do that right now - try again!"

local TrollEffects = {}

local function log(...) if Config.DebugLogging then print("[Troll]", ...) end end

---------------------------------------------------------------- the effects
TrollEffects.List = {}   -- [id] = { Id, Name, Emoji, Credits, ProductId, Module, ... }
local byProduct = {}     -- [ProductId] = that effect
for _, info in ipairs(EffectList) do
	local def = table.clone(info)
	def.ProductId = (Config.TrollProducts or {})[info.Id] or 0
	def.Module = script:FindFirstChild(info.Id)
	if not def.Module then warn("[Troll] no module for " .. info.Id .. " under TrollEffects") end
	TrollEffects.List[info.Id] = def
	if def.ProductId ~= 0 then byProduct[def.ProductId] = def end
end

function TrollEffects.IsProduct(productId)
	return byProduct[productId] ~= nil or (REVENGE_PRODUCT ~= 0 and productId == REVENGE_PRODUCT)
end

---------------------------------------------------------------- saved free ones
local credits = {}   -- [player] = { [effect id] = count }, once read
local locks   = {}   -- [player] = true while their counts are being changed

local function dataApi()
	local settings = ServerScriptService:FindFirstChild("SettingsServer")
	return settings and settings:FindFirstChild("PlayerData")
end

local function creditsOf(player, def)
	local mine = credits[player]
	if not mine then
		mine = {}
		credits[player] = mine
	end
	if mine[def.Id] == nil then
		local api = dataApi()
		local ok, value, state = false, nil, nil
		if api then ok, value, state = pcall(api.Get.Invoke, api.Get, player, def.Credits) end
		-- their save didn't load: the real count is unknown, so it isn't guessed (a 0 saved over
		-- it would wipe what they have). Nothing is written; it's read again next time.
		if not ok or state == "failed" or state == "invalid" then return 0, false end
		if mine[def.Id] == nil and player.Parent == Players then
			mine[def.Id] = math.max(0, math.floor(tonumber(ok and value or nil) or 0))
			player:SetAttribute(def.Credits, mine[def.Id])   -- the count on its button
		end
	end
	return mine[def.Id] or 0, mine[def.Id] ~= nil
end

-- the count changed by `by` and saved at once: true only once it is stored
local function changeCredits(player, def, by)
	while locks[player] do task.wait() end
	locks[player] = true
	local ok, stored = pcall(function()
		local api = dataApi()
		if not api or player.Parent ~= Players then return false end
		local have, known = creditsOf(player, def)
		if not known then return false end   -- (their save didn't load: never written over)
		local n = have + by
		if n < 0 then return false end
		local saved = api.SaveNow:Invoke(player, def.Credits, n)
		if saved then
			credits[player][def.Id] = n
			if player.Parent then player:SetAttribute(def.Credits, n) end
		end
		return saved
	end)
	locks[player] = nil
	if not ok then warn("[Troll] saved trolls: " .. tostring(stored)) end
	return ok and stored == true
end

-- read on joining, so each button's count is right from the start
local function preload(player)
	local settings = ServerScriptService:WaitForChild("SettingsServer", 10)
	if settings then settings:WaitForChild("PlayerData", 10) end
	for _, def in pairs(TrollEffects.List) do creditsOf(player, def) end
end
Players.PlayerAdded:Connect(function(player) task.spawn(preload, player) end)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(preload, player) end

---------------------------------------------------------------- telling the buyer
local function notify(player, text)
	if player and player.Parent == Players then
		Remotes.TrollAlert:FireClient(player, { Kind = "Notice", Text = text })
	end
end

---------------------------------------------------------------- the target
-- the ride's riders who are players (either can be missing)
local function ridersOf(ride)
	local list = {}
	for _, plr in ipairs({ ride.Driver or false, ride.Passenger or false }) do
		if typeof(plr) == "Instance" and plr:IsA("Player") then table.insert(list, plr) end
	end
	return list
end

local function namesOf(ride)
	if not ride then return nil end
	local names = {}
	for _, plr in ipairs({ ride.Driver or false, ride.Passenger or false }) do
		if plr then table.insert(names, ("%s (@%s)"):format(tostring(plr.DisplayName), tostring(plr.Name))) end
	end
	return #names > 0 and table.concat(names, " & ") or nil
end

-- over the finish line a moment ago (CourseProgress holds them at 100% for a while): their
-- victory cutscene is playing, and there is nothing left to troll
local function finished(ride)
	for _, plr in ipairs(ridersOf(ride)) do
		if (tonumber(plr:GetAttribute("CourseProgress")) or 0) >= 1 then return true end
	end
	return false
end

-- a Skip Stage is being bought or done for them (SkipStage): it moves the scooter
local function skipping(ride)
	for _, plr in ipairs(ridersOf(ride)) do
		if plr:GetAttribute("SkipStageBusy") then return true end
	end
	return false
end

-- The ride on `scooter`, if `buyer` may troll it now; otherwise nil and why not.
-- `watching`: they must be spectating it right now (asking, not the receipt).
-- `fromRide`: asked from ON a scooter (see the header) - riding instead of in the lobby, and
-- (while asking, i.e. with `watching`) within RIDE_RANGE instead of spectating it.
local function targetFor(buyer, scooter, watching, fromRide)
	if fromRide then
		if watching and not RideManager.PlayerRide[buyer] then return nil, "You need to be riding to do that!" end
	elseif RideManager.PlayerRide[buyer] or TeamManager.FindSlot(buyer) then
		return nil, "You can only troll from the lobby!"
	end
	if typeof(scooter) ~= "Instance" then return nil, "Watch a duo to troll them!" end
	local ride = RideManager.Rides[scooter]
	if not ride or not DuoState.Watchable(ride) then return nil, "That duo isn't riding any more." end
	if ride.Driver == buyer or ride.Passenger == buyer then return nil, "You can't troll yourself!" end
	if fromRide and watching then
		local mine = RideManager.PlayerRide[buyer]
		local a = mine and mine.Scooter and mine.Scooter.PrimaryPart
		local b = scooter.PrimaryPart
		if not (a and b) or (a.Position - b.Position).Magnitude > RIDE_RANGE then return nil, "They're too far away!" end
	elseif watching and buyer.ReplicationFocus ~= scooter.PrimaryPart then return nil, "Watch a duo to troll them!" end
	if ride.Troll or ride.TrollShow then return nil, "They're already being trolled!" end
	if finished(ride) then return nil, "They've already finished!" end
	if not DuoState.Trollable(ride) or skipping(ride) then return nil, "They can't be trolled right now!" end
	return ride
end

---------------------------------------------------------------- playing it
-- The effect on this ride, for this buyer (nil in a Studio test). True once it has started:
-- the ride is the effect's now, and nothing else can take it. `force`: Studio tests on
-- stand-in riders, which DuoState can't count as a duo. `extra` (optional):
--   FromRide  asked from ON a scooter: an Explode then names the buyer's ride as the cause of
--             the death, which offers its victims REVENGE (DeathManager)
--   Revenge   this IS a revenge: its death is a "Revenge" (never a revenge of its own), and the
--             riders' banner says so
--   OnEnd     called with true once the ride is down, false if it ended first; replaces the
--             usual "given back as a free one" (REVENGE handles its own ending)
local function begin(def, buyer, ride, force, extra)
	extra = extra or {}
	if not def.Module then return false end
	if not force and not DuoState.Trollable(ride) then return false end
	if ride.Troll or ride.TrollShow then return false end
	local life = DeathManager.Claim(ride)   -- no obstacle can take this ride now
	if not life then return false end
	local ctx = {
		Def = def, Ride = ride, Scooter = ride.Scooter, Life = life,
		Buyer = buyer, BuyerName = buyer and buyer.DisplayName or "Someone",
		Riders = ridersOf(ride), Names = namesOf(ride),
		Revenge = extra.Revenge and true or nil,
	}
	if extra.Revenge then
		ctx.Cause = { Kind = "Revenge" }
	elseif extra.FromRide and def.Id == "Explode" and buyer then
		local attacker = RideManager.PlayerRide[buyer]   -- the duo the buyer is riding with
		if attacker and attacker ~= ride then
			ctx.Cause = { Kind = "RideExplode", AttackerRide = attacker, ByName = buyer.DisplayName, ByUserId = buyer.UserId }
		end
	end
	ride.Troll = { Effect = def.Id, Buyer = buyer }
	ride.TrollShow = true
	log(ctx.BuyerName, "bought", def.Name, "on", tostring(ctx.Names))
	task.spawn(function()
		local ok, done = pcall(require(def.Module).Run, ctx)
		if not ok then
			warn("[Troll] " .. def.Name .. " failed: " .. tostring(done))
			done = false
		end
		ride.TrollShow = nil
		ride.Troll = nil
		if extra.OnEnd then
			local okEnd, err = pcall(extra.OnEnd, ok and done == true)
			if not okEnd then warn("[Troll] revenge ending: " .. tostring(err)) end
			return
		end
		if ok and done then return end
		-- cut short (a rider left, the ride ended, something broke): the buyer gets it back
		if buyer and buyer.Parent == Players and changeCredits(buyer, def, 1) then
			notify(buyer, LEFT_NOTE:format(def.Name))
			TrollWebhook.Note(def, buyer, "Cut short (the duo left) - given back as a free " .. def.Name, ctx.Names)
		elseif buyer then
			warn("[Troll] couldn't give " .. buyer.Name .. " back their " .. def.Name)
		end
	end)
	return true
end

---------------------------------------------------------------- asking (the Troll window)
local lastAsk = {}   -- [player] = os.clock()
local pending = {}   -- [buyer] = { Def, Scooter, Ride, At }: waiting for Roblox's receipt

-- "started" (a saved free one: it is playing), "prompted" (Roblox's purchase window is open),
-- or "refused" and why. mode "ride": asked from ON a scooter (see the header).
local function ask(buyer, effectId, scooter, mode)
	local now = os.clock()
	if now - (lastAsk[buyer] or 0) < ASK_GAP then return "refused", nil end
	lastAsk[buyer] = now
	local def = type(effectId) == "string" and TrollEffects.List[effectId]
	if not def or def.ProductId == 0 or not def.Module then return "refused", "That troll isn't ready yet." end
	local fromRide = mode == "ride"
	if fromRide and not RIDE_EFFECTS[def.Id] then return "refused", "That troll isn't ready yet." end

	-- not watching anyone: bought for later (saved as a free one on the receipt)
	if scooter == nil and not fromRide then
		if RideManager.PlayerRide[buyer] or TeamManager.FindSlot(buyer) then
			return "refused", "You can only troll from the lobby!"
		end
		pending[buyer] = { Def = def, Stock = true, At = now }
		MarketplaceService:PromptProductPurchase(buyer, def.ProductId)
		return "prompted", nil
	end

	local ride, why = targetFor(buyer, scooter, true, fromRide)
	if not ride then return "refused", why end

	-- a free one they have saved: spent now, no purchase
	if creditsOf(buyer, def) > 0 then
		if not changeCredits(buyer, def, -1) then return "refused", FAILED_ASK end
		if begin(def, buyer, ride, nil, { FromRide = fromRide }) then
			TrollWebhook.Note(def, buyer, "Used a saved free " .. def.Name, namesOf(ride))
			return "started", nil
		end
		changeCredits(buyer, def, 1)   -- not used after all: theirs again
		return "refused", "They can't be trolled right now!"
	end

	pending[buyer] = { Def = def, Scooter = scooter, Ride = ride, At = now, FromRide = fromRide }
	MarketplaceService:PromptProductPurchase(buyer, def.ProductId)
	return "prompted", nil
end

Remotes:WaitForChild("TrollRequest").OnServerInvoke = function(buyer, effectId, scooter, mode)
	local ok, status, why = pcall(ask, buyer, effectId, scooter, mode)
	if not ok then
		warn("[Troll] " .. tostring(status))
		status, why = "refused", FAILED_ASK
	end
	-- from a ride there's no Troll window to say why: the red notice at the bottom does
	if mode == "ride" and status == "refused" and why then Remotes.Notice:FireClient(buyer, why) end
	return status, why
end

-- the purchase window closed without a purchase: the order goes
MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
	if purchased or not byProduct[productId] then return end
	local player = Players:GetPlayerByUserId(userId)
	local order = player and pending[player]
	if order and order.Def.ProductId == productId then pending[player] = nil end
end)

Players.PlayerRemoving:Connect(function(player)
	pending[player], lastAsk[player], credits[player], locks[player] = nil, nil, nil, nil
end)

---------------------------------------------------------------- buying (Roblox's receipt)
local handled = {}   -- [PurchaseId] = true: receipts this server has dealt with

function TrollEffects.ProcessReceipt(receipt)
	if REVENGE_PRODUCT ~= 0 and receipt.ProductId == REVENGE_PRODUCT then
		return TrollEffects.ProcessRevengeReceipt(receipt)
	end
	local id = tostring(receipt.PurchaseId)
	if handled[id] then return Enum.ProductPurchaseDecision.PurchaseGranted end
	local def = byProduct[receipt.ProductId]
	if not def then return Enum.ProductPurchaseDecision.NotProcessedYet end
	local buyer = Players:GetPlayerByUserId(receipt.PlayerId)
	if not buyer then return Enum.ProductPurchaseDecision.NotProcessedYet end   -- offered again when they're back

	local order = pending[buyer]
	if order and order.Def == def and order.Stock then
		-- bought for later: straight into their saved free ones
		if changeCredits(buyer, def, 1) then
			pending[buyer] = nil
			handled[id] = true
			notify(buyer, STOCK_NOTE:format(def.Name))
			TrollWebhook.Log(def, receipt, "Bought for later - saved as a free " .. def.Name, nil)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if order and order.Def == def and os.clock() - order.At < ORDER_TTL then
		pending[buyer] = nil
		local ride = targetFor(buyer, order.Scooter, false, order.FromRide)
		if ride and ride == order.Ride and begin(def, buyer, ride, nil, { FromRide = order.FromRide }) then
			handled[id] = true
			TrollWebhook.Log(def, receipt, def.Outcome or "Started!", namesOf(ride))
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end
	-- nothing to troll any more: kept as a free one for their next go
	if changeCredits(buyer, def, 1) then
		handled[id] = true
		notify(buyer, SAVED_NOTE:format(def.Name))
		log(buyer.Name, "bought a", def.Name, "that couldn't be used: saved as a free one")
		TrollWebhook.Log(def, receipt, "Couldn't be used (the duo was gone) - saved as a free " .. def.Name,
			order and namesOf(order.Ride))
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet   -- nothing given yet: Roblox offers it again
end

---------------------------------------------------------------- REVENGE
local REVENGE_DEF          = { Id = "Revenge", Name = "REVENGE", Emoji = "\u{1F4A5}" }   -- the webhook's title
local REVENGE_HOLD         = 45    -- seconds the countdown waits for the purchase window, at most
local REVENGE_RECEIPT_WAIT = 20    -- after "bought", how long it waits for Roblox's receipt
local REVENGE_GAP          = 1     -- seconds between one rider's presses
local REVENGE_AWAY = "They got away before your revenge landed - you got a FREE Explode Players!"
local REVENGE_LEFT = "They left before your revenge landed!"

local revengePending = {}   -- [buyer] = { Ride, Down, Rev, Target, Token }: what their purchase is for
local revengeAsk     = {}   -- [player] = os.clock()
local revengeHandled = {}   -- [PurchaseId] = true

-- the attacking duo can be exploded right now: still that same ride (a revive keeps it), on
-- its scooter, riding, nothing else on it
local function explodable(target)
	if type(target) ~= "table" or target._ended or target.Down or target.Troll or target.TrollShow then return false end
	local scooter = target.Scooter
	if typeof(scooter) ~= "Instance" or not scooter.Parent or RideManager.Rides[scooter] ~= target then return false end
	return DuoState.Trollable(target) and not finished(target) and not skipping(target)
end

-- this death's revenge can be bought right now (DeathManager asks, to show the button)
local function revengeOpen(ride, down)
	local rv = down and down.Revenge
	if not rv or rv.Status ~= "ready" or ride._ended or ride.Down ~= down then return false end
	if down.Buyer or down.Reviving then return false end   -- a revive is being bought or done
	return explodable(rv.Target)
end
DeathManager.RevengeOpen = revengeOpen

-- the victims' streaming (and so their view) on a part, or back on themselves (nil)
local function focusOn(ride, part)
	for _, plr in ipairs(ridersOf(ride)) do
		if plr.Parent == Players then pcall(function() plr.ReplicationFocus = part end) end
	end
end

-- the purchase under way is over without a revenge: the button comes back, the countdown
-- carries on (and if both voted SKIP meanwhile, the run ends). `token` names that purchase.
local function releaseRevenge(ride, down, rv, token)
	if rv.Token ~= token or rv.Status ~= "buying" then return end
	rv.Status, rv.Buyer, rv.Paid = "ready", nil, false
	rv.Token += 1
	if ride.Down == down and not ride._ended then
		DeathManager.ResumeDown(ride)
		DeathManager.Send(ride)
		DeathManager.CheckSkips(ride)
	end
end

-- EXPLODE BACK (REVENGE) pressed on the popup, or the presser's screen saying the purchase
-- window closed ("closed")
local function requestRevenge(player, action)
	local ride = RideManager.PlayerRide[player]
	local down = ride and ride.Down
	local rv = down and down.Revenge
	if not rv or ride._ended then return end
	if player ~= ride.Driver and player ~= ride.Passenger then return end
	if action == "closed" then
		if rv.Status == "buying" and rv.Buyer == player and not rv.Paid then releaseRevenge(ride, down, rv, rv.Token) end
		return
	end
	local now = os.clock()
	if now - (revengeAsk[player] or 0) < REVENGE_GAP then return end
	revengeAsk[player] = now
	if REVENGE_PRODUCT == 0 then warn("[Troll] REVENGE: set Config.RevengeProductId") return end
	-- checked and taken in one go, with nothing in between that can yield: whoever gets here
	-- first has it; the partner's press then finds it taken ("Your friend is getting revenge...")
	if not revengeOpen(ride, down) then DeathManager.Send(ride) return end
	rv.Status, rv.Buyer, rv.Paid = "buying", player, false
	rv.Token += 1
	local token = rv.Token
	down.Votes[player] = nil   -- asking for it takes back their SKIP
	revengePending[player] = { Ride = ride, Down = down, Rev = rv, Target = rv.Target, Token = token }
	DeathManager.HoldDown(ride)
	DeathManager.Send(ride)
	local ok, err = pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, player, REVENGE_PRODUCT)
	if not ok then
		warn("[Troll] couldn't open the revenge purchase for " .. player.Name .. ": " .. tostring(err))
		releaseRevenge(ride, down, rv, token)
		return
	end
	-- left open, the countdown doesn't wait for ever (a receipt that still comes is honoured)
	task.delay(REVENGE_HOLD, function() releaseRevenge(ride, down, rv, token) end)
end

Remotes:WaitForChild("RevengeRequest").OnServerEvent:Connect(function(player, action)
	local ok, err = pcall(requestRevenge, player, action)
	if not ok then warn("[Troll] revenge request: " .. tostring(err)) end
end)

-- the purchase window closed: not bought -> the button comes back; bought -> wait a while for
-- the receipt, then let go (a late receipt is still honoured)
MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
	if REVENGE_PRODUCT == 0 or productId ~= REVENGE_PRODUCT then return end
	local player = Players:GetPlayerByUserId(userId)
	local order = player and revengePending[player]
	if not order then return end
	local rv = order.Rev
	if rv.Status ~= "buying" or rv.Buyer ~= player or rv.Token ~= order.Token then return end
	if purchased then
		rv.Paid = true
		local token = order.Token
		task.delay(REVENGE_RECEIPT_WAIT, function() releaseRevenge(order.Ride, order.Down, rv, token) end)
	else
		releaseRevenge(order.Ride, order.Down, rv, order.Token)
	end
end)

-- Roblox's receipt for "Get Revenge!" (via ProcessReceipt). It explodes the attacking duo if
-- that's still possible (Q: even if the victims' run has ended since - they just don't watch);
-- otherwise the buyer alone gets a free Explode Players. Granted only once one of those is done.
function TrollEffects.ProcessRevengeReceipt(receipt)
	local id = tostring(receipt.PurchaseId)
	if revengeHandled[id] then return Enum.ProductPurchaseDecision.PurchaseGranted end
	local buyer = Players:GetPlayerByUserId(receipt.PlayerId)
	if not buyer then return Enum.ProductPurchaseDecision.NotProcessedYet end   -- offered again when they're back
	local explodeDef = TrollEffects.List.Explode
	if not explodeDef then return Enum.ProductPurchaseDecision.NotProcessedYet end
	local order = revengePending[buyer]
	local rv = order and order.Rev
	-- still this death's revenge? not once it's used, nor while the partner is buying it
	local usable = rv ~= nil and (rv.Status == "ready" or (rv.Status == "buying" and rv.Buyer == buyer))
	if usable and explodable(order.Target) then
		local ride, down, target = order.Ride, order.Down, order.Target
		local watching = ride.Down == down and not ride._ended
		local statusWas, buyerWas = rv.Status, rv.Buyer
		rv.Status, rv.Buyer = watching and "playing" or "used", buyer   -- taken: never twice
		rv.Token += 1
		local started = begin(explodeDef, buyer, target, false, {
			Revenge = true,
			OnEnd = function(done)
				focusOn(ride, nil)
				if rv.Status == "playing" then rv.Status = "used" end
				rv.Watch = nil
				if ride.Down ~= down or ride._ended then return end
				if done then
					-- it landed: the popup comes back and the countdown carries on
					DeathManager.ResumeDown(ride)
					DeathManager.Send(ride)
					DeathManager.CheckSkips(ride)
				else
					-- the attackers left mid-way: the show stops and the victims go back to the lobby
					if buyer.Parent == Players then notify(buyer, REVENGE_LEFT) end
					DeathManager.Finish(ride, "revenge target left")
				end
			end,
		})
		if started then
			revengeHandled[id] = true
			revengePending[buyer] = nil
			if watching then
				local scooter = target.Scooter
				rv.Watch = { Scooter = scooter, At = scooter:GetPivot().Position }
				focusOn(ride, scooter.PrimaryPart)
				DeathManager.HoldDown(ride)
				DeathManager.Send(ride)
				-- told again once it has streamed in to them (a far scooter isn't there at first)
				for _, after in ipairs({ 0.6, 1.4, 2.6 }) do
					task.delay(after, function()
						if rv.Status == "playing" and ride.Down == down and not ride._ended then DeathManager.Send(ride) end
					end)
				end
			end
			TrollWebhook.Log(REVENGE_DEF, receipt, "REVENGE - exploded back " .. (namesOf(target) or "the duo"), namesOf(target))
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		-- (someone else got them first) not used after all: as it was, then the fallback below
		rv.Status, rv.Buyer = statusWas, buyerWas
	end
	-- the attackers can't be exploded: the buyer alone gets a free Explode Players
	if changeCredits(buyer, explodeDef, 1) then
		revengeHandled[id] = true
		revengePending[buyer] = nil
		if rv and rv.Status == "buying" and rv.Buyer == buyer then
			rv.Status, rv.Buyer = "away", nil   -- this death's revenge is spent (the popup: UNABLE TO GET REVENGE!)
			rv.Token += 1
		end
		if order and order.Ride.Down == order.Down and not order.Ride._ended then
			DeathManager.ResumeDown(order.Ride)
			DeathManager.Send(order.Ride)
			DeathManager.CheckSkips(order.Ride)
		end
		notify(buyer, REVENGE_AWAY)
		TrollWebhook.Log(REVENGE_DEF, receipt, "REVENGE - the duo was gone: given a free Explode Players",
			order and namesOf(order.Target))
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet   -- nothing given yet: Roblox offers it again
end

-- the button follows the attackers live (they die, finish, revive...)
task.spawn(function()
	while true do
		task.wait(0.5)
		for _, ride in pairs(RideManager.Rides) do
			local down = type(ride) == "table" and ride.Down
			local rv = down and down.Revenge
			if rv and rv.Status == "ready" and not ride._ended then
				local ok, open = pcall(revengeOpen, ride, down)
				if (ok and open == true) ~= (rv.LastOpen == true) then DeathManager.Send(ride) end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	revengePending[player], revengeAsk[player] = nil, nil
end)

---------------------------------------------------------------- studio
-- Studio only, never in a live server. From the command bar while testing (Server view):
--   hook:Invoke("start", "Rocket", scooter [, buyer])   play it on that scooter now (stand-in riders too)
--   hook:Invoke("receipt", "Rocket", buyer)             a fake receipt for the buyer's order
--   hook:Invoke("revenge", nil, buyer)                  a fake "Get Revenge!" receipt for the buyer
if RunService:IsStudio() then
	local hook = Instance.new("BindableFunction")
	hook.Name = "TrollStudioTest"
	hook.OnInvoke = function(what, effectId, a, b)
		if what == "revenge" then
			return TrollEffects.ProcessRevengeReceipt({
				PurchaseId = HttpService:GenerateGUID(false), PlayerId = a.UserId,
				ProductId = REVENGE_PRODUCT, CurrencySpent = 0,
			})
		end
		local def = TrollEffects.List[effectId]
		if not def then return "no such effect" end
		if what == "start" then
			local ride = RideManager.Rides[a]
			if not ride then return "not a ride's scooter" end
			return begin(def, b, ride, true)
		elseif what == "receipt" then
			return TrollEffects.ProcessReceipt({
				PurchaseId = HttpService:GenerateGUID(false), PlayerId = a.UserId,
				ProductId = def.ProductId, CurrencySpent = 0,
			})
		end
		return "start | receipt"
	end
	hook.Parent = ServerStorage
end

return TrollEffects
