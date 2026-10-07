--=====================================================================
-- UfoTimeline   (ReplicatedStorage.TrollFx)
--
-- UFO ABDUCTION second by second. The same kind of clock as RocketTimeline / ExplodeTimeline /
-- FreezeTimeline, with the same functions, so the server (ScooterSystem.TrollShow), the show
-- (StarterPlayerScripts.TrollFx.Ufo), the Troll spectate camera and the two riders' own camera
-- use it exactly as the others (TrollFx.Timelines picks by the scooter's Troll attribute).
-- Times are seconds from the scooter's TrollStart (server time). Every timing, height and speed
-- of the show is one of the constants below.
--
--   0 .. ARRIVE          the scooter stops dead; a UFO swoops in and hovers HEIGHT studs above
--   BEAM                 its tractor beam switches on round the scooter and both riders
--   LIFT_START .. EXPLODE  they float up the beam together, turning slowly, into the UFO
--   EXPLODE              taken aboard: scooter and riders are gone
--   .. EXPLODE + FLY     the UFO shoots off into the sky
--   END                  the show is over: the death popup opens (DeathManager). The same time
--                        after EXPLODE as the other shows.
--=====================================================================

local R = require(script.Parent:WaitForChild("RocketTimeline"))

local T = {}

T.LEAD       = R.LEAD
T.ARRIVE     = 0.6      -- the UFO swooping in
T.BEAM       = 0.8      -- the beam switching on
T.LIFT_START = 1.0      -- they start floating up
T.EXPLODE    = 2.6      -- taken aboard
T.FLY        = 0.9      -- seconds it takes to shoot off out of sight
T.END        = T.EXPLODE + (R.END - R.EXPLODE)

T.HEIGHT     = 20       -- studs the UFO hovers above the scooter
T.LIFT_H     = T.HEIGHT - 3.5   -- how far they float up (the chassis ends just under the UFO)
T.SPIN       = 2.5      -- radians they turn on the way up
T.FLY_DIST   = 280      -- studs it flies off
T.ARRIVE_FROM = Vector3.new(-50, 35, 0)   -- where it swoops in from (studs: right, up, back of the scooter)

local function clamp01(x) return math.clamp(x, 0, 1) end
local smooth = R.Smooth
T.Smooth = smooth

-- 0 .. 1 up the beam: slow off the ground, faster towards the top
function T.Lift(t)
	return clamp01((t - T.LIFT_START) / (T.EXPLODE - T.LIFT_START))
end

-- studs above where it stood
function T.Rise(t)
	return T.LIFT_H * T.Lift(t) ^ 1.6
end

-- The chassis at time t: straight up the beam from where it stood (`base`), turning slowly and
-- rocking a little as it goes
function T.Pose(base, t)
	local u = T.Lift(t)
	if u <= 0 then return base end
	local rock = 0.08 * math.min(u * 4, 1)
	return CFrame.new(0, T.Rise(t), 0) * base
		* CFrame.Angles(math.sin(t * 5) * rock, T.SPIN * u ^ 1.5, math.cos(t * 4) * rock)
end

-- 0 .. 1: how far the beam is on (it opens quickly, and closes as they are taken aboard)
function T.BeamOn(t)
	if t < T.BEAM then return 0 end
	if t >= T.EXPLODE then return 1 - clamp01((t - T.EXPLODE) / 0.2) end
	return smooth((t - T.BEAM) / 0.2)
end

-- The UFO at time t: swooping in, hovering and bobbing over where the scooter stood, then
-- shooting off up and away. Upright, facing the scooter's way.
function T.Ufo(base, t)
	local look = base.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = flat.Magnitude > 0.05 and flat.Unit or Vector3.new(0, 0, -1)
	local facing = CFrame.lookAt(Vector3.zero, flat)
	local hover = base.Position + Vector3.new(0, T.HEIGHT + math.sin(t * 3) * 0.4, 0)
	local bank = 0
	local pos = hover
	if t < T.ARRIVE then
		local e = 1 - (1 - clamp01(t / T.ARRIVE)) ^ 3
		local from = hover + facing:VectorToWorldSpace(T.ARRIVE_FROM)
		pos = from:Lerp(hover, e)
		bank = -(1 - e) * 0.4
	elseif t >= T.EXPLODE then
		local u = (t - T.EXPLODE) / T.FLY
		local away = facing:VectorToWorldSpace(Vector3.new(0.5, 1, -0.6)).Unit
		pos = hover + away * (T.FLY_DIST * u ^ 2)
		bank = math.min(u * 2, 1) * 0.3
	end
	return CFrame.new(pos) * facing * CFrame.Angles(0, 0, bank)
end

-- how hard a watcher's camera shakes (0 .. 1): a hum while it hovers, a thud as it arrives,
-- a buzz up the beam, a kick as they are taken
function T.Shake(t)
	if t < 0 then return 0 end
	if t < T.ARRIVE + 0.3 then
		local k = (t - T.ARRIVE) / 0.3
		return (k >= 0) and 0.05 + 0.25 * (1 - k) ^ 2 or 0.05
	end
	if t < T.EXPLODE then return 0.05 + 0.12 * T.Lift(t) end
	local k = (t - T.EXPLODE) / 0.8
	return k < 1 and 0.55 * (1 - k) ^ 2 or 0
end

-- A watcher's camera: behind where the scooter stood (`yaw` round it, on `side`), further back
-- and higher as they go up, widening a little to keep the UFO in view. Returns the eye, the point
-- looked at, and how many degrees wider the view is.
function T.Camera(base, target, t, yaw, side)
	local look = base.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = flat.Magnitude > 0.05 and flat.Unit or Vector3.new(0, 0, -1)
	local heading = math.atan2(-flat.X, -flat.Z) + (yaw or 0)
	local fwd   = Vector3.new(-math.sin(heading), 0, -math.cos(heading))
	local right = Vector3.new(math.cos(heading), 0, -math.sin(heading))
	local lift  = smooth(T.Lift(t))
	local back  = 15 + 6 * lift
	local up    = 6 + 0.45 * T.Rise(math.min(t, T.EXPLODE))
	local eye   = base.Position - fwd * back + right * (5.2 * (side or 1)) + Vector3.new(0, up, 0)
	local fov   = 6 + 8 * lift
	if t >= T.EXPLODE then
		fov = fov + 6 * (1 - clamp01((t - T.EXPLODE) / 0.5))
	end
	return eye, target, fov
end

-- walls: exactly the rocket's
T.Clear        = R.Clear
T.Pulled       = R.Pulled
T.RISE_IN_WALL = R.RISE_IN_WALL

function T.BestSide(base, skip, yaw, prefer)
	return R.SideWithRoom(T, base, skip, yaw, prefer, { 0.3, T.LIFT_START + 0.5, T.EXPLODE - 0.05 })
end

return T
