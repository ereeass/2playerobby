-- FOOTSTEP SETTINGS
-- Change the numbers below to adjust the footsteps. Nothing else needs editing.
-- (Changes apply the next time you press Play / the next server.)

return {
	-- Overall footstep loudness.
	--   1    = about as loud as Roblox's default footsteps
	--   0.6  = subtle (current)
	--   0    = footsteps off
	Volume = 0.6,

	-- Balance between the three surfaces (1 = normal). Use these to make just one
	-- surface quieter or louder, e.g. Dirt = 0.8.
	SurfaceVolume = {
		Grass = 1,
		Dirt  = 1.25,
		Rock  = 1,
	},

	-- The sound for each surface. Each file is a recording of several steps and the
	-- script plays one step of it per footfall. (A different sound id here is played
	-- from its start instead, until its steps are measured.)
	Sounds = {
		Grass = 140375026362889,
		Dirt  = 120506599872820,
		Rock  = 98950681642146,
	},

	-- A tiny random change on every step so repeats never sound identical.
	-- 0.04 = +/-4% pitch, 0.08 = +/-8% volume. Keep these small.
	PitchVariation  = 0.04,
	VolumeVariation = 0.08,
}
