--=====================================================================
-- ReviveSpot   (ScooterSystem, server)
--
-- Where a revived ride comes back (DeathManager). Never where it died: a safe spot a little
-- way BACK along the course, so the pair replays a short stretch instead of reappearing
-- inside whatever killed them.
--
--   The course   the course's own line (CourseProgress.CoursePath: start gate to finish, a
--                point every 2 studs). Every ride is followed along it while its scooter is on
--                solid ground (every TRACK_EVERY s), so when it goes down we know how far along
--                the course the trouble STARTED - where it was last driving, not where a hammer
--                threw it or where it sank (Incident).
--   The search   from BACK_MIN studs behind that point, backwards along the line, a candidate
--                every STEP studs, never behind where the ride started nor more than
--                REACHED_SLACK behind the checkpoint it last reached. The first one that passes
--                every check wins.
--   The checks   for the scooter with both riders standing on it:
--                  hazards   not inside any obstacle's zone - everything tagged "Hazard" (its
--                            box, or its HazardZone parts - see below - plus its HazardMargin
--                            attribute, default ZONE_MARGIN) and any obstacle that has killed
--                            a ride (DeathManager.Hit passes it) - and no kill part near it
--                            (KillZone / Landmine parts within KILL_MARGIN, a KillGate within
--                            GATE_MARGIN)
--                  ground    solid ground under both wheels and both sides, level enough, not
--                            water, a kill part or an obstacle
--                  room      nothing solid where the scooter and its riders would be
--                  players   no other player or scooter within CLEAR_RADIUS
--                  moving    nothing round it moves for MOTION_WAIT seconds (an obstacle the
--                            server moves, a moving platform, a rolling boulder)
--   Fallback     the checkpoint lot the ride last reached: its clearest parking bay (where
--                rides start anyway).
--
-- A new obstacle: tag its model "Hazard" (a HazardMargin number attribute sets how much room
-- it gets; a RunUp number attribute keeps revives that many studs further back along the
-- course in front of it, for things that must be crossed at speed - the Rotten Bridge),
-- or have its script pass it: DeathManager.Hit(ride, obstacle). A tagged model's
-- whole box is its zone - unless it holds parts named "HazardZone" (invisible, not solid,
-- not queried): then exactly those boxes are, and the rest of the model (its road, its
-- scenery) counts as ordinary ground. Use them where the danger covers only part of a big
-- model: each dart's flight, each log's swing, the lane the boulders roll across. Parts
-- tagged KillZone, KillGate, Landmine, WaterHazard and RottenPlank (planks that give way
-- under a scooter: solid here on the server, broken on the riders' screens) are known already.
--=====================================================================

local CollectionService   = game:GetService("CollectionService")
local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local RS                  = game:GetService("ReplicatedStorage")

local Shared      = RS:WaitForChild("ScooterSystem"):WaitForChild("Shared")
local Config      = require(Shared:WaitForChild("Config"))
local Checkpoints = require(Shared:WaitForChild("Checkpoints"))
local CoursePath  = require(ServerScriptService:WaitForChild("CourseProgress"):WaitForChild("CoursePath"))

local RideManager        = require(script.Parent:WaitForChild("RideManager"))
local CheckpointProgress = require(script.Parent:WaitForChild("CheckpointProgress"))
local CollisionGroups    = require(script.Parent:WaitForChild("CollisionGroups"))

local HAZARD_TAG    = "Hazard"
local ZONE_MARGIN   = 6       -- studs kept clear round a Hazard's box (unless it says otherwise)
local KILL_MARGIN   = 3       -- ...round a kill part (KillZone, Landmine)
local GATE_MARGIN   = 8       -- ...round a laser gate
local BACK_MIN      = 12      -- at least this far back along the course from where the trouble started
local STEP          = 1       -- studs between candidates (fine enough not to step over a narrow safe gap)
local REACHED_SLACK = 40      -- how far behind the last checkpoint reached the search may go
local CLEAR_RADIUS  = 12      -- studs kept from any other player or scooter (centre to centre)
local MAX_SLOPE     = 32      -- degrees
local MOTION_WAIT   = 0.25    -- seconds a spot's surroundings are watched for movement
local MOTION_REACH  = 6       -- studs round the scooter that must be standing still
local MOTION_TRIES  = 8       -- watches per search at most (then the lot)
local LEARN_MAX     = 160     -- an obstacle bigger than this (studs) is never learned as a zone
local TRACK_EVERY   = 0.25    -- seconds between samples of where each ride is
local TRACK_KEEP    = 40      -- samples kept (10 s)
local REACQUIRE     = 20      -- studs off the line where it was expected: look for it again, further
-- the scooter with both riders standing on it, in the chassis' own space (measured on the
-- scooter models: wheels 1.28 below the chassis origin, 2.9 wide, 6.8 long; riders ~6 tall).
-- The box starts 0.7 above the wheels, so the road itself is never "in the way".
local WHEEL_OFFSET  = 2.2     -- studs from the middle to each wheel along the deck
local SIDE_OFFSET   = 1.4     -- ground is checked this far to either side
local BODY_CENTRE   = CFrame.new(0, 2.9, -0.3)
local BODY_SIZE     = Vector3.new(3.4, 7, 7.2)
local PROBES = {               -- points of that box tested against the obstacles' zones
	Vector3.new(0, 0, 0), Vector3.new(0, 0, -3.6), Vector3.new(0, 0, 3.6),
	Vector3.new(-1.7, 0, 0), Vector3.new(1.7, 0, 0), Vector3.new(0, -3, 0),
}
local BREAK_MARGIN  = 3       -- ...round a plank that gives way under a scooter (RottenPlank)
local MARGIN = { kill = KILL_MARGIN, mine = KILL_MARGIN, gate = GATE_MARGIN, hazard = ZONE_MARGIN, breaks = BREAK_MARGIN }
-- the order a part's tags are read in: the widest berth wins when there are two
local KIND_TAGS = {
	{ HAZARD_TAG, "hazard" }, { "KillGate", "gate" }, { "Landmine", "mine" }, { "KillZone", "kill" },
	{ "RottenPlank", "breaks" },   -- the Rotten Bridge: solid on the server, but it breaks under a scooter
}

local ReviveSpot = {}

local function log(...) if Config.DebugLogging then print("[Revive]", ...) end end

---------------------------------------------------------------- the course
local P = CoursePath.Points
local S = { 0 }             -- studs along the line at each point
for i = 2, #P do S[i] = S[i - 1] + (P[i] - P[i - 1]).Magnitude end
local LENGTH = S[#P]

local function checkpointS(order)
	return CoursePath.Checkpoints[order] or 0
end

-- the first point at or past `s`
local function indexAt(s)
	local lo, hi = 1, #P
	while lo < hi do
		local mid = (lo + hi) // 2
		if S[mid] < s then lo = mid + 1 else hi = mid end
	end
	return lo
end

local function pointAt(s)
	s = math.clamp(s, 0, LENGTH)
	local i = math.max(2, indexAt(s))
	local seg = S[i] - S[i - 1]
	return P[i - 1]:Lerp(P[i], seg > 0 and (s - S[i - 1]) / seg or 0)
end

-- studs along the line of the point on it nearest `pos`, looking only between sMin and sMax
local function measure(pos, sMin, sMax)
	sMin, sMax = math.max(0, sMin), math.min(LENGTH, sMax)
	local first = math.max(1, indexAt(sMin) - 1)
	local last = math.min(#P, indexAt(sMax))
	local bestS, bestD = sMin, math.huge
	for i = first, last - 1 do
		local a, b = P[i], P[i + 1]
		local ab = b - a
		local len2 = ab:Dot(ab)
		local t = (len2 > 0) and math.clamp((pos - a):Dot(ab) / len2, 0, 1) or 0
		local d = (a + ab * t - pos).Magnitude
		if d < bestD then
			bestD = d
			bestS = S[i] + (S[i + 1] - S[i]) * t
		end
	end
	return math.clamp(bestS, sMin, sMax), bestD
end

---------------------------------------------------------------- what things are
CollisionGroups.Ensure()

-- what a scooter would roll on: solid parts it collides with - never a character, never
-- another scooter (neither collides with a scooter), never a boulder catcher
local groundRay = RaycastParams.new()
groundRay.CollisionGroup = CollisionGroups.Body
groundRay.RespectCanCollide = true
groundRay.FilterType = Enum.RaycastFilterType.Exclude

local solidQuery = OverlapParams.new()   -- anything the scooter would be stuck in
solidQuery.CollisionGroup = CollisionGroups.Body
solidQuery.RespectCanCollide = true
solidQuery.FilterType = Enum.RaycastFilterType.Exclude

local anyQuery = OverlapParams.new()     -- everything, solid or not (kill parts often aren't)
anyQuery.RespectCanCollide = false
anyQuery.FilterType = Enum.RaycastFilterType.Exclude

local learned   = setmetatable({}, { __mode = "k" })   -- [instance] = true: obstacles that have killed a ride
local kindCache = setmetatable({}, { __mode = "k" })   -- [part] = kind or false
local zoneCache = setmetatable({}, { __mode = "k" })   -- [obstacle] = its HazardZone parts (maybe none)

-- a tagged obstacle's HazardZone parts: exactly where its danger is (none: all of it)
local function zonePartsOf(inst)
	local list = zoneCache[inst]
	if not list then
		list = {}
		for _, d in ipairs(inst:GetDescendants()) do
			if d.Name == "HazardZone" and d:IsA("BasePart") then table.insert(list, d) end
		end
		zoneCache[inst] = list
	end
	return list
end

-- "water", "hazard", "gate", "mine", "kill", "breaks" or nil: what touching this part would
-- mean - and the tagged thing it belongs to (its HazardMargin, if it has one, is its berth)
local function kindOf(part)
	local cached = kindCache[part]
	if cached ~= nil then
		if cached then return cached[1], cached[2] end
		return nil
	end
	local kind, owner = nil, nil
	if CollectionService:HasTag(part, "WaterHazard") then kind, owner = "water", part end
	local node = part
	while not kind and node and node ~= workspace do
		for _, t in ipairs(KIND_TAGS) do
			-- an obstacle that marks its danger with HazardZone parts: the rest of it is
			-- ordinary ground and scenery
			if CollectionService:HasTag(node, t[1]) and not (t[2] == "hazard" and #zonePartsOf(node) > 0) then
				kind, owner = t[2], node
				break
			end
		end
		if not kind and learned[node] then kind, owner = "hazard", node end
		node = node.Parent
	end
	kindCache[part] = kind and { kind, owner } or false
	return kind, owner
end
local function forget() table.clear(kindCache) table.clear(zoneCache) end
CollectionService:GetInstanceAddedSignal(HAZARD_TAG):Connect(forget)
CollectionService:GetInstanceRemovedSignal(HAZARD_TAG):Connect(forget)

local function inWater(pos)
	for _, w in ipairs(CollectionService:GetTagged("WaterHazard")) do
		if w:IsA("BasePart") then
			local p, h = w.CFrame:PointToObjectSpace(pos), w.Size / 2
			if math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y + 0.5 and math.abs(p.Z) <= h.Z then return true end
		end
	end
	return false
end

-- the box round an instance (a Model's own, a part's, or round a Folder's parts)
local function boxOf(inst)
	if inst:IsA("BasePart") then return inst.CFrame, inst.Size end
	if inst:IsA("Model") then
		local ok, cf, size = pcall(inst.GetBoundingBox, inst)
		if ok and size.Magnitude > 0 then return cf, size end
		return nil
	end
	local lo, hi
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			local cf, sz = d.CFrame, d.Size
			local e = Vector3.new(
				math.abs(cf.RightVector.X) * sz.X + math.abs(cf.UpVector.X) * sz.Y + math.abs(cf.LookVector.X) * sz.Z,
				math.abs(cf.RightVector.Y) * sz.X + math.abs(cf.UpVector.Y) * sz.Y + math.abs(cf.LookVector.Y) * sz.Z,
				math.abs(cf.RightVector.Z) * sz.X + math.abs(cf.UpVector.Z) * sz.Y + math.abs(cf.LookVector.Z) * sz.Z) / 2
			lo = lo and lo:Min(cf.Position - e) or cf.Position - e
			hi = hi and hi:Max(cf.Position + e) or cf.Position + e
		end
	end
	if not lo then return nil end
	return CFrame.new((lo + hi) / 2), hi - lo
end

-- every obstacle's zone, read fresh for each search (some of them move)
local zones = {}
-- stretches of the course just before an obstacle with a RunUp attribute (you can't come
-- back there: it has to be crossed at speed, and a scooter standing in front of it couldn't
-- get up to speed in time): { from, to, name } in studs along the course
local runUps = {}
local function readZones()
	table.clear(zones)
	table.clear(runUps)
	-- `box`: what the zone is the box of; `inst`: the obstacle it belongs to
	local function add(box, inst)
		local cf, size = boxOf(box)
		if not cf then return end
		local margin = tonumber(inst:GetAttribute("HazardMargin")) or ZONE_MARGIN
		table.insert(zones, { inst = inst, cf = cf, half = size / 2 + Vector3.one * margin })
	end
	for _, inst in ipairs(CollectionService:GetTagged(HAZARD_TAG)) do
		if inst:IsDescendantOf(workspace) then
			local first = #zones + 1
			local parts = zonePartsOf(inst)
			if #parts > 0 then
				for _, p in ipairs(parts) do add(p, inst) end
			else
				add(inst, inst)
			end
			-- driving forward, wherever the course comes into this obstacle's zones: the RunUp
			-- studs before that are left out too
			local runUp = tonumber(inst:GetAttribute("RunUp"))
			if runUp and runUp > 0 then
				local was = false
				for i = 1, #P do
					local q, inside = P[i] + Vector3.new(0, 3, 0), false
					for k = first, #zones do
						local z = zones[k]
						local p = z.cf:PointToObjectSpace(q)
						if math.abs(p.X) <= z.half.X and math.abs(p.Y) <= z.half.Y and math.abs(p.Z) <= z.half.Z then
							inside = true
							break
						end
					end
					if inside and not was then
						table.insert(runUps, { from = S[i] - runUp, to = S[i], name = inst.Name })
					end
					was = inside
				end
			end
		end
	end
	for inst in pairs(learned) do
		if inst:IsDescendantOf(workspace) then add(inst, inst) end
	end
end

local function zoneAt(point)
	for _, z in ipairs(zones) do
		local p = z.cf:PointToObjectSpace(point)
		if math.abs(p.X) <= z.half.X and math.abs(p.Y) <= z.half.Y and math.abs(p.Z) <= z.half.Z then return z end
	end
	return nil
end

local function runUpAt(s)
	for _, r in ipairs(runUps) do
		if s >= r.from and s <= r.to then return r end
	end
	return nil
end

---------------------------------------------------------------- following each ride
local tracks = setmetatable({}, { __mode = "k" })   -- [ride] = { s, t, hist = { {t, s} } }

local function reachedOf(ride)
	return CheckpointProgress.RideReached(ride) or Checkpoints.OrderOf(ride.CheckpointId) or 1
end

local function track(ride)
	local chassis = ride.Scooter and ride.Scooter.PrimaryPart
	if not chassis then return end
	local pos = chassis.Position
	-- only while it is driving on something: not thrown, falling or sinking
	groundRay.FilterDescendantsInstances = {}
	local hit = workspace:Raycast(pos + Vector3.new(0, 0.5, 0), Vector3.new(0, -4.5, 0), groundRay)
	if not hit or inWater(pos) then return end
	local tr = tracks[ride]
	if not tr then
		tr = { hist = {} }
		tracks[ride] = tr
	end
	local s, off
	if tr.s then s, off = measure(pos, tr.s - 30, tr.s + 60) end
	-- first sight, or far off the line where it was expected (it got there some other way
	-- than driving): look along the whole stretch it can be on
	if not s or off > REACQUIRE then
		local reached = reachedOf(ride)
		local s2, off2 = measure(pos, checkpointS(reached) - 30, (CoursePath.Checkpoints[reached + 1] or LENGTH) + 10)
		if not s or off2 < off then s = s2 end
	end
	tr.s, tr.t = s, os.clock()
	table.insert(tr.hist, { t = tr.t, s = s })
	if #tr.hist > TRACK_KEEP then table.remove(tr.hist, 1) end
end

local sinceTrack = 0
RunService.Heartbeat:Connect(function(dt)
	sinceTrack += dt
	if sinceTrack < TRACK_EVERY then return end
	sinceTrack = 0
	for _, ride in pairs(RideManager.Rides) do
		if not ride._ended and not ride.Down then
			local ok, err = pcall(track, ride)
			if not ok then warn("[Revive] tracking: " .. tostring(err)) end
		end
	end
end)

-- How far along the course (studs) this ride was when last driving - where its trouble
-- started. nil before it has been seen on the ground.
function ReviveSpot.Incident(ride)
	local tr = ride and tracks[ride]
	return tr and tr.s or nil
end

-- The ride carries on from `s` (a revive): follow it from there.
function ReviveSpot.Relaunched(ride, s)
	if not ride then return end
	tracks[ride] = { s = s, t = os.clock(), hist = {} }
end

-- An obstacle that killed a ride (DeathManager.Hit's `source`). Unless it is already known
-- (tagged, or a kill part handled part by part) or huge, its box becomes a zone too.
function ReviveSpot.Learn(source)
	if typeof(source) ~= "Instance" or source == workspace or not source:IsDescendantOf(workspace) then return end
	if learned[source] then return end
	local node = source
	while node and node ~= workspace do
		if CollectionService:HasTag(node, "WaterHazard") then return end
		for _, t in ipairs(KIND_TAGS) do
			if CollectionService:HasTag(node, t[1]) then return end
		end
		node = node.Parent
	end
	local _, size = boxOf(source)
	if not size or size.X > LEARN_MAX or size.Y > LEARN_MAX or size.Z > LEARN_MAX then return end
	learned[source] = true
	table.clear(kindCache)
	log("new obstacle learned:", source:GetFullName())
end

---------------------------------------------------------------- one spot
-- what a search leaves out of every check: the scooters (they are ghosts to each other, and
-- have their own clearance check) and every character
local function context(ride)
	local sys = workspace:FindFirstChild("RideSystem")
	local bin = sys and sys:FindFirstChild("Scooters")
	local exclude = {}
	if bin then table.insert(exclude, bin) end
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then table.insert(exclude, plr.Character) end
	end
	local riders = {}
	if ride then
		if ride.Driver then riders[ride.Driver] = true end
		if ride.Passenger then riders[ride.Passenger] = true end
	end
	-- an invisible box the overlap checks use (precise, unlike bounding boxes)
	local probe = Instance.new("Part")
	probe.Name = "ReviveProbe"
	probe.Anchored, probe.CanCollide, probe.CanTouch, probe.CanQuery = true, false, false, false
	probe.Transparency = 1
	probe.CastShadow = false
	probe.Parent = workspace
	return { exclude = exclude, riders = riders, scooter = ride and ride.Scooter, bin = bin, probe = probe }
end

local function groundAt(q, ctx)
	groundRay.FilterDescendantsInstances = ctx.exclude
	local hit = workspace:Raycast(q + Vector3.new(0, 4, 0), Vector3.new(0, -12, 0), groundRay)
	if not hit then return nil, "no ground" end
	if hit.Normal.Y < math.cos(math.rad(MAX_SLOPE)) then return nil, "too steep" end
	local kind = kindOf(hit.Instance)
	if kind then return nil, "on a " .. kind end
	if inWater(hit.Position + Vector3.new(0, 0.2, 0)) then return nil, "in the water" end
	return hit.Position
end

-- The scooter standing on the course at `s`, facing along it: its chassis CFrame, or nil and why.
local function place(s, ctx)
	local p = pointAt(s)
	local d = pointAt(s + 2) - pointAt(s - 2)
	local flat = Vector3.new(d.X, 0, d.Z)
	if flat.Magnitude < 0.5 then return nil, "no heading" end
	local fwd = flat.Unit
	local right = fwd:Cross(Vector3.yAxis)
	local front, why = groundAt(p + fwd * WHEEL_OFFSET, ctx)
	if not front then return nil, "front wheel: " .. why end
	local rear
	rear, why = groundAt(p - fwd * WHEEL_OFFSET, ctx)
	if not rear then return nil, "rear wheel: " .. why end
	local mid
	mid, why = groundAt(p, ctx)
	if not mid then return nil, "middle: " .. why end
	for _, side in ipairs({ -1, 1 }) do
		local g
		g, why = groundAt(p + right * (SIDE_OFFSET * side), ctx)
		if not g then return nil, "side: " .. why end
		if math.abs(g.Y - mid.Y) > 1.2 then return nil, "uneven sideways" end
	end
	if math.abs(mid.Y - (front.Y + rear.Y) / 2) > 0.8 then return nil, "bumpy" end
	local along = front - rear
	if along.Magnitude < 1 then return nil, "no heading" end
	if math.deg(math.asin(math.clamp(math.abs(along.Unit.Y), 0, 1))) > MAX_SLOPE then return nil, "too steep" end
	local centre = (front + rear) / 2
	local cf = CFrame.lookAt(centre, centre + along.Unit)
	return cf + cf.UpVector * Config.ScooterLift
end

-- how far `point` lies outside the scooter's box `body`
local function outside(body, point)
	local p, h = body:PointToObjectSpace(point), BODY_SIZE / 2
	return Vector3.new(math.max(math.abs(p.X) - h.X, 0), math.max(math.abs(p.Y) - h.Y, 0), math.max(math.abs(p.Z) - h.Z, 0)).Magnitude
end

-- the nearest a part comes to the scooter's box (from its middle and both ends)
local function gap(body, part)
	local best = math.huge
	for _, z in ipairs({ 0, -3.6, 3.6 }) do
		local from = (body * CFrame.new(0, 0, z)).Position
		local ok, p = pcall(part.GetClosestPointOnSurface, part, from)
		best = math.min(best, outside(body, ok and p or part.Position))
	end
	return best
end

-- Every check but the movement watch, for a chassis CFrame: true, or false and why.
local function check(cf, ctx)
	local body = cf * BODY_CENTRE
	-- inside an obstacle's zone?
	for _, off in ipairs(PROBES) do
		local z = zoneAt(body * off)
		if z then return false, "inside " .. z.inst.Name end
	end
	local probe = ctx.probe
	-- room: nothing solid where the scooter and riders would be
	probe.Size, probe.CFrame = BODY_SIZE, body
	solidQuery.FilterDescendantsInstances = ctx.exclude
	local solid = workspace:GetPartsInPart(probe, solidQuery)
	if #solid > 0 then return false, "blocked by " .. solid[1].Name end
	-- no kill part or obstacle close by
	probe.Size = BODY_SIZE + Vector3.one * (2 * math.max(ZONE_MARGIN, GATE_MARGIN, KILL_MARGIN))
	anyQuery.FilterDescendantsInstances = ctx.exclude
	for _, part in ipairs(workspace:GetPartsInPart(probe, anyQuery)) do
		local kind, owner = kindOf(part)
		if kind and kind ~= "water" then
			local margin = (owner and tonumber(owner:GetAttribute("HazardMargin"))) or MARGIN[kind]
			if gap(body, part) < margin then
				return false, "near a " .. kind .. " (" .. part.Parent.Name .. ")"
			end
		end
	end
	-- no other player or scooter close by
	for _, plr in ipairs(Players:GetPlayers()) do
		if not ctx.riders[plr] then
			local ch = plr.Character
			local hum = ch and ch:FindFirstChildOfClass("Humanoid")
			local root = ch and ch:FindFirstChild("HumanoidRootPart")
			if root and hum and hum.Health > 0 and (root.Position - cf.Position).Magnitude < CLEAR_RADIUS then
				return false, "too close to " .. plr.Name
			end
		end
	end
	if ctx.bin then
		for _, sc in ipairs(ctx.bin:GetChildren()) do
			local pp = sc:IsA("Model") and sc ~= ctx.scooter and sc.PrimaryPart
			if pp and (pp.Position - cf.Position).Magnitude < CLEAR_RADIUS then
				return false, "too close to another scooter"
			end
		end
	end
	return true
end

-- nothing round the spot moves for MOTION_WAIT seconds (yields)
local function still(cf, ctx)
	local probe = ctx.probe
	local body = cf * BODY_CENTRE
	probe.Size, probe.CFrame = BODY_SIZE + Vector3.one * (2 * MOTION_REACH), body
	anyQuery.FilterDescendantsInstances = ctx.exclude
	local before = {}
	for _, part in ipairs(workspace:GetPartsInPart(probe, anyQuery)) do before[part] = part.CFrame end
	task.wait(MOTION_WAIT)
	probe.Size, probe.CFrame = BODY_SIZE + Vector3.one * (2 * MOTION_REACH), body
	anyQuery.FilterDescendantsInstances = ctx.exclude
	local seen = {}
	for _, part in ipairs(workspace:GetPartsInPart(probe, anyQuery)) do
		local was = before[part]
		if not was then return false, "something came in (" .. part.Name .. ")" end
		local now = part.CFrame
		if (now.Position - was.Position).Magnitude > 0.05 or now.LookVector:Dot(was.LookVector) < 0.9995
			or now.UpVector:Dot(was.UpVector) < 0.9995 then
			return false, "moving (" .. part:GetFullName() .. ")"
		end
		seen[part] = true
	end
	for part in pairs(before) do
		if part.Parent and not seen[part] then return false, "moving (" .. part:GetFullName() .. ")" end
	end
	return true
end

---------------------------------------------------------------- the lot
-- The clearest parking bay of checkpoint `order`'s lot (or its start part without bays).
local function lotSpot(ride, order, ctx)
	local cp = Checkpoints.ByOrder(order) or Checkpoints.GetById(ride.CheckpointId)
	if not cp then return nil end
	local parts = {}
	if cp.BayPrefix then
		local sys = workspace:FindFirstChild("RideSystem")
		local locs = sys and sys:FindFirstChild("StartLocations")
		for i = 1, 12 do
			local name = cp.BayPrefix .. i
			local p = (locs and locs:FindFirstChild(name, true)) or workspace:FindFirstChild(name, true)
			if p and p:IsA("BasePart") then table.insert(parts, p) end
		end
	end
	if #parts == 0 and cp.SpawnPartName then
		local p = workspace:FindFirstChild(cp.SpawnPartName, true)
		if p and p:IsA("BasePart") then table.insert(parts, p) end
	end
	local best, bestRoom
	for _, part in ipairs(parts) do
		local a = part:FindFirstChild("ScooterSpawn")
		local base = a and a.WorldCFrame or part.CFrame
		local cf = CFrame.new(base.Position + Vector3.new(0, Config.ScooterLift, 0)) * base.Rotation
		-- room: the nearest other player or scooter
		local room = math.huge
		for _, plr in ipairs(Players:GetPlayers()) do
			local root = not ctx.riders[plr] and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
			if root then room = math.min(room, (root.Position - cf.Position).Magnitude) end
		end
		for _, sc in ipairs(ctx.bin and ctx.bin:GetChildren() or {}) do
			local pp = sc:IsA("Model") and sc ~= ctx.scooter and sc.PrimaryPart
			if pp then room = math.min(room, (pp.Position - cf.Position).Magnitude) end
		end
		if not bestRoom or room > bestRoom then best, bestRoom = cf, room end
	 end
	return best
end

---------------------------------------------------------------- the search
local function search(ride, incidentS, ctx)
	readZones()
	local startOrder = Checkpoints.OrderOf(ride.CheckpointId) or 1
	local reached = reachedOf(ride)
	local lower = math.max(checkpointS(startOrder), checkpointS(reached) - REACHED_SLACK, 0)
	local from = (incidentS or lower) - BACK_MIN
	local why, rejected, watches = nil, {}, 0
	local s = from
	while s >= lower do
		local cf
		local ru = runUpAt(s)
		if ru then
			why = "in the run-up to " .. ru.name
		else
			cf, why = place(s, ctx)
		end
		if cf then
			local ok
			ok, why = check(cf, ctx)
			if ok then
				if watches >= MOTION_TRIES then why = "too much moving about" break end
				watches += 1
				ok, why = still(cf, ctx)
				if ok then
					return cf, { s = s, back = (incidentS or s) - s, rejected = rejected }
				end
			end
		end
		local key = tostring(why):gsub(" %b()", "")
		rejected[key] = (rejected[key] or 0) + 1
		s -= STEP
	end
	local cf = lotSpot(ride, reached, ctx)
	return cf, { lot = reached, s = cf and measure(cf.Position, checkpointS(reached) - 60, checkpointS(reached) + 60) or nil, rejected = rejected }
end

-- The safe spot for this ride to come back at: a chassis CFrame and { s = studs along the
-- course, back = how far behind the trouble, lot = the checkpoint whose lot it fell back on,
-- rejected = { why = count } }, or nil. `incidentS` defaults to the ride's own Incident.
-- Yields a little (the movement watch).
function ReviveSpot.Find(ride, incidentS)
	local ctx = context(ride)
	local ok, cf, info = pcall(search, ride, incidentS or ReviveSpot.Incident(ride), ctx)
	ctx.probe:Destroy()
	if not ok then
		warn("[Revive] the search failed: " .. tostring(cf))
		return nil
	end
	return cf, info
end

-- Is this chassis CFrame still clear right now (no movement watch)? true, or false and why.
function ReviveSpot.StillSafe(cf, ride)
	readZones()
	local ctx = context(ride)
	local ok, safe, why = pcall(check, cf, ctx)
	ctx.probe:Destroy()
	if not ok then return false, tostring(safe) end
	return safe, why
end

-- (for tests) the course line
ReviveSpot.Course = { Length = LENGTH, PointAt = pointAt, Measure = measure, CheckpointS = checkpointS }

return ReviveSpot
