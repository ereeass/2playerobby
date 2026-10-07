-- Quiet, positional animal sounds for the client-side critters (FoodLotPigeons, Seagulls,
-- JungleMonkeys, SnowPenguins). Each call plays one short sound from the critter's own
-- part, so it moves with the animal and fades with distance; nothing loops. They land in
-- the SFX volume slider like every other sound (SettingsController).
--
--   CritterSounds.Play(part, kind, volume?)   one sound of that kind from `part`
--   CritterSounds.Timer(min, max)             a countdown that fires every min..max s

local CritterSounds = {}

-- clip: longer recordings play a random slice this long, faded in and out
CritterSounds.Kinds = {
	PigeonCoo  = { ids = { 7616212411, 6988256442 }, volume = 0.12, clip = 2.2, speed = { 0.92, 1.08 } },
	PigeonFlap = { ids = { 9113444620, 9113444792 }, volume = 0.2, speed = { 0.95, 1.1 } },
	GullCry    = { ids = { 9118858259, 9118858265, 9118858279, 134235552168300 }, volume = 0.13, clip = 2.4, speed = { 0.94, 1.06 } },
	GullFlap   = { ids = { 9113444620 }, volume = 0.14, speed = { 0.8, 0.9 } },
	Monkey     = { ids = { 9113788931, 9113789256, 9113790054 }, volume = 0.1, clip = 2.0, speed = { 0.95, 1.12 } },
	Penguin    = { ids = { 70370050532637 }, volume = 0.1, clip = 1.8, speed = { 0.95, 1.1 } },
}

local HEAR_FULL = 10    -- studs: full (already quiet) volume inside this
local HEAR_MAX  = 70    -- studs: silent beyond this
local FADE      = 0.25  -- seconds of fade at each end of a clipped slice

function CritterSounds.Play(part, kind, volume)
	local k = CritterSounds.Kinds[kind]
	if not (k and part and part.Parent) then return end
	local id = k.ids[math.random(#k.ids)]
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance, s.RollOffMaxDistance = HEAR_FULL, HEAR_MAX
	s.PlaybackSpeed = k.speed[1] + math.random() * (k.speed[2] - k.speed[1])
	s:SetAttribute("AudioCategory", "SFX")
	local target = (volume or k.volume) * (0.8 + math.random() * 0.3)
	s.Volume = k.clip and 0 or target
	s.Parent = part

	task.spawn(function()
		local t = os.clock()
		while not s.IsLoaded and s.Parent and os.clock() - t < 5 do task.wait(0.1) end
		if not (s.Parent and s.IsLoaded) then s:Destroy() return end
		local len = s.TimeLength
		local play = len
		if k.clip and len > k.clip + 0.2 then
			s.TimePosition = math.random() * (len - k.clip)
			play = k.clip
		end
		s:Play()
		local real = play / s.PlaybackSpeed
		if k.clip then
			-- fade the slice in and out so it never clicks
			local t0 = os.clock()
			while s.Parent and os.clock() - t0 < real do
				local e = os.clock() - t0
				s.Volume = target * math.min(1, e / FADE, (real - e) / FADE)
				task.wait()
			end
		else
			task.wait(real)
		end
		if s.Parent then s:Destroy() end
	end)
end

-- ticks down; :Due(dt) is true once every min..max seconds
function CritterSounds.Timer(min, max)
	local t = { left = min + math.random() * (max - min) }
	function t:Due(dt)
		self.left -= dt
		if self.left > 0 then return false end
		self.left = min + math.random() * (max - min)
		return true
	end
	return t
end

return CritterSounds
