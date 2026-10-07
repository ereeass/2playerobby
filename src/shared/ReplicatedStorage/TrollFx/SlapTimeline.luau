--=====================================================================
-- SlapTimeline   (ReplicatedStorage.TrollFx)
--
-- GIANT SLAP second by second. The same kind of clock as the other shows' (RocketTimeline,
-- ExplodeTimeline, FreezeTimeline, UfoTimeline), with the same functions, so the server
-- (ScooterSystem.TrollShow), the show (StarterPlayerScripts.TrollFx.Slap), the Troll spectate
-- camera and the two riders' own camera use it exactly as the others (TrollFx.Timelines picks
-- by the scooter's Troll attribute). Times are seconds from the scooter's TrollStart (server
-- time). Every timing, pose and speed of the show is one of the constants below.
--
--   0 .. ENTER       the scooter stops dead; a rumble; a huge shadow grows beside them
--   ENTER .. ARRIVE  a GIANT cartoon glove on a stick swoops down from out of the sky
--   ARRIVE .. SLAP   it hangs there beside them. An awkward pause. It winds up, trembling.
--   SLAP .. IMPACT   THE SLAP: a sudden swing
--   IMPACT .. FLING  SMACK! - everything freezes for a moment (the hit-stop)
--   FLING .. EXPLODE they are flung away, tumbling, up and off into the distance; the hand
--                    follows through, recoils and goes back up out of sight
--   EXPLODE          a twinkle where they disappear: scooter and riders are gone
--   END              the show is over: the death popup opens (DeathManager). The same time
--                    after EXPLODE as the other shows.
--=====================================================================

local R = require(script.Parent:WaitForChild("RocketTimeline"))

local T = {}

T.LEAD    = R.LEAD
T.ENTER   = 0.7      -- the hand starts coming down
T.ARRIVE  = 1.0      -- it has arrived beside them
T.SLAP    = 1.75     -- the swing starts (after the awkward pause)
T.IMPACT  = 1.85     -- SMACK
T.HITSTOP = 0.12     -- seconds everything freezes on the impact
T.FLING   = T.IMPACT + T.HITSTOP
T.EXPLODE = 3.0      -- gone (the twinkle)
T.END     = T.EXPLODE + (R.END - R.EXPLODE)

-- the fling (studs and seconds, in the scooter's own flat space: X right, Y up, -Z ahead)
T.FLING_VEL  = Vector3.new(62, 46, -14)   -- how fast they leave (away from the hand, up, a bit ahead)
T.GRAVITY    = 38                          -- how fast the arc comes down (studs/s/s)
T.TUMBLE     = Vector3.new(5, 3, -13)      -- how fast they tumble (radians/s round X, Y, Z)

-- the hand's poses (in the scooter's own flat space; lean: radians, + = fingers back away from
-- them, - = over towards them; turn: radians round its own length - 0 = its palm on them,
-- about 1.2 = the back of the glove to whoever is watching from behind them). It comes in on
-- their LEFT, showing off, then turns palm-first into the slap and knocks them to the right.
local FROM   = { pos = Vector3.new(-11, 62, -3), lean = 0.3, turn = 1.2 }
local HOVER  = { pos = Vector3.new(-8, 8, -11), lean = 0.55, turn = 1.2 }
local WINDUP = { pos = Vector3.new(-9.5, 9, -11), lean = 0.85, turn = 1.35 }
local HIT    = { pos = Vector3.new(-1.6, 5.5, -1), lean = -0.15, turn = 0.4 }
local FOLLOW = { pos = Vector3.new(1.5, 5, -1), lean = -0.5, turn = -0.2 }
local RECOIL = { pos = Vector3.new(-7, 8.5, -2), lean = 0.45, turn = 0.8 }
local EXIT   = { pos = Vector3.new(-15, 75, -2), lean = 0.25, turn = 1.1 }
local FOLLOW_T, RECOIL_T, EXIT_T = 0.1, 0.35, 0.6   -- seconds for each, after the hit-stop

local function clamp01(x) return math.clamp(x, 0, 1) end
local smooth = R.Smooth
T.Smooth = smooth

local function backOut(u)
	local c1 = 1.9
	return 1 + (c1 + 1) * (u - 1) ^ 3 + c1 * (u - 1) ^ 2
end

local function mix(a, b, k)
	return a.pos:Lerp(b.pos, k), a.lean + (b.lean - a.lean) * k, a.turn + (b.turn - a.turn) * k
end

-- the scooter's own flat frame where it stood: upright, facing its way
function T.Flat(base)
	local look = base.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = flat.Magnitude > 0.05 and flat.Unit or Vector3.new(0, 0, -1)
	return CFrame.lookAt(base.Position, base.Position + flat)
end

-- The hand at time t, in the scooter's flat space: where its palm is, its lean, whether it is
-- there at all, whether it is moving fast (its motion blur), and its turn
function T.Hand(t)
	if t < T.ENTER then return FROM.pos, FROM.lean, false, false, FROM.turn end
	if t < T.ARRIVE then
		local p, l, r = mix(FROM, HOVER, backOut(clamp01((t - T.ENTER) / (T.ARRIVE - T.ENTER))))
		return p, l, true, true, r
	end
	if t < T.SLAP then
		-- the awkward pause: winding up slowly, trembling with it
		local k = smooth((t - T.ARRIVE) / (T.SLAP - T.ARRIVE))
		local p, l, r = mix(HOVER, WINDUP, k)
		return p, l + math.sin(t * 38) * 0.02 * k, true, false, r
	end
	if t < T.IMPACT then
		local u = clamp01((t - T.SLAP) / (T.IMPACT - T.SLAP))
		local p, l, r = mix(WINDUP, HIT, u * u)
		return p, l, true, true, r
	end
	if t < T.FLING then return HIT.pos, HIT.lean, true, false, HIT.turn end
	local s = t - T.FLING
	if s < FOLLOW_T then
		local p, l, r = mix(HIT, FOLLOW, smooth(s / FOLLOW_T))
		return p, l, true, true, r
	end
	s -= FOLLOW_T
	if s < RECOIL_T then
		local p, l, r = mix(FOLLOW, RECOIL, backOut(clamp01(s / RECOIL_T)))
		return p, l, true, false, r
	end
	s -= RECOIL_T
	if s < EXIT_T then
		local u = clamp01(s / EXIT_T)
		local p, l, r = mix(RECOIL, EXIT, u * u)
		return p, l, true, true, r
	end
	return EXIT.pos, EXIT.lean, false, false, EXIT.turn
end

-- where they are flung to (studs from where they stood, in the flat space), and their tumble
function T.Fling(t)
	if t < T.FLING then return Vector3.zero, Vector3.zero end
	local s = t - T.FLING
	local v = T.FLING_VEL
	return Vector3.new(v.X * s, v.Y * s - 0.5 * T.GRAVITY * s * s, v.Z * s), T.TUMBLE * s
end

-- studs above where it stood
function T.Rise(t)
	return math.max(T.Fling(t).Y, 0)
end

-- The chassis at time t: where it stood (`base`) until the slap, then flung away tumbling
function T.Pose(base, t)
	if t < T.FLING then return base end
	local off, spin = T.Fling(t)
	local flat = T.Flat(base)
	return CFrame.new(flat:VectorToWorldSpace(off)) * base * CFrame.Angles(spin.X, spin.Y, spin.Z)
end

-- how hard a watcher's camera shakes (0 .. 1): a building rumble, a thud as the hand arrives,
-- the trembling pause, then a HUGE kick on the slap
function T.Shake(t)
	if t < 0 then return 0 end
	if t < T.ENTER then return 0.06 + 0.14 * clamp01(t / T.ENTER) end
	if t < T.SLAP then
		local k = (t - T.ARRIVE) / 0.35
		return (k >= 0 and k < 1) and 0.05 + 0.3 * (1 - k) ^ 2 or 0.05
	end
	if t < T.IMPACT then return 0.05 end
	local k = (t - T.IMPACT) / 0.8
	return k < 1 and 1.4 * (1 - k) ^ 2 or 0
end

-- A watcher's camera: behind where the scooter stood (`yaw` round it, on `side`), easing back
-- and up through the pause to take in the giant hand, then a sudden "uh oh" zoom just before the
-- swing, a punch on the slap, then wide to watch them fly. Returns the eye, the point looked at,
-- and how many degrees wider the view is.
T.ZOOM = 0.3   -- seconds of the "uh oh" zoom, right before the swing
function T.Camera(base, target, t, yaw, side)
	local look = base.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = flat.Magnitude > 0.05 and flat.Unit or Vector3.new(0, 0, -1)
	local heading = math.atan2(-flat.X, -flat.Z) + (yaw or 0)
	local fwd   = Vector3.new(-math.sin(heading), 0, -math.cos(heading))
	local right = Vector3.new(math.cos(heading), 0, -math.sin(heading))
	local pause = smooth((t - T.ENTER) / (T.ARRIVE - T.ENTER))
	local zoom  = smooth((t - (T.SLAP - T.ZOOM)) / T.ZOOM)
	if t >= T.IMPACT then pause, zoom = 0, 0 end
	local back  = 16 + 7 * pause - 6 * zoom
	local up    = 7.5 + 4 * pause - 2 * zoom
	local eye   = base.Position - fwd * back + right * (5.2 * (side or 1)) + Vector3.new(0, up, 0)
	local fov   = 8 * pause - 18 * zoom
	if t >= T.IMPACT then
		fov = 12 * (1 - clamp01((t - T.IMPACT) / 0.5)) + 6 * clamp01((t - T.FLING) / 0.6)
	end
	return eye, target, fov
end

-- walls: exactly the rocket's
T.Clear        = R.Clear
T.Pulled       = R.Pulled
T.RISE_IN_WALL = R.RISE_IN_WALL

function T.BestSide(base, skip, yaw, prefer)
	return R.SideWithRoom(T, base, skip, yaw, prefer, { 0.5, T.IMPACT, T.EXPLODE - 0.05 })
end

return T
