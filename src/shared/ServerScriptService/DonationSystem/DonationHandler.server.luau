--=====================================================================
-- DonationSystem / DonationHandler
--
-- Owns MarketplaceService.ProcessReceipt for the whole game. Roblox
-- allows ONE ProcessReceipt callback per server, so any developer
-- products you add later must be handled in processReceipt below.
--
-- The board only changes once Roblox hands us a receipt, i.e. after the
-- purchase has really gone through. Clicking a button changes nothing.
--=====================================================================

local MarketplaceService = game:GetService("MarketplaceService")
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local ServerStorage      = game:GetService("ServerStorage")
local HttpService        = game:GetService("HttpService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local Config             = require(ReplicatedStorage:WaitForChild("DonationSystem"):WaitForChild("Config"))
local DataManager        = require(script.Parent.DataManager)
local LeaderboardManager = require(script.Parent.LeaderboardManager)
local DonationWebhook    = require(script.Parent.DonationWebhook)   -- the team's Discord log
local ScooterSelection   = require(game:GetService("ServerScriptService"):WaitForChild("ScooterSystem"):WaitForChild("ScooterSelection"))
local DeathManager       = require(game:GetService("ServerScriptService"):WaitForChild("ScooterSystem"):WaitForChild("DeathManager"))
local ReviveProductId    = require(ReplicatedStorage:WaitForChild("ScooterSystem"):WaitForChild("Shared"):WaitForChild("Config")).ReviveProductId or 0
local ScooterWebhook     = require(game:GetService("ServerScriptService"):WaitForChild("ScooterSystem"):WaitForChild("ScooterWebhook"))   -- the team's Discord log of scooter sales
local SkipStage          = require(game:GetService("ServerScriptService"):WaitForChild("ScooterSystem"):WaitForChild("SkipStage"))
local TrollEffects       = require(game:GetService("ServerScriptService"):WaitForChild("ScooterSystem"):WaitForChild("TrollEffects"))
local SpinWheel          = require(game:GetService("ServerScriptService"):WaitForChild("ScooterSystem"):WaitForChild("SpinWheel"))
local NukeAll            = require(game:GetService("ServerScriptService"):WaitForChild("ScooterSystem"):WaitForChild("NukeAll"))
local LavaDragon         = require(game:GetService("ServerScriptService"):WaitForChild("ScooterSystem"):WaitForChild("LavaDragon"))
local BlackHoleAll       = require(game:GetService("ServerScriptService"):WaitForChild("ScooterSystem"):WaitForChild("BlackHoleAll"))
local Gifting            = require(game:GetService("ServerScriptService"):WaitForChild("ScooterSystem"):WaitForChild("Gifting"))
local Crates             = require(game:GetService("ServerScriptService"):WaitForChild("ScooterSystem"):WaitForChild("Crates"))

local amountByProduct = {}
local unset = 0
for amount, productId in pairs(Config.DonationProducts) do
	if productId and productId ~= 0 then
		amountByProduct[productId] = amount
	else
		unset += 1
	end
end
if unset > 0 then
	warn(("[Donations] %d donate button(s) have no Developer Product ID yet (ReplicatedStorage.DonationSystem.Config)"):format(unset))
end

--------------------------------------------------------------------- receipts
local function processReceipt(receipt)
	local amount = amountByProduct[receipt.ProductId]
	if amount then
		-- What they actually paid wins over the button label, in case a
		-- product's price and its Config entry ever drift apart.
		local spent = tonumber(receipt.CurrencySpent) or 0
		if spent > 0 then amount = spent end

		if LeaderboardManager.RecordDonation(receipt.PlayerId, amount, receipt.PurchaseId) then
			DonationWebhook.Log(receipt.PlayerId, amount, receipt.PurchaseId)   -- in the background
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		-- Not saved yet: Roblox offers this receipt again later (and when
		-- the player next joins), and DataManager makes the retry safe.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- A revive bought on the death popup (ScooterSystem.DeathManager): it revives that ride
	-- now, or - with nothing left to revive - is saved as a free revive for next time
	if receipt.ProductId == ReviveProductId and ReviveProductId ~= 0 then
		return DeathManager.ProcessReviveReceipt(receipt)
	end

	-- 5x REVIVES / INFINITE REVIVES (under the death popup): the buyer's saved revives or their
	-- permanent infinite revives, saved with the receipt (never twice), and the ride revived now
	if DeathManager.IsRevivePack(receipt.ProductId) then
		return DeathManager.ProcessPackReceipt(receipt)
	end

	-- A scooter bought with a developer product: a permanent unlock, saved before the
	-- purchase is confirmed (Shared.Scooters: Unlock = { Type = "Product", ProductId = ... })
	if ScooterSelection.IsScooterProduct(receipt.ProductId) then
		if ScooterSelection.GrantProduct(receipt.PlayerId, receipt.ProductId) then
			ScooterWebhook.LogProduct(receipt)   -- in the background
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet   -- offered again (e.g. when they rejoin)
	end

	-- A scooter bought as a GIFT for another player (Skins menu gift button): delivered to
	-- them (or saved for when they're back) before it is confirmed (ScooterSystem.Gifting)
	if Gifting.IsProduct(receipt.ProductId) then
		return Gifting.ProcessReceipt(receipt)
	end

	-- Skip Stage: the buyer's ride moves on a stage (or the skip is saved for later if it
	-- can't be used now). Granted only once it is used or saved (ScooterSystem.SkipStage).
	if SkipStage.IsProduct(receipt.ProductId) then
		return SkipStage.ProcessReceipt(receipt)
	end

	-- A Troll bought in the Troll window: it plays on the duo the buyer was watching, or - with
	-- them gone - is saved as a free one for next time (ScooterSystem.TrollEffects)
	if TrollEffects.IsProduct(receipt.ProductId) then
		return TrollEffects.ProcessReceipt(receipt)
	end

	-- A crate bought in the Shop: the server rolls its prize and saves it with the receipt,
	-- then everyone near the buyer sees it open (ScooterSystem.Crates; IDs in Shared.Crates)
	if Crates.IsProduct(receipt.ProductId) then
		return Crates.ProcessReceipt(receipt)
	end

	-- Spins bought at the Daily Wheel: added to the player's spin balance once saved
	-- (ScooterSystem.SpinWheel; the IDs are in Shared.SpinWheel.Products)
	if SpinWheel.IsProduct(receipt.ProductId) then
		return SpinWheel.ProcessReceipt(receipt)
	end

	-- NUKE ALL, bought at the Nuke Podium (ScooterSystem.NukeAll)
	if NukeAll.IsProduct(receipt.ProductId) then
		return NukeAll.ProcessReceipt(receipt)
	end

	-- LAVA DRAGON, bought at the Lava Dragon Podium (ScooterSystem.LavaDragon)
	if LavaDragon.IsProduct(receipt.ProductId) then
		return LavaDragon.ProcessReceipt(receipt)
	end

	-- BLACK HOLE - KILL ALL, bought at the Black Hole Podium (ScooterSystem.BlackHoleAll)
	if BlackHoleAll.IsProduct(receipt.ProductId) then
		return BlackHoleAll.ProcessReceipt(receipt)
	end

	-- Other developer products go here, for example:
	-- if receipt.ProductId == 123456789 then
	--     ...give the item...
	--     return Enum.ProductPurchaseDecision.PurchaseGranted
	-- end

	warn(("[Donations] Receipt for product %d, which is not in Config.DonationProducts; left unprocessed")
		:format(receipt.ProductId))
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

MarketplaceService.ProcessReceipt = processReceipt

--------------------------------------------------------------------- players
local function onPlayer(plr)
	task.spawn(LeaderboardManager.LoadPlayer, plr)
end
Players.PlayerAdded:Connect(onPlayer)
for _, plr in ipairs(Players:GetPlayers()) do onPlayer(plr) end

LeaderboardManager.Start()

--------------------------------------------------------------------- studio
if DataManager.Backend == "Memory" and RunService:IsStudio() then
	print("[Donations] Studio test: donations are kept in memory and vanish when the test stops")

	-- Preview helper, Studio only and memory only, never exists in a live
	-- server. From the command bar while testing (Server view):
	--   game.ServerStorage.DonationStudioTest:Invoke(userId, amount)
	local hook = Instance.new("BindableFunction")
	hook.Name = "DonationStudioTest"
	hook.OnInvoke = function(userId, amount)
		return LeaderboardManager.RecordDonation(userId, amount, HttpService:GenerateGUID(false))
	end
	hook.Parent = ServerStorage
end
