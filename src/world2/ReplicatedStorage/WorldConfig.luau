--=====================================================================
-- WorldConfig   (ReplicatedStorage)   *** WORLD 2 ***
--
-- EVERYTHING that is different from one world (place) to the next, in one place. Every other
-- script is the same in every world and reads its world's settings from here - so a new
-- world is: copy the place, build its course, and fill this in. Nothing else changes.
--
-- Keep this module OUT of any shared Package: each place has its own copy.
--
-- Also per world, but not in here (they're in the map itself):
--   * the start gate tagged "RunStartLine" and the finish gate tagged "FinishLine"
--   * each checkpoint's parking lot with its bays (<BayPrefix>1 .. 4, each a part with a
--     ScooterSpawn attachment) and its arrival part (CheckpointId attribute = the Id below)
--   * hazard tags on the obstacles: KillZone, KillGate, Landmine, WaterHazard, RottenPlank,
--     Hazard (revive spots keep clear of these), IcySurface ...
--   * the loading screen's picture and camera: ReplicatedFirst.LoadingScreen.LoadingGui >
--     Background (Image + CameraPosition / CameraLookAt / CameraFOV / ImageAspect attributes)
--   * the portals: each WorldPortal model's PlaceId (where it goes) and RequiresUnlock (the
--     unlock needed to use it, "" = open to everyone)
--   * the course line: after building the course run, in Studio's command bar (Edit mode)
--         require(game.ServerStorage.CoursePathBuilder).Build()
--=====================================================================

local V = Vector3.new

local WorldConfig = {}

WorldConfig.Id   = 2
WorldConfig.Name = "World 2"

-- every world's place, by world number (the portals and future world-select use these)
WorldConfig.PlaceIds = {
	[1] = 121371815815493,
	[2] = 109921805573489,
}

---------------------------------------------------------------- saved progress
-- This world's OWN saved progress (so World 2 doesn't unlock from World 1's checkpoints).
-- Spins, skins, revives, skips, troll credits and playtime are shared by every world.
WorldConfig.CheckpointSaveKey = "CheckpointProgress_W2"   -- World 2's own (never World 1's)
-- set on a player (saved) when their duo drives over this world's finish line
WorldConfig.FinishUnlocks     = "BeatWorld2"   -- (a World 3 portal would ask for this)
-- this world's Fastest Duos leaderboard (its own OrderedDataStore)
WorldConfig.FastestDuosStore  = "FastestDuos_W2"
-- this world's playtime leaderboard: only time played in World 2 (its own stores, so it
-- started empty; World 1's board keeps "Playtime_v1")
-- (reset again 2026-09-30 by switching to new, empty stores; "Playtime_W2" is untouched)
WorldConfig.PlaytimeStore     = "Playtime_W2_2"

---------------------------------------------------------------- checkpoints
-- The course's checkpoints, in Order (see Shared.Checkpoints for what each field does).
-- Image: the picture on its card in the booth's checkpoint selector.
WorldConfig.Checkpoints = {
	-- the start: the Checkpoint 1 Parking Lot next to the lobby (its 4 bays Checkpoint1_Bay1..4,
	-- and the start gate tagged RunStartLine). Rename it, give it a picture, or move the lot.
	{ Id = "W2_1", DisplayName = "Cocoa Crossing", Order = 1, Unlocked = true, Image = "rbxassetid://93412079957327", BayPrefix = "Checkpoint1_Bay", Biome = "Town" },   -- (decal 116829256873537)
	-- Checkpoint 2 Valentine Lot (bays Checkpoint2_Bay1..4, arrival Checkpoint2_Arrival). Add an Image when you have one.
	{ Id = "W2_2", DisplayName = "Sweetheart Square", Order = 2, Unlocked = true, Image = "rbxassetid://137196444537002", BayPrefix = "Checkpoint2_Bay", Biome = "Valentine" },   -- (decal 110996790652025)
	-- Checkpoint 3 Lava Lot (bays Checkpoint3_Bay1..4, arrival Checkpoint3_Arrival). Add an Image when you have one.
	{ Id = "W2_3", DisplayName = "Magma Rocks", Order = 3, Unlocked = true, Image = "rbxassetid://138091921431947", BayPrefix = "Checkpoint3_Bay", Biome = "Lava" },   -- (decal 86675555060032)
	-- Checkpoint 4 Lab Lot (bays Checkpoint4_Bay1..4, arrival Checkpoint4_Arrival). Add an Image when you have one.
	{ Id = "W2_4", DisplayName = "Toxic Lab", Order = 4, Unlocked = true, Image = "rbxassetid://82538001652168", BayPrefix = "Checkpoint4_Bay", Biome = "Lab" },   -- (decal 138147220513008)
	-- Checkpoint 5 Pirate Lot (bays Checkpoint5_Bay1..4, arrival Checkpoint5_Arrival). Add an Image when you have one.
	{ Id = "W2_5", DisplayName = "Pirate Cove", Order = 5, Unlocked = true, Image = "rbxassetid://132692341240336", BayPrefix = "Checkpoint5_Bay", Biome = "Pirate" },   -- (decal 82471499746526)
	-- each new checkpoint as you build it (its lot needs bays <BayPrefix>1..4 and an arrival
	-- part with a CheckpointId attribute = its Id):
	-- { Id = "W2_2", DisplayName = "...", Order = 2, Unlocked = true, Image = "rbxassetid://...", BayPrefix = "W2Checkpoint2_Bay", Biome = "Beach" },
}
-- extra biomes this world adds (name = the unlock popup's colour); the built-in ones are
-- Town, Beach, Snow, Jungle, Food (Shared.Checkpoints)
WorldConfig.Biomes = {
	Valentine = Color3.fromRGB(255, 96, 150),
	Lava      = Color3.fromRGB(255, 110, 30),
	Lab       = Color3.fromRGB(120, 255, 70),
	Pirate    = Color3.fromRGB(60, 170, 230),
}
-- and their placeholder card art in the checkpoint selector: name = { sky top, sky bottom, ground }
WorldConfig.BiomeArt = {
	Valentine = { Color3.fromRGB(255, 170, 200), Color3.fromRGB(214, 64, 108), Color3.fromRGB(255, 214, 228) },
	Lava      = { Color3.fromRGB(255, 140, 60), Color3.fromRGB(150, 30, 20), Color3.fromRGB(60, 52, 54) },
	Lab       = { Color3.fromRGB(170, 255, 140), Color3.fromRGB(40, 140, 60), Color3.fromRGB(196, 202, 208) },
	Pirate    = { Color3.fromRGB(120, 200, 255), Color3.fromRGB(20, 90, 160), Color3.fromRGB(150, 104, 64) },
}

---------------------------------------------------------------- area music
-- The track that plays while riding each area (by the checkpoint Order it starts at).
-- Start / End trim silence off the file (seconds).
WorldConfig.AreaMusic = {
	[1] = { Name = "Chocolate area music",  Id = 117308572731045, Start = 0, End = 207.72 },
	[2] = { Name = "Valentines area music", Id = 108385958192107, Start = 0, End = 142.8 },
	[3] = { Name = "Magma area music",      Id = 113072554742140, Start = 0, End = 110.59 },  -- (last 5 s of the file cut)
	[4] = { Name = "Scientist area music",  Id = 123910361934785, Start = 0, End = 63.58 },
	[5] = { Name = "Pirate area music",     Id = 139806933564011, Start = 0, End = 115.03 },  -- (last 5 s of the file cut)
}

---------------------------------------------------------------- the course line
-- Gaps in the course nothing can walk (a raised drawbridge...), laid straight across by
-- CoursePathBuilder: { After = the checkpoint Order it comes after, From, To, What }
WorldConfig.CourseGaps = {
	{ After = 2, From = V(-179, 173, 872), To = V(-179, 173, 898), What = "the Valentine drawbridge (raised until its button is hit)" },
}

---------------------------------------------------------------- NUKE ALL (map spots)
-- (ReplicatedStorage.TrollFx.NukeTimeline: the timings and sizes stay there)
-- World 2's spots (2026-09-30): it lands in the open water in the middle of the course,
-- between the Lava lot, the Lab lot and the volcano
WorldConfig.Nuke = {
	GROUND_ZERO = V(-405, 146, 800),   -- the middle of the map, where it lands
	DROP_HEIGHT = 700,                 -- studs above it that it hangs, then falls from
	EST_FROM    = V(-265, 321, 150),   -- the opening shot of the whole map: from (over the lobby) ...
	EST_TO      = V(-257, 296, 200),   -- ... pushing in to ...
	EST_LOOK    = V(-385, 201, 800),   -- ... looking at
	WIDE_EYE    = V(-265, 521, 340),   -- the wide shot it falls and explodes in
	WIDE_BACK   = V(-215, 601, 190),   -- where that camera drifts back to afterwards
}

---------------------------------------------------------------- LAVA DRAGON (map spots)
-- (ReplicatedStorage.TrollFx.DragonTimeline: the timings and sizes stay there)
-- World 2's spots (2026-09-30): it rises out of the open water behind the volcano (between the
-- Lava lot, the Lab lot and the heart hammers) and flies the whole World 2 course
WorldConfig.Dragon = {
	SEA         = 142.06,               -- the sea's surface (Workspace.Map.Water's top)
	GROUND_ZERO = V(-405, 146, 800),    -- where the fireball lands
	POOL        = V(-405, 142.5, 800),  -- the lava pool it rises out of (on the sea)
	HOVER       = V(-405, 306, 800),    -- where it hangs and roars
	-- its flight: from HOVER, over the whole course, ending where it charges the fireball
	PATH = {
		V(-405, 306, 800),
		V(-300, 300, 640),
		V(-160, 320, 440),   -- the start
		V(-150, 300, 560),
		V(-200, 330, 750),   -- checkpoint 2
		V(-190, 350, 900),   -- the drawbridge
		V(-316, 310, 790),   -- checkpoint 3
		V(-400, 420, 650),   -- over the volcano
		V(-490, 340, 865),   -- checkpoint 4
		V(-500, 380, 1050),
		V(-566, 330, 930),   -- checkpoint 5
		V(-630, 360, 720),
		V(-637, 330, 560),   -- the finish
		V(-555, 560, 660),   -- the last point: where it charges the fireball
	},
	EST_FROM  = V(-265, 321, 150),   -- the opening shot
	EST_TO    = V(-257, 296, 200),
	EST_LOOK  = V(-395, 111, 800),
	RISE_EYE  = V(-452, 186, 772),   -- watching it rise out of the pool (low over the water, inside the lava rock road)
	RISE_EYE2 = V(-500, 275, 770),
	WIDE_EYE  = V(-265, 521, 340),   -- the wide shot of the fireball and the blast
	WIDE_BACK = V(-215, 601, 190),
}

---------------------------------------------------------------- BLACK HOLE - KILL ALL (map spots)
-- (ReplicatedStorage.TrollFx.BlackHoleAllTimeline: the timings and sizes stay there)
-- World 2's spots: high over the open water in the middle of the course (the same middle as
-- NUKE ALL's), above everything on it (nothing there stands taller than about 380).
WorldConfig.BlackHoleAll = {
	CENTER      = V(-405, 545, 800),   -- the black hole's middle
	GROUND_ZERO = V(-405, 146, 800),   -- the middle of the map under it (where the debris is torn up from)
	EST_FROM    = V(-265, 321, 150),   -- the opening shot of the whole map: from (over the lobby) ...
	EST_TO      = V(-257, 296, 200),   -- ... pushing in to ...
	EST_LOOK    = V(-385, 201, 800),   -- ... looking at (tilting up to the black hole as it forms)
	PULL_EYE    = V(-265, 665, 340),   -- the wide shot of the pull, a little above it (it drifts in from here)
	PULL_BACK   = V(-215, 740, 190),   -- where that camera is thrown back to after the implosion
}

return WorldConfig
