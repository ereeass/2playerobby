-- Checkpoint 3 Snow Lot penguins, on THIS machine only and only while this player rides a
-- scooter (driver or motor rider) near the lot - like the Mesa insects and jungle monkeys.
-- They live on the snowy rocks round the edge of the lot (not in the parking bays):
-- waddle about rocking side to side, stop and flap, look round, and now and then flop on
-- their bellies and slide. Decoration only: no collision, touch or queries.
-- Sound (ReplicatedStorage.CritterSounds, very quiet): now and then one calls out, and
-- a happy flap sometimes comes with a little call.

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local COUNT  = 7
local NEAR   = 150
local CENTRE = Vector3.new(-653.4, 251, 793.9)
local LEASH  = 6
local S      = 1.3
local WALKABLE = { Rock = true, Snow = true, SnowDrift = true }

local CritterSounds = require(game:GetService("ReplicatedStorage"):WaitForChild("CritterSounds"))
local callTimer = CritterSounds.Timer(2.5, 6)

local player = Players.LocalPlayer
local lot = workspace:WaitForChild("Checkpoint 3 Snow Lot")

local rp = RaycastParams.new()
rp.FilterType = Enum.RaycastFilterType.Include
local function gather()
	local list = {}
	for _, n in ipairs({ "SnowyCliff", "Ground", "Props" }) do
		local m = lot:FindFirstChild(n)
		if m then table.insert(list, m) end
	end
	rp.FilterDescendantsInstances = list
	return #list > 0
end

-- the snow/rock under a spot, or nil if it isn't somewhere a penguin walks. The rocks
-- round the lot are stepped, tilted, studded blocks, so the centre alone isn't enough:
-- the surface must be nearly flat and the penguin's whole footprint (FOOT round it)
-- the same ground at the same height - never half sunk into a higher block beside it,
-- tipped into a sloping slab or hanging off an edge.
local FOOT, FLAT, LEVEL = 0.8 * S, 0.9, 0.2
local FOOTPRINT = { Vector3.new(FOOT, 0, 0), Vector3.new(-FOOT, 0, 0), Vector3.new(0, 0, FOOT), Vector3.new(0, 0, -FOOT) }
local function castDown(p)
	return workspace:Raycast(p + Vector3.new(0, 8, 0), Vector3.new(0, -16, 0), rp)
end
local function groundAt(p)
	local hit = castDown(p)
	if not (hit and WALKABLE[hit.Instance.Name] and hit.Normal.Y >= FLAT) then return nil end
	for _, off in ipairs(FOOTPRINT) do
		local h = castDown(p + off)
		if not (h and WALKABLE[h.Instance.Name] and math.abs(h.Position.Y - hit.Position.Y) <= LEVEL) then return nil end
	end
	return hit.Position
end

local function myChassis()
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local weld = root and root:FindFirstChild("ScooterRiderWeld")
	return weld and weld.Part0
end

local BLACK, WHITE, ORANGE = Color3.fromRGB(30, 32, 40), Color3.fromRGB(244, 246, 250), Color3.fromRGB(250, 150, 30)

local function bit(size, col, round, cls)
	local p = Instance.new(cls or "Part")
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
	p.Size, p.Color, p.Material = size * S, col, Enum.Material.SmoothPlastic
	if round then local m = Instance.new("SpecialMesh") m.MeshType = Enum.MeshType.Sphere m.Parent = p end
	p.Parent = workspace.CurrentCamera
	return p
end

-- pieces: offset from the feet (facing -Z); flippers and feet move
local function makePenguin(all)
	local pg = { fixed = {} }
	local function fixed(size, col, at, round, cls)
		local p = bit(size, col, round, cls) table.insert(all, p)
		table.insert(pg.fixed, { p = p, at = at * S })
	end
	fixed(Vector3.new(1.2, 1.6, 1.1), BLACK, Vector3.new(0, 0.95, 0), true)
	fixed(Vector3.new(0.9, 1.3, 0.45), WHITE, Vector3.new(0, 0.85, -0.38), true)
	fixed(Vector3.new(0.95, 0.9, 0.95), BLACK, Vector3.new(0, 1.95, -0.05), true)
	fixed(Vector3.new(0.7, 0.5, 0.35), WHITE, Vector3.new(0, 1.9, -0.4), true)
	fixed(Vector3.new(0.13, 0.13, 0.08), BLACK, Vector3.new(0.17, 2.02, -0.56), true)
	fixed(Vector3.new(0.13, 0.13, 0.08), BLACK, Vector3.new(-0.17, 2.02, -0.56), true)
	fixed(Vector3.new(0.22, 0.16, 0.38), ORANGE, Vector3.new(0, 1.85, -0.68), false, "WedgePart")
	pg.flipL = bit(Vector3.new(0.14, 0.95, 0.42), BLACK, true) table.insert(all, pg.flipL)
	pg.flipR = bit(Vector3.new(0.14, 0.95, 0.42), BLACK, true) table.insert(all, pg.flipR)
	pg.footL = bit(Vector3.new(0.34, 0.1, 0.46), ORANGE, true) table.insert(all, pg.footL)
	pg.footR = bit(Vector3.new(0.34, 0.1, 0.46), ORANGE, true) table.insert(all, pg.footR)
	return pg
end

local penguins, all = nil, {}
local parts, cfs = {}, {}

local function spawn()
	if not gather() then return end
	penguins = {}
	local taken = {}
	for i = 1, COUNT do
		for _ = 1, 40 do
			local a = math.random() * math.pi * 2
			local r = 29 + math.random() * 14
			local home = groundAt(CENTRE + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r))
			local ok = home and math.abs(home.Y - CENTRE.Y) < 6
			if ok then for _, q in ipairs(taken) do if (q - home).Magnitude < 4 then ok = false break end end end
			if ok then
				table.insert(taken, home)
				table.insert(penguins, { pg = makePenguin(all), home = home, pos = home, yaw = math.random() * 6.28,
					target = nil, rest = math.random() * 2, phase = math.random() * 6, slide = 0, flap = 0 })
				break
			end
		end
	end
end

local function clear()
	for _, p in ipairs(all) do p:Destroy() end
	table.clear(all)
	penguins = nil
end

local t = 0
RunService.Heartbeat:Connect(function(dt)
	local chassis = myChassis()
	if not (chassis and (chassis.Position - CENTRE).Magnitude < NEAR) then
		if penguins then clear() end
		return
	end
	if not penguins then spawn() end
	if not penguins then return end
	t += dt
	if callTimer:Due(dt) and #penguins > 0 then
		local b = penguins[math.random(#penguins)]
		CritterSounds.Play(b.pg.fixed[3].p, "Penguin")   -- from its head
	end
	table.clear(parts) table.clear(cfs)
	for _, b in ipairs(penguins) do
		local walking, sliding = false, b.slide > 0
		if b.rest > 0 then
			b.rest -= dt
			b.flap = math.max(0, b.flap - dt)
		elseif not b.target then
			local try = b.home + Vector3.new((math.random() - 0.5) * 2 * LEASH, 0, (math.random() - 0.5) * 2 * LEASH)
			b.target = groundAt(try)
			if not b.target then b.rest = 0.3 end
			if b.target and math.random() < 0.25 then b.slide = 2 end        -- belly slide there
		else
			local to = Vector3.new(b.target.X - b.pos.X, 0, b.target.Z - b.pos.Z)
			if to.Magnitude < 0.3 then
				b.target, b.slide = nil, 0
				b.rest = 1 + math.random() * 2.5
				if math.random() < 0.5 then                                    -- happy flap
					b.flap = 1.2
					if math.random() < 0.3 then CritterSounds.Play(b.pg.fixed[3].p, "Penguin", 0.07) end
				end
			else
				local want = math.atan2(-to.X, -to.Z)
				local diff = (want - b.yaw + math.pi) % (2 * math.pi) - math.pi
				b.yaw += math.clamp(diff, -3 * dt, 3 * dt)
				if math.abs(diff) < 0.5 then
					local speed = sliding and 4.5 or 1.4
					local step = CFrame.Angles(0, b.yaw, 0).LookVector * math.min(speed * dt, to.Magnitude)
					local nextP = groundAt(b.pos + step)
					if nextP then b.pos = nextP else b.target, b.slide = nil, 0 end
				end
				walking = not sliding
			end
		end
		local base = CFrame.new(b.pos) * CFrame.Angles(0, b.yaw, 0)
		local body
		if sliding and b.target then
			body = base * CFrame.new(0, 0.55 * S, 0) * CFrame.Angles(-math.rad(80), 0, 0) * CFrame.new(0, -0.95 * S, 0)   -- flat on its belly
		else
			local rock = walking and math.sin(t * 9 + b.phase) * 0.14 or math.sin(t * 1.2 + b.phase) * 0.03
			local look = (not walking) and math.sin(t * 0.8 + b.phase) * 0.5 or 0
			body = base * CFrame.Angles(0, look * 0.3, rock)
		end
		for _, f in ipairs(b.pg.fixed) do
			parts[#parts + 1] = f.p cfs[#cfs + 1] = body * CFrame.new(f.at)
		end
		local flap = b.flap > 0 and math.sin(t * 22) * 0.5 + 0.6 or (sliding and 1.3 or 0.15)
		parts[#parts + 1] = b.pg.flipL cfs[#cfs + 1] = body * CFrame.new(0.62 * S, 1.3 * S, 0) * CFrame.Angles(0, 0, flap) * CFrame.new(0, -0.45 * S, 0)
		parts[#parts + 1] = b.pg.flipR cfs[#cfs + 1] = body * CFrame.new(-0.62 * S, 1.3 * S, 0) * CFrame.Angles(0, 0, -flap) * CFrame.new(0, -0.45 * S, 0)
		local step = walking and math.sin(t * 9 + b.phase) * 0.12 * S or 0
		parts[#parts + 1] = b.pg.footL cfs[#cfs + 1] = body * CFrame.new(0.25 * S, 0.05 * S, -0.2 * S + step)
		parts[#parts + 1] = b.pg.footR cfs[#cfs + 1] = body * CFrame.new(-0.25 * S, 0.05 * S, -0.2 * S - step)
	end
	workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end)
