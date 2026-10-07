--=====================================================================
-- FreezeTimeline   (ReplicatedStorage.TrollFx)
--
-- FREEZE PLAYERS second by second - Explode Players with ice instead of a bomb. The same kind
-- of clock as ExplodeTimeline (and RocketTimeline), with the same functions, so the server
-- (ScooterSystem.TrollShow), the show (StarterPlayerScripts.TrollFx.Freeze), the Troll
-- spectate camera and the two riders' own camera use it exactly as they use the others
-- (TrollFx.Timelines picks by the scooter's Troll attribute). Times are seconds from the
-- scooter's TrollStart (server time). Every timing of the show is one of the constants below.
--
--   0 .. FROZEN      the scooter stops dead; frost races up and a block of ice grows round
--                    the scooter and both riders, from the ground up
--   FROZEN .. CRACK  trapped: a solid block of ice, mist rolling off it, glinting
--   CRACK .. EXPLODE the ice strains: cracks spread, it creaks and trembles harder and harder
--   EXPLODE          the ice shatters apart: scooter and riders are gone with it
--   END              the show is over: the death popup opens (DeathManager). The same time
--                    after the shatter as the explosion's.
--=====================================================================

local R = require(script.Parent:WaitForChild("RocketTimeline"))

local T = {}

T.LEAD    = R.LEAD
T.FROZEN  = 0.7                          -- the ice has fully formed
T.CRACK   = 1.7                          -- the first cracks
T.EXPLODE = 2.5                          -- the shatter
T.END     = T.EXPLODE + (R.END - R.EXPLODE)

local function clamp01(x) return math.clamp(x, 0, 1) end
local smooth = R.Smooth
T.Smooth = smooth

-- 0 .. 1 through the whole show, up to the shatter
function T.Build(t)
	return clamp01(t / T.EXPLODE)
end

-- 0 .. 1: how much of the ice has formed (eased: fast, then settling)
function T.Grow(t)
	local u = clamp01(t / T.FROZEN)
	return 1 - (1 - u) ^ 3
end

-- 0 .. 1: how far the cracks have spread
function T.Crack(t)
	return clamp01((t - T.CRACK) / (T.EXPLODE - T.CRACK))
end

-- it never goes up
function T.Rise() return 0 end

-- how hard the block shakes (studs): still while it forms and holds, then a rattle that grows
-- as it cracks
function T.Tremble(t)
	if t < T.CRACK or t >= T.EXPLODE then return 0 end
	return 0.02 + 0.1 * T.Crack(t) ^ 1.5
end

-- the chassis (and the ice) at time t: where it stood (`base`), the tremble on top
function T.Pose(base, t)
	local tr = T.Tremble(t)
	if tr <= 0 then return base end
	return base * CFrame.new(
		math.noise(t * 23, 1.3) * 2 * tr, math.noise(t * 27, 7.1) * 2 * tr, math.noise(t * 25, 4.7) * 2 * tr)
		* CFrame.Angles(math.noise(t * 19, 2.2) * tr * 0.1, 0, math.noise(t * 21, 9.4) * tr * 0.1)
end

-- how hard a watcher's camera shakes (0 .. 1): a thud as the ice sets, the strain as it
-- cracks, then the explosion's kick at the shatter
function T.Shake(t)
	if t < 0 then return 0 end
	if t < T.CRACK then
		local set = (t - T.FROZEN) / 0.35
		return (set >= 0 and set < 1) and 0.3 * (1 - set) ^ 2 or 0.02
	end
	if t < T.EXPLODE then return 0.06 + 0.35 * T.Crack(t) ^ 1.5 end
	local k = (t - T.EXPLODE) / 0.9
	return k < 1 and 1.0 * (1 - k) ^ 2 or 0
end

-- A watcher's camera: behind where the scooter stands (`yaw` round it, on `side`), a little
-- further back than the bomb's (the block is bigger), creeping in as it holds, then the punch
-- at the shatter. Returns the eye, the point looked at, and how many degrees wider the view is.
function T.Camera(base, target, t, yaw, side)
	local look = base.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = flat.Magnitude > 0.05 and flat.Unit or Vector3.new(0, 0, -1)
	local heading = math.atan2(-flat.X, -flat.Z) + (yaw or 0)
	local fwd   = Vector3.new(-math.sin(heading), 0, -math.cos(heading))
	local right = Vector3.new(math.cos(heading), 0, -math.sin(heading))
	local build = smooth(T.Build(t))
	local back  = 15 - 2.5 * build
	local up    = 8.4 - 1.2 * build
	local eye   = base.Position - fwd * back + right * (5.6 * (side or 1)) + Vector3.new(0, up, 0)
	local fov   = -5 * build
	if t >= T.EXPLODE then
		local k = clamp01((t - T.EXPLODE) / 0.9)
		fov = fov * (1 - smooth(k)) + 8 * (1 - clamp01((t - T.EXPLODE) / 0.5))
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
