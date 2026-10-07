--=====================================================================
-- DailyRewards   (shared: what each day of the Daily Rewards calendar gives)
--
-- Read by the server (ScooterSystem.DailyRewards, which grants them) and by the
-- calendar (StarterGui.DailyGui). A day missing from Days is shown as "coming soon"
-- and can't be claimed yet; adding it later is all it takes.
--   Kind    "Revive" / "Skip": that many saved revives / stage skips (the same counts
--           REVIVE and Skip Stage spend and show) - "Skin": the skin with that Id
--           (Shared.Scooters), which can then only be had here (Limited)
--=====================================================================

local DailyRewards = {}

DailyRewards.Interval = 24 * 60 * 60   -- seconds from claiming one day to the next being ready
DailyRewards.Count    = 7              -- days on the calendar

DailyRewards.Days = {
	[1] = { Kind = "Revive", Amount = 1, Name = "Revive",     Icon = "rbxassetid://78100362096481" },   -- decal 125988062611790
	[2] = { Kind = "Skip",   Amount = 2, Name = "Stage Skip", Icon = "rbxassetid://75109346159902" },   -- decal 97260459563578
	[3] = { Kind = "Skin",   Skin = "Grass", Name = "Grass Skin", Limited = true },
	[4] = { Kind = "Revive", Amount = 2, Name = "Revive",     Icon = "rbxassetid://78100362096481" },
	[5] = { Kind = "Skin",   Skin = "Bee",   Name = "Bee Skin",   Limited = true },
	[6] = { Kind = "Skip",   Amount = 1, Name = "Stage Skip", Icon = "rbxassetid://75109346159902" },
	[7] = { Kind = "Skin",   Skin = "Beach", Name = "Beach Skin", Limited = true },
}
-- after Day 7 nothing more is claimable yet: the calendar says "More rewards coming soon!"

function DailyRewards.Get(day)
	return DailyRewards.Days[day]
end

return DailyRewards
