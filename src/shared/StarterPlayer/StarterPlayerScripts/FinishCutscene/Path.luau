--=====================================================================
-- FinishCutscene / Path
--
-- The line the cinematic scooter rolls along: the last stretch of the road it really
-- came in on (FinishLine's recording, smoothed), then on past the finish, drifting
-- toward the middle of it and straightening out along the gate. Where too little was
-- recorded (they set off close to the line) the rest is laid straight along the gate.
-- Every laid point sits on the ground under it at the height the chassis rides (a ray
-- down that looks past scooters, characters and anything that doesn't collide).
--   path:At(s)     the chassis CFrame s studs along, looking along the path
--   path:Bend(s)   how fast the heading turns there (radians a stud, + = left)
--   path.Cross     s of the finish line;  path.Length  the whole path
--=====================================================================

local Path = {}
Path.__index = Path

local STEP   = 0.25   -- studs between the finished path's points
local LAY    = 0.5    -- studs between laid (unrecorded) points
local SMOOTH = 3      -- points averaged each side (1.5 studs), taking the wobble out of the real line

local function flat(v) return Vector3.new(v.X, 0, v.Z) end
local function unit(v, fallback) return v.Magnitude > 1e-4 and v.Unit or fallback end

-- crossing: FinishLine's. behind: studs of road wanted before the line. pastLine: studs
-- wanted after it. laneClamp: how far off the gate's middle it may end. ignore: what the
-- ground rays look past.
function Path.Build(crossing, behind, pastLine, laneClamp, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	params.IgnoreWater = true
	local function groundY(p)
		local hit = workspace:Raycast(p + Vector3.new(0, 4, 0), Vector3.new(0, -16, 0), params)
		return hit and hit.Position.Y
	end

	local gateCF = crossing.GateCF
	local fwd = unit(flat(gateCF.LookVector), Vector3.new(0, 0, -1))
	local C = crossing.Point
	-- how high the chassis rides over the ground, for the points that are laid
	local ride = 1.28
	local gy = groundY(C)
	if gy then ride = math.clamp(C.Y - gy, 0.6, 3) end
	local function onGround(p)
		local y = groundY(p)
		return y and Vector3.new(p.X, y + ride, p.Z) or p
	end

	-- 1) the recorded road in, newest first, back past `behind` (and a little, for smoothing)
	local want = behind + 3
	local back, len = { C }, 0
	local rec = crossing.Approach
	for i = #rec - 1, 1, -1 do
		local p = rec[i].pos
		len += (p - back[#back]).Magnitude
		table.insert(back, p)
		if len >= want then break end
	end
	-- 2) too little of it: straight on back the way it came (or square to the gate)
	local dir = (#back >= 3) and unit(flat(back[#back] - back[#back - 2]), -fwd) or -fwd
	while len < want do
		table.insert(back, onGround(back[#back] + dir * LAY))
		len += LAY
	end
	local pts = {}
	for i = #back, 1, -1 do table.insert(pts, back[i]) end
	local crossIndex = #pts

	-- 3) past the line: leaving the way it came in, bending toward the middle of the finish
	--    and straightening out along the gate
	local inDir = unit(flat(C - pts[math.max(1, crossIndex - 2)]), fwd)
	local lane = math.clamp(crossing.Lateral, -laneClamp, laneClamp)
	local E = gateCF * Vector3.new(lane, gateCF:PointToObjectSpace(C).Y, -pastLine)
	local L = (E - C).Magnitude
	local n = math.max(2, math.ceil(L / LAY))
	for i = 1, n do
		local u = i / n
		local u2, u3 = u * u, u * u * u
		local p = C * (2 * u3 - 3 * u2 + 1) + inDir * (L * (u3 - 2 * u2 + u))
			+ E * (-2 * u3 + 3 * u2) + fwd * (L * (u3 - u2))
		table.insert(pts, onGround(p))
	end

	-- 4) smoothed: each point the average of its neighbours (fewer toward the ends)
	local sm = {}
	for i = 1, #pts do
		local k = math.min(SMOOTH, i - 1, #pts - i)
		local sum = Vector3.zero
		for j = i - k, i + k do sum += pts[j] end
		sm[i] = sum / (2 * k + 1)
	end

	-- 5) evenly spaced by distance, for quick lookups
	local cum = { 0 }
	for i = 2, #sm do cum[i] = cum[i - 1] + (sm[i] - sm[i - 1]).Magnitude end
	local P, j = {}, 1
	for k = 0, math.floor(cum[#cum] / STEP) do
		local s = k * STEP
		while j < #sm - 1 and cum[j + 1] < s do j += 1 end
		local seg = cum[j + 1] - cum[j]
		local u = (seg > 1e-4) and math.clamp((s - cum[j]) / seg, 0, 1) or 0
		P[k + 1] = sm[j]:Lerp(sm[j + 1], u)
	end
	return setmetatable({ P = P, Length = (#P - 1) * STEP, Cross = cum[crossIndex], Forward = fwd }, Path)
end

function Path:Point(s)
	local f = math.clamp(s / STEP, 0, #self.P - 1)
	local i = math.floor(f)
	local a = self.P[i + 1]
	local b = self.P[math.min(i + 2, #self.P)]
	return a:Lerp(b, f - i)
end

function Path:Direction(s)
	return unit(self:Point(s + 0.6) - self:Point(s - 0.6), self.Forward)
end

function Path:At(s)
	local p = self:Point(s)
	return CFrame.lookAt(p, p + self:Direction(s))
end

function Path:Bend(s)
	local a, b = flat(self:Direction(s - 1)), flat(self:Direction(s + 1))
	if a.Magnitude < 1e-3 or b.Magnitude < 1e-3 then return 0 end
	a, b = a.Unit, b.Unit
	return math.atan2(a:Cross(b).Y, a:Dot(b)) / 2   -- + = turning left (anticlockwise from above)
end

return Path
