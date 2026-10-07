-- Checkpoint 5 Food Lot pigeons, on THIS machine only and only while this player rides a
-- scooter (driver or motor rider) near the lot - like the other critters. Three little flocks
-- peck at crumbs by the giant food, bobbing their heads and waddling about. A scooter coming
-- within SCARE studs scatters them: they burst up and each lands on top of a giant food
-- (burger, cupcake, fries, cheese, strawberry). Once it's clear they flutter back down to
-- their crumbs. Decoration only: no collision, touch or queries.
-- Sound (ReplicatedStorage.CritterSounds, very quiet): now and then one on the ground
-- coos, and a flock bursting up or fluttering back down gives a soft flap of wings.

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local NEAR  = 150
local LOT   = Vector3.new(-647, 325, 154)
local SCARE = 18
local CALM  = { 6, 11 }        -- seconds clear before they come back down
local S     = 1.1
local FLOCKS = { Vector3.new(-650, 0, 137.5), Vector3.new(-651, 0, 171), Vector3.new(-666, 0, 168) }
local PER_FLOCK = 4
local ROOSTS = { "Burger", "Cupcake", "Fries", "Cheese", "Strawberry" }

local CritterSounds = require(game:GetService("ReplicatedStorage"):WaitForChild("CritterSounds"))
local cooTimer = CritterSounds.Timer(1.5, 4)

local player = Players.LocalPlayer
local lot = workspace:WaitForChild("Checkpoint 5 Food Lot")
local scooters = workspace:WaitForChild("RideSystem"):WaitForChild("Scooters")

local function myChassis()
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local weld = root and root:FindFirstChild("ScooterRiderWeld")
	return weld and weld.Part0
end

local GREY, DARKG, NECK, BAR, BEAK, EYE, LEG =
	Color3.fromRGB(150, 156, 170), Color3.fromRGB(96, 100, 116), Color3.fromRGB(70, 130, 120),
	Color3.fromRGB(60, 62, 72), Color3.fromRGB(50, 46, 46), Color3.fromRGB(240, 130, 40), Color3.fromRGB(210, 110, 120)
local CRUMB = { Color3.fromRGB(214, 170, 110), Color3.fromRGB(180, 130, 80), Color3.fromRGB(236, 206, 150) }

local function bit(size, col, round, cls)
	local p = Instance.new(cls or "Part")
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
	p.Size, p.Color, p.Material = size * S, col, Enum.Material.SmoothPlastic
	if round then local m = Instance.new("SpecialMesh") m.MeshType = Enum.MeshType.Sphere m.Parent = p end
	p.Parent = workspace.CurrentCamera
	return p
end

local function makePigeon(all)
	local g = { body = {}, head = {}, wings = {}, legs = {} }
	local function add(list, size, col, at, round, cls, rot)
		local p = bit(size, col, round, cls) table.insert(all, p) table.insert(list, { p = p, at = CFrame.new(at * S) * (rot or CFrame.identity) })
	end
	add(g.body, Vector3.new(0.62, 0.6, 1.0), GREY, Vector3.new(0, 0, 0), true)
	add(g.body, Vector3.new(0.46, 0.34, 0.5), NECK, Vector3.new(0, 0.28, -0.36), true)
	add(g.body, Vector3.new(0.4, 0.1, 0.55), BAR, Vector3.new(0, 0.05, 0.62), false, "WedgePart")
	-- head pieces are placed relative to the head joint so it can bob and peck
	add(g.head, Vector3.new(0.36, 0.36, 0.38), DARKG, Vector3.new(0, 0, 0), true)
	add(g.head, Vector3.new(0.08, 0.08, 0.2), BEAK, Vector3.new(0, -0.03, -0.26), false, "WedgePart")
	add(g.head, Vector3.new(0.07, 0.07, 0.07), EYE, Vector3.new(0.15, 0.06, -0.1), true)
	add(g.head, Vector3.new(0.07, 0.07, 0.07), EYE, Vector3.new(-0.15, 0.06, -0.1), true)
	for _, side in ipairs({ 1, -1 }) do
		local w = bit(Vector3.new(1.0, 0.06, 0.5), GREY, true) table.insert(all, w)
		local bar = bit(Vector3.new(0.5, 0.065, 0.14), BAR, false) table.insert(all, bar)
		table.insert(g.wings, { side = side, w = w, bar = bar })
		local leg = bit(Vector3.new(0.06, 0.28, 0.06), LEG) table.insert(all, leg)
		table.insert(g.legs, { side = side, p = leg })
	end
	return g
end

-- cf = body middle; head = extra CFrame on the head (bob/peck); spread/flap as the gulls
local function pose(g, cf, head, spread, flap, standing, out)
	for _, e in ipairs(g.body) do out.p[#out.p + 1] = e.p out.c[#out.c + 1] = cf * e.at end
	local hj = cf * CFrame.new(0, 0.42 * S, -0.42 * S) * head
	for _, e in ipairs(g.head) do out.p[#out.p + 1] = e.p out.c[#out.c + 1] = hj * e.at end
	for _, w in ipairs(g.wings) do
		local s = w.side
		local hinge = cf * CFrame.new(s * 0.27 * S, 0.12 * S, -0.05 * S)
			* CFrame.Angles(0, -s * (1 - spread) * 1.35, 0) * CFrame.Angles(0, 0, s * flap - s * (1 - spread) * 0.3)
		out.p[#out.p + 1] = w.w out.c[#out.c + 1] = hinge * CFrame.new(s * 0.5 * S, 0, 0)
		out.p[#out.p + 1] = w.bar out.c[#out.c + 1] = hinge * CFrame.new(s * 0.45 * S, 0.01 * S, 0.1 * S)
	end
	for _, l in ipairs(g.legs) do
		out.p[#out.p + 1] = l.p
		out.c[#out.c + 1] = standing and (cf * CFrame.new(l.side * 0.12 * S, -0.38 * S, 0.05 * S))
			or (cf * CFrame.new(l.side * 0.1 * S, -0.2 * S, 0.4 * S) * CFrame.Angles(math.rad(80), 0, 0))
	end
end

local function bez(a, b, c, d, u) local v = 1 - u return a * v * v * v + b * 3 * v * v * u + c * 3 * v * u * u + d * u * u * u end

local rp = RaycastParams.new()
rp.FilterType = Enum.RaycastFilterType.Include
local function groundAt(p) rp.FilterDescendantsInstances = { lot } local h = workspace:Raycast(Vector3.new(p.X, LOT.Y + 40, p.Z), Vector3.new(0, -80, 0), rp) return h and h.Position end

local birds, all, flocks = nil, {}, {}
local out = { p = {}, c = {} }
local t = 0

local function spawn()
	birds = {}
	table.clear(flocks)
	local roosts = {}
	local food = lot:FindFirstChild("Food")
	for _, n in ipairs(ROOSTS) do
		local m = food and food:FindFirstChild(n)
		if m then
			local cf, s = m:GetBoundingBox()
			rp.FilterDescendantsInstances = { m }
			local h = workspace:Raycast(cf.Position + Vector3.new(0, s.Y / 2 + 5, 0), Vector3.new(0, -s.Y - 10, 0), rp)
			if h then table.insert(roosts, h.Position) end
		end
	end
	for fi, spot in ipairs(FLOCKS) do
		local g0 = groundAt(spot)
		if g0 then
			local flock = { centre = g0, calm = 0, scattered = false }
			table.insert(flocks, flock)
			-- crumbs on the ground
			for i = 1, 9 do
				local c = bit(Vector3.new(0.18, 0.08, 0.14) * (0.8 + math.random() * 0.6), CRUMB[math.random(#CRUMB)], true)
				c.CFrame = CFrame.new(g0 + Vector3.new((math.random() - 0.5) * 4, 0.04, (math.random() - 0.5) * 4)) * CFrame.Angles(0, math.random() * 6.28, 0)
				table.insert(all, c)
			end
			for i = 1, PER_FLOCK do
				local roost = #roosts > 0 and roosts[(fi + i) % #roosts + 1] or (g0 + Vector3.new(0, 6, 0))
				local home = g0 + Vector3.new((math.random() - 0.5) * 3, 0, (math.random() - 0.5) * 3)
				table.insert(birds, { g = makePigeon(all), flock = flock, state = "ground", pos = home, yaw = math.random() * 6.28,
					target = nil, rest = math.random() * 1.5, phase = math.random() * 6,
					roost = roost + Vector3.new((math.random() - 0.5) * 1.4, 0, (math.random() - 0.5) * 1.4) })
			end
		end
	end
end

local function clear()
	for _, p in ipairs(all) do p:Destroy() end
	table.clear(all)
	birds = nil
end

local function scooterNear(pos, d)
	for _, sc in ipairs(scooters:GetChildren()) do
		local pp = sc:IsA("Model") and sc.PrimaryPart
		if pp and ((pp.Position - pos) * Vector3.new(1, 0, 1)).Magnitude < d then return pp.Position end
	end
end

local function flyTo(b, to, dur, height)
	local from = b.pos
	b.path = { from, from + Vector3.new(0, height, 0), to + Vector3.new(0, height * 0.6, 0), to }
	b.u, b.dur = 0, dur
end

RunService.Heartbeat:Connect(function(dt)
	t += dt
	local chassis = myChassis()
	if not (chassis and (chassis.Position - LOT).Magnitude < NEAR) then
		if birds then clear() end
		return
	end
	if not birds then spawn() end
	-- each flock scatters together, and comes back together once it's clear
	for _, f in ipairs(flocks) do
		local threat = scooterNear(f.centre, SCARE)
		if threat and not f.scattered then
			f.scattered, f.calm = true, CALM[1] + math.random() * (CALM[2] - CALM[1])
			local flapped = false
			for _, b in ipairs(birds) do
				if b.flock == f and b.state == "ground" then
					b.state, b.delay = "takeoff", math.random() * 0.35
					if not flapped then flapped = true CritterSounds.Play(b.g.body[1].p, "PigeonFlap") end
				end
			end
		elseif f.scattered then
			if threat or scooterNear(f.centre, SCARE * 1.4) then f.calm = math.max(f.calm, 3) end
			f.calm -= dt
			if f.calm <= 0 then
				f.scattered = false
				local flapped = false
				for _, b in ipairs(birds) do
					if b.flock == f and b.state == "roost" then
						if not flapped then flapped = true CritterSounds.Play(b.g.body[1].p, "PigeonFlap", 0.1) end
						b.home = f.centre + Vector3.new((math.random() - 0.5) * 3, 0, (math.random() - 0.5) * 3)
						b.state = "land" flyTo(b, b.home, 1.6 + math.random() * 0.8, 3)
					end
				end
			end
		end
	end
	-- now and then one pecking about coos
	if cooTimer:Due(dt) and #birds > 0 then
		local b = birds[math.random(#birds)]
		if b and b.state == "ground" then CritterSounds.Play(b.g.head[1].p, "PigeonCoo") end
	end
	table.clear(out.p) table.clear(out.c)
	for _, b in ipairs(birds) do
		if b.state == "takeoff" then
			b.delay -= dt
			if b.delay <= 0 then b.state = "fly" flyTo(b, b.roost, 1.1 + math.random() * 0.6, 5) end
		end
		if b.state == "ground" or b.state == "takeoff" or b.state == "roost" then
			local walking = false
			if b.state == "ground" then
				if b.rest > 0 then
					b.rest -= dt
				elseif not b.target then
					b.target = b.flock.centre + Vector3.new((math.random() - 0.5) * 4, 0, (math.random() - 0.5) * 4)
				else
					local to = (b.target - b.pos) * Vector3.new(1, 0, 1)
					if to.Magnitude < 0.2 then b.target, b.rest = nil, 0.5 + math.random() * 2
					else
						b.yaw = math.atan2(-to.X, -to.Z)
						b.pos += to.Unit * math.min(1.3 * dt, to.Magnitude)
						walking = true
					end
				end
			end
			local base = b.state == "roost" and b.roost or b.pos
			local cf = CFrame.new(base + Vector3.new(0, 0.42 * S, 0)) * CFrame.Angles(0, b.yaw, 0)
			local head
			if walking then
				head = CFrame.new(0, 0, -math.max(0, math.sin(t * 12 + b.phase)) * 0.12 * S)     -- head bob
			elseif b.state ~= "roost" and math.sin(t * 3 + b.phase) > 0.2 then
				local k = math.max(0, math.sin(t * 14 + b.phase))
				head = CFrame.new(0, -0.35 * k * S, -0.12 * k * S) * CFrame.Angles(-0.9 * k, 0, 0)  -- pecking
			else
				head = CFrame.Angles(0, math.sin(t * 0.9 + b.phase) * 0.6, 0)                      -- looking round
			end
			if walking then cf *= CFrame.Angles(0, 0, math.sin(t * 12 + b.phase) * 0.08) end
			pose(b.g, cf, head, 0, 0, true, out)
		else
			b.u = math.min(1, b.u + dt / b.dur)
			local P = b.path
			local pos = bez(P[1], P[2], P[3], P[4], b.u)
			local ahead = bez(P[1], P[2], P[3], P[4], math.min(1, b.u + 0.03))
			local flat = (ahead - pos) * Vector3.new(1, 0, 1)
			if flat.Magnitude > 0.01 then b.yaw = math.atan2(-flat.X, -flat.Z) end
			local dir = ahead - pos
			local cf = CFrame.lookAt(pos + Vector3.new(0, 0.42 * S, 0), pos + Vector3.new(0, 0.42 * S, 0) + (dir.Magnitude > 0.01 and dir or Vector3.new(0, 0, -1)))
			pose(b.g, cf, CFrame.identity, 1, math.sin(t * 26 + b.phase) * 0.8, false, out)
			if b.u >= 1 then
				if b.state == "fly" then b.state = "roost" b.pos = b.roost
				else b.state, b.pos, b.target, b.rest = "ground", b.home, nil, 1 end
			end
		end
	end
	workspace:BulkMoveTo(out.p, out.c, Enum.BulkMoveMode.FireCFrameChanged)
end)
