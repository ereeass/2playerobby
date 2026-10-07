--=====================================================================
-- NukeTimeline   (ReplicatedStorage.TrollFx)
--
-- NUKE ALL second by second: one clock for the server (ScooterSystem.NukeAll: when every ride
-- goes down, when the lobby goes down) and for every player's cinematic
-- (StarterGui.NukeGui.NukeCinematic). Times are seconds from the server's start time. Every
-- timing, shot, position and size of the cinematic is one of the constants below. Nothing here
-- moves anything - it only says where things are at time t. (It has LEAD, EXPLODE and END like
-- the other trolls' clocks, so ScooterSystem.TrollShow plays it on each ride.)
--
--   0 .. EST_END        the establishing shot: the whole map, sirens blaring
--   (a quick cut through black)
--   EST_END .. CLOSE_END   the nuke, close up, hanging high over the middle of the map
--   CLOSE_END .. PULL_END  the camera pulls right back out; it starts to fall (FALL_START)
--   .. IMPACT           it falls onto the map; a dead-silent pause just before (HUSH)
--   IMPACT (= EXPLODE)  a flash, the fireball, a shockwave over the whole map, the mushroom cloud
--                       (every scooter out on the course is gone in it)
--   END                 the cinematic is over: the rides go down (death popup), the lobby
--                       goes down (respawn), everyone's screen comes back
--=====================================================================

local T = {}

-- this world's map spots (ReplicatedStorage.WorldConfig.Nuke): where it lands and where the
-- camera stands. Everything else here (timings, sizes) is the same in every world.
local MAP = require(game:GetService("ReplicatedStorage"):WaitForChild("WorldConfig")).Nuke or {}

---------------------------------------------------------------- timing
T.LEAD       = 0.8     -- the server starts the clock this far ahead, so every player has it
T.EST_END    = 3.4     -- the establishing shot ends (cut through black)
T.CUT        = 0.3     -- the cut's fade, each way
T.CLOSE_END  = 6.6     -- the close-up ends
T.FALL_START = 7.0     -- the nuke lets go
T.PULL_END   = 7.7     -- the camera has pulled all the way out
T.HUSH       = 9.3     -- the sirens cut: dead silence
T.IMPACT     = 9.8     -- boom
T.EXPLODE    = T.IMPACT
T.END        = 15.0    -- it's over
T.END_FADE   = 0.6     -- the fade to black before the screen comes back

---------------------------------------------------------------- the map
T.GROUND_ZERO = MAP.GROUND_ZERO or Vector3.new(-440, 185, 520)   -- the middle of the map, on the water
T.DROP_HEIGHT = MAP.DROP_HEIGHT or 700                           -- studs above it that the nuke hangs, then falls from
T.DROP        = T.GROUND_ZERO + Vector3.new(0, T.DROP_HEIGHT, 0)
T.NUKE_HALF   = 35                            -- half the nuke's length (it lands nose-first)

---------------------------------------------------------------- the shots
-- the whole map, from beyond the lobby (a slow push in)
T.EST_FROM = MAP.EST_FROM or Vector3.new(-300, 360, -130)
T.EST_TO   = MAP.EST_TO   or Vector3.new(-292, 335, -80)
T.EST_LOOK = MAP.EST_LOOK or Vector3.new(-420, 240, 520)
T.EST_FOV  = 70
-- the close-up: circling the nuke, a little above it, the map far below
T.CLOSE_R    = { 96, 77 }       -- studs out, start .. end
T.CLOSE_UP   = { 136, 96 }      -- studs above its middle, start .. end (looking down past it at the map)
T.CLOSE_TURN = { 2.6, 3.6 }     -- radians round it, start .. end
T.CLOSE_FOV  = 55
-- the wide shot the nuke falls in and explodes in
T.WIDE_EYE   = MAP.WIDE_EYE  or Vector3.new(-300, 560, 60)
T.WIDE_BACK  = MAP.WIDE_BACK or Vector3.new(-250, 640, -90)    -- where it drifts back to afterwards
T.WIDE_AIM   = { 0.12, 0.55 }                 -- where it looks, from the nuke (0) to the ground (1): start .. end of the fall
T.WIDE_FOV   = 68

---------------------------------------------------------------- the explosion (studs, seconds)
T.FIREBALL   = 230    -- the fireball's radius at its biggest
T.SHOCKWAVE  = 900    -- the shockwave ring's radius: over the whole map
T.HEAT       = 700    -- the orange heat dome's radius: it covers the whole map a moment (the
                      -- camera stays outside it: a ball can't be seen from inside)
T.STEM       = 420    -- the mushroom cloud's height
T.CAP        = 190    -- its cap's radius

local function clamp01(x) return math.clamp(x, 0, 1) end
local function smooth(x) x = clamp01(x); return x * x * (3 - 2 * x) end
local function smoother(x) x = clamp01(x); return x * x * x * (x * (x * 6 - 15) + 10) end
T.Smooth, T.Smoother, T.Clamp01 = smooth, smoother, clamp01

-- 0 .. 1 of the fall
function T.Fall(t)
	return clamp01((t - T.FALL_START) / (T.IMPACT - T.FALL_START))
end

-- the nuke at time t: hanging nose-down over the map, turning slowly, then falling faster and
-- faster until its nose touches the ground at IMPACT
function T.Nuke(t)
	local u = T.Fall(t)
	local top = T.DROP + Vector3.new(0, math.sin(t * 2) * 1.5, 0)
	local bottom = T.GROUND_ZERO + Vector3.new(0, T.NUKE_HALF, 0)
	local pos = top:Lerp(bottom, u * u)
	local wobble = u > 0 and 0.04 * math.sin(t * 13) or 0
	return CFrame.new(pos) * CFrame.Angles(0, 0.35 * t, 0) * CFrame.Angles(-math.pi / 2 + wobble, 0, wobble)
end

-- the camera at time t: its CFrame and field of view
function T.Camera(t)
	local nuke = T.Nuke(t).Position
	if t < T.EST_END then
		local k = smoother(t / T.EST_END)
		return CFrame.lookAt(T.EST_FROM:Lerp(T.EST_TO, k), T.EST_LOOK), T.EST_FOV
	end
	-- the close-up (and where the pull-out starts from)
	local function close(tt)
		local k = smoother((tt - T.EST_END) / (T.CLOSE_END - T.EST_END))
		local r = T.CLOSE_R[1] + (T.CLOSE_R[2] - T.CLOSE_R[1]) * k
		local up = T.CLOSE_UP[1] + (T.CLOSE_UP[2] - T.CLOSE_UP[1]) * k
		local a = T.CLOSE_TURN[1] + (T.CLOSE_TURN[2] - T.CLOSE_TURN[1]) * k
		local c = T.Nuke(tt).Position
		return c + Vector3.new(math.sin(a) * r, up, math.cos(a) * r)
	end
	if t < T.CLOSE_END then
		return CFrame.lookAt(close(t), nuke), T.CLOSE_FOV
	end
	if t < T.PULL_END then
		-- pulled right back out, still on the nuke
		local k = smoother((t - T.CLOSE_END) / (T.PULL_END - T.CLOSE_END))
		local eye = close(T.CLOSE_END):Lerp(T.WIDE_EYE, k)
		local look = nuke:Lerp(nuke:Lerp(T.GROUND_ZERO, T.WIDE_AIM[1]), k)
		return CFrame.lookAt(eye, look), T.CLOSE_FOV + (T.WIDE_FOV - T.CLOSE_FOV) * k
	end
	if t < T.IMPACT then
		-- the fall: the camera keeps the nuke and the map it's falling onto in frame
		local look = nuke:Lerp(T.GROUND_ZERO, T.WIDE_AIM[1] + (T.WIDE_AIM[2] - T.WIDE_AIM[1]) * smooth(T.Fall(t)))
		return CFrame.lookAt(T.WIDE_EYE, look), T.WIDE_FOV
	end
	-- the explosion and after: drifting back, looking up at the cloud as it rises
	local s = t - T.IMPACT
	local k = smoother(s / (T.END - T.IMPACT))
	local eye = T.WIDE_EYE:Lerp(T.WIDE_BACK, k)
	local look = T.GROUND_ZERO + Vector3.new(0, 60 + 160 * smooth(s / 4), 0)
	local punch = 14 * (1 - smooth(s / 0.9))
	return CFrame.lookAt(eye, look), T.WIDE_FOV + punch
end

-- how hard the camera shakes (0 .. 2): a growing rumble, then the impact
function T.Shake(t)
	if t < 0 then return 0 end
	if t < T.IMPACT then
		local base = 0.04 + 0.08 * clamp01(t / T.IMPACT)
		if t >= T.FALL_START then base += 0.12 * T.Fall(t) end
		return base
	end
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

-- 0 .. 1: the white flash of the impact
function T.Flash(t)
	local s = t - T.IMPACT
	if s < 0 then return 0 end
	if s < 0.15 then return 1 end
	return (1 - clamp01((s - 0.15) / 1.6)) ^ 1.5
end

-- (the other trolls' clocks have these; nothing uses them for this one)
function T.Rise() return 0 end

return T
