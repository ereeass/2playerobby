-- Knocks road cones (tagged "KnockableCone") flying when the scooter THIS player rides
-- drives into one - on this machine only. Both riders of a scooter run this and both
-- see the same scooter, so the two of them see the cone go; nobody else does.
--
-- The real cone is only hidden here (LocalTransparencyModifier), and a copy that exists
-- only on this machine tumbles away with physics. REVERT seconds later the copy is
-- gone and the real cone is back, standing where it always was.
-- Collision groups are set up by ServerScriptService.KnockableCones.

local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")

local TAG    = "KnockableCone"
local REVERT = 10             -- seconds until the cone is back
local BOX    = Vector3.new(2.4, 3, 7.5)       -- around the scooter, in its own axes
local BOX_OFFSET = CFrame.new(0, 0.1, -0.4)   -- centred between the wheels

local player  = Players.LocalPlayer
local knocked = {}   -- [cone] = true while it's knocked over here

-- the chassis this player is welded to, if they are riding (RiderAttach)
local function myChassis()
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local weld = root and root:FindFirstChild("ScooterRiderWeld")
	return weld and weld.Part0
end

-- only look at cones
local params = OverlapParams.new()
params.FilterType = Enum.RaycastFilterType.Include
local function refresh()
	params.FilterDescendantsInstances = CollectionService:GetTagged(TAG)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(refresh)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(refresh)
refresh()

local function coneOf(part)
	local m = part:FindFirstAncestorOfClass("Model")
	while m and not CollectionService:HasTag(m, TAG) do m = m:FindFirstAncestorOfClass("Model") end
	return m
end

local function knock(cone, chassis)
	knocked[cone] = true

	-- a copy that only exists here
	local copy = cone:Clone()
	CollectionService:RemoveTag(copy, TAG)
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("LuaSourceContainer") then d:Destroy() end
	end
	local parts, main = {}, nil
	for _, p in ipairs(copy:GetDescendants()) do
		if p:IsA("BasePart") then
			table.insert(parts, p)
			if not main or p.Size.Magnitude > main.Size.Magnitude then main = p end
		end
	end
	if not main then knocked[cone] = nil copy:Destroy() return end
	for _, p in ipairs(parts) do
		if p ~= main then
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = main, p
			w.Parent = main
		end
		p.CollisionGroup = "KnockedCone"
		p.CanTouch = false
		p.CanQuery = false
		p.Anchored = false
	end

	-- hide the real one, here only, and let the copy (which starts inside it) fly free
	local originals = {}
	for _, p in ipairs(cone:GetDescendants()) do
		if p:IsA("BasePart") then
			table.insert(originals, { part = p, collide = p.CanCollide })
			p.LocalTransparencyModifier = 1
			p.CanCollide = false
		end
	end

	copy.Parent = workspace

	-- sent off the way the scooter was going, tipping forward and spinning
	local v = chassis.AssemblyLinearVelocity
	local flat = Vector3.new(v.X, 0, v.Z)
	local dir = flat.Magnitude > 1 and flat.Unit or chassis.CFrame.LookVector
	-- (gravity here is Roblox's 196: it takes a firm pop to get any air)
	local speed = math.max(flat.Magnitude, 18)
	local side = chassis.CFrame.RightVector * (math.random() - 0.5) * 12
	main.AssemblyLinearVelocity = dir * speed * 1.1 + side + Vector3.new(0, 30 + speed * 0.4, 0)
	main.AssemblyAngularVelocity = dir:Cross(Vector3.yAxis) * -(12 + math.random() * 8)
		+ Vector3.new(0, (math.random() - 0.5) * 16, 0)

	task.delay(REVERT, function()
		copy:Destroy()
		for _, o in ipairs(originals) do
			if o.part.Parent then
				o.part.LocalTransparencyModifier = 0
				o.part.CanCollide = o.collide
			end
		end
		knocked[cone] = nil
	end)
end

RunService.Heartbeat:Connect(function()
	local chassis = myChassis()
	if not chassis then return end
	local hits = workspace:GetPartBoundsInBox(chassis.CFrame * BOX_OFFSET, BOX, params)
	for _, part in ipairs(hits) do
		local cone = coneOf(part)
		if cone and not knocked[cone] then knock(cone, chassis) end
	end
end)
