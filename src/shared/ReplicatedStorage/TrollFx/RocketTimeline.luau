--=====================================================================
-- RocketTimeline   (ReplicatedStorage.TrollFx)
--
-- ROCKET LAUNCH second by second: one clock for the server (when the explosion is due, when
-- the death popup opens) and for every machine that shows it (StarterPlayerScripts.TrollFx:
-- the rocket and the scooter's climb; the Troll spectate camera; the two riders' own camera).
-- Times are seconds from the scooter's TrollStart attribute (server time). Nothing here moves
-- anything - it only says where things are at time t.
--
--   0 .. APPEAR       ALARM: the scooter stops dead; a red flash, beeps, sparks
--   APPEAR            the rocket booster pops out from under the scooter and stands it up
--                     on its nozzle (the scooter hops up onto it: `perch` studs)
--   .. IGNITE_END     it catches and builds: smoke, sparks, a growing flame, a rising roar
--   .. LIFT_END       LIFT-OFF: straight up RISE studs, level, slow then fast
--   EXPLODE           a cartoon explosion at the top: scooter, riders and booster are gone
--   END               the show is over: the death popup opens (DeathManager)
-- The server starts the clock LEAD seconds after the purchase, so every machine has the start
-- time before the show begins: purchase to popup is LEAD + END = 5 seconds.
--=====================================================================

local T = {}

T.LEAD       = 0.2
T.APPEAR     = 0.55
T.POP        = 0.3      -- the booster's pop-out, and the scooter's hop onto it
T.IGNITE_END = 1.7
T.LIFT_END   = 3.7
T.EXPLODE    = 3.7
T.END        = 4.8
T.RISE       = 100      -- studs, straight up
T.HOP        = 2.5      -- studs it jumps as it lights, before the climb

local function clamp01(x) return math.clamp(x, 0, 1) end
local function smooth(x)
	x = clamp01(x)
	return x * x * (3 - 2 * x)
end
T.Smooth = smooth

-- 0 .. 1 through the climb
function T.Lift(t)
	return clamp01((t - T.IGNITE_END) / (T.LIFT_END - T.IGNITE_END))
end

-- 0 .. 1 through the booster's pop-out, overshooting a little and settling (a springy hop)
function T.Pop(t)
	local u = clamp01((t - T.APPEAR) / T.POP)
	if u <= 0 then return 0 end
	local c1 = 1.9
	return 1 + (c1 + 1) * (u - 1) ^ 3 + c1 * (u - 1) ^ 2
end

-- studs above where it stood: up onto the booster (`perch`), then a hop as it lights, then
-- slow, then faster and faster
function T.Rise(t, perch)
	local r = (perch or 0) * T.Pop(t)
	local u = T.Lift(t)
	if u <= 0 then return r end
	return r + T.HOP * smooth(u / 0.1) + (T.RISE - T.HOP) * u ^ 2.2
end

-- how hard the scooter shakes (studs): a jitter in the alarm, growing through ignition, a
-- buzz in the climb
function T.Tremble(t)
	if t < 0 or t >= T.EXPLODE then return 0 end
	if t < T.APPEAR then return 0.035 end
	if t < T.IGNITE_END then return 0.035 + 0.1 * clamp01((t - T.APPEAR) / (T.IGNITE_END - T.APPEAR)) end
	return 0.05
end

-- The chassis at time t, from where it stood (`base`, its CFrame then): straight up in the
-- world, level, the tremble on top.
function T.Pose(base, t, perch)
	local tr = T.Tremble(t)
	local jitter = CFrame.identity
	if tr > 0 then
		jitter = CFrame.new(
			math.noise(t * 23, 1.3) * 2 * tr, math.noise(t * 27, 7.1) * 2 * tr, math.noise(t * 25, 4.7) * 2 * tr)
			* CFrame.Angles(math.noise(t * 19, 2.2) * tr * 0.15, 0, math.noise(t * 21, 9.4) * tr * 0.15)
	end
	return CFrame.new(0, T.Rise(t, perch), 0) * base * jitter
end

-- how hard a watcher's camera shakes (0 .. 1): the alarm and ignition build it, the climb
-- holds it, the explosion kicks it
function T.Shake(t)
	if t < 0 then return 0 end
	if t < T.IGNITE_END then return 0.06 + 0.3 * clamp01(t / T.IGNITE_END) end
	if t < T.EXPLODE then return 0.36 - 0.18 * T.Lift(t) end
	local k = (t - T.EXPLODE) / 0.9
	return k < 1 and 1.1 * (1 - k) ^ 2 or 0
end

-- A watcher's camera (the Troll spectate camera, the two riders' own): behind where the scooter
-- stood - `yaw` radians round it, on `side` (1 right, -1 left) - rising after it a little over
-- half as fast and looking at it all the way up, then at the explosion. `target` is the point
-- looked at. Returns the eye, that point, and how many degrees wider the view is.
function T.Camera(base, target, t, yaw, side)
	local look = base.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = flat.Magnitude > 0.05 and flat.Unit or Vector3.new(0, 0, -1)
	local heading = math.atan2(-flat.X, -flat.Z) + (yaw or 0)
	local fwd   = Vector3.new(-math.sin(heading), 0, -math.cos(heading))
	local right = Vector3.new(math.cos(heading), 0, -math.sin(heading))
	local build = smooth(t / T.IGNITE_END)
	local lift  = smooth(T.Lift(t))
	local back  = 13 + 4 * build + 7 * lift
	local up    = 8.6 + 1.4 * build + 0.6 * T.Rise(math.min(t, T.EXPLODE))
	local eye   = base.Position - fwd * back + right * (5.2 * (side or 1)) + Vector3.new(0, up, 0)
	local fov   = 12 * lift
	if t >= T.EXPLODE then
		-- a punch at the explosion, then back to the normal view before the popup takes over
		local k = clamp01((t - T.EXPLODE) / 0.9)
		fov = fov * (1 - smooth(k)) + 10 * (1 - clamp01((t - T.EXPLODE) / 0.5))
	end
	return eye, target, fov
end

-- Where a camera at `eye` looking at `look` can really be: pulled in toward `look`, in front of
-- the first solid, visible thing between them (never nearer than `min` studs). `skip` is what it
-- sees through (the scooter, the players, the booster, invisible walls - added to as it goes).
-- Returns the eye and how much of the way (0 .. 1) is clear.
function T.Clear(eye, look, skip, min)
	local dir = eye - look
	local len = dir.Magnitude
	if len < 1e-3 then return eye, 1 end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true   -- triggers and kill zones never count
	for _ = 1, 4 do
		params.FilterDescendantsInstances = skip
		local hit = workspace:Raycast(look, dir, params)
		if not hit then return eye, 1 end
		if hit.Instance.Transparency < 0.9 then
			local d = math.max((hit.Position - look).Magnitude - 0.8, math.min(min or 4, len))
			return look + dir / len * d, d / len
		end
		table.insert(skip, hit.Instance)
	end
	return eye, 1
end

-- A camera pulled in by a wall (`room`: how much of the way is clear) also rises - up to RISE_
-- IN_WALL studs - so it looks down over the wall at the scooter instead of sitting on its back.
T.RISE_IN_WALL = 8
function T.Pulled(eye, look, room)
	return look + (eye - look) * room + Vector3.new(0, (1 - room) * T.RISE_IN_WALL, 0)
end

-- The side (1 right, -1 left) where a show's camera has the most room at the moments in
-- `samples` - any show's clock `tl` with Rise and Camera (this one, ExplodeTimeline) - so it
-- never ends up inside a cliff beside a parking bay.
function T.SideWithRoom(tl, base, skip, yaw, prefer, samples)
	local room = {}
	for _, side in ipairs({ 1, -1 }) do
		local total = 0
		for _, t in ipairs(samples) do
			local target = base.Position + Vector3.new(0, tl.Rise(t) + 2, 0)
			local eye = tl.Camera(base, target, t, yaw, side)
			local _, share = T.Clear(eye, target, table.clone(skip), 0)
			total += share
		end
		room[side] = total
	end
	prefer = prefer or 1
	return (room[-prefer] > room[prefer] + 0.3) and -prefer or prefer
end

-- this show's: at the start, at lift-off and at the top
function T.BestSide(base, skip, yaw, prefer)
	return T.SideWithRoom(T, base, skip, yaw, prefer, { 0.5, T.IGNITE_END, T.EXPLODE - 0.05 })
end

return T
