-- AREA MUSIC SETTINGS
-- While a pair is riding, each area's own track plays for them (quietly, looped) instead of
-- the lobby playlist; back in the lobby the playlist carries on. Played on each rider's own
-- machine only (StarterPlayerScripts.AreaMusic), and it follows their Music Volume setting.
--
-- Enabled = false switches area music off completely: everything is exactly as it was before
-- it existed (the lobby playlist plays all the time, as always).

return {
	Enabled = true,

	-- how loud (the lobby playlist is 0.125), and how long a change of track takes to fade (s)
	Volume = 0.12,
	Fade   = 2,       -- between two areas' tracks
	FadeIn = 0.4,     -- from the lobby playlist: in almost at once

	-- the area that starts at each checkpoint (its Order in Shared.Checkpoints): each world's
	-- own tracks, in ReplicatedStorage.WorldConfig.AreaMusic. Start / End (seconds) trim
	-- silence off the ends of the file: the track plays from Start, and loops from End
	-- straight back to Start (measured from each file).
	Tracks = require(game:GetService("ReplicatedStorage"):WaitForChild("WorldConfig")).AreaMusic or {},
}
