--=====================================================================
-- IntroCinematic / Config   *** WORLD 1 ONLY ***
--
-- Every setting of the intro cinematic, in one place. Times are seconds on the cinematic's
-- own clock (0 = its first frame, Duration = the frame the player's own camera takes over).
-- Positions are World 1 map coordinates.
--=====================================================================

local V = Vector3.new

return {
	--------------------------------------------------------------- where and when
	PlaceId  = 121371815815493,          -- World 1: the intro never plays in any other place
	Duration = 12.2,                      -- exactly: the hand-off happens on the frame the clock reaches this
	SeenKey  = "HasSeenIntroCutscene",   -- in the player's save (SettingsServer's PlayerData)
	AnswerWait = 3,                      -- first join: the blurred opening waits at most this much longer for "has this player seen it?"
	PrepareWait = 2,                     -- ...and for the intro's own models/sounds to be ready

	--------------------------------------------------------------- the look
	Letterbox = 0.075,   -- the black bars: the same share every other cutscene uses (FinishCutscene.Fade)
	BarsIn    = 0.35,
	BarsOutAt = 11.8,    -- ...and slide away over the last BarsOut seconds
	BarsOut   = 0.35,
	Face      = "rbxassetid://83577611508064",   -- the excited open-mouth grin (classic heads; moving heads pull the same face)

	--------------------------------------------------------------- cast
	-- The DRIVER is always the watching player's own avatar; the MOTOR is a classic bacon-hair
	-- avatar the server builds once (ServerScriptService.IntroCinematicServer).
	Bacon = {   -- the classic default bacon (all Roblox's own items)
		Hair  = 63690008,                              -- "Pal Hair"
		Shirt = 144076358,                             -- "Blue and Black Motorcycle Shirt"
		Pants = 144076760,                             -- "Dark Green Jeans"
		Skin  = Color3.fromRGB(242, 243, 243),         -- the pale default skin
		Face  = "rbxasset://textures/face.png",        -- the classic smile (built into Roblox)
	},

	--------------------------------------------------------------- scene 1: into the booths
	-- Both walk into their booth from outside (so a new player sees: get in a capsule), turn
	-- round to face out and stand there, feet on the floor.
	DriverBooth = "DriverCapsule",   -- RideSystem.CapsuleStations.<Station>.<this>
	MotorBooth  = "MotorCapsule",
	Station     = "Station1",
	BoothFacing = V(1, 0, 0),        -- the way the booths open (the characters face out)
	WalkIn = { From = 0.3, To = 1.9, Turn = 0.35, Distance = 6.5 },   -- walk this many studs in, then turn round
	BoothCam = {                      -- camera glides between these: wide on the booths, easing in
		{ t = 0.00, pos = V(-152.5, 222.4, 264.4), look = V(-170, 218.6, 264.6), fov = 60 },
		{ t = 3.80, pos = V(-161.2, 220.1, 265.3), look = V(-171, 218.5, 264.6), fov = 55 },
	},

	--------------------------------------------------------------- scene 2: leaving the lot
	-- The scooter pulls out of Bay 3 of Checkpoint 1's lot, merges to the middle of the road at
	-- the start gate and follows Road1's centre line (IntroCinematic.RidePath).
	RideStart = V(-144.2, 0, 316.3),   -- Bay 3 (height found from the ground)
	RideVia   = { V(-144.2, 0, 328) },  -- straight out of the bay first (clear of the lot's centre median)
	RideDir   = V(0, 0, 1),
	RideGo    = 3.78,                -- when it pulls away
	RideDistance = function(t)       -- studs travelled t seconds after RideGo (gentle, then away down Road1)
		return 75 * (t / 3.57) ^ 1.7
	end,
	-- camera in the scooter's own frame (x its right, y up, -z ahead): close on its left side
	-- (the open side of the lot), pulling out and back as it leaves...
	RideCam = {
		{ t = 3.78, pos = V(-8.5, 3.4, -1.6), look = V(0, 2.6, -0.2), fov = 58 },
		{ t = 5.60, pos = V(-13, 6.5, 7.5), look = V(0, 2.0, -9.0), fov = 64 },
	},
	RideHold = 5.60,   -- ...then it stops following and watches the scooter drive away, honking
	Whip = { From = 3.70, To = 3.94, Blur = 16, Lift = 26 },   -- booth -> scooter: a fast swish pan, arcing up this high
	FlightStart = 7.35,                                        -- the scooter shot hands over to the flight here

	--------------------------------------------------------------- scenes 3-6: one continuous flight
	-- world positions; the flight starts where the scooter shot ends (FlightStart) and lands
	-- exactly on the player's own gameplay camera at Duration
	Flight = {
		{ t = 7.70, pos = V(-205, 258, 410), look = V(-300, 222, 430), fov = 76 },   -- up over Road 2's laser gates
		{ t = 8.05, pos = V(-320, 268, 505), look = V(-370, 215, 610), fov = 78 },   -- beach lot, Rotten Bridge, the lighthouse
		{ t = 8.40, pos = V(-340, 300, 650), look = V(-430, 240, 830), fov = 78 },   -- mesas and the Shiba Sphinx
		{ t = 8.75, pos = V(-470, 290, 870), look = V(-610, 260, 800), fov = 76 },   -- snow lot, Atlas ahead
		{ t = 9.05, pos = V(-525, 305, 720), look = V(-590, 318, 620), fov = 70 },   -- swinging round to his face
		{ t = 9.30, pos = V(-547, 311, 627), look = V(-587, 314, 611), fov = 64 },   -- face to face
		{ t = 9.50, pos = V(-550, 311, 626), look = V(-587, 312.5, 611), fov = 62 },   -- THE SCREAM
		{ t = 9.85, pos = V(-556, 312.5, 624), look = V(-587, 313, 611), fov = 68 },   -- blown back a little
		{ t = 10.20, pos = V(-557, 316, 623), look = V(-574, 312, 600), fov = 70 },   -- his head whips round: follow his look
		{ t = 10.75, pos = V(-500, 318, 560), look = V(-300, 250, 380), fov = 78 },   -- ...off toward the lobby
		{ t = 11.60, pos = V(-215, 248, 190), look = nil, fov = 74 },                  -- past the lobby, swinging in behind the player (look = the player)
		-- then just behind the player and Duration (the gameplay camera) are added in code
	},
	Shake = { From = 9.40, Peak = 9.46, To = 9.90, Degrees = 1.6, Studs = 0.7 },

	--------------------------------------------------------------- Atlas
	Atlas = {
		RearBackAt = 9.28, ScreamAt = 9.42, ScreamEnd = 9.85, TurnAt = 9.85, TurnEnd = 10.20,
		RearBack   = 10,    -- degrees his head tips back before the scream
		JawOpen    = 38,    -- degrees the jaw drops open
		JawDrop    = 3.2,   -- studs it also slides down
		ShakeDeg   = 6,     -- head shake while screaming
		Lobby      = V(-153.7, 212, 225),   -- where he turns to look (the spawn)
		EyeGrow    = 1.2,
		Mouth      = "rbxassetid://116840044578949",   -- the scream mouth (stretches open on his face)
		MouthSize  = Vector3.new(12, 13, 0),            -- studs wide / tall at full scream
		MouthBelow = 9,                                  -- studs under the middle of his nose
		MouthOut   = 4.5,                                -- studs in front of his face
	},

	--------------------------------------------------------------- sound
	-- On this machine only. Id "" = off. The soundtrack follows the player's music volume, the
	-- rest their SFX volume. All from Roblox's licensed libraries (APM Music, Pro Sound Effects)
	-- or sounds the game already uses.
	Sounds = {
		Soundtrack = { Id = "rbxassetid://9043233916",   Volume = 0.5,  At = 0.00, Music = true },   -- "On The Double Funk" (APM Music): fast funk, brass stabs
		Scream     = { Id = "rbxassetid://9125652666",   Volume = 1.0,  At = 9.42, Speed = 0.72 },   -- a man's scream, pitched down: a GIANT screaming (Pro Sound Effects)
		ScreamRoar = { Id = "rbxassetid://9116296498",   Volume = 0.75, At = 9.42, Speed = 0.8 },    -- ...with a deep lion roar under it for the size (Pro Sound Effects)
		Ready      = { Id = "rbxassetid://4612374036",   Volume = 0.35, At = 2.25 },   -- the Invite button's success chime: both are in
		Whoosh1    = { Id = "rbxassetid://127438224839678", Volume = 0.55, At = 3.70 },
		Horn       = { Id = "rbxassetid://94706203403618",  Volume = 0.5,  At = 4.30, OnScooter = true },   -- the scooter's own horn, from the scooter
		Horn2      = { Id = "rbxassetid://94706203403618",  Volume = 0.6,  At = 6.10, OnScooter = true },   -- ...honking as it drives away (fades with distance)
		Horn3      = { Id = "rbxassetid://94706203403618",  Volume = 0.6,  At = 6.55, OnScooter = true },
		Whoosh2    = { Id = "rbxassetid://127438224839678", Volume = 0.5,  At = 7.32, Speed = 0.85 },
		Whoosh3    = { Id = "rbxassetid://127438224839678", Volume = 0.45, At = 8.30, Speed = 1.1 },
		Whoosh4    = { Id = "rbxassetid://127438224839678", Volume = 0.5,  At = 9.18, Speed = 0.8 },
		Bass       = { Id = "rbxassetid://9043176424",   Volume = 0.8,  At = 9.42 },   -- the nuke's bass hit
		Rumble     = { Id = "rbxassetid://9119388384",   Volume = 0.6,  At = 9.42 },
		Whoosh5    = { Id = "rbxassetid://127438224839678", Volume = 0.55, At = 10.00, Speed = 1.2 },
		Whoosh6    = { Id = "rbxassetid://127438224839678", Volume = 0.5,  At = 10.75, Speed = 0.9 },
	},
	SoundtrackFade = 0.8,   -- the soundtrack fades out over the last this many seconds
	Wind = { Id = "rbxassetid://15675021174", Volume = 0.45 },   -- the loading fly-down's wind, under the flight
	EngineRev = { From = 3.78, To = 7.4, Speed = { 0.9, 1.45 } },  -- the scooter's own MotorHum as it pulls away

	--------------------------------------------------------------- streaming
	-- asked for before it plays, so the far side of the course is there when the camera arrives
	StreamPoints = {
		V(-153, 215, 330), V(-300, 222, 440), V(-370, 215, 600), V(-280, 280, 670),
		V(-470, 240, 860), V(-600, 240, 800), V(-600, 310, 620), V(-360, 250, 420),
	},
	StreamWait = 2.5,

	--------------------------------------------------------------- screen
	HideCoreGui = { "PlayerList", "Backpack", "EmotesMenu" },
	TimeScale = 1,   -- testing only: 0.1 = ten times slower (always 1 in the game)
	TestFrom  = 0,   -- testing only: start this far in (always 0 in the game)
	Watchdog = 18,   -- if anything ever hangs, the player's camera comes back this long after it started
}
