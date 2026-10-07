-- ObstacleSfx: every World 2 obstacle's sound effect, one place. Each one is its own sound,
-- picked to match the obstacle. Plays from a part in the world, so it's 3D: nearby players hear
-- it, far ones don't. Works from server scripts (heard by everyone) and client Fx scripts alike.
--   ObstacleSfx.Play(name, part)   plays that obstacle's sound from `part` (made once, reused)
local M = {}

M.Sounds = {
	HeartHammer      = { id = 9120222027,     volume = 0.55, near = 12, far = 110 },  -- toy squeak on the slam
	StompBear        = { id = 9114036511,     volume = 0.7,  near = 14, far = 120 },  -- deep cartoon thump on landing
	CupidBow         = { id = 9113166206,     volume = 0.5,  near = 10, far = 90 },   -- arrow whooshing out
	Tentacle         = { id = 9126209045,     volume = 0.7,  near = 12, far = 110 },  -- wet slap on the road
	LavaCannon       = { id = 9114463219,     volume = 0.6,  near = 12, far = 110 },  -- fire whoosh as it shoots
	ShipCannon       = { id = 87901747080042, volume = 0.45, near = 14, far = 140 },  -- cannon boom
	Volcano          = { id = 9113220677,     volume = 0.9,  near = 30, far = 260 },  -- rumbling eruption
	Drawbridge       = { id = 9113763820,     volume = 0.6,  near = 12, far = 110 },  -- chains rattling
	ChocolateBoulder = { id = 9118661726,     volume = 0.55, near = 14, far = 140 },  -- boulder tumbling down
	ChemicalBall     = { id = 9112752570,     volume = 0.5,  near = 10, far = 100, looped = true },  -- bubbling potion ball
	AnchorChain      = { id = 9113760230,     volume = 0.4,  near = 10, far = 90 },   -- anchor chain clinking
	LavaMonsterRoar  = { id = 9113980319,     volume = 0.35, near = 14, far = 130 },  -- the lava monster's roar (kept low and local)
	FireballSplash   = { id = 9119482204,     volume = 0.6,  near = 15, far = 160 },  -- its fireball hitting the sea
	LavaSplash       = { id = 9116324604,     volume = 0.7,  near = 20, far = 200 },  -- lava bursting up out of the sea
}

function M.Get(name, part)
	local def = M.Sounds[name]
	if not (def and part) then return nil end
	local s = part:FindFirstChild("Sfx_" .. name)
	if not s then
		s = Instance.new("Sound")
		s.Name = "Sfx_" .. name
		s.SoundId = "rbxassetid://" .. def.id
		s.Volume = def.volume
		s.Looped = def.looped == true
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = def.near
		s.RollOffMaxDistance = def.far
		s.Parent = part
	end
	return s
end

function M.Play(name, part)
	local s = M.Get(name, part)
	if s then s.TimePosition = 0; s:Play() end
	return s
end

return M
