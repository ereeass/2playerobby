--=====================================================================
-- BlackHoleTimeline   (ReplicatedStorage.TrollFx)
--
-- BLACK HOLE second by second. The same kind of clock as the other shows' (RocketTimeline,
-- ExplodeTimeline, FreezeTimeline, UfoTimeline, SlapTimeline), with the same functions, so
-- the server (ScooterSystem.TrollShow), the show (StarterPlayerScripts.TrollFx.BlackHole), the
-- Troll spectate camera and the two riders' own camera use it exactly as the others
-- (TrollFx.Timelines picks by the scooter's Troll attribute). Times are seconds from the
-- scooter's TrollStart (server time). Every timing, size and distance is one of the constants
-- below.
--
--   0 .. OPEN          the scooter stops dead; a black hole tears open ahead of it
--   OPEN .. PULL       it builds: spinning faster, bits of the ground and sparks swirling in,
--                      the scooter shaking and straining against it
--   PULL .. EXPLODE    it wins: the scooter and both riders are dragged in, spiralling and
--                      spinning faster and faster
--   EXPLODE            GULP - swallowed: scooter and riders are gone
--   .. + COLLAPSE      the hole bulges, then slams shut in a flash
--   END                the show is over: the death popup opens (DeathManager). The same time
--                      after EXPLODE as the other shows.
-- Only ever the one scooter the troll was bought onto is moved - and only in the picture each
-- screen draws. There is no force, no gravity and no area: nobody else is ever touched.
--=====================================================================

local R = require(script.Parent:WaitForChild("RocketTimeline"))

local T = {}

T.LEAD     = R.LEAD
T.OPEN     = 0.6      -- it has torn fully open
T.PULL     = 1.35     -- the pull wins: they start sliding in
T.EXPLODE  = 2.8      -- swallowed
T.COLLAPSE = 0.4      -- seconds the hole takes to slam shut after
T.END      = T.EXPLODE + (R.END - R.EXPLODE)

T.HOLE_AT  = Vector3.new(0, 5, -15)   -- where it opens (studs: right, up, behind; -Z is ahead of them)
T.CORE     = 3                         -- studs: the black middle's radius, fully open
T.GROW     = 0.3                       -- how much bigger it swells as it feeds (0.3: 30%)
T.TWIST    = 7                         -- radians they spiral round on the way in
T.SWIRL    = 3                         -- studs out from the straight line they spiral
T.ROLL     = 11                        -- radians they roll over on the way in

local function clamp01(x) return math.clamp(x, 0, 1) end
local smooth = R.Smooth
T.Smooth = smooth

local function backOut(u)
	local c1 = 1.7
	return 1 + (c1 + 1) * (u - 1) ^ 3 + c1 * (u - 1) ^ 2
end

-- the scooter's own flat frame where it stood: upright, facing its way
function T.Flat(base)
	local look = base.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = flat.Magnitude > 0.05 and flat.Unit or Vector3.new(0, 0, -1)
	return CFrame.lookAt(base.Position, base.Position + flat)
end

-- where the hole is (the middle of it)
function T.Hole(base)
	return T.Flat(base) * CFrame.new(T.HOLE_AT)
end

-- 0 .. 1 .. (1 + GROW): how open it is - tearing open with a snap, swelling as it feeds,
-- a bulge as it swallows, then slammed shut
function T.Size(t)
	if t < 0 then return 0 end
	if t < T.OPEN then return math.max(backOut(t / T.OPEN), 0) end
	if t < T.EXPLODE then return 1 + T.GROW * smooth((t - T.OPEN) / (T.EXPLODE - T.OPEN)) end
	local k = (t - T.EXPLODE) / T.COLLAPSE
	if k >= 1 then return 0 end
	local full = 1 + T.GROW
	if k < 0.35 then return full * (1 + 0.25 * math.sin(k / 0.35 * math.pi)) end   -- the bulge
	return full * (1 - smooth((k - 0.35) / 0.65))
end

-- 0 .. 1: how hard it is pulling (the spin, the swirl, the noise, the shake)
function T.Power(t)
	if t >= T.EXPLODE then return 1 end
	return clamp01(t / T.EXPLODE) ^ 0.8
end

-- 0 .. 1 of the way in
function T.Pull(t)
	return clamp01((t - T.PULL) / (T.EXPLODE - T.PULL))
end

-- The chassis at time t: where it stood (`base`), straining and creeping forward as it builds,
-- then dragged into the hole - spiralling round the way in, rolling over and over
function T.Pose(base, t)
	if t < 0 then return base end
	local hole = T.Hole(base).Position
	local flat = T.Flat(base)
	if t < T.PULL then
		-- straining: a shake, a creep towards it, the nose lifting
		local k = clamp01((t - T.OPEN * 0.5) / (T.PULL - T.OPEN * 0.5))
		local tr = 0.03 + 0.1 * k
		local creep = (hole - base.Position).Unit * (0.8 * k * k)
		return CFrame.new(creep) * base * CFrame.new(
			math.noise(t * 23, 1.3) * 2 * tr, math.noise(t * 27, 7.1) * 2 * tr, math.noise(t * 25, 4.7) * 2 * tr)
			* CFrame.Angles(0.12 * k + math.noise(t * 19, 2.2) * tr * 0.2, 0, math.noise(t * 21, 9.4) * tr * 0.2)
	end
	local u = T.Pull(t)
	local e = u ^ 2.2
	local start = base.Position + (hole - base.Position).Unit * 0.8
	local along = start:Lerp(hole, e)
	local a = T.TWIST * e
	local r = T.SWIRL * math.sin(math.pi * e)
	local swirl = flat.RightVector * math.cos(a) * r + flat.UpVector * math.sin(a) * r
	return CFrame.new(along + swirl - base.Position) * base
		* CFrame.Angles(0.12 + 0.6 * e, 0, T.ROLL * e ^ 1.4)
end

-- studs above where it stood
function T.Rise(t)
	return math.max(T.Pose(CFrame.identity, math.min(t, T.EXPLODE)).Position.Y, 0)
end

-- how hard a watcher's camera shakes (0 .. 1): a jolt as it tears open, rising with its
-- pull, a kick as it slams shut
function T.Shake(t)
	if t < 0 then return 0 end
	if t < T.EXPLODE then
		local jolt = t < 0.4 and 0.35 * (1 - t / 0.4) ^ 2 or 0
		return math.max(jolt, 0.05 + 0.35 * T.Power(t) ^ 1.5)
	end
	local shut = T.EXPLODE + T.COLLAPSE
	if t < shut then return 0.4 end
	local k = (t - shut) / 0.8
	return k < 1 and 1.1 * (1 - k) ^ 2 or 0
end

-- A watcher's camera: behind where the scooter stood (`yaw` round it, on `side`), a little
-- higher and further back than usual so the hole ahead is in view, the view stretching wider
-- as they're dragged in, a punch as it slams shut. Returns the eye, the point looked at, and
-- how many degrees wider the view is.
function T.Camera(base, target, t, yaw, side)
	local look = base.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = flat.Magnitude > 0.05 and flat.Unit or Vector3.new(0, 0, -1)
	local heading = math.atan2(-flat.X, -flat.Z) + (yaw or 0)
	local fwd   = Vector3.new(-math.sin(heading), 0, -math.cos(heading))
	local right = Vector3.new(math.cos(heading), 0, -math.sin(heading))
	local pull  = smooth(T.Pull(t))
	local back  = 15 + 2 * smooth(t / T.OPEN) - 3 * pull
	local up    = 7.5 + 1.5 * pull
	local eye   = base.Position - fwd * back + right * (5.2 * (side or 1)) + Vector3.new(0, up, 0)
	local fov   = 4 * T.Power(t) + 14 * pull
	local shut  = T.EXPLODE + T.COLLAPSE
	if t >= shut then
		fov = 18 * (1 - smooth((t - shut) / 0.8)) + 8 * (1 - clamp01((t - shut) / 0.4))
	end
	return eye, target, fov
end

-- walls: exactly the rocket's
T.Clear        = R.Clear
T.Pulled       = R.Pulled
T.RISE_IN_WALL = R.RISE_IN_WALL

function T.BestSide(base, skip, yaw, prefer)
	return R.SideWithRoom(T, base, skip, yaw, prefer, { 0.5, T.PULL, T.EXPLODE - 0.05 })
end

return T
