-- Tunables for the two-player electric scooter.
return {
	CountdownSeconds     = 3,

	DriverRole           = "Driver",
	PassengerRole        = "Passenger",
	CheckpointPickerRole = "Driver",

	-- The Driver's checkpoint window in the booth (ReplicatedStorage.CheckpointSelector).
	-- true: once both booths are filled the Driver picks the start and presses START,
	-- then the 3, 2, 1 (the Passenger sees "Driver is choosing.." meanwhile).
	-- false: the 3, 2, 1 starts as soon as both booths are filled, from the first open
	-- checkpoint in Shared.Checkpoints.
	CheckpointPicker     = true,
	-- If the Driver hasn't pressed START this many seconds after the window opened, both
	-- players are quietly sent back to the lobby spawn (no countdown, no message).
	PickTimeoutSeconds   = 120,

	-- Where a checkpoint with no SpawnPartName or bays starts: an invisible marker
	-- (under Workspace.RideSystem.StartLocations, or anywhere in Workspace) whose
	-- ScooterSpawn attachment sits on the ground; it faces the way rides set off.
	-- This one is Bay 1 of the Checkpoint 1 Parking Lot, and moves with the lot.
	FallbackStartPlate   = "Checkpoint1_Bay1",

	-- Distance from the Chassis origin down to the bottom of the wheels. Measured
	-- from the built model (1.279), not guessed, so the scooter rests on the plate.
	ScooterLift          = 1.28,
	CharacterLift        = 3.5,

	-- Steering. The lock eases off with speed: the same fork angle turns the same
	-- circle at any speed, so a full 30 degrees at top speed would spin the scooter
	-- round a 9-stud circle at ~130 deg/s. Measured with both wheels on the ground.
	-- Tuned for snappier turns: at top speed ~79 deg/s round a ~15-stud circle, 90 deg in
	-- ~1.2 s (was 55 deg/s, ~22 studs, ~2 s). Past ~16 deg the tyres are at their grip limit
	-- at top speed, so more lock there only sharpens the turn-in.
	SteerAngleDeg        = 32,    -- full lock at low speed: tight obby turns
	SteerAngleAtSpeedDeg = 19,    -- lock at top speed
	SteerFullLockBelow   = 10,    -- studs/s: full lock up to here...
	SteerEasedAbove      = 20,    -- studs/s: ...easing linearly to SteerAngleAtSpeedDeg here
	SteerRampSeconds     = 0.1,   -- seconds for the fork to swing from straight to full lock
	                              -- (A and D are on/off keys; see Shared.Steering)

	-- Spin on the spot (ServerScriptService.ScooterSystem.SpinInPlace): standing still
	-- with A/D held, the scooter turns round where it is. false = off, exactly as before.
	SpinInPlace          = false,
	SpinInPlaceRate      = 2.2,   -- rad/s (~125 deg/s: a full turn in about 3 s)
	SpinInPlaceBelow     = 1.5,   -- studs/s: slower than this along its nose counts as standing still

	-- Electric motor. Throttle is a RAMPED target speed, not a torque switch:
	-- measured on this build, commanding zero velocity with any real torque locks
	-- the wheel dead in under half a second, while zero torque barely decays at
	-- all. Releasing GO therefore has to bleed the target down gradually.
	MaxAngularVelocity   = 26,    -- ~20.8 studs/s at this wheel radius
	AccelRate            = 18,    -- rad/s per second while GO is held
	CoastRate            = 7,     -- rad/s per second once GO is released
	BrakeRate            = 22,    -- rad/s per second while Space brakes, or when slowing against
	                              -- the current direction. From top speed: ~1.2 s, ~12 studs

	-- Reverse (rear rider holds S). Slower than forward, like a real e-scooter.
	MaxReverseAngularVelocity = 14,   -- ~11.3 studs/s
	ReverseAccelRate          = 12,   -- rad/s per second while S is held and already rolling back

	-- Rolling downhill with nothing pressed (coasting). Stopped on a hill, the scooter
	-- creeps down it: gently, faster on steeper hills, never faster than the cap. Holding
	-- Space (brake) still holds it still. Flatter than RollMinSlopeDeg it stays put.
	RollPerSlopeDeg  = 0.3,   -- rad/s of roll per degree of slope: 15 deg ~3.6 studs/s
	RollMaxAngularVelocity = 8,   -- ~6.4 studs/s, however steep
	RollAccelRate    = 4,     -- rad/s per second: about a second to reach that speed
	RollMinSlopeDeg  = 3,

	-- Death popup (ServerScriptService.ScooterSystem.DeathManager, StarterGui.DeathGui)
	DeathSeconds         = 10,    -- how long the SKIP / REVIVE popup counts down
	-- REVIVE: this Developer Product (29 Robux), bought for the pair on the popup. The server
	-- prompts it and revives on Roblox's receipt (DeathManager); 0 = off, REVIVE only shakes.
	ReviveProductId      = 3715224310,
	RevengeProductId     = 3716866689,
	-- the two offers under the popup's box (a death with no revenge; DeathManager, DeathClient)
	ReviveFiveProductId     = 3717073493,   -- 5x REVIVES: the ride revived now + 4 saved revives
	ReviveInfiniteProductId = 3717073564,   -- INFINITE REVIVES: REVIVE free for good (saved)
	ReviveFiveImage         = "rbxassetid://83940025562974",   -- (decal 72704365623975)
	ReviveInfiniteImage     = "rbxassetid://96232270209394",   -- (decal 77594468000975)
	-- each picture cropped to a square round its artwork (x, y, size, in the image's pixels),
	-- so the hearts sit in the middle of their tiles (the uploads have them off-centre)
	ReviveFiveImageRect     = { 27, 32, 427 },
	ReviveInfiniteImageRect = { 38, 16, 446 },   -- "Get Revenge!": EXPLODE BACK (REVENGE) on the death popup (TrollEffects)
	-- the countdown waits while a rider has the purchase open, but never longer than this
	ReviveHoldSeconds    = 45,

	-- Skip Stage (ServerScriptService.ScooterSystem.SkipStage, StarterGui.SkipStageGui): the
	-- Developer Product that moves a ride on to its next checkpoint (or, from the last one, to
	-- just before the finish line). 0 = not set up yet: the button stays hidden.
	SkipStageProductId   = 3715226646,

	-- NUKE ALL (the Nuke Podium on the lobby's podium shop base; ServerScriptService.ScooterSystem.
	-- NukeAll): its Developer Product. 0 = not set up yet: pressing E only says it's coming soon.
	NukeAllProductId     = 3715386186,
	-- LAVA DRAGON (the Lava Dragon Podium, next to the Nuke Podium; ServerScriptService.ScooterSystem.
	-- LavaDragon): its Developer Product. 0 = not set up yet: pressing E only says it's coming soon.
	LavaDragonProductId  = 3715397770,
	-- BLACK HOLE - KILL ALL (the Black Hole Podium, next to the Nuke Podium; ServerScriptService.
	-- ScooterSystem.BlackHoleAll): its Developer Product. 0 = not set up yet: pressing E only says
	-- it's coming soon. (Not the troll menu's Black Hole, TrollProducts.BlackHole.)
	BlackHoleAllProductId = 3716892781,

	-- OVERSIZED ACCESSORIES (ServerScriptService.ScooterSystem.OversizedAccessories): while a
	-- player rides, an accessory past these limits is hidden (only for the ride - never saved,
	-- never their Roblox avatar) and comes back when they get off. Studs, for a normal-size
	-- avatar; both scale with the avatar's own BodyHeightScale. Normal hats and hair measure
	-- ~2 studs long and reach ~3 studs from the body's centre.
	OversizedAccessories = {
		Enabled          = true,
		HideOversized    = false, -- true = make oversized accessories invisible for the ride; false = keep
		                          -- them visible (they still can't collide or touch hazards either way)
		MaxSize          = 4.5,   -- the accessory's longest side (a long back sword/staff is ~4)
		MaxReach         = 4.5,   -- how far its furthest point sticks out from the HumanoidRootPart
		LayeredAllowance = 1.5,   -- layered clothing wraps the whole body: it gets this much more room
	},

	-- Troll effects (the Troll window; ServerScriptService.ScooterSystem.TrollEffects): each one's
	-- Developer Product, by its Id in ReplicatedStorage.TrollFx.Effects. 0 = not set up yet: its
	-- button stays hidden.
	TrollProducts        = {
		Rocket = 3715267801,   -- ROCKET LAUNCH
		Explode = 3715287709,   -- EXPLODE PLAYERS
		Freeze  = 3715369836,   -- FREEZE PLAYERS
		Ufo     = 3715373756,   -- UFO ABDUCTION
		Slap    = 3715375057,   -- GIANT SLAP
		BlackHole = 3715378499, -- BLACK HOLE
	},

	DebugLogging         = true,
}
