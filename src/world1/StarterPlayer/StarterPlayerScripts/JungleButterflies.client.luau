-- Checkpoint 4 Jungle Lot butterflies and fireflies, on THIS machine only and only while this
-- player rides a scooter (driver or motor rider) near the lot - like the jungle monkeys.
--   butterflies  flutter from flower to flower (the lot's Blooms) on wobbly paths, land,
--                slowly open and close their wings, then pick another flower
--   fireflies    drift lazily over the ferns (the Fronds), blinking a soft glow on and off
-- Decoration only: no collision, touch, queries or lights (glow is Neon, cheap on mobile).

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local NEAR        = 150
local LOT         = Vector3.new(-569.5, 337.6, 496.2)
local BUTTERFLIES = 8
local FIREFLIES   = 18
local S           = 1.3

local player = Players.LocalPlayer
local jungle = workspace:WaitForChild("Checkpoint 4 Jungle Lot"):WaitForChild("Jungle")

local function myChassis()
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local weld = root and root:FindFirstChild("ScooterRiderWeld")
	return weld and weld.Part0
end

local WINGS = {
	{ Color3.fromRGB(60, 140, 255), Color3.fromRGB(30, 80, 190) },    -- blue
	{ Color3.fromRGB(250, 140, 30), Color3.fromRGB(40, 30, 25) },     -- orange / black
	{ Color3.fromRGB(255, 225, 70), Color3.fromRGB(230, 170, 40) },   -- yellow
	{ Color3.fromRGB(245, 120, 200), Color3.fromRGB(180, 70, 170) },  -- pink
	{ Color3.fromRGB(250, 250, 250), Color3.fromRGB(200, 205, 215) }, -- white
}

local function bit(size, col, round, mat)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
	p.Size, p.Color, p.Material = size, col, mat or Enum.Material.SmoothPlastic
	if round then local m = Instance.new("SpecialMesh") m.MeshType = Enum.MeshType.Sphere m.Parent = p end
	p.Parent = workspace.CurrentCamera
	return p
end

local flowers, fronds = {}, {}
local function gather()
	table.clear(flowers) table.clear(fronds)
	local f = jungle:FindFirstChild("Flowers")
	if f then for _, p in ipairs(f:GetChildren()) do if p.Name == "Bloom" then table.insert(flowers, p.Position + Vector3.new(0, p.Size.Y / 2 + 0.15, 0)) end end end
	local fe = jungle:FindFirstChild("Ferns")
	if fe then for _, p in ipairs(fe:GetChildren()) do if p.Name == "Frond" then table.insert(fronds, p.Position) end end end
	return #flowers > 1 and #fronds > 0
end

local all, bugs, flies = {}, nil, nil
local parts, cfs = {}, {}

local function bez(a, b, c, u) local v = 1 - u return a * v * v + b * 2 * v * u + c * u * u end

local function newTrip(b)
	local target
	repeat target = flowers[math.random(#flowers)] until target ~= b.at or #flowers < 2
	local from = b.pos
	local mid = (from + target) / 2 + Vector3.new((math.random() - 0.5) * 8, 3 + math.random() * 4, (math.random() - 0.5) * 8)
	b.trip = { from, mid, target }
	b.u, b.dur, b.at = 0, math.max(2, (target - from).Magnitude / 3.5), target
end

local function spawn()
	if not gather() then return end
	bugs, flies = {}, {}
	for i = 1, BUTTERFLIES do
		local c = WINGS[(i - 1) % #WINGS + 1]
		local b = { phase = math.random() * 6, rest = math.random() * 3 }
		b.body = bit(Vector3.new(0.09, 0.09, 0.5) * S, Color3.fromRGB(30, 26, 24), true)
		b.wings = {}
		for _, side in ipairs({ 1, -1 }) do
			local up = bit(Vector3.new(0.62, 0.02, 0.48) * S, c[1], true)
			local lo = bit(Vector3.new(0.44, 0.02, 0.36) * S, c[2], true)
			table.insert(b.wings, { side = side, up = up, lo = lo })
			table.insert(all, up) table.insert(all, lo)
		end
		table.insert(all, b.body)
		b.at = flowers[(i - 1) % #flowers + 1]
		b.pos = b.at
		b.yaw = math.random() * 6.28
		table.insert(bugs, b)
	end
	for i = 1, FIREFLIES do
		local core = bit(Vector3.new(0.22, 0.22, 0.22), Color3.fromRGB(215, 255, 90), true, Enum.Material.Neon)
		local halo = bit(Vector3.new(0.7, 0.7, 0.7), Color3.fromRGB(200, 255, 110), true, Enum.Material.Neon)
		halo.Transparency = 0.8
		table.insert(all, core) table.insert(all, halo)
		local home = fronds[math.random(#fronds)] + Vector3.new((math.random() - 0.5) * 3, 0.8 + math.random() * 2.5, (math.random() - 0.5) * 3)
		table.insert(flies, { core = core, halo = halo, home = home, phase = math.random() * 20,
			blink = 1.8 + math.random() * 1.6, sp = 0.4 + math.random() * 0.4 })
	end
end

local function clear()
	for _, p in ipairs(all) do p:Destroy() end
	table.clear(all)
	bugs, flies = nil, nil
end

local t = 0
RunService.Heartbeat:Connect(function(dt)
	local chassis = myChassis()
	if not (chassis and (chassis.Position - LOT).Magnitude < NEAR) then
		if bugs then clear() end
		return
	end
	if not bugs then spawn() end
	if not bugs then return end
	t += dt
	table.clear(parts) table.clear(cfs)
	for _, b in ipairs(bugs) do
		local cf, open
		if b.rest > 0 then
			-- sitting on a flower: wings slowly open and close
			b.rest -= dt
			cf = CFrame.new(b.pos + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, b.yaw, 0)
			open = 0.9 - (math.sin(t * 1.6 + b.phase) * 0.5 + 0.5) * 1.3
			if b.rest <= 0 then newTrip(b) end
		else
			b.u = math.min(1, b.u + dt / b.dur)
			local T = b.trip
			local pos = bez(T[1], T[2], T[3], b.u)
			-- fluttery wobble on top of the path, fading out as it lands
			local w = math.sin(b.u * math.pi)
			pos += Vector3.new(math.sin(t * 5 + b.phase) * 0.5, math.sin(t * 9 + b.phase) * 0.35, math.cos(t * 4 + b.phase) * 0.5) * w
			local ahead = bez(T[1], T[2], T[3], math.min(1, b.u + 0.03))
			local flat = (ahead - pos) * Vector3.new(1, 0, 1)
			if flat.Magnitude > 0.01 then b.yaw = math.atan2(-flat.X, -flat.Z) end
			b.pos = pos
			cf = CFrame.new(pos) * CFrame.Angles(0, b.yaw, 0) * CFrame.Angles(math.rad(10), 0, 0)
			open = math.sin(t * 24 + b.phase) * 0.9
			if b.u >= 1 then b.pos = b.at b.rest = 2 + math.random() * 4 end
		end
		parts[#parts + 1] = b.body cfs[#cfs + 1] = cf
		for _, wg in ipairs(b.wings) do
			local s = wg.side
			local hinge = cf * CFrame.Angles(0, 0, s * open)
			parts[#parts + 1] = wg.up cfs[#cfs + 1] = hinge * CFrame.new(s * 0.3 * S, 0, -0.1 * S) * CFrame.Angles(0, s * 0.35, 0)
			parts[#parts + 1] = wg.lo cfs[#cfs + 1] = hinge * CFrame.new(s * 0.22 * S, 0, 0.22 * S) * CFrame.Angles(0, -s * 0.3, 0)
		end
	end
	for _, f in ipairs(flies) do
		local k = t * f.sp + f.phase
		local pos = f.home + Vector3.new(math.sin(k) * 1.6 + math.sin(k * 2.3) * 0.6, math.sin(k * 1.4) * 0.7, math.cos(k * 0.9) * 1.6 + math.cos(k * 1.9) * 0.5)
		parts[#parts + 1] = f.core cfs[#cfs + 1] = CFrame.new(pos)
		parts[#parts + 1] = f.halo cfs[#cfs + 1] = CFrame.new(pos)
		-- blink: glow swells up and fades out, then a dark gap
		local c = ((t + f.phase) % f.blink) / f.blink
		local glow = c < 0.45 and math.sin(c / 0.45 * math.pi) or 0
		f.core.Transparency = 0.85 - glow * 0.85
		f.halo.Transparency = 1 - glow * 0.3
	end
	workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end)
