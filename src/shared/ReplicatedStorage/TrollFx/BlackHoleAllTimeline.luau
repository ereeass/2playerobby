--=====================================================================
-- BlackHoleAllTimeline   (ReplicatedStorage.TrollFx)
--
-- BLACK HOLE - KILL ALL second by second: one clock for the server (ScooterSystem.BlackHoleAll,
-- through NukeAll's shared global show: when every ride goes down, when the lobby goes down)
-- and for every player's cinematic (StarterGui.BlackHoleAllGui.BlackHoleAllCinematic). Times
-- are seconds from the server's start time. Every timing, shot and size is one of the
-- constants below. Nothing here moves anything - it only says where things are at time t.
-- (It has LEAD, EXPLODE and END like the trolls' clocks, so ScooterSystem.TrollShow plays it
-- on each ride.) Not the troll menu's BLACK HOLE (BlackHoleTimeline), which swallows one duo.
--
--   0 .. EST_END         the whole map; the sky darkens, a purple tear opens high over it (FORM_AT)
--   (a quick cut through black)
--   EST_END .. PULL_AT   close up: the black hole forms - its black core, the glowing disc
--                        spinning up round it, sparks streaming in
--   PULL_AT .. COLLAPSE  the wide shot: everything is pulled in - chunks of the map torn up and
--                        spiralling into it, jets of light out of its poles, the camera dragged
--                        towards it
--   COLLAPSE .. IMPLODE  it caves in on itself, spinning faster and faster (HUSH: dead silence)
--   IMPLODE (= EXPLODE)  a flash, a burst of light and a ring racing out over the whole map
--                        (every scooter out on the course is gone in it)
--   END                  it's over: the rides go down (death popup), the lobby goes down
--                        (respawn), everyone's screen comes back
--=====================================================================

local T = {}

-- this world's map spots (ReplicatedStorage.WorldConfig.BlackHoleAll): where it hangs and where
-- the camera stands. Everything else here (timings, sizes) is the same in every world.
local MAP = require(game:GetService("ReplicatedStorage"):WaitForChild("WorldConfig")).BlackHoleAll or {}

---------------------------------------------------------------- timing
T.LEAD     = 0.8     -- the server starts the clock this far ahead, so every player has it
T.FORM_AT  = 1.4     -- the tear opens over the map
T.EST_END  = 3.4     -- the establishing shot ends (cut through black)
T.CUT      = 0.3     -- the cut's fade, each way
T.GROWN    = 6.4     -- it's fully formed
T.PULL_AT  = 7.0     -- the wide shot: everything starts being pulled in
T.JETS_ON  = 7.6     -- the jets of light out of its poles
T.COLLAPSE = 11.6    -- it caves in on itself ...
T.HUSH     = 11.9    -- ... everything cuts to silence ...
T.IMPLODE  = 12.6    -- ... and it's gone: the burst
T.EXPLODE  = T.IMPLODE
T.END      = 17.0    -- it's over
T.END_FADE = 0.6     -- the fade to black before the screen comes back
T.BLEND    = 0.6     -- seconds each shot blends into the next (except the cut)

---------------------------------------------------------------- the map
T.CENTER      = MAP.CENTER or Vector3.new(-440, 580, 520)
T.GROUND_ZERO = MAP.GROUND_ZERO or (T.CENTER - Vector3.new(0, 395, 0))
T.EST_FROM    = MAP.EST_FROM or (T.CENTER + Vector3.new(140, -220, -650))
T.EST_TO      = MAP.EST_TO or (T.EST_FROM + Vector3.new(8, -25, 50))
T.EST_LOOK    = MAP.EST_LOOK or (T.GROUND_ZERO + Vector3.new(20, 55, 0))
T.PULL_EYE    = MAP.PULL_EYE or (T.CENTER + Vector3.new(140, 120, -460))
T.PULL_BACK   = MAP.PULL_BACK or (T.PULL_EYE + Vector3.new(50, 60, -150))
-- the side it's seen from (the lobby's), flat
local toEye = (T.EST_FROM - T.CENTER) * Vector3.new(1, 0, 1)
T.FACE = toEye.Magnitude > 1 and toEye.Unit or Vector3.new(0, 0, -1)

---------------------------------------------------------------- sizes (studs)
T.CORE  = 70         -- the black core's radius, fully formed
T.HALO  = 1.32       -- the shimmering halo bent round it, x the core
-- the accretion disc: glowing rings round the core, x the core's radius (R) and studs wide (W)
T.RINGS = {
	{ R = 1.45, W = 30 },
	{ R = 1.95, W = 46 },
	{ R = 2.6,  W = 60 },
	{ R = 3.4,  W = 84 },
}
T.TILT      = math.rad(28)    -- the disc tips this far towards the camera (the disc lies flat: tipped, it's seen as a ring)
T.SPIN      = { 0.35, 1.5, 7 } -- the disc's spin (radians a second): forming, the pull, the collapse
T.JET       = 650             -- each jet's length out of its pole
T.DEBRIS    = 60              -- chunks of the map torn up and pulled in
T.DEBRIS_R  = { 120, 620 }    -- how far out from the middle they're torn from
T.INRUSH    = 900             -- the ring of light rushing in as it collapses: its radius at the start
T.BURST     = 230             -- the burst of light's radius at its biggest
T.RING_OUT  = 1100            -- the ring racing out over the map

local function clamp01(x) return math.clamp(x, 0, 1) end
local function smooth(x) x = clamp01(x); return x * x * (3 - 2 * x) end
local function smoother(x) x = clamp01(x); return x * x * x * (x * (x * 6 - 15) + 10) end
T.Smooth, T.Smoother, T.Clamp01 = smooth, smoother, clamp01

---------------------------------------------------------------- the black hole at time t
-- the disc's tilt: its pole tips towards the camera's side
T.DISC = CFrame.new(T.CENTER) * CFrame.fromAxisAngle(T.FACE:Cross(Vector3.yAxis).Unit, -T.TILT)

-- 0 .. 1 of the collapse
function T.Collapse(t)
	return clamp01((t - T.COLLAPSE) / (T.IMPLODE - T.COLLAPSE))
end

-- 0 .. 1: how big it is (the core and the disc grow together; the disc goes first in the collapse)
function T.Grow(t)
	if t < T.FORM_AT or t >= T.IMPLODE then return 0, 0 end
	local g
	if t < T.EST_END then
		g = 0.35 * smooth((t - T.FORM_AT) / (T.EST_END - T.FORM_AT))
	else
		g = 0.35 + 0.65 * smoother((t - T.EST_END) / (T.GROWN - T.EST_END))
	end
	-- breathing as it feeds
	if t > T.PULL_AT then g = g * (1 + 0.04 * math.sin((t - T.PULL_AT) * 5) * clamp01((t - T.PULL_AT) / 1.5)) end
	local c = T.Collapse(t)
	return g * (1 - c * c * c), g * (1 - smooth(c))   -- core, disc
end

-- radians a second the disc turns
function T.SpinSpeed(t)
	if t < T.PULL_AT then return T.SPIN[1] + (T.SPIN[2] - T.SPIN[1]) * smooth((t - T.EST_END) / (T.PULL_AT - T.EST_END)) end
	if t < T.COLLAPSE then return T.SPIN[2] end
	return T.SPIN[2] + (T.SPIN[3] - T.SPIN[2]) * T.Collapse(t)
end

-- 0 .. 1: the jets out of its poles
function T.Jets(t)
	return smooth((t - T.JETS_ON) / 0.6) * (1 - smooth((t - T.COLLAPSE) / 0.5))
end

-- 0 .. 1: the world darkening round it (and lifting again after)
function T.Dark(t)
	if t < T.IMPLODE then
		return 0.55 * smooth(t / T.EST_END) + 0.45 * smooth((t - T.EST_END) / (T.PULL_AT - T.EST_END))
	end
	return 1 - 0.7 * smooth((t - T.IMPLODE) / 2.5)
end

-- a chunk of the map torn up and pulled in: same on every machine (no randomness)
local function hash(i, k) return (math.sin(i * 12.9898 + k * 78.233) * 43758.5453) % 1 end
local DEBRIS_FIRST = T.PULL_AT + 0.2
local DEBRIS_LAST  = T.COLLAPSE - 1.6
-- where chunk i is at time t, how big it is (0 .. 1) and its spin; nil when it isn't out
function T.Debris(i, t)
	local go = DEBRIS_FIRST + (DEBRIS_LAST - DEBRIS_FIRST) * hash(i, 1)
	local dur = 1.7 + 1.0 * hash(i, 2)
	local u = (t - go) / dur
	if u < 0 or u >= 1 or t >= T.IMPLODE then return nil end
	local a0 = i * 2.39996 + hash(i, 3)
	local r0 = T.DEBRIS_R[1] + (T.DEBRIS_R[2] - T.DEBRIS_R[1]) * math.sqrt(hash(i, 4))
	local a = a0 + u * u * 4.5                    -- spiralling in, faster and faster
	local r = r0 * (1 - u ^ 1.6)
	local y = T.GROUND_ZERO.Y + (T.CENTER.Y - T.GROUND_ZERO.Y) * (1 - (1 - u) ^ 2)
	local pos = Vector3.new(T.CENTER.X + math.cos(a) * r, y, T.CENTER.Z + math.sin(a) * r)
	local size = (1 - u ^ 3) * smooth(u / 0.08)
	return pos, size, CFrame.Angles(u * 7 + a0, u * 5, u * 3)
end
function T.DebrisSize(i) return 16 + 26 * hash(i, 5) end

---------------------------------------------------------------- the camera
local function shotEst(t)
	local k = smoother(t / T.EST_END)
	local look = T.EST_LOOK:Lerp(T.CENTER, 0.2 + 0.4 * smooth((t - T.FORM_AT) / (T.EST_END - T.FORM_AT)))
	return CFrame.lookAt(T.EST_FROM:Lerp(T.EST_TO, k), look), 70
end
local function shotForm(t)
	-- circling it from the lobby's side, a little above the disc, pushing in
	local k = smoother((t - T.EST_END) / (T.PULL_AT - T.EST_END))
	local dir = CFrame.Angles(0, math.rad(-25 + 45 * k), 0):VectorToWorldSpace(T.FACE)
	local eye = T.CENTER + dir * (560 - 130 * k) + Vector3.new(0, 170 - 40 * k, 0)
	return CFrame.lookAt(eye, T.CENTER - Vector3.new(0, 20, 0)), 60
end
local function pullEye(t)
	local k = smooth((t - T.PULL_AT) / (T.IMPLODE - T.PULL_AT))
	return T.PULL_EYE:Lerp(T.CENTER, 0.3 * k ^ 1.5), k
end
local function shotPull(t)
	-- the wide shot, the map below: dragged in towards it, the view stretching wider
	local eye, k = pullEye(t)
	return CFrame.lookAt(eye, T.CENTER:Lerp(T.GROUND_ZERO, 0.22)), 70 + 14 * k
end
local function shotAfter(t)
	-- thrown back by the burst
	local s = t - T.IMPLODE
	local eye = pullEye(T.IMPLODE):Lerp(T.PULL_BACK, 1 - (1 - clamp01(s / 3)) ^ 3)
	local punch = 14 * (1 - smooth(s / 0.9))
	return CFrame.lookAt(eye, T.CENTER:Lerp(T.GROUND_ZERO, 0.3)), 84 - 12 * smooth(s / 2) + punch
end

local SHOTS = {
	{ 0,         shotEst },
	{ T.EST_END, shotForm, cut = true },
	{ T.PULL_AT, shotPull },
	{ T.IMPLODE, shotAfter },
}

-- the camera at time t: its CFrame and field of view (each shot blends into the next)
function T.Camera(t)
	local i = 1
	for n = #SHOTS, 1, -1 do
		if t >= SHOTS[n][1] then i = n break end
	end
	local cf, fov = SHOTS[i][2](t)
	local since = t - SHOTS[i][1]
	if i > 1 and not SHOTS[i].cut and since < T.BLEND then
		local pcf, pfov = SHOTS[i - 1][2](t)
		local k = smoother(since / T.BLEND)
		cf = pcf:Lerp(cf, k)
		fov = pfov + (fov - pfov) * k
	end
	return cf, fov
end

-- how hard the camera shakes (0 .. 2): a growing rumble, violent in the collapse, the burst
function T.Shake(t)
	if t < 0 then return 0 end
	if t < T.FORM_AT then return 0.03 end
	if t < T.EST_END then return 0.05 + 0.15 * clamp01((t - T.FORM_AT) / (T.EST_END - T.FORM_AT)) end
	if t < T.PULL_AT then return 0.1 end
	if t < T.COLLAPSE then return 0.12 + 0.3 * clamp01((t - T.PULL_AT) / (T.COLLAPSE - T.PULL_AT)) end
	if t < T.IMPLODE then return 0.45 + 0.5 * T.Collapse(t) end
	local s = t - T.IMPLODE
	return 0.1 + 1.8 * (1 - clamp01(s / 3)) ^ 2
end

-- 0 .. 1: the black of the cut, and of the end
function T.Black(t)
	local d = math.abs(t - T.EST_END)
	local cut = d < T.CUT and (1 - d / T.CUT) or 0
	local fin = clamp01((t - (T.END - T.END_FADE)) / T.END_FADE)
	return math.max(cut, fin)
end

-- 0 .. 1: the flash of the implosion
function T.Flash(t)
	local s = t - T.IMPLODE
	if s < 0 then return 0 end
	if s < 0.12 then return 1 end
	return (1 - clamp01((s - 0.12) / 1.5)) ^ 1.5
end

-- (the trolls' clocks have these; nothing uses them for this one)
function T.Rise() return 0 end

return T
