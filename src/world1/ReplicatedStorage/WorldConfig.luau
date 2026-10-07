--=====================================================================
-- WorldConfig   (ReplicatedStorage)   *** WORLD 1 ***
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

WorldConfig.Id   = 1
WorldConfig.Name = "World 1"

-- every world's place, by world number (the portals and future world-select use these)
WorldConfig.PlaceIds = {
	[1] = 121371815815493,
	[2] = 109921805573489,
}

---------------------------------------------------------------- saved progress
-- This world's OWN saved progress (so World 2 doesn't unlock from World 1's checkpoints).
-- Spins, skins, revives, skips, troll credits and playtime are shared by every world.
WorldConfig.CheckpointSaveKey = "CheckpointProgress"   -- World 1 keeps its original key
-- set on a player (saved) when their duo drives over this world's finish line
-- this world's playtime leaderboard (its own stores). Reset 2026-09-30 by switching to new,
-- empty stores; the old "Playtime_v1" data is untouched (put that name back to bring it back).
WorldConfig.PlaytimeStore     = "Playtime_W1_2"
WorldConfig.FinishUnlocks     = "BeatWorld1"
-- this world's Fastest Duos leaderboard (its own OrderedDataStore)
WorldConfig.FastestDuosStore  = "FastestDuos_v2"

---------------------------------------------------------------- checkpoints
-- The course's checkpoints, in Order (see Shared.Checkpoints for what each field does).
-- Image: the picture on its card in the booth's checkpoint selector.
WorldConfig.Checkpoints = {
	{ Id = "Test1", DisplayName = "Hammer Hills",  Order = 1, Unlocked = true, Image = "rbxassetid://131424022812850", BayPrefix = "Checkpoint1_Bay", Biome = "Town" },
	{ Id = "Test2", DisplayName = "Dusty Dunes",   Order = 2, Unlocked = true, Image = "rbxassetid://73456228078424",  BayPrefix = "Checkpoint2_Bay", Biome = "Beach" },
	{ Id = "Test3", DisplayName = "Frozen Ruins",  Order = 3, Unlocked = true, Image = "rbxassetid://79698163767715",  BayPrefix = "Checkpoint3_Bay", Biome = "Snow" },
	{ Id = "Test4", DisplayName = "Spiked Forest", Order = 4, Unlocked = true, Image = "rbxassetid://126720996743876", BayPrefix = "Checkpoint4_Bay", Biome = "Jungle" },
	{ Id = "Test5", DisplayName = "Sugar Rush",    Order = 5, Unlocked = true, Image = "rbxassetid://72766810298830",  BayPrefix = "Checkpoint5_Bay", Biome = "Food" },
}
-- extra biomes this world adds (name = the unlock popup's colour); the built-in ones are
-- Town, Beach, Snow, Jungle, Food (Shared.Checkpoints)
WorldConfig.Biomes = {}
-- and their placeholder card art in the checkpoint selector: name = { sky top, sky bottom, ground }
WorldConfig.BiomeArt = {}

---------------------------------------------------------------- area music
-- The track that plays while riding each area (by the checkpoint Order it starts at).
-- Start / End trim silence off the file (seconds).
WorldConfig.AreaMusic = {
	[1] = { Name = "First area music",  Id = 134511747150295, Start = 23.7, End = 156.8 },
	[2] = { Name = "Desert area music", Id = 106668964312263, Start = 0,    End = 63.2 },
	[3] = { Name = "Snow area music",   Id = 95286559055295,  Start = 0,    End = 100.2 },
	[4] = { Name = "Jungle area music", Id = 133281522259309, Start = 0,    End = 66.7 },
	[5] = { Name = "Candy area music",  Id = 83766287291563,  Start = 0,    End = 112.25 },
}

---------------------------------------------------------------- the course line
-- Gaps in the course nothing can walk (a raised drawbridge...), laid straight across by
-- CoursePathBuilder: { After = the checkpoint Order it comes after, From, To, What }
WorldConfig.CourseGaps = {
	{ After = 4, From = V(-583, 330, 159), To = V(-611, 330, 156), What = "the drawbridge (raised until its button is hit)" },
}

---------------------------------------------------------------- NUKE ALL (map spots)
-- (ReplicatedStorage.TrollFx.NukeTimeline: the timings and sizes stay there)
WorldConfig.Nuke = {
	GROUND_ZERO = V(-440, 185, 520),   -- the middle of the map, where it lands
	DROP_HEIGHT = 700,                 -- studs above it that it hangs, then falls from
	EST_FROM    = V(-300, 360, -130),  -- the opening shot of the whole map: from ...
	EST_TO      = V(-292, 335, -80),   -- ... pushing in to ...
	EST_LOOK    = V(-420, 240, 520),   -- ... looking at
	WIDE_EYE    = V(-300, 560, 60),    -- the wide shot it falls and explodes in
	WIDE_BACK   = V(-250, 640, -90),   -- where that camera drifts back to afterwards
}

---------------------------------------------------------------- LAVA DRAGON (map spots)
-- (ReplicatedStorage.TrollFx.DragonTimeline: the timings and sizes stay there)
WorldConfig.Dragon = {
	SEA         = 181.1,                -- the sea's surface (Workspace.Map.Water's top)
	GROUND_ZERO = V(-440, 185, 520),    -- where the fireball lands
	POOL        = V(-470, 181.5, 470),  -- the lava pool it rises out of (on the sea)
	HOVER       = V(-470, 345, 470),    -- where it hangs and roars
	-- its flight: from HOVER, over the whole course, ending where it charges the fireball
	PATH = {
		V(-470, 345, 470),
		V(-400, 320, 540),
		V(-379, 315, 600),   -- checkpoint 2
		V(-382, 345, 743),
		V(-549, 470, 803),
		V(-652, 345, 797),   -- checkpoint 3
		V(-627, 520, 595),
		V(-568, 470, 498),   -- checkpoint 4
		V(-556, 420, 300),
		V(-590, 415, 160),   -- checkpoint 5
		V(-791, 450, 148),
		V(-895, 395, 34),    -- the finish
		V(-800, 520, 250),
		V(-590, 600, 380),   -- the last point: where it charges the fireball
	},
	EST_FROM  = V(-300, 360, -130),   -- the opening shot
	EST_TO    = V(-292, 335, -80),
	EST_LOOK  = V(-430, 150, 520),
	RISE_EYE  = V(-230, 235, 290),    -- watching it rise out of the pool
	RISE_EYE2 = V(-250, 320, 290),
	WIDE_EYE  = V(-250, 520, 90),     -- the wide shot of the fireball and the blast
	WIDE_BACK = V(-220, 600, -60),
}

---------------------------------------------------------------- BLACK HOLE - KILL ALL (map spots)
-- (ReplicatedStorage.TrollFx.BlackHoleAllTimeline: the timings and sizes stay there)
-- It hangs high over the middle of the map, above everything on it (the tallest things near
-- it - the balloons, the Ice Atlas statue - top out under 480), so the whole course is under it.
WorldConfig.BlackHoleAll = {
	CENTER      = V(-440, 580, 520),   -- the black hole's middle
	GROUND_ZERO = V(-440, 185, 520),   -- the middle of the map under it (where the debris is torn up from)
	EST_FROM    = V(-300, 360, -130),  -- the opening shot of the whole map: from ...
	EST_TO      = V(-292, 335, -80),   -- ... pushing in to ...
	EST_LOOK    = V(-420, 240, 520),   -- ... looking at (tilting up to the black hole as it forms)
	PULL_EYE    = V(-300, 700, 60),    -- the wide shot of the pull, a little above it (it drifts in from here)
	PULL_BACK   = V(-250, 760, -90),   -- where that camera is thrown back to after the implosion
}

return WorldConfig
