--=====================================================================
-- DragonTimeline   (ReplicatedStorage.TrollFx)
--
-- LAVA DRAGON second by second: one clock for the server (ScooterSystem.LavaDragon, through
-- NukeAll's shared global show: when every ride goes down, when the lobby goes down) and for
-- every player's cinematic (StarterGui.DragonGui.DragonCinematic). Times are seconds from the
-- server's start time. Every timing, shot, position and size is one of the constants below.
-- Nothing here moves anything - it only says where things are at time t. (It has LEAD, EXPLODE
-- and END like the trolls' clocks, so ScooterSystem.TrollShow plays it on each ride.)
--
--   0 .. EST_END          the whole map, a roar echoing, the sea glowing red where it will rise
--   (a quick cut through black)
--   EST_END .. HOVER_AT   the lava pool on the sea boils; the dragon bursts up out of it (BURST)
--   HOVER_AT .. SWEEP     it hangs in the air and ROARS, right in the camera
--   SWEEP .. CHARGE       it dives and flies the whole course, breathing fire on all of it
--   CHARGE .. SPIT        high over the map it charges a fireball in its jaws (HUSH: silence)
--   SPIT .. IMPACT        the fireball falls onto the middle of the map
--   IMPACT (= EXPLODE)    a flash, a firestorm, lava bursting up everywhere, a shockwave
--                         (every scooter out on the course is gone in it)
--   END                   it's over: the rides go down (death popup), the lobby goes down
--                         (respawn), everyone's screen comes back
--=====================================================================

local T = {}

-- this world's map spots (ReplicatedStorage.WorldConfig.Dragon): the sea, the pool, its
-- flight over the course and where the camera stands. Timings and sizes are the same in
-- every world.
local MAP = require(game:GetService("ReplicatedStorage"):WaitForChild("WorldConfig")).Dragon or {}

---------------------------------------------------------------- timing
T.LEAD      = 0.8     -- the server starts the clock this far ahead, so every player has it
T.EST_END   = 3.0     -- the establishing shot ends (cut through black)
T.CUT       = 0.3     -- the cut's fade, each way
T.BURST     = 3.6     -- the dragon bursts out of the lava
T.HOVER_AT  = 5.0     -- it has risen: hanging there, roaring
T.SWEEP     = 6.4     -- it dives at the course
T.BREATH_ON = 6.9     -- the fire breath starts ...
T.BREATH_OFF = 11.6   -- ... and stops
T.CHARGE    = 12.4    -- it's high over the map: the fireball grows in its jaws
T.HUSH      = 12.9    -- everything cuts to silence
T.SPIT      = 13.2    -- it spits it
T.IMPACT    = 13.7    -- boom
T.EXPLODE   = T.IMPACT
T.END       = 19.0    -- it's over
T.END_FADE  = 0.6     -- the fade to black before the screen comes back

---------------------------------------------------------------- the dragon
T.SCALE      = 5                              -- the model (ReplicatedStorage.TrollFx.LavaDragonModel) is scaled up this much
T.FLAP_SPEED = 5.5                            -- wing beats (radians a second)

---------------------------------------------------------------- the map
T.SEA         = MAP.SEA or 181.1                                -- the sea's surface (Workspace.Map.Water, which rays pass through)
T.GROUND_ZERO = MAP.GROUND_ZERO or Vector3.new(-440, 185, 520)  -- the middle of the map: where the fireball lands
T.POOL        = MAP.POOL or Vector3.new(-470, T.SEA + 0.4, 470) -- the lava pool on the sea it rises out of
T.POOL_R      = 120                                             -- the pool's radius
T.HOVER       = MAP.HOVER or Vector3.new(-470, 345, 470)        -- where it hangs and roars
-- its flight: from the hover, down the whole course (checkpoint 2 .. the finish), then up to
-- where it charges the fireball. Each point is high enough over what's under it.
T.PATH = MAP.PATH or { T.HOVER, T.HOVER + Vector3.new(0, 150, -200) }   -- (WorldConfig.Dragon.PATH: starts at HOVER, the last point is where it charges)
T.CHARGE_AT = T.PATH[#T.PATH]

---------------------------------------------------------------- the shots
-- the whole map, from beyond the lobby (a slow push in), the red glow on the sea below
T.EST_FROM = MAP.EST_FROM or Vector3.new(-300, 360, -130)
T.EST_TO   = MAP.EST_TO   or Vector3.new(-292, 335, -80)
T.EST_LOOK = MAP.EST_LOOK or Vector3.new(-430, 150, 520)
T.EST_FOV  = 70
-- the rise: from low over the sea, looking at the pool and then up at the dragon
T.RISE_EYE  = MAP.RISE_EYE  or Vector3.new(-230, 235, 290)
T.RISE_EYE2 = MAP.RISE_EYE2 or Vector3.new(-250, 320, 290)
T.RISE_FOV  = 62
-- the roar: right in front of its face, pushing in
T.ROAR_DIST = { 190, 120 }    -- studs in front of its head, start .. end
T.ROAR_FOV  = { 58, 46 }
-- the flight: chasing it, behind, above and a little to the side
T.CHASE_BACK, T.CHASE_UP, T.CHASE_SIDE, T.CHASE_AHEAD = 170, 70, 230, 150
T.CHASE_FOV = 72
-- the fireball: the wide shot it falls and explodes in
T.WIDE_EYE  = MAP.WIDE_EYE  or Vector3.new(-250, 520, 90)
T.WIDE_BACK = MAP.WIDE_BACK or Vector3.new(-220, 600, -60)
T.WIDE_FOV  = 70
T.BLEND     = 0.5     -- seconds each shot blends into the next (except the cut)

---------------------------------------------------------------- the blast (studs, seconds)
T.FIREBALL  = 210     -- the firestorm's radius at its biggest
T.SHOCKWAVE = 850     -- the shockwave ring's radius: over the whole map
T.HEAT      = 650     -- the orange heat dome's radius
T.GEYSERS   = 14      -- lava bursting up around the map
T.GEYSER_R  = { 140, 620 }   -- how far out from the middle they are

local function clamp01(x) return math.clamp(x, 0, 1) end
local function smooth(x) x = clamp01(x); return x * x * (3 - 2 * x) end
local function smoother(x) x = clamp01(x); return x * x * x * (x * (x * 6 - 15) + 10) end
T.Smooth, T.Smoother, T.Clamp01 = smooth, smoother, clamp01

---------------------------------------------------------------- the flight path
-- a smooth curve through PATH, walked at an even speed (by length)
local function catmull(p0, p1, p2, p3, u)
	local u2, u3 = u * u, u * u * u
	return 0.5 * ((2 * p1) + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u2 + (-p0 + 3 * p1 - 3 * p2 + p3) * u3)
end
local curve, lengths, total = {}, { 0 }, 0
do
	local P = T.PATH
	local n = #P
	for i = 1, n - 1 do
		local p0, p1, p2, p3 = P[math.max(i - 1, 1)], P[i], P[i + 1], P[math.min(i + 2, n)]
		for s = 0, 19 do table.insert(curve, catmull(p0, p1, p2, p3, s / 20)) end
	end
	table.insert(curve, P[n])
	for i = 2, #curve do
		total += (curve[i] - curve[i - 1]).Magnitude
		lengths[i] = total
	end
end
T.PathLength = total
-- the point `d` studs along the curve
local function along(d)
	d = math.clamp(d, 0, total)
	local lo, hi = 1, #curve
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if lengths[mid] < d then lo = mid else hi = mid end
	end
	local seg = lengths[hi] - lengths[lo]
	local k = seg > 0 and (d - lengths[lo]) / seg or 0
	return curve[lo]:Lerp(curve[hi], k)
end
-- 0 .. 1 of the way along it: a quick start, an even speed, easing into the charge
local function flight(t)
	local u = clamp01((t - T.SWEEP) / (T.CHARGE - T.SWEEP))
	-- an even speed with a short ease in and out (the ends are 12% of the time each)
	local e = 0.12
	local v = 1 / (1 - e)                       -- the cruising speed that covers it all
	if u < e then return v * u * u / (2 * e) end
	if u > 1 - e then local w = 1 - u; return 1 - v * w * w / (2 * e) end
	return v * (u - e / 2)
end

---------------------------------------------------------------- the dragon at time t
local function facing(pos, dir, bank, pitchUp)
	dir = dir.Magnitude > 1e-3 and dir.Unit or Vector3.new(0, 0, -1)
	return CFrame.lookAt(pos, pos + dir) * CFrame.Angles(pitchUp or 0, 0, bank or 0)
end

-- where it is when it isn't flying the course (before SWEEP, after CHARGE)
local ROAR_FACE = (T.RISE_EYE2 - T.HOVER) * Vector3.new(1, 0, 1)   -- it roars at the camera

function T.OnPath(t)
	return along(flight(t) * total)
end

-- the dragon's CFrame (it faces its -Z, like the model) and whether it's out (seen) at all
function T.Dragon(t)
	if t < T.BURST then
		return CFrame.new(T.POOL - Vector3.new(0, 300, 0)), false
	end
	if t < T.HOVER_AT then
		-- bursting straight up out of the pool, nose to the sky, twisting round, levelling off
		local u = clamp01((t - T.BURST) / (T.HOVER_AT - T.BURST))
		local k = 1 - (1 - u) ^ 3
		local pos = T.POOL:Lerp(T.HOVER, k) + Vector3.new(0, -60 * (1 - k), 0)
		local yaw = math.atan2(-ROAR_FACE.X, -ROAR_FACE.Z) + (1 - smooth(u)) * math.pi * 1.5
		local nose = math.rad(75) * (1 - smoother(u))
		return CFrame.new(pos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(nose, 0, 0), true
	end
	if t < T.SWEEP then
		-- hanging in the air roaring at the camera, rearing back
		local u = clamp01((t - T.HOVER_AT) / (T.SWEEP - T.HOVER_AT))
		local pos = T.HOVER + Vector3.new(0, math.sin(t * T.FLAP_SPEED) * 6, 0)
		local rear = math.rad(18) * math.sin(math.pi * clamp01(u * 1.3))
		return facing(pos, ROAR_FACE, 0, rear), true
	end
	if t < T.CHARGE then
		-- flying the course: along the curve, facing where it's going, banking into the turns
		local pos = T.OnPath(t)
		local ahead = T.OnPath(t + 0.12) - T.OnPath(t - 0.12)
		if ahead.Magnitude < 1 then ahead = T.OnPath(T.SWEEP + 0.3) - T.HOVER end
		local ahead2 = T.OnPath(t + 0.35) - T.OnPath(t + 0.11)
		local turn = 0
		if ahead2.Magnitude > 1 then
			local a, b = ahead.Unit * Vector3.new(1, 0, 1), ahead2.Unit * Vector3.new(1, 0, 1)
			turn = math.clamp(a:Cross(b).Y * 4, -0.7, 0.7)
		end
		-- never steeper than about 35 degrees, nose up or down
		local flat = ahead * Vector3.new(1, 0, 1)
		local dir = flat.Unit + Vector3.new(0, math.clamp(ahead.Unit.Y / math.max(flat.Magnitude / ahead.Magnitude, 0.2), -0.7, 0.7), 0)
		return facing(pos, dir, turn, 0), true
	end
	-- the charge: hanging high over the map, facing its middle, rearing back and then lunging as it spits
	local toward = (T.GROUND_ZERO - T.CHARGE_AT) * Vector3.new(1, 0, 1)
	if t < T.SPIT + 0.4 then
		local u = clamp01((t - T.CHARGE) / (T.SPIT - T.CHARGE))
		local rear = math.rad(25) * smooth(u)
		local lunge = t > T.SPIT and math.rad(-55) * smooth((t - T.SPIT) / 0.25) or 0
		local pos = T.CHARGE_AT + Vector3.new(0, math.sin(t * T.FLAP_SPEED) * 5, 0)
		return facing(pos, toward, 0, rear + lunge), true
	end
	-- then off it goes, up and away over the map
	local s = t - (T.SPIT + 0.4)
	local pos = T.CHARGE_AT + toward.Unit * (60 * s + 25 * s * s) + Vector3.new(0, 30 * s + 18 * s * s, 0)
	return facing(pos, toward + Vector3.new(0, toward.Magnitude * 0.25, 0), 0, 0), s < 4.5
end

-- the wings' beat: radians, + up (a slow glide on the flight's straight runs)
function T.Flap(t)
	local speed = T.FLAP_SPEED
	if t >= T.SWEEP and t < T.CHARGE then speed *= 0.8 end
	if t < T.HOVER_AT then speed *= 1.3 end
	return 0.15 + 0.55 * math.sin(t * speed)
end

-- 0 .. 1: the fire breath, on the flight
function T.Breath(t)
	if t < T.BREATH_ON or t > T.BREATH_OFF then return 0 end
	return smooth((t - T.BREATH_ON) / 0.3) * (1 - smooth((t - (T.BREATH_OFF - 0.3)) / 0.3))
end

-- 0 .. 1: the fireball growing in its jaws
function T.Charge(t)
	if t < T.CHARGE or t >= T.SPIT then return 0 end
	return smooth((t - T.CHARGE) / (T.SPIT - T.CHARGE))
end

-- 0 .. 1 of the fireball's fall (from the dragon's jaws to the middle of the map)
function T.Fall(t)
	return clamp01((t - T.SPIT) / (T.IMPACT - T.SPIT))
end

-- 0 .. 1: the pool on the sea: glowing, then gone after the blast
function T.Pool(t)
	return smooth(t / 2.5) * (1 - smooth((t - (T.IMPACT + 3)) / 2))
end

---------------------------------------------------------------- the camera
local function shotEst(t)
	local k = smoother(t / T.EST_END)
	return CFrame.lookAt(T.EST_FROM:Lerp(T.EST_TO, k), T.EST_LOOK), T.EST_FOV
end
local function shotRise(t)
	local k = smoother((t - T.EST_END) / (T.HOVER_AT - T.EST_END))
	local eye = T.RISE_EYE:Lerp(T.RISE_EYE2, k)
	local dragon = T.Dragon(math.max(t, T.BURST)).Position
	local look = t < T.BURST and T.POOL + Vector3.new(0, 30, 0) or (T.POOL + Vector3.new(0, 30, 0)):Lerp(dragon, smooth((t - T.BURST) / 0.5))
	return CFrame.lookAt(eye, look), T.RISE_FOV
end
local function shotRoar(t)
	local k = smoother((t - T.HOVER_AT) / (T.SWEEP - T.HOVER_AT))
	local cf = T.Dragon(t)
	local head = cf * Vector3.new(0, 25, -65)
	local dist = T.ROAR_DIST[1] + (T.ROAR_DIST[2] - T.ROAR_DIST[1]) * k
	local flat = (cf.LookVector * Vector3.new(1, 0, 1)).Unit
	local eye = head + flat * dist + Vector3.new(0, -30, 0) + flat:Cross(Vector3.yAxis) * dist * 0.6
	return CFrame.lookAt(eye, head + Vector3.new(0, -10, 0)), T.ROAR_FOV[1] + (T.ROAR_FOV[2] - T.ROAR_FOV[1]) * k
end
local function shotChase(t)
	local pos = T.Dragon(t).Position
	local ahead = T.OnPath(t + 0.25) - T.OnPath(t - 0.25)
	ahead = ahead.Magnitude > 1 and ahead.Unit or (T.OnPath(T.SWEEP + 0.3) - T.HOVER).Unit
	local flat = (ahead * Vector3.new(1, 0, 1))
	flat = flat.Magnitude > 1e-3 and flat.Unit or Vector3.new(0, 0, -1)
	local side = flat:Cross(Vector3.yAxis)
	local eye = pos - flat * T.CHASE_BACK + Vector3.new(0, T.CHASE_UP, 0) + side * T.CHASE_SIDE
	local look = pos + flat * T.CHASE_AHEAD + Vector3.new(0, -70, 0)
	return CFrame.lookAt(eye, look), T.CHASE_FOV
end
local function shotCharge(t)
	-- over its shoulder, looking down at the middle of the map
	local cf = T.Dragon(math.min(t, T.SPIT))
	local flat = (T.GROUND_ZERO - T.CHARGE_AT) * Vector3.new(1, 0, 1)
	flat = flat.Unit
	local side = flat:Cross(Vector3.yAxis)
	local eye = cf.Position - flat * 150 + Vector3.new(0, 20, 0) + side * 330
	return CFrame.lookAt(eye, cf.Position:Lerp(T.GROUND_ZERO, 0.14) + flat * 60), 62
end
local function shotWide(t)
	local s = t - T.IMPACT
	if s < 0 then
		local ball = T.CHARGE_AT:Lerp(T.GROUND_ZERO, T.Fall(t))
		return CFrame.lookAt(T.WIDE_EYE, ball:Lerp(T.GROUND_ZERO, 0.5)), T.WIDE_FOV
	end
	local k = smoother(s / (T.END - T.IMPACT))
	local eye = T.WIDE_EYE:Lerp(T.WIDE_BACK, k)
	local look = T.GROUND_ZERO + Vector3.new(0, 40 + 120 * smooth(s / 4), 0)
	local punch = 14 * (1 - smooth(s / 0.9))
	return CFrame.lookAt(eye, look), T.WIDE_FOV + punch
end

local SHOTS = {
	{ 0,           shotEst },
	{ T.EST_END,   shotRise, cut = true },
	{ T.HOVER_AT,  shotRoar },
	{ T.SWEEP,     shotChase },
	{ T.CHARGE,    shotCharge },
	{ T.SPIT,      shotWide },
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

-- how hard the camera shakes (0 .. 2)
function T.Shake(t)
	if t < 0 then return 0 end
	if t < T.BURST then return 0.04 + 0.1 * clamp01((t - T.EST_END) / (T.BURST - T.EST_END)) end
	if t < T.HOVER_AT then return 0.5 * (1 - clamp01((t - T.BURST) / 1.2)) + 0.1 end
	if t < T.SWEEP then return 0.12 + 0.5 * math.sin(math.pi * clamp01((t - T.HOVER_AT - 0.15) / 1.1)) end   -- the roar
	if t < T.IMPACT then return 0.1 end
	local s = t - T.IMPACT
	return 0.12 + 1.8 * (1 - clamp01(s / 3)) ^ 2
end

-- 0 .. 1: the black of the cut, and of the end
function T.Black(t)
	local d = math.abs(t - T.EST_END)
	local cut = d < T.CUT and (1 - d / T.CUT) or 0
	local fin = clamp01((t - (T.END - T.END_FADE)) / T.END_FADE)
	return math.max(cut, fin)
end

-- 0 .. 1: the flash of the impact
function T.Flash(t)
	local s = t - T.IMPACT
	if s < 0 then return 0 end
	if s < 0.12 then return 1 end
	return (1 - clamp01((s - 0.12) / 1.4)) ^ 1.5
end

-- (the trolls' clocks have these; nothing uses them for this one)
function T.Rise() return 0 end

return T
