-- Checkpoint registry.
--
-- THIS WORLD'S CHECKPOINTS live in ReplicatedStorage.WorldConfig (Checkpoints, Biomes): each
-- world (place) has its own. This module is the same in every world.
--
-- PROGRESSION (ServerScriptService.ScooterSystem.CheckpointProgress)
-- Each player's progress is their own and saved to their account: the highest checkpoint
-- (by Order) they have reached, everything below it included. Checkpoint 1 is everyone's.
-- A pair in a booth may start from any checkpoint up to the LOWER of their two progresses
-- (DuoLimit): Driver 10 + Passenger 6 can pick 1-6, and 7-10 show LOCKED. Reaching the
-- next checkpoint together (both riders driving onto its lot - or through its arrival part -
-- on one ride) unlocks it for each of them who didn't have it yet.
--
-- Unlocked here means the checkpoint is RELEASED (built and open to anyone who has
-- earned it); Unlocked = false says COMING SOON for everyone and can't be picked.
--
-- Checkpoint 1: the Checkpoint 1 Parking Lot, each booth station in its own bay
-- (BayPrefix: the lot's Checkpoint1_Bay1 .. 4 markers, which live inside the lot and move
-- with it).
-- Checkpoint 2: the Checkpoint 2 Beach Lot at the end of Road3, bays Checkpoint2_Bay1 .. 4,
-- arrival part Checkpoint2_Arrival (CheckpointId = "Test2") across its entrance.
-- Checkpoint 3: the Checkpoint 3 Snow Lot (1.5x the size) at the end of the Narrow Dirt
-- Road, bays Checkpoint3_Bay1 .. 4, arrival part Checkpoint3_Arrival (CheckpointId = "Test3").
-- Checkpoint 4: the Checkpoint 4 Jungle Lot, a floating rainforest island at the end of the
-- Atlas Spiral Road, bays Checkpoint4_Bay1 .. 4, arrival part Checkpoint4_Arrival
-- (CheckpointId = "Test4").
-- Checkpoint 5: the Checkpoint 5 Food Lot, a floating glass plate piled with food, bays
-- Checkpoint5_Bay1 .. 4, arrival part Checkpoint5_Arrival (CheckpointId = "Test5").
--
-- BayPrefix (optional) names a set of start parts, one per station:
-- <BayPrefix><station id>, so teams starting together never share a spot.
-- (Ids stay "TestN" so nothing keyed on them changes; DisplayName is what shows.)
-- DisplayName is the LOCATION name (the big text on the booth card and the unlock
-- popup); the small "CHECKPOINT <Order>" above it comes from Order.
--
-- Biome picks the colour of the "UNLOCKED NEW CHECKPOINT" popup (Biomes below).
--
-- A new checkpoint is an entry with its own Id, a DisplayName, the next Order, a Biome,
-- Unlocked = true once it's built, and either a BayPrefix or a SpawnPartName pointing at a
-- part under Workspace.RideSystem.StartLocations; plus an arrival part on the course with
-- a CheckpointId attribute set to its Id. Image (optional, "rbxassetid://...") is the
-- picture on its card; without one the card shows placeholder art.

local World = require(game:GetService("ReplicatedStorage"):WaitForChild("WorldConfig"))

local Checkpoints = {}

-- this world's checkpoints (WorldConfig.Checkpoints), e.g.
--   { Id = "Test1", DisplayName = "Hammer Hills", Order = 1, Unlocked = true,
--     Image = "rbxassetid://...", BayPrefix = "Checkpoint1_Bay", Biome = "Town" }
Checkpoints.List = World.Checkpoints or {}

-- the popup colour for each biome's checkpoints (plus any this world adds: WorldConfig.Biomes)
Checkpoints.Biomes = {
	Town   = Color3.fromRGB(255, 176, 72),
	Beach  = Color3.fromRGB(255, 222, 102),
	Snow   = Color3.fromRGB(150, 220, 255),
	Jungle = Color3.fromRGB(120, 224, 96),
	Food   = Color3.fromRGB(255, 136, 204),
}
for name, color in pairs(World.Biomes or {}) do Checkpoints.Biomes[name] = color end
Checkpoints.DefaultColor = Color3.fromRGB(255, 255, 255)

function Checkpoints.GetById(id)
	for _, c in ipairs(Checkpoints.List) do
		if c.Id == id then return c end
	end
	return nil
end

function Checkpoints.ByOrder(order)
	for _, c in ipairs(Checkpoints.List) do
		if c.Order == order then return c end
	end
	return nil
end

function Checkpoints.OrderOf(id)
	local c = Checkpoints.GetById(id)
	return c and c.Order or nil
end

function Checkpoints.MaxOrder()
	local best = 1
	for _, c in ipairs(Checkpoints.List) do best = math.max(best, c.Order) end
	return best
end

function Checkpoints.ColorOf(cp)
	return (cp and Checkpoints.Biomes[cp.Biome]) or Checkpoints.DefaultColor
end

-- The highest checkpoint a pair may start from: the lower of the two players' progress.
-- With only one of them known it's theirs; nothing known, checkpoint 1.
function Checkpoints.DuoLimit(a, b)
	if a and b then return math.min(a, b) end
	return a or b or 1
end

-- Can a pair whose limit is `limit` start from checkpoint `id`?
function Checkpoints.IsAccessible(id, limit)
	local c = Checkpoints.GetById(id)
	return c ~= nil and c.Unlocked == true and c.Order <= math.max(1, limit or 1)
end

function Checkpoints.GetDefault()
	local best
	for _, c in ipairs(Checkpoints.List) do
		if c.Unlocked and (not best or c.Order < best.Order) then best = c end
	end
	return best
end

-- Every checkpoint, as the booth shows it (for no one in particular: released or not).
function Checkpoints.GetMenu()
	return Checkpoints.MenuFor(math.huge)
end

-- The booth's list for a pair whose limit is `limit`: a released checkpoint above it comes
-- with Locked = true (its card says LOCKED and START won't take it).
function Checkpoints.MenuFor(limit)
	limit = math.max(1, limit or 1)
	local out = {}
	for _, c in ipairs(Checkpoints.List) do
		local released = c.Unlocked == true
		table.insert(out, {
			Id = c.Id, DisplayName = c.DisplayName, Image = c.Image,
			Order = c.Order, Unlocked = released,
			Locked = released and c.Order > limit or nil,
			Biome = c.Biome,
		})
	end
	table.sort(out, function(a, b) return a.Order < b.Order end)
	return out
end

-- released at all (for anyone who has earned it)
function Checkpoints.IsSelectable(id)
	local c = Checkpoints.GetById(id)
	return c ~= nil and c.Unlocked == true
end

return Checkpoints
