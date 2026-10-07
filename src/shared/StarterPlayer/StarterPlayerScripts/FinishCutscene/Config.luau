--=====================================================================
-- FinishCutscene / Config
--
-- Every setting of the finish-line victory cinematic, in one place. Times are seconds,
-- distances studs. The scene's clock starts (t = 0) the moment it appears out of the
-- first fade; every time below is on that clock.
--=====================================================================

return {
	--------------------------------------------------------------- the finish line
	-- A finish line is any part with this CollectionService tag. Its LookVector points the
	-- way riders cross it (they come from its back); Size.X is the line's width, Size.Y the
	-- height it counts over. The course's is Workspace["Finish Area"].FinishGate.Gate: an
	-- invisible slab on the painted line, in a Persistent model so every player's game
	-- always has it. Move or resize it to move the line; tag another part for another one.
	FinishTag = "FinishLine",

	--------------------------------------------------------------- timing
	Duration     = 5.0,    -- the cinematic, from appearing to gone
	FadeOut      = 0.25,   -- gameplay -> black, the moment the line is crossed
	FadeIn       = 0.35,   -- black -> the cinematic (the start of Duration)
	EndFadeOut   = 0.35,   -- the cinematic -> black (the end of Duration)
	ReturnFadeIn = 0.4,    -- black -> gameplay, once everything is back
	Letterbox    = 0.075,  -- the black bars top and bottom while it plays: at most this share of the screen's height each (0 = none); Fade only crops to a 2:1 frame, so wide phones get none and 16:9 slim ones

	--------------------------------------------------------------- the drive
	-- The scene starts StartBehind before the line, on the stretch of road the scooter
	-- really came in on, and rolls across at these speeds (studs/s at times; gameplay tops
	-- out near 21). With the values below it travels about 19 studs, reaching the line at
	-- about 2.9 s and ending about 7 past it; the line time follows from these by itself.
	StartBehind = 12,
	Speed = {
		{ 0.0, 3.4 },
		{ 1.5, 4.2 },
		{ 3.0, 4.6 },
		{ 4.2, 3.2 },
		{ 5.0, 1.8 },
	},
	LaneClamp = 3,   -- past the line it drifts toward the middle of the finish, ending at most this far off it

	--------------------------------------------------------------- camera
	-- Shots in the scooter's own (level) frame: x to its right, y up from the chassis, z
	-- BEHIND it (+z behind, -z ahead). pos = where the camera is, look = the point it looks
	-- at, fov = the lens (degrees). The camera glides through them, smooth in position and
	-- in speed. CameraSide 1 swings it round the scooter's right, -1 round its left; it
	-- takes the other side by itself if the world is in the way of the chosen one.
	Camera = {
		{ t = 0.00, pos = Vector3.new(4.4, 8.2, 10.4),  look = Vector3.new(0, 1.8, -3.2), fov = 54 },  -- behind, above and to the side: both riders' backs, the scooter, the road and the line ahead
		{ t = 1.50, pos = Vector3.new(3.8, 7.4, 9.2),   look = Vector3.new(0, 2.0, -3.6), fov = 53 },  -- ...easing in while the driver cheers
		{ t = 2.35, pos = Vector3.new(8.0, 4.8, 4.6),   look = Vector3.new(0, 2.4, -1.2), fov = 52 },  -- swinging round the side (inside the arch's pillars)
		{ t = 3.15, pos = Vector3.new(7.4, 4.2, -9.0),  look = Vector3.new(0, 2.5, -0.2), fov = 50 },  -- front three-quarter as they cross
		{ t = 4.20, pos = Vector3.new(6.4, 4.4, -11.0), look = Vector3.new(0, 2.6, -0.4), fov = 51 },
		{ t = 5.00, pos = Vector3.new(5.8, 4.9, -12.0), look = Vector3.new(0, 2.8, -0.6), fov = 52 },
	},
	CameraSide  = 1,
	CameraShake = 0.035,   -- a hint of hand-held drift (studs); 0 = rock steady
	CrossPunch  = 2.5,     -- the lens tightens this many degrees for a beat as they cross

	--------------------------------------------------------------- celebration
	-- The DRIVER throws both arms up and pumps both fists (harder for a moment at the line);
	-- with PassengerCheers the back rider keeps a hand on the driver and punches the other
	-- one up as they cross.
	-- By default this is a pose made with the riders' own ride IK: no animation asset is
	-- needed, it fits every avatar, and the feet stay planted on the deck. To use an
	-- animation for the driver instead, put its asset id here, e.g. "rbxassetid://123":
	--   * an R15 animation (R6 avatars keep the built-in pose)
	--   * owned by you / this game's group (or Roblox), or it won't play in this game
	--   * looping, and ideally arms and upper body only (the legs are held on the deck anyway)
	-- If it doesn't load, the built-in pose is used.
	CelebrationAnimationId = "",
	RaiseArmsAt     = 0.30,   -- when the driver's arms go up
	RaiseArmsTime   = 0.45,   -- ...taking this long, with a little overshoot
	FistPumpRate    = 1.7,    -- fist pumps a second
	FistPumpSize    = 0.14,   -- how far the fists pump (studs)
	PassengerCheers = true,

	--------------------------------------------------------------- confetti
	Confetti = {
		Colors = {
			Color3.fromRGB(255, 94, 170), Color3.fromRGB(255, 212, 60), Color3.fromRGB(90, 205, 255),
			Color3.fromRGB(135, 232, 105), Color3.fromRGB(186, 128, 255), Color3.fromRGB(255, 150, 72),
			Color3.fromRGB(255, 255, 255),
		},
		Size = Vector3.new(0.3, 0.035, 0.2),   -- one piece of paper
		Pool = 150,                            -- the most pieces there ever are (made once, reused)
		-- falling round the riders: Rate pieces a second from ShowerFrom, RateAfter once they
		-- cross (for AfterFor seconds), then RateEnd
		ShowerFrom = 1.2, Rate = 7, RateAfter = 24, AfterFor = 1.6, RateEnd = 10,
		-- as they cross: a spray from each side of the finish arch (Burst pieces each, in three
		-- quick waves) and a pop of BurstTop above the riders
		Burst = 34, BurstTop = 18,
		ArchHalfWidth = 9.3, ArchHeight = 0.5,   -- where the sprays start: this far either side of the gate's middle, this far above it
		Gravity = 16, Drag = 3.2,                -- they drift down at about Gravity / Drag studs a second
		Life = { 2.6, 3.8 },                     -- seconds a piece stays in the air (on the ground it stays)
	},

	--------------------------------------------------------------- sounds
	-- Played on this machine only as they cross, in the SFX volume. Id "" or Volume 0 = off.
	Sounds = {
		Pop   = { Id = "rbxassetid://6335911565",    Volume = 0.45 },   -- a confetti popper
		Cheer = { Id = "rbxassetid://105154404054447", Volume = 0.3 },   -- a small crowd cheering and clapping
	},

	--------------------------------------------------------------- screen
	-- Roblox's own screens put away while it plays (any Enum.CoreGuiType names); the
	-- game's own HUD always is. Each comes back exactly as it was.
	HideCoreGui = { "PlayerList", "Backpack", "EmotesMenu" },

	--------------------------------------------------------------- safety
	Watchdog = 12,     -- if anything ever hangs, everything is put back this long after the finish at the latest
	Debug    = false,  -- print what it's doing
}
