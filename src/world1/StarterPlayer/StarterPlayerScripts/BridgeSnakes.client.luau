-- Rotten Bridge snakes: three harmless snakes slithering along the bridge's rope handrails,
-- on THIS machine only and only while this player rides a scooter (driver or motor rider)
-- near the bridge - like the Mesa insects and the jungle monkeys. Each one glides along its
-- rope with a wavy body, turns round at the ends, stops now and then, and flicks its
-- tongue. Decoration only: no collision, touch or queries; removed when the ride leaves.

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local NEAR     = 130
local BRIDGE   = Vector3.new(-382, 231, 621)
local SEGMENTS = 16
local SPACING  = 0.34     -- studs between body segments along the rope

local player = Players.LocalPlayer
local rails = workspace:WaitForChild("Rotten Bridge"):WaitForChild("Rails")

local function myChassis()
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local weld = root and root:FindFirstChild("ScooterRiderWeld")
	return weld and weld.Part0
end

local STYLES = {
	{ body = Color3.fromRGB(62, 150, 60), band = Color3.fromRGB(226, 206, 60), belly = Color3.fromRGB(200, 214, 120) },  -- green / yellow bands
	{ body = Color3.fromRGB(176, 96, 40), band = Color3.fromRGB(60, 36, 22), belly = Color3.fromRGB(226, 180, 120) },   -- orange / brown bands
	{ body = Color3.fromRGB(120, 190, 70), band = Color3.fromRGB(40, 90, 36), belly = Color3.fromRGB(210, 230, 150) },   -- lime
}

-- each handrail as one line of points along the bridge, from its rope pieces
local function readRopes()
	local sides = {}
	for _, r in ipairs(rails:GetChildren()) do
		if r:IsA("BasePart") and r.Name == "Rope" then
			local key = math.floor(r.Position.X / 4 + 0.5)
			sides[key] = sides[key] or {}
			table.insert(sides[key], r)
		end
	end
	local lines = {}
	for _, list in pairs(sides) do
		if #list >= 4 then
			local axis = (list[#list].Position - list[1].Position).Unit
			table.sort(list, function(a, b) return a.Position:Dot(axis) < b.Position:Dot(axis) end)
			local pts = {}
			for _, r in ipairs(list) do
				local half = r.CFrame.LookVector * r.Size.Z / 2
				local a, b = r.Position - half, r.Position + half
				if (b - a):Dot(axis) < 0 then a, b = b, a end
				table.insert(pts, a) table.insert(pts, b)
			end
			local line, acc = { { p = pts[1], s = 0 } }, 0
			for i = 2, #pts do
				local d = (pts[i] - pts[i - 1]).Magnitude
				if d > 0.01 then acc += d table.insert(line, { p = pts[i], s = acc }) end
			end
			line.len = acc
			table.insert(lines, line)
		end
	end
	return lines
end

-- a point and direction a distance `s` along a rope line
local function along(line, s)
	s = math.clamp(s, 0, line.len)
	local lo, hi = 1, #line
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if line[mid].s < s then lo = mid else hi = mid end
	end
	local a, b = line[lo], line[hi]
	local k = (s - a.s) / math.max(b.s - a.s, 1e-4)
	return a.p:Lerp(b.p, k), (b.p - a.p).Unit
end

local function bit(size, col, round)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
	p.Size, p.Color, p.Material = size, col, Enum.Material.SmoothPlastic
	if round then local m = Instance.new("SpecialMesh") m.MeshType = Enum.MeshType.Sphere m.Parent = p end
	p.Parent = workspace.CurrentCamera
	return p
end

local snakes, parts, cfs = nil, {}, {}

local function spawn()
	local lines = readRopes()
	if #lines == 0 then return end
	snakes = {}
	for i = 1, 3 do
		local line = lines[(i - 1) % #lines + 1]
		local st = STYLES[i]
		local sn = { line = line, s = line.len * (0.2 + 0.3 * i), dir = (i % 2 == 0) and -1 or 1,
			speed = 1.6 + math.random() * 1.2, rest = math.random() * 1.5, phase = math.random() * 6, body = {} }
		for k = 1, SEGMENTS do
			local u = (k - 1) / (SEGMENTS - 1)
			local r = 0.42 * (1 - u * 0.75)                         -- thick behind the head, thin tail
			if k == 1 then r = 0.36 end
			local p = bit(Vector3.new(r * 2, r * 1.6, r * 2.3), (k % 3 == 0) and st.band or st.body, true)
			table.insert(parts, p) table.insert(sn.body, { p = p, r = r })
		end
		-- head, eyes, tongue
		sn.head = bit(Vector3.new(0.72, 0.5, 0.95), st.body, true)
		sn.eyeL = bit(Vector3.new(0.18, 0.18, 0.18), Color3.fromRGB(250, 220, 60), true)
		sn.eyeR = bit(Vector3.new(0.18, 0.18, 0.18), Color3.fromRGB(250, 220, 60), true)
		sn.tongue = bit(Vector3.new(0.06, 0.03, 0.5), Color3.fromRGB(200, 30, 50))
		for _, p in ipairs({ sn.head, sn.eyeL, sn.eyeR, sn.tongue }) do table.insert(parts, p) end
		table.insert(snakes, sn)
	end
end

local function clear()
	for _, p in ipairs(parts) do p:Destroy() end
	table.clear(parts)
	snakes = nil
end

local t = 0
local list = {}
RunService.Heartbeat:Connect(function(dt)
	local chassis = myChassis()
	if not (chassis and (chassis.Position - BRIDGE).Magnitude < NEAR) then
		if snakes then clear() end
		return
	end
	if not snakes then spawn() end
	if not snakes then return end
	t += dt
	table.clear(list) table.clear(cfs)
	for _, sn in ipairs(snakes) do
		local line = sn.line
		local moving = false
		if sn.rest > 0 then
			sn.rest -= dt
		else
			sn.s += sn.dir * sn.speed * dt
			moving = true
			local bodyLen = SEGMENTS * SPACING
			if sn.s > line.len - 0.5 then sn.s, sn.dir = line.len - 0.5, -1 end
			if sn.s < bodyLen + 0.5 and sn.dir < 0 then sn.dir = 1 end
			if sn.s < bodyLen + 0.5 then sn.s = bodyLen + 0.5 end
			if math.random() < dt * 0.25 then sn.rest = 0.6 + math.random() * 1.8 end
			if math.random() < dt * 0.08 then sn.dir = -sn.dir end
		end
		-- the body trails behind the head along the rope, weaving side to side
		local wave = moving and 1 or 0.35
		local prev
		for k, seg in ipairs(sn.body) do
			local s = sn.s - sn.dir * (k - 1) * SPACING
			local pos, fwd = along(line, s)
			fwd = fwd * sn.dir
			local side = fwd:Cross(Vector3.yAxis)
			side = side.Magnitude > 0.01 and side.Unit or Vector3.xAxis
			local w = math.sin((s * 2.2) - t * 5 * sn.dir + sn.phase) * 0.28 * wave * math.min(1, k / 3)
			local p = pos + side * w + Vector3.new(0, 0.1 + seg.r * 0.8, 0)
			local look = prev and (prev - p) or fwd
			if look.Magnitude < 0.01 then look = fwd end
			list[#list + 1] = seg.p
			cfs[#cfs + 1] = CFrame.lookAt(p, p + look)
			prev = p
		end
		-- head a little ahead of the first segment, raised
		local first = cfs[#cfs - SEGMENTS + 1]
		local lift = math.sin(t * 2 + sn.phase) * 0.1
		local head = first * CFrame.new(0, 0.12 + lift, -0.5)
		list[#list + 1] = sn.head cfs[#cfs + 1] = head
		list[#list + 1] = sn.eyeL cfs[#cfs + 1] = head * CFrame.new(0.24, 0.14, -0.18)
		list[#list + 1] = sn.eyeR cfs[#cfs + 1] = head * CFrame.new(-0.24, 0.14, -0.18)
		-- tongue flicks out now and then
		local flick = (math.sin(t * 9 + sn.phase) > 0.55) and 1 or 0
		list[#list + 1] = sn.tongue cfs[#cfs + 1] = head * CFrame.new(0, -0.05, -0.45 - 0.3 * flick)
	end
	workspace:BulkMoveTo(list, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end)
