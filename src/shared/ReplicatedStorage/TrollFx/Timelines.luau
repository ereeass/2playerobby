--=====================================================================
-- Timelines   (ReplicatedStorage.TrollFx)
--
-- The clock of each show-and-explode troll, by the scooter's Troll attribute: whatever shows or
-- films one (the Troll spectate camera, the two riders' own camera) asks here rather than
-- naming a troll. Each has LEAD, EXPLODE, END, Rise, Camera, Shake, Clear, Pulled, BestSide.
-- A new one: its <Id>Timeline module in this folder, and a line here.
--=====================================================================

local folder = script.Parent

local Timelines = {
	Rocket  = require(folder:WaitForChild("RocketTimeline")),
	Explode = require(folder:WaitForChild("ExplodeTimeline")),
	Freeze  = require(folder:WaitForChild("FreezeTimeline")),
	Ufo     = require(folder:WaitForChild("UfoTimeline")),
	Slap    = require(folder:WaitForChild("SlapTimeline")),
	BlackHole = require(folder:WaitForChild("BlackHoleTimeline")),
}

-- the clock of the troll playing on `scooter` right now, or nil
function Timelines.Of(scooter)
	local id = scooter and scooter:GetAttribute("Troll")
	local tl = type(id) == "string" and Timelines[id]
	return type(tl) == "table" and tl or nil
end

return Timelines
