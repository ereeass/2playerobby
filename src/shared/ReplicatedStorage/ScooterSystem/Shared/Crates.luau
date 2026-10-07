--=====================================================================
-- Crates   (shared: the crates' settings)
--
-- Read by the server (ScooterSystem.Crates: the roll and the prize), the Shop window (its
-- odds and price - StarterGui.ShopGui.ShopUI.Menu) and the opening (StarterPlayerScripts.
-- CrateOpenFx), so what the shop shows is always what the server rolls.
--   GiftProductId  the same crate bought as a GIFT for another player (ScooterSystem.Crates)
--   ProductId  the crate's Developer Product. 0 = not set up yet: its BUY says SOON! and
--              nothing can be bought. Paste the ID in here.
--   Price      what BUY shows until the product's own price has loaded
--   Prizes     the scooters it can give, left to right as the shop shows them. Skin = a
--              Shared.Scooters Id; Chance = its REAL chance in percent (they should add up to
--              100); Rarity = its name and colour in the opening
--   Duplicate  what a prize they already own gives instead: Kind "Revive" (saved revives,
--              REVIVE's count) or "Skip" (stage skips), Amount, and the text the opening shows
--   Model      ReplicatedStorage.CrateModels[Model]: the crate that drops and opens
--=====================================================================

local Crates = {}

-- OWNER TEST: true = the owners' accounts below may see and buy / gift crates even where paid
-- random items are restricted (the owners are in Australia), to try them. Nobody else is
-- affected. Set it back to false when done.
Crates.OwnerTest = true
Crates.Owners = {
	[476180958]  = true,   -- Vexerixx
	[7415418006] = true,   -- Ereeass
}
function Crates.Allowed(player)
	if Crates.OwnerTest and player and Crates.Owners[player.UserId] then return true end
	return player ~= nil and player:GetAttribute("PaidSpinsBlocked") == false
end

Crates.List = {
	Premium = {
		Name      = "PREMIUM CRATE",
		ProductId     = 3717074801,
		GiftProductId = 3717074832,   -- the same crate bought for someone else
		Price     = 49,
		Model     = "Premium",
		Prizes = {
			{ Skin = "InkDemon", Chance = 50, Rarity = "COMMON",    Color = Color3.fromRGB(205, 214, 228) },
			{ Skin = "Dragon",   Chance = 30, Rarity = "RARE",      Color = Color3.fromRGB(70, 170, 255) },
			{ Skin = "Oni",      Chance = 15, Rarity = "EPIC",      Color = Color3.fromRGB(196, 92, 255) },
			{ Skin = "Reaper",   Chance = 5,  Rarity = "LEGENDARY", Color = Color3.fromRGB(255, 210, 60) },
		},
		Duplicate = { Kind = "Revive", Amount = 2, Text = "+2 Revives" },
	},
}

function Crates.Get(id)
	return Crates.List[id]
end

-- the crate a Developer Product opens, and whether it is that crate's GIFT product
function Crates.ForProduct(productId)
	for id, c in pairs(Crates.List) do
		if c.ProductId and c.ProductId ~= 0 and c.ProductId == productId then return id, c, false end
		if c.GiftProductId and c.GiftProductId ~= 0 and c.GiftProductId == productId then return id, c, true end
	end
	return nil
end

-- a prize's entry by its skin (for the opening's rarity colour)
function Crates.PrizeOf(id, skin)
	local c = Crates.List[id]
	if not c then return nil end
	for _, p in ipairs(c.Prizes) do
		if p.Skin == skin then return p end
	end
	return nil
end

return Crates
