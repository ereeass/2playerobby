--=====================================================================
-- ExplodeTimeline   (ReplicatedStorage.TrollFx)
--
-- EXPLODE PLAYERS second by second - Rocket Launch without the rocket. The same kind of clock
-- as RocketTimeline, with the same functions, so the server (ScooterSystem.TrollShow), the show
-- (StarterPlayerScripts.TrollFx.Explode), the Troll spectate camera and the two riders' own
-- camera use it exactly as they use the rocket's (TrollFx.Timelines picks by the scooter's
-- Troll attribute). Times are seconds from the scooter's TrollStart (server time).
--
--   0 .. EXPLODE   the scooter stops dead where it is and it builds: flashing red, beeps
--                  coming faster and faster, sparks and smoke, shaking harder and harder
--                  (it never leaves the spot: nothing rises, nothing is launched)
--   EXPLODE        the rocket's cartoon explosion, right there: scooter and riders are gone
--   END            the show is over: the death popup opens (DeathManager). The same time
--                  after the explosion as the rocket's.
--=====================================================================

local R = require(script.Parent:WaitForChild("RocketTimeline"))

local T = {}

T.LEAD    = R.LEAD
T.EXPLODE = 2.4
T.END     = T.EXPLODE + (R.END - R.EXPLODE)

local function clamp01(x) return math.clamp(x, 0, 1) end
local smooth = R.Smooth
T.Smooth = smooth

-- 0 .. 1 through the build-up
function T.Build(t)
	return clamp01(t / T.EXPLODE)
end

-- it never goes up
function T.Rise() return 0 end

-- the alarm's beeps: faster and faster as it builds (seconds between two, at time t)
function T.BeepGap(t)
	return 0.42 - 0.32 * T.Build(t) ^ 1.3
end

-- how hard the scooter shakes (studs): a jitter that grows to a violent rattle
function T.Tremble(t)
	if t < 0 or t >= T.EXPLODE then return 0 end
	return 0.035 + 0.16 * T.Build(t) ^ 1.6
end

-- The chassis at time t: where it stood (`base`), the tremble on top - the rocket's jitter
function T.Pose(base, t)
	local tr = T.Tremble(t)
	if tr <= 0 then return base end
	return base * CFrame.new(
		math.noise(t * 23, 1.3) * 2 * tr, math.noise(t * 27, 7.1) * 2 * tr, math.noise(t * 25, 4.7) * 2 * tr)
		* CFrame.Angles(math.noise(t * 19, 2.2) * tr * 0.15, 0, math.noise(t * 21, 9.4) * tr * 0.15)
end

-- how hard a watcher's camera shakes (0 .. 1): builds with it, then the rocket's explosion kick
function T.Shake(t)
	if t < 0 then return 0 end
	if t < T.EXPLODE then return 0.06 + 0.4 * T.Build(t) ^ 1.5 end
	local k = (t - T.EXPLODE) / 0.9
	return k < 1 and 1.1 * (1 - k) ^ 2 or 0
end

-- A watcher's camera: behind where the scooter stands (`yaw` round it, on `side`), creeping in
-- and narrowing a little as it builds, then the rocket's punch at the explosion. Returns the
-- eye, the point looked at, and how many degrees wider the view is (the rocket's Camera).
function T.Camera(base, target, t, yaw, side)
	local look = base.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = flat.Magnitude > 0.05 and flat.Unit or Vector3.new(0, 0, -1)
	local heading = math.atan2(-flat.X, -flat.Z) + (yaw or 0)
	local fwd   = Vector3.new(-math.sin(heading), 0, -math.cos(heading))
	local right = Vector3.new(math.cos(heading), 0, -math.sin(heading))
	local build = smooth(T.Build(t))
	local back  = 14 - 2.5 * build
	local up    = 8.2 - 1.2 * build
	local eye   = base.Position - fwd * back + right * (5.2 * (side or 1)) + Vector3.new(0, up, 0)
	local fov   = -5 * build
	if t >= T.EXPLODE then
		-- the rocket's punch at the explosion, then back to the normal view before the popup
		local k = clamp01((t - T.EXPLODE) / 0.9)
		fov = fov * (1 - smooth(k)) + 10 * (1 - clamp01((t - T.EXPLODE) / 0.5))
	end
	return eye, target, fov
end

-- walls: exactly the rocket's
T.Clear        = R.Clear
T.Pulled       = R.Pulled
T.RISE_IN_WALL = R.RISE_IN_WALL

function T.BestSide(base, skip, yaw, prefer)
	return R.SideWithRoom(T, base, skip, yaw, prefer, { 0.3, T.EXPLODE - 0.05 })
end

return T
