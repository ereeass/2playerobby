--=====================================================================
-- Scooters   (shared registry: the single source of truth)
--
-- One entry per scooter in the SCOOTERS menu, in SortOrder. The menu has
-- at least Scooters.Slots slots; entries fill them in order and the rest stay empty.
-- More entries than slots: the menu adds rows (4 cards each) by itself.
--
--   Id           the saved id (never rename one that has shipped)
--   DisplayName  the name on its card
--   Model        its working model in ServerStorage.ScooterModels: rides spawn it,
--                and the server makes a visual-only copy for the menu from it
--   SortOrder    its place in the menu
--   Unlock       who may ride it (checked on the server, ScooterSelection):
--     { Type = "Free" }
--     { Type = "Group",      GroupId = 123, MinRank = 1 }  -- in a Roblox group (its card offers the join prompt)
--     { Type = "GroupReward", GroupId = 123, MinRank = 1 } -- granted by the server when a session starts,
--                                                          -- to a group member who has rejoined since it
--                                                          -- first saw them in the group ("join, like,
--                                                          -- rejoin"; a like can't be checked, so the
--                                                          -- rejoin stands in for it). Saved for good;
--                                                          -- riding it also needs them still in the group
--     { Type = "GamePass",   GamePassId = 123 }            -- owns a game pass
--     { Type = "Badge",      BadgeId = 123 }               -- has a badge
--     { Type = "Product",    ProductId = 123, Price = 25 } -- bought once with a developer
--                                                          -- product: DonationHandler grants
--                                                          -- it and it is saved for good
--                            GiftProductId = 456           -- (optional) its GIFT product: bought
--                                                          -- for another player in the server from
--                                                          -- the card's gift button (ScooterSystem.
--                                                          -- Gifting). 0 = no gift product yet: the
--                                                          -- gift button only shows in Studio
--     { Type = "DailyReward", Day = 3 }                   -- LIMITED: only from that day of the Daily
--                                                          -- Rewards calendar (DailyRewards); saved for
--                                                          -- good. Never sold: its card says LIMITED
--     { Type = "Limited", Notice = "..." }               -- LIMITED, and not obtainable yet: its card says
--                                                          -- LIMITED, and picking it shows Notice. Whatever
--                                                          -- gives it later saves it in OwnedScooters
--     { Type = "Archived", LegacyProductId = 123 }        -- no longer sold and not on the menu
--                                                          -- (Scooters.Archived): its owners keep it
--     { Type = "Checkpoint", Checkpoint = "SnowyHills" }   -- reached a checkpoint } plug the progress
--     { Type = "World",      World = 3 }                   -- completed a world    } system into
--                                                          --   ScooterSelection.Progress
--
-- Adding a scooter: put its model in ServerStorage.ScooterModels and add an entry.
--=====================================================================

local Scooters = {}

Scooters.DefaultId = "Red"   -- new players, and anyone whose pick is no longer valid
Scooters.Slots     = 12      -- at least 4 columns x 3 rows in the menu (it grows by whole rows)
-- the gift icon (the cards' gift button, the Gift page, the gift messages); "" = a drawn box
Scooters.GiftIcon  = "rbxassetid://76080931798664"   -- decal 99783390875674

Scooters.List = {
	{ Id = "Red", DisplayName = "DEFAULT", Model = "RedScooter", SortOrder = 1,
		Unlock = { Type = "Free" } },
	{ Id = "Ice", DisplayName = "ICE", Model = "IceScooter", SortOrder = 2,
		Unlock = { Type = "GroupReward", GroupId = 32303102, MinRank = 1 } },   -- Obstacle Labs members, granted on a rejoin
	{ Id = "Bee", DisplayName = "BEE", Model = "BeeScooter", SortOrder = 11,
		-- Limited: Day 5 of the Daily Rewards calendar. It used to be sold (25 Robux,
		-- LegacyProductId): anyone who bought it keeps it, and a purchase Roblox still
		-- owes a receipt for is still granted - but it is never offered for sale again.
		Unlock = { Type = "DailyReward", Day = 5, LegacyProductId = 3714461156 } },
	{ Id = "Rainbow", DisplayName = "RAINBOW", Model = "RainbowScooter", SortOrder = 12,
		-- the default scooter (same physics, same parts) with a rainbow body and a thin rainbow
		-- trail. Limited: won from the Spin the Wheel
		Unlock = { Type = "Limited", Notice = "This item can be obtained from Spin the Wheel!" },
		-- a flat side-on picture of it: the lobby Spin the Wheel shows this in its slot (a
		-- SurfaceGui can't draw the 3D preview)
		Picture = "rbxassetid://79120496698579" },
	{ Id = "Gold", DisplayName = "GOLD", Model = "GoldScooter", SortOrder = 13,
		-- the default scooter (same physics, same parts) in polished gold, with the Ice
		-- Scooter's speed trail in gold (Chassis.GoldTrail, run by ScooterFx). Limited: a Spin
		-- the Wheel prize
		Unlock = { Type = "Limited", Notice = "This item can be obtained from Spin the Wheel!" },   -- a wheel prize
		Picture = "rbxassetid://92980375374628" },   -- the lobby wheel's side-on picture (decal 133059647600704)
	{ Id = "Grass", DisplayName = "GRASS", Model = "GrassScooter", SortOrder = 14,
		-- the default scooter (same physics, same parts) covered in grass, flicking a few grass
		-- clippings off its rear tyre (Chassis.GrassTrail, run by ScooterFx). Limited: a
		-- Daily Rewards skin
		Unlock = { Type = "DailyReward", Day = 3 } },   -- Daily Rewards only
	{ Id = "Galaxy", DisplayName = "GALAXY", Model = "GalaxyScooter", SortOrder = 5,
		-- the default scooter (same physics, same parts) in deep space, with a little stardust
		-- off its rear tyre (Chassis.GalaxyTrail, run by ScooterFx). Sold for Robux
		Unlock = { Type = "Product", ProductId = 3715387396, Price = 20, GiftProductId = 3716902965 } },   -- sold for Robux
	{ Id = "Candy", DisplayName = "CANDY", Model = "CandyScooter", SortOrder = 6,
		-- the default scooter (same physics, same parts) in pink-and-white candy-cane stripes,
		-- popping sprinkles off its rear tyre (Chassis.CandyTrail, run by ScooterFx). Sold for Robux
		--
		Unlock = { Type = "Product", ProductId = 3715387425, Price = 15, GiftProductId = 3716902826 } },   -- sold for Robux
	{ Id = "Chrome", DisplayName = "CHROME", Model = "ChromeScooter", SortOrder = 15,
		-- the default scooter (same physics, same parts) in mirror-polished chrome, with quick
		-- glints off its rear tyre (Chassis.ChromeTrail, run by ScooterFx). Limited: a Spin
		-- the Wheel prize
		Unlock = { Type = "Limited", Notice = "This item can be obtained from Spin the Wheel!" },   -- a wheel prize
		Picture = "rbxassetid://113819811265064" },   -- the lobby wheel's side-on picture of the premium Chrome (was 110801344730011)
	{ Id = "Beach", DisplayName = "BEACH", Model = "BeachScooter", SortOrder = 16,
		-- the default scooter (same physics, same parts) in sand with seashells and starfish,
		-- spraying sand grains and a few sea droplets off its rear tyre (Chassis.BeachTrail,
		-- run by ScooterFx). Limited: a Daily Rewards skin
		Unlock = { Type = "DailyReward", Day = 7 } },   -- Daily Rewards only
	{ Id = "Pixel", DisplayName = "PIXEL", Model = "PixelScooter", SortOrder = 10,
		-- the default scooter (same physics, same parts) in a retro 8-bit block pattern, popping
		-- square arcade-coloured pixels off its rear tyre (Chassis.PixelTrail, run by
		-- ScooterFx). Sold for Robux
		Unlock = { Type = "Product", ProductId = 3715387502, Price = 25, GiftProductId = 3716902776 } },   -- sold for Robux
	{ Id = "Dragon", DisplayName = "DRAGON", Model = "DragonScooter", SortOrder = 17,
		-- the default scooter (same physics, same parts) built round a mechanical dragon: a
		-- dragon head on the bars, a twin glowing reactor along the deck, folding wings, a jointed
		-- tail and energy wheels. Fire exhaust off its rear (Chassis.DragonExhaustL/RTrail, run by
		-- ScooterFx); the reactor, wings, tail, eyes and boost fire are run by DragonReactorFx.
		-- Limited: from crates (the crate system grants it with ScooterSelection.GrantSkin). It was
		-- sold for 49 Robux until 2026-10-08; everyone who bought it keeps it (OwnedScooters)
		Unlock = { Type = "Limited", Notice = "This item can be obtained from crates!" } },
	{ Id = "Oni", DisplayName = "CYBER ONI", Model = "OniScooter", SortOrder = 18,
		-- the default scooter (same physics, same parts) as a sealed cyber oni: an oni mask with
		-- curved horns on the bars, chains, hinged talismans, crimson armour and a swinging lantern.
		-- Cursed smoke off its rear (Chassis.OniSmokeTrail, run by ScooterFx); the eyes, markings,
		-- talismans, chains, aura and the oni spirit are run by OniScooterFx.
		-- Limited: from crates (the crate system grants it with ScooterSelection.GrantSkin)
		Unlock = { Type = "Limited", Notice = "This item can be obtained from crates!" } },
	{ Id = "Reaper", DisplayName = "DEATH REAPER", Model = "ReaperScooter", SortOrder = 19,
		-- the default scooter (same physics, same parts) as a soul collector: a hooded reaper skull
		-- on the bars, a great scythe over the front, torn cloth, hanging chains, a soul lantern,
		-- bone armour and violet wheels. Mist and small souls off its rear (Chassis.ReaperMistTrail,
		-- run by ScooterFx); the eyes, scythe energy, cloth, chains, lantern, soul stream and
		-- spectral hands are run by ReaperScooterFx.
		-- Limited: from crates (the crate system grants it with ScooterSelection.GrantSkin)
		Unlock = { Type = "Limited", Notice = "This item can be obtained from crates!" } },
	{ Id = "InkDemon", DisplayName = "INK DEMON", Model = "InkDemonScooter", SortOrder = 20,
		-- the default scooter (same physics, same parts) possessed by a hand-drawn ink demon: an
		-- ink demon face with horns and white eyes on the bars, paper talismans, ink tendrils, drips,
		-- brush strokes over a paper frame and sketch lines. Ink splatter off its rear wheel
		-- (Chassis.InkSplatTrail, run by ScooterFx); the eyes, tendrils, drips, sketch lines,
		-- brush strokes, wheel splashes and brush trail are run by InkDemonFx.
		-- Limited: from crates (the crate system grants it with ScooterSelection.GrantSkin)
		Unlock = { Type = "Limited", Notice = "This item can be obtained from crates!" } },
	{ Id = "Watcher", DisplayName = "THE WATCHER", Model = "WatcherScooter", SortOrder = 21,
		-- the default scooter (same physics, same parts) grown into an ancient all-seeing artifact:
		-- a great lidded eye in a ring of cracked ivory stone on the bars, a smaller eye at the
		-- rear, orbiting eye-orbs, celestial rings, floating stone and gold, hanging artifacts,
		-- glyphs and eyes in the wheels. Gold streaks off its rear (Chassis.WatcherGoldTrail, run
		-- by ScooterFx); the eyes, orbs, rings, floating pieces, glyphs, trail and reality shifts
		-- are run by WatcherFx.
		-- Sold for Robux (on the lobby podium where the Dragon used to stand)
		Unlock = { Type = "Product", ProductId = 3717069494, Price = 49, GiftProductId = 3717069790 } },   -- sold for Robux
}

-- ARCHIVED (2026-10-06: these never sold). Off the SCOOTERS menu and no longer for sale.
-- Their models stay in ServerStorage.ScooterModels, so anyone who bought one keeps riding it
-- (ScooterSelection still checks OwnedScooters for them), and a purchase Roblox still owes a
-- receipt for is granted (LegacyProductId). Scooters.Get finds them; the menu (Scooters.List) doesn't.
-- To bring one back: move its entry into Scooters.List with { Type = "Product", ProductId = .., Price = .. }.
Scooters.Archived = {
	{ Id = "Glass", DisplayName = "GLASS", Model = "GlassScooter", SortOrder = 4,
		-- the default scooter (same physics, same parts) in see-through glass, with a faint
		-- glassy shimmer off its rear tyre (Chassis.GlassTrail, run by ScooterFx). Archived
		-- 2026-10-07 (was sold for 20 Robux); a gift Roblox still owes a receipt for is delivered
		Unlock = { Type = "Archived", LegacyProductId = 3715387334, LegacyGiftProductId = 3716902895, WasPrice = 20 } },
	{ Id = "Magma", DisplayName = "MAGMA", Model = "MagmaScooter", SortOrder = 3,
		-- the default scooter (same physics, same parts) in volcanic rock with glowing cracks,
		-- dropping a little hot magma under its rear tyre (Chassis.MagmaTrail, run by
		-- ScooterFx). Sold for Robux: its card shows the product's price
		Unlock = { Type = "Archived", LegacyProductId = 3715385688, WasPrice = 15 } },
	{ Id = "ToxicSlime", DisplayName = "TOXIC SLIME", Model = "ToxicSlimeScooter", SortOrder = 9,
		-- the default scooter (same physics, same parts) in glossy toxic slime, flicking slime
		-- drops off its rear tyre and leaving small splats that fade (Chassis.SlimeTrail and
		-- SlimeSplatTrail, run by ScooterFx). Sold for Robux
		Unlock = { Type = "Archived", LegacyProductId = 3715387439, WasPrice = 15 } },   -- sold for Robux
	{ Id = "Camo", DisplayName = "CAMO", Model = "CamoScooter", SortOrder = 8,
		-- the default scooter (same physics, same parts) in woodland camouflage, kicking up
		-- little dust puffs and dirt clods off its rear tyre (Chassis.CamoTrail, run by
		-- ScooterFx). Sold for Robux
		Unlock = { Type = "Archived", LegacyProductId = 3715387453, WasPrice = 15 } },   -- sold for Robux
	{ Id = "Troll", DisplayName = "TROLL", Model = "TrollScooter", SortOrder = 7,
		-- the default scooter (same physics, same parts) in teal covered in troll faces (the
		-- TROLL button's icon), popping tiny troll faces off its rear tyre (Chassis.TrollTrail,
		-- run by ScooterFx). Sold for Robux
		Unlock = { Type = "Archived", LegacyProductId = 3715387479, WasPrice = 15 } },   -- sold for Robux
}

table.sort(Scooters.List, function(a, b) return a.SortOrder < b.SortOrder end)
local byId = {}
for _, s in ipairs(Scooters.List) do byId[s.Id] = s end
for _, s in ipairs(Scooters.Archived) do byId[s.Id] = s end

function Scooters.Get(id)
	return type(id) == "string" and byId[id] or nil
end

function Scooters.Default()
	return byId[Scooters.DefaultId]
end

return Scooters
