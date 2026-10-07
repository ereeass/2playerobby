-- Scorpions (models tagged "Scorpion", on the dusty sand path) wander about on THIS
-- player's screen: pick a spot near home on the path, turn to face it, scuttle over with
-- their legs twitching and tail swaying, pause, repeat. Decoration only.
-- A scooter rolling over one squishes it cartoon-flat (a puff of sand, no blood), and it
-- pops back up at home SQUISH_TIME seconds later. Any scooter does it, so everyone sees it.
local CollectionService = game:GetService("CollectionService")
local RunService        = game:GetService("RunService")
local Debris            = game:GetService("Debris")

local SQUISH_TIME = 8     -- seconds flat before it pops back up
local POP_TIME    = 0.35  -- seconds to spring back to shape
local scooters = workspace:WaitForChild("RideSystem"):WaitForChild("Scooters")
local hitParams = OverlapParams.new()
hitParams.FilterType = Enum.RaycastFilterType.Include
hitParams.FilterDescendantsInstances = { scooters }

local WANDER = 6        -- studs from home
local SPEED  = 2.2      -- studs/s
local TURN   = 3        -- rad/s

local ground = workspace:WaitForChild("Dusty Sand Path"):WaitForChild("Ground")
local rp = RaycastParams.new()
rp.FilterType = Enum.RaycastFilterType.Include
rp.FilterDescendantsInstances = { ground }

-- The models are Atomic, so each one streams in whole; they can stream out and back in
-- (both riders, whoever joined or wherever they were), so bugs are re-hooked every time.
local bugs = {}
local function add(m)
	if not m:IsA("Model") then return end
	local root = m:WaitForChild("Root")
	if not m:IsDescendantOf(workspace) then return end
	for i = #bugs, 1, -1 do if bugs[i].model == m then table.remove(bugs, i) end end
	local parts = {}
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") and p ~= root then
			table.insert(parts, { part = p, rel = root.CFrame:ToObjectSpace(p.CFrame), size = p.Size, name = p.Name, phase = math.random() * 6 })
		end
	end
	local pos = root.Position
	local _, yaw = root.CFrame:ToOrientation()
	table.insert(bugs, { model = m, root = root, parts = parts, home = m:GetAttribute("Home") or pos, pos = pos, yaw = yaw, target = nil, rest = math.random() * 2 })
end
for _, m in ipairs(CollectionService:GetTagged("Scorpion")) do task.spawn(add, m) end
CollectionService:GetInstanceAddedSignal("Scorpion"):Connect(add)
CollectionService:GetInstanceRemovedSignal("Scorpion"):Connect(function(m)
	for i = #bugs, 1, -1 do if bugs[i].model == m then table.remove(bugs, i) end end
end)

-- a little puff of sand where it got flattened
local function puff(pos)
	local holder = Instance.new("Part")
	holder.Anchored, holder.CanCollide, holder.CanTouch, holder.CanQuery = true, false, false, false
	holder.Transparency, holder.Size, holder.CFrame = 1, Vector3.new(2, 0.2, 2), CFrame.new(pos)
	holder.Parent = workspace
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(226, 204, 158))
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.2) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.5, 1)
	e.Speed = NumberRange.new(3, 6)
	e.SpreadAngle = Vector2.new(180, 20)
	e.Drag = 3
	e.Parent = holder
	e:Emit(14)
	Debris:AddItem(holder, 2)
end

-- 0 = normal shape .. 1 = pancake: squashed down, spread a bit wider
local function pose(b, rootCF, k)
	local sy, sxz = 1 - 0.85 * k, 1 + 0.25 * k
	for _, e in ipairs(b.parts) do
		local r = e.rel
		e.part.Size = Vector3.new(e.size.X * sxz, e.size.Y * sy, e.size.Z * sxz)
		e.part.CFrame = rootCF * CFrame.new(r.X * sxz, r.Y * sy, r.Z * sxz) * r.Rotation
	end
end

local function groundAt(p)
	local hit = workspace:Raycast(p + Vector3.new(0, 6, 0), Vector3.new(0, -14, 0), rp)
	return hit and hit.Position
end

local t = 0
RunService.Heartbeat:Connect(function(dt)
	t += dt
	for _, b in ipairs(bugs) do
		if b.model.Parent and not b.squished then
			-- a scooter's wheels or body right on top of it?
			local hits = workspace:GetPartBoundsInBox(CFrame.new(b.pos + Vector3.new(0, 1, 0)), Vector3.new(2.2, 2.4, 2.2), hitParams)
			if #hits > 0 then
				b.squished = os.clock()
				puff(b.pos)
			end
		end
		if b.model.Parent and b.squished then
			local age = os.clock() - b.squished
			local rootCF = CFrame.new(b.pos) * CFrame.Angles(0, b.yaw, 0)
			if age < SQUISH_TIME then
				pose(b, rootCF, math.min(1, age / 0.08))   -- flat almost instantly
			else
				if not b.popped then
					-- back home, springing up out of the sand
					b.popped = true
					b.pos = groundAt(b.home) or b.home
					rootCF = CFrame.new(b.pos) * CFrame.Angles(0, b.yaw, 0)
					puff(b.pos)
				end
				local k = (age - SQUISH_TIME) / POP_TIME
				if k >= 1 then
					pose(b, rootCF, 0)
					b.squished, b.popped, b.target, b.rest = nil, nil, nil, 1
				else
					-- a little overshoot bounce
					pose(b, rootCF, (1 - k) - math.sin(k * math.pi) * 0.25)
				end
			end
			b.root.CFrame = rootCF
		end
		if b.model.Parent and not b.squished then
			local moving = false
			if b.rest > 0 then
				b.rest -= dt
			elseif not b.target then
				local try = b.home + Vector3.new((math.random() - 0.5) * 2 * WANDER, 0, (math.random() - 0.5) * 2 * WANDER)
				b.target = groundAt(try)
				if not b.target then b.rest = 0.3 end
			else
				local to = Vector3.new(b.target.X - b.pos.X, 0, b.target.Z - b.pos.Z)
				if to.Magnitude < 0.3 then
					b.target = nil
					b.rest = 0.8 + math.random() * 2.5
				else
					-- turn towards it, then walk
					local want = math.atan2(-to.X, -to.Z)
					local diff = (want - b.yaw + math.pi) % (2 * math.pi) - math.pi
					b.yaw += math.clamp(diff, -TURN * dt, TURN * dt)
					if math.abs(diff) < 0.4 then
						local step = CFrame.Angles(0, b.yaw, 0).LookVector * math.min(SPEED * dt, to.Magnitude)
						local nextP = groundAt(b.pos + step)
						if nextP then b.pos = nextP else b.target = nil end
					end
					moving = true
				end
			end
			local rootCF = CFrame.new(b.pos) * CFrame.Angles(0, b.yaw, 0)
			b.root.CFrame = rootCF
			for _, e in ipairs(b.parts) do
				local extra = CFrame.identity
				if e.name == "Leg" and moving then
					extra = CFrame.Angles(0, math.sin(t * 18 + e.phase) * 0.35, math.sin(t * 18 + e.phase) * 0.12)
				elseif e.name == "Tail" or e.name == "Stinger" then
					extra = CFrame.Angles(math.sin(t * 2 + e.phase * 0.2) * 0.05, math.sin(t * 1.3) * 0.06, 0)
				elseif (e.name == "Claw" or e.name == "Finger") and not moving then
					extra = CFrame.Angles(0, math.sin(t * 3 + e.phase) * 0.1, 0)
				end
				e.part.CFrame = rootCF * e.rel * extra
			end
		end
	end
end)
