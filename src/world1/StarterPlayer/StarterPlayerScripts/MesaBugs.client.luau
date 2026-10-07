-- Tumbleweed Mesa insects: a few tiny bugs crawling over the mesa rocks beside the Mesa
-- Boardwalk. Made on THIS machine only, and only while this player is riding a scooter
-- near the boardwalk, so nobody else ever renders them; they're removed again when the
-- ride leaves. They crawl along the rock surface (over ledges, up walls), wander, pause,
-- and stay near where they started. Decoration only: no collision, touch or queries.
-- Kinds: beetles, ants, ladybugs, spiders and hopping grasshoppers (KINDS below).
-- Performance: a handful of 3-6 part bugs, one BulkMoveTo per frame, and each bug only
-- probes the rock every few frames; bugs far from the camera don't move at all.

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local COUNT      = 18      -- bugs
local NEAR       = 160     -- studs from the boardwalk: bugs exist while the ride is this close
local ACTIVE     = 70      -- studs from the camera: bugs this close move
local LEASH      = 6       -- studs a bug wanders from its spot
local PROBE_EVERY = 3      -- frames between surface probes (staggered per bug)

local player = Players.LocalPlayer
local mesa = workspace:WaitForChild("TumbleweedMesa"):WaitForChild("Mesa")
local walk = workspace:WaitForChild("Mesa Boardwalk")
local deck = walk:WaitForChild("Deck")

-- the map streams in, so the rocks and planks are gathered again each time bugs spawn
local rp = RaycastParams.new()
rp.FilterType = Enum.RaycastFilterType.Include
local planks = {}
local function gather()
	local rocks = {}
	for _, p in ipairs(mesa:GetDescendants()) do
		if p:IsA("BasePart") and p.Name == "Rock" then table.insert(rocks, p) end
	end
	rp.FilterDescendantsInstances = rocks
	table.clear(planks)
	for _, p in ipairs(deck:GetChildren()) do
		if p.Name == "Plank" then table.insert(planks, p) end
	end
	return #rocks > 0 and #planks > 0
end
-- the boardwalk's middle, fixed in the map (streaming can't skew it)
local walkCentre = Vector3.new(-443.4, 239.4, 860.4)

local function myChassis()
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local weld = root and root:FindFirstChild("ScooterRiderWeld")
	return weld and weld.Part0
end

-- insect kinds. Each piece: size, offset (x, y, z; -z is the head end), colour, round
-- (a sphere mesh), wig (legs that wiggle as it walks), yaw (turned flat on the rock).
-- lift = how high the body sits off the rock; speed = how fast it crawls; hop = jumps.
local SIZE = 1.7    -- overall scale
local function C(r, g, b) return Color3.fromRGB(r, g, b) end
local KINDS = {
	{ name = "beetle", lift = 0.2, speed = { 0.9, 1.8 }, colors = { { C(28, 24, 22), C(16, 14, 12) }, { C(38, 92, 60), C(22, 50, 34) }, { C(84, 58, 36), C(52, 36, 22) } },
	  pieces = { { size = Vector3.new(0.36, 0.24, 0.56), at = Vector3.new(0, 0, 0.04), c = 1, round = true },
	             { size = Vector3.new(0.2, 0.17, 0.2), at = Vector3.new(0, 0.01, -0.33), c = 2, round = true },
	             { size = Vector3.new(0.64, 0.03, 0.4), at = Vector3.new(0, -0.08, 0), c = 2, wig = true, round = true } } },
	{ name = "ant", lift = 0.15, speed = { 1.6, 2.6 }, colors = { { C(128, 40, 26), C(90, 28, 18) }, { C(24, 20, 18), C(14, 12, 10) } },
	  pieces = { { size = Vector3.new(0.24, 0.22, 0.32), at = Vector3.new(0, 0.02, 0.26), c = 1, round = true },
	             { size = Vector3.new(0.14, 0.13, 0.2), at = Vector3.new(0, 0, 0), c = 1, round = true },
	             { size = Vector3.new(0.18, 0.16, 0.18), at = Vector3.new(0, 0.01, -0.2), c = 2, round = true },
	             { size = Vector3.new(0.58, 0.025, 0.34), at = Vector3.new(0, -0.07, 0), c = 2, wig = true, round = true } } },
	{ name = "ladybug", lift = 0.18, speed = { 0.7, 1.3 }, colors = { { C(214, 36, 30), C(18, 16, 16) }, { C(240, 150, 30), C(18, 16, 16) } },
	  pieces = { { size = Vector3.new(0.4, 0.24, 0.42), at = Vector3.new(0, 0.02, 0.02), c = 1, round = true },
	             { size = Vector3.new(0.2, 0.14, 0.16), at = Vector3.new(0, 0, -0.24), c = 2, round = true },
	             { size = Vector3.new(0.1, 0.04, 0.1), at = Vector3.new(0.09, 0.13, 0.04), c = 2, round = true },
	             { size = Vector3.new(0.1, 0.04, 0.1), at = Vector3.new(-0.1, 0.13, -0.05), c = 2, round = true },
	             { size = Vector3.new(0.5, 0.025, 0.3), at = Vector3.new(0, -0.07, 0), c = 2, wig = true, round = true } } },
	{ name = "spider", lift = 0.16, speed = { 1.4, 2.4 }, colors = { { C(36, 30, 26), C(22, 18, 16) }, { C(92, 70, 46), C(58, 44, 30) } },
	  pieces = { { size = Vector3.new(0.32, 0.26, 0.36), at = Vector3.new(0, 0.03, 0.16), c = 1, round = true },
	             { size = Vector3.new(0.22, 0.18, 0.22), at = Vector3.new(0, 0.01, -0.12), c = 2, round = true },
	             { size = Vector3.new(0.95, 0.03, 0.06), at = Vector3.new(0, -0.05, -0.05), c = 2, wig = true, yaw = 28 },
	             { size = Vector3.new(0.95, 0.03, 0.06), at = Vector3.new(0, -0.05, 0.02), c = 2, wig = true, yaw = -28 },
	             { size = Vector3.new(0.9, 0.03, 0.06), at = Vector3.new(0, -0.05, -0.02), c = 2, wig = true } } },
	{ name = "grasshopper", lift = 0.16, speed = { 0.6, 1.1 }, hop = true, colors = { { C(110, 150, 60), C(76, 110, 40) }, { C(176, 150, 90), C(130, 108, 62) } },
	  pieces = { { size = Vector3.new(0.18, 0.18, 0.62), at = Vector3.new(0, 0.02, 0.04), c = 1, round = true },
	             { size = Vector3.new(0.17, 0.2, 0.17), at = Vector3.new(0, 0.05, -0.34), c = 1, round = true },
	             { size = Vector3.new(0.16, 0.025, 0.5), at = Vector3.new(0, 0.12, 0.1), c = 2 },
	             { size = Vector3.new(0.04, 0.2, 0.44), at = Vector3.new(0.12, 0.06, 0.18), c = 2 },
	             { size = Vector3.new(0.04, 0.2, 0.44), at = Vector3.new(-0.12, 0.06, 0.18), c = 2 },
	             { size = Vector3.new(0.4, 0.025, 0.26), at = Vector3.new(0, -0.06, -0.08), c = 2, wig = true, round = true } } },
}

local function bit(size, col, meshScale)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
	p.Size, p.Color, p.Material = size, col, Enum.Material.SmoothPlastic
	if meshScale then
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Scale = meshScale
		m.Parent = p
	end
	return p
end

-- a spot on a rock beside the boardwalk (not on it), with the surface's normal
local function findSpot(taken)
	for _ = 1, 60 do
		local pl = planks[math.random(#planks)]
		local a = math.random() * math.pi * 2
		local from = pl.Position + Vector3.new(math.cos(a), 0, math.sin(a)) * (4 + math.random() * 10) + Vector3.new(0, 2 + math.random() * 6, 0)
		local hit
		if math.random() < 0.5 then
			hit = workspace:Raycast(from + Vector3.new(0, 8, 0), Vector3.new(0, -24, 0), rp)       -- a rock top
		else
			local back = (from - pl.Position) * Vector3.new(1, 0, 1)
			hit = workspace:Raycast(pl.Position + Vector3.new(0, from.Y - pl.Position.Y, 0), back.Unit * 18, rp)  -- a rock face
		end
		if hit then
			local ok = true
			for _, q in ipairs(taken) do if (q - hit.Position).Magnitude < 3 then ok = false break end end
			local d = (hit.Position - pl.Position).Magnitude
			if ok and d > 3 and d < 18 then return hit.Position, hit.Normal end
		end
	end
end

local bugs, parts, cframes = nil, {}, {}

local function spawnBugs()
	if not gather() then return end
	bugs = {}
	table.clear(parts)
	local taken = {}
	for i = 1, COUNT do
		local pos, nrm = findSpot(taken)
		if pos then
			table.insert(taken, pos)
			local kind = KINDS[(i - 1) % #KINDS + 1]           -- an even mix of every kind
			local cols = kind.colors[math.random(#kind.colors)]
			local s = SIZE * (0.85 + math.random() * 0.3)
			local pieces = {}
			for _, pc in ipairs(kind.pieces) do
				local p = bit(pc.size * s, cols[pc.c], pc.round and Vector3.one or nil)
				p.Parent = workspace.CurrentCamera
				table.insert(parts, p)
				table.insert(pieces, { at = pc.at * s, wig = pc.wig, yaw = math.rad(pc.yaw or 0) })
			end
			local tangent = nrm:Cross(Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)).Unit
			table.insert(bugs, {
				pos = pos, n = nrm, h = tangent, home = pos, s = s, pieces = pieces, lift = kind.lift * s, hop = kind.hop,
				speed = kind.speed[1] + math.random() * (kind.speed[2] - kind.speed[1]), turn = 0, rest = math.random() * 2,
				phase = math.random() * 6, tick = i % PROBE_EVERY,
			})
		end
	end
end

local function clearBugs()
	for _, p in ipairs(parts) do p:Destroy() end
	table.clear(parts)
	bugs = nil
end

local function rotate(v, axis, a)
	return v * math.cos(a) + axis:Cross(v) * math.sin(a) + axis * axis:Dot(v) * (1 - math.cos(a))
end

local t = 0
RunService.Heartbeat:Connect(function(dt)
	local chassis = myChassis()
	local near = chassis and (chassis.Position - walkCentre).Magnitude < NEAR
	if not near then
		if bugs then clearBugs() end
		return
	end
	if not bugs then spawnBugs() end
	if not bugs then return end
	t += dt
	local cam = workspace.CurrentCamera.CFrame.Position
	table.clear(cframes)
	for i, b in ipairs(bugs) do
		local moving = false
		if (b.pos - cam).Magnitude < ACTIVE then
			if b.rest > 0 then
				b.rest -= dt
			else
				moving = true
				-- wander: the heading drifts, and pulls back home past the leash
				b.turn = math.clamp(b.turn + (math.random() - 0.5) * 6 * dt, -1.6, 1.6)
				b.h = rotate(b.h, b.n, b.turn * dt)
				local toHome = b.home - b.pos
				if toHome.Magnitude > LEASH then
					local want = (toHome - b.n * toHome:Dot(b.n))
					if want.Magnitude > 0.01 then b.h = b.h:Lerp(want.Unit, math.min(1, 2 * dt)) end
				end
				b.h = (b.h - b.n * b.h:Dot(b.n))
				b.h = b.h.Magnitude > 0.01 and b.h.Unit or b.n:Cross(Vector3.xAxis).Unit
				b.pos += b.h * b.speed * dt
				b.tick += 1
				if b.tick >= PROBE_EVERY then
					b.tick = 0
					-- stick to the rock: a wall ahead to climb, else the surface under us
					local ahead = workspace:Raycast(b.pos + b.n * 0.15, b.h * 0.4, rp)
					local hit = ahead or workspace:Raycast(b.pos + b.n * 0.6, -b.n * 1.4, rp)
					if hit then
						b.pos, b.n = hit.Position, hit.Normal
					else
						-- over an edge: step back and turn round
						b.pos -= b.h * b.speed * dt * PROBE_EVERY
						b.h = -b.h
					end
				end
				if math.random() < dt * 0.35 then b.rest = 0.4 + math.random() * 1.8 end
			end
		end
		local right = b.h:Cross(b.n)
		-- grasshoppers go in little hops, everything else crawls
		local up = b.lift
		if b.hop and moving then up += math.abs(math.sin(t * 5 + b.phase)) * 0.35 * b.s end
		local cf = CFrame.fromMatrix(b.pos + b.n * up, right, b.n)
		local wig = moving and math.sin(t * 28 + b.phase) * 0.35 or 0
		for _, pc in ipairs(b.pieces) do
			cframes[#cframes + 1] = cf * CFrame.new(pc.at) * CFrame.Angles(0, pc.yaw + (pc.wig and wig or 0), 0)
		end
	end
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end)
