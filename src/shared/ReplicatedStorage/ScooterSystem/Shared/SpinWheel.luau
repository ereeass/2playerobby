--=====================================================================
-- SpinWheel   (shared: the Daily Wheel's settings)
--
-- Read by the server (ScooterSystem.SpinWheel) and the wheel's window and model
-- (StarterGui.SpinWheelWindow, Workspace["Spin the Wheel"]).
--   Slots     the five slots, clockwise from the pointer at the top.
--               Name     what the wheel shows
--               Chance   its REAL chance, in percent: the server rolls it (ScooterSystem.
--                        SpinWheel), and the five should add up to 100
--               Color    the slot's colour
--               Reward   what winning it gives (none yet = nothing):
--                          { Kind = "Skin", Skin = <Shared.Scooters Id> }  the skin, through
--                          the Skins system; already theirs = never a second copy
--                          { Kind = "Revive", Amount = n }  saved revives (REVIVE's count)
--                          { Kind = "Skip",   Amount = n }  stage skips (Skip Stage's count)
--               Icon     a picture for the slot (a Skin shows the scooter instead)
--   Confetti  a prize this likely or rarer (percent) is celebrated with confetti
--                        a slot with a Reward shows its chance on the wheel; a Skin shows
--                        the scooter side on
--   Products  extra spins for Robux. ProductId 0 = the Developer Product isn't set up yet
--             (its button says so and nothing can be bought). Paste each ID in here.
--=====================================================================

local SpinWheel = {}

-- seconds of time IN THE GAME for each free spin. The clock only runs while the player is in
-- the server; how far they've got is saved, so leaving at 7 minutes and rejoining carries on
-- from 7 minutes - time away never counts. Each spin it earns goes on their saved balance at
-- once and the clock starts over.
SpinWheel.Interval = 15 * 60

SpinWheel.Slots = {
	-- the owners' chances (2026-09-29): 15 + 35 + 15 + 5 + 30 = 100
	{ Name = "Chrome Scooter", Chance = 15, Color = Color3.fromRGB(255, 150, 28),   -- orange
		Reward = { Kind = "Skin", Skin = "Chrome" } },
	{ Name = "Gold Scooter", Chance = 35, Color = Color3.fromRGB(255, 52, 150),     -- pink
		Reward = { Kind = "Skin", Skin = "Gold" } },
	{ Name = "+1 Stage Skip", Chance = 15, Color = Color3.fromRGB(170, 70, 255),    -- purple
		Reward = { Kind = "Skip", Amount = 1 }, Icon = "rbxassetid://75109346159902" },   -- the Daily Rewards' skip
	{ Name = "Rainbow Scooter", Chance = 5, Color = Color3.fromRGB(42, 158, 255),    -- blue
		Reward = { Kind = "Skin", Skin = "Rainbow" } },
	{ Name = "+1 Revive", Chance = 30, Color = Color3.fromRGB(96, 218, 44),         -- green
		Reward = { Kind = "Revive", Amount = 1 }, Icon = "rbxassetid://78100362096481" },   -- the Daily Rewards' revive
}

SpinWheel.ConfettiChance = 10

-- What a slot's prize is called on the REWARD banner ("RAINBOW SCOOTER"): its Name. The
-- server sends it with the result it rolled.
function SpinWheel.RewardText(slot)
	local s = SpinWheel.Slots[slot]
	return s and string.upper(s.Name or "?") or "?"
end

-- Price is only what the button shows until the product's own price has loaded
SpinWheel.Products = {
	{ Spins = 1,  Price = 5,  ProductId = 3715283511 },
	{ Spins = 3,  Price = 15, ProductId = 3715283566 },
	{ Spins = 10, Price = 50, ProductId = 3715283592 },
}

return SpinWheel
