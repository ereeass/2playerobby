-- Checkpoint 4 Jungle Lot monkeys, on THIS machine only and only while this player rides a
-- scooter (driver or motor rider) near the lot - like the Mesa insects (MesaBugs). Each of
-- the three big trees gets:
--   a climber  goes up and down the trunk hand over hand, stops to look around, and now
--              and then sits on top of the crown for a bit
--   a swinger  hangs from one of the tree's vines, swinging on it (the vine swings too,
--              here only, and is put back when the monkeys go)
-- Decoration only: no collision, touch or queries; removed when the ride leaves.
-- Sound (ReplicatedStorage.CritterSounds, very quiet): now and then one chatters.

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local NEAR  = 150                                   -- studs from the lot
local LOT   = Vector3.new(-569.5, 337.6, 496.2)
local TREES = { "Tree-21_9", "Tree-22_31", "Tree-21_47" }
local S     = 1.4                                   -- monkey size

local CritterSounds = require(game:GetService("ReplicatedStorage"):WaitForChild("CritterSounds"))
local chatterTimer = CritterSounds.Timer(1.8, 4.5)

local player = Players.LocalPlayer
local jungle = workspace:WaitForChild("Checkpoint 4 Jungle Lot"):WaitForChild("Jungle")

local function myChassis()
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local weld = root and root:FindFirstChild("ScooterRiderWeld")
	return weld and weld.Part0
end

local FUR, TAN, DARK = Color3.fromRGB(112, 72, 42), Color3.fromRGB(222, 184, 138), Color3.fromRGB(24, 18, 14)

local function bit(size, col, round)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
	p.Size, p.Color, p.Material = size * S, col, Enum.Material.SmoothPlastic
	if round then
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
	end
	p.Parent = workspace.CurrentCamera
	return p
end

-- one monkey: fixed pieces (offset from its middle, facing -Z) and limbs that swing at a joint
local function makeMonkey(allParts)
	local m = { fixed = {}, limbs = {}, tail = {} }
	local function fixed(size, col, round, at) local p = bit(size, col, round) table.insert(allParts, p) table.insert(m.fixed, { p = p, at = at * S }) end
	local function limb(key, size, col, joint)
		local p = bit(size, col, true) table.insert(allParts, p)
		m.limbs[key] = { p = p, joint = joint * S, len = size.Y * S }
	end
	fixed(Vector3.new(1.1, 1.4, 0.9), FUR, true, Vector3.new(0, 0, 0))
	fixed(Vector3.new(0.8, 1.0, 0.3), TAN, true, Vector3.new(0, -0.05, -0.36))
	fixed(Vector3.new(1, 1, 1), FUR, true, Vector3.new(0, 1.05, -0.05))
	fixed(Vector3.new(0.8, 0.6, 0.35), TAN, true, Vector3.new(0, 0.95, -0.45))
	fixed(Vector3.new(0.15, 0.15, 0.1), DARK, true, Vector3.new(0.17, 1.17, -0.53))
	fixed(Vector3.new(0.15, 0.15, 0.1), DARK, true, Vector3.new(-0.17, 1.17, -0.53))
	fixed(Vector3.new(0.12, 0.08, 0.08), DARK, true, Vector3.new(0, 0.9, -0.63))
	fixed(Vector3.new(0.36, 0.36, 0.14), TAN, true, Vector3.new(0.55, 1.1, 0))
	fixed(Vector3.new(0.36, 0.36, 0.14), TAN, true, Vector3.new(-0.55, 1.1, 0))
	limb("armL", Vector3.new(0.26, 1.15, 0.26), FUR, Vector3.new(0.5, 0.45, 0))
	limb("armR", Vector3.new(0.26, 1.15, 0.26), FUR, Vector3.new(-0.5, 0.45, 0))
	limb("legL", Vector3.new(0.3, 0.8, 0.3), FUR, Vector3.new(0.3, -0.55, 0))
	limb("legR", Vector3.new(0.3, 0.8, 0.3), FUR, Vector3.new(-0.3, -0.55, 0))
	for i = 1, 3 do
		local p = bit(Vector3.new(0.18, 0.18, 0.62), FUR, true) table.insert(allParts, p)
		table.insert(m.tail, p)
	end
	return m
end

-- put a monkey at `root` with its limb angles (0 = hanging straight down, pi = straight up)
local function pose(m, root, a, out)
	for _, f in ipairs(m.fixed) do
		out.parts[#out.parts + 1] = f.p
		out.cfs[#out.cfs + 1] = root * CFrame.new(f.at)
	end
	for key, l in pairs(m.limbs) do
		out.parts[#out.parts + 1] = l.p
		out.cfs[#out.cfs + 1] = root * CFrame.new(l.joint) * CFrame.Angles(a[key] or 0, 0, 0) * CFrame.new(0, -l.len / 2, 0)
	end
	-- tail: a curl out of its back
	local cf = root * CFrame.new(0, -0.45 * S, 0.4 * S)
	for i, p in ipairs(m.tail) do
		cf = cf * CFrame.Angles(-0.55 + math.sin(a.tail + i) * 0.25, 0, 0) * CFrame.new(0, 0, 0.28 * S)
		out.parts[#out.parts + 1] = p
		out.cfs[#out.cfs + 1] = cf
		cf = cf * CFrame.new(0, 0, 0.28 * S)
	end
end

-- a tree's trunk (centre and half width at a height), crown top, and vines
local function readTree(tree)
	local trunks, vines, leaves, crown = {}, {}, {}, nil
	for _, p in ipairs(tree:GetChildren()) do
		if p.Name == "Trunk" then table.insert(trunks, p)
		elseif p.Name == "Liana" then table.insert(vines, p)
		elseif p.Name == "LianaLeaf" then table.insert(leaves, p)
		elseif p.Name == "Crown" then crown = p end
	end
	if #trunks == 0 or not crown then return nil end
	table.sort(trunks, function(x, y) return x.Position.Y < y.Position.Y end)
	local function at(y)
		local best = trunks[1]
		for _, p in ipairs(trunks) do if math.abs(p.Position.Y - y) < math.abs(best.Position.Y - y) then best = p end end
		return Vector3.new(best.Position.X, y, best.Position.Z), best.Size.X / 2
	end
	local low = trunks[1].Position.Y + 1.5
	local high = trunks[#trunks].Position.Y + trunks[#trunks].Size.Y / 2 - 1.2
	return { at = at, low = low, high = high, crown = crown, vines = vines, leaves = leaves }
end

local active, allParts, vineHome = nil, {}, {}
local out = { parts = {}, cfs = {} }

local function spawn()
	active = {}
	for _, name in ipairs(TREES) do
		local tree = jungle:FindFirstChild(name)
		local info = tree and readTree(tree)
		if info then
			table.insert(active, { kind = "climb", tree = info, m = makeMonkey(allParts), y = info.low + math.random() * (info.high - info.low),
				angle = math.random() * 6.28, target = nil, wait = math.random() * 2, phase = math.random() * 6, look = 0 })
			-- the longest vine gets a swinger
			local vine
			for _, v in ipairs(info.vines) do if not vine or v.Size.Y > vine.Size.Y then vine = v end end
			if vine then
				vineHome[vine] = vine.CFrame
				-- the leaf on the vine's end swings with it
				local bottom = (vine.CFrame * CFrame.new(0, -vine.Size.Y / 2, 0)).Position
				local leaf
				for _, l in ipairs(info.leaves) do
					if (l.Position - bottom).Magnitude < 2.5 and (not leaf or (l.Position - bottom).Magnitude < (leaf.Position - bottom).Magnitude) then leaf = l end
				end
				if leaf then vineHome[leaf] = leaf.CFrame end
				table.insert(active, { kind = "swing", vine = vine, home = vine.CFrame, leaf = leaf, leafRel = leaf and vine.CFrame:ToObjectSpace(leaf.CFrame),
					m = makeMonkey(allParts), phase = math.random() * 6, speed = 1.6 + math.random() * 0.6 })
			end
		end
	end
end

local function clear()
	for _, p in ipairs(allParts) do p:Destroy() end
	table.clear(allParts)
	for v, cf in pairs(vineHome) do if v.Parent then v.CFrame = cf end end
	table.clear(vineHome)
	active = nil
end

local t = 0
RunService.Heartbeat:Connect(function(dt)
	local chassis = myChassis()
	if not (chassis and (chassis.Position - LOT).Magnitude < NEAR) then
		if active then clear() end
		return
	end
	if not active then spawn() end
	t += dt
	if chatterTimer:Due(dt) and #active > 0 then
		local mk = active[math.random(#active)]
		CritterSounds.Play(mk.m.fixed[3].p, "Monkey")   -- from its head
	end
	table.clear(out.parts) table.clear(out.cfs)
	for _, mk in ipairs(active) do
		local a = { tail = t * 1.5 + mk.phase }
		if mk.kind == "climb" then
			local tr = mk.tree
			local root
			if mk.sitting then
				-- sitting on the crown, looking round, now and then scratching its head
				mk.sitting -= dt
				local c = tr.crown
				local dir = Vector3.new(math.cos(mk.angle), 0, math.sin(mk.angle))
				local pos = c.Position + dir * (math.min(c.Size.X, c.Size.Z) / 2 - 1.2) + Vector3.new(0, c.Size.Y / 2 + 0.75 * S, 0)
				root = CFrame.lookAt(pos, pos + dir) * CFrame.Angles(0, math.sin(t * 0.9 + mk.phase) * 0.6, 0)
				local scratch = math.sin(t * 0.7 + mk.phase) > 0.6
				a.legL, a.legR = -1.45, -1.35
				a.armL = scratch and (2.6 + math.sin(t * 14) * 0.2) or 0.3
				a.armR = 0.3
				if mk.sitting <= 0 then mk.sitting = nil; mk.y = tr.high; mk.target = tr.low + math.random() * (tr.high - tr.low) * 0.6 end
			else
				local moving = false
				if mk.wait > 0 then
					mk.wait -= dt
					mk.look = math.sin(t * 1.3 + mk.phase) * 0.8
				elseif not mk.target then
					mk.target = tr.low + math.random() * (tr.high - tr.low)
					if math.random() < 0.3 then mk.target = tr.high end
				else
					local d = mk.target - mk.y
					local step = (d > 0 and 2.2 or 3) * dt
					if math.abs(d) <= step then
						mk.y = mk.target
						if mk.target >= tr.high - 0.01 and math.random() < 0.7 then
							mk.sitting = 3 + math.random() * 3   -- up onto the crown
						end
						mk.target, mk.wait = nil, 0.8 + math.random() * 2
					else
						mk.y += step * (d > 0 and 1 or -1)
						mk.angle += dt * 0.35 * math.sin(mk.phase + t * 0.2)     -- drifts round the trunk
						moving = true
					end
					mk.look *= 0.9
				end
				local c, half = tr.at(mk.y)
				local dir = Vector3.new(math.cos(mk.angle), 0, math.sin(mk.angle))
				local pos = c + dir * (half + 0.45 * S)
				root = CFrame.lookAt(pos, pos - dir) * CFrame.Angles(0, mk.look * 0.4, 0)
				-- hand over hand: arms up gripping, legs hugging, alternating while it moves
				local k = moving and math.sin(t * 9 + mk.phase) or 0
				a.armL, a.armR = 2.6 + k * 0.35, 2.6 - k * 0.35
				a.legL, a.legR = -0.9 - k * 0.35, -0.9 + k * 0.35
			end
			pose(mk.m, root, a, out)
		else
			-- swinging on the vine: the vine swings about its top, the monkey hangs off the end
			local v, home = mk.vine, mk.home
			local len = v.Size.Y
			local top = home * CFrame.new(0, len / 2, 0)
			local swing = math.sin(t * mk.speed + mk.phase) * 0.45
			local pivot = CFrame.new(top.Position) * CFrame.Angles(swing, 0, swing * 0.3)
			v.CFrame = pivot * CFrame.new(0, -len / 2, 0)
			if mk.leaf then mk.leaf.CFrame = v.CFrame * mk.leafRel end
			local grip = pivot * CFrame.new(0, -len + 0.2, 0)
			local face = Vector3.new(math.cos(mk.phase), 0, math.sin(mk.phase))
			local root = CFrame.new(grip.Position) * (pivot - pivot.Position) * CFrame.lookAt(Vector3.zero, face) * CFrame.new(-0.5 * S, -1.6 * S, 0)
			a.armL = math.pi                                   -- holding on
			a.armR = 0.6 + math.sin(t * 2.4 + mk.phase) * 0.6  -- waving the free arm
			local kick = math.sin(t * mk.speed + mk.phase + 1)
			a.legL, a.legR = -0.3 + kick * 0.4, -0.3 - kick * 0.4
			pose(mk.m, root, a, out)
		end
	end
	workspace:BulkMoveTo(out.parts, out.cfs, Enum.BulkMoveMode.FireCFrameChanged)
end)
