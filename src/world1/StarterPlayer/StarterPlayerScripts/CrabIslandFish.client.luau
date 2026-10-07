-- Little fish leaping out of the sea by the crab island (TropicalIsland, beside Road 3 on the
-- Checkpoint 1 run), on THIS machine only and only while this player rides a scooter (driver
-- or motor rider) past it - like the other critters. Now and then one fish (sometimes two)
-- jumps in an arc in open water ahead of / beside the riders, with a small splash going in
-- and out. Kept sparse on purpose. Decoration only: no collision, touch or queries.

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris       = game:GetService("Debris")

local ISLAND   = Vector3.new(-342, 0, 378)
local NEAR     = 110               -- studs from the island (flat) for the fish to show
local WATER    = 181.06
local GAP      = { 2.2, 4 }       -- seconds between jumps
local PAIR     = 0.15             -- chance a second fish follows
local FISH = {
	{ body = Color3.fromRGB(250, 130, 40), fin = Color3.fromRGB(255, 255, 255) },   -- orange
	{ body = Color3.fromRGB(70, 150, 230), fin = Color3.fromRGB(250, 220, 60) },    -- blue
	{ body = Color3.fromRGB(200, 210, 220), fin = Color3.fromRGB(120, 140, 160) },  -- silver
}

local player = Players.LocalPlayer
local blockers = RaycastParams.new()
blockers.FilterType = Enum.RaycastFilterType.Exclude

local function myChassis()
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local weld = root and root:FindFirstChild("ScooterRiderWeld")
	return weld and weld.Part0
end

local function bit(size, col, round, cls)
	local p = Instance.new(cls or "Part")
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
	p.Size, p.Color, p.Material = size, col, Enum.Material.SmoothPlastic
	if round then local m = Instance.new("SpecialMesh") m.MeshType = Enum.MeshType.Sphere m.Parent = p end
	p.Parent = workspace.CurrentCamera
	return p
end

-- open water here? (nothing - island, road, piers - between the sky and the surface)
local function openWater(p)
	blockers.FilterDescendantsInstances = { workspace.CurrentCamera, player.Character }
	return workspace:Raycast(Vector3.new(p.X, WATER + 80, p.Z), Vector3.new(0, -79, 0), blockers) == nil
end

local function splash(pos, big)
	local ring = bit(Vector3.new(0.15, 1.2, 1.2), Color3.new(1, 1, 1), false)
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.25
	ring.CFrame = CFrame.new(pos.X, WATER + 0.08, pos.Z) * CFrame.Angles(0, 0, math.pi / 2)
	local s = big and 5 or 3.5
	TweenService:Create(ring, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.15, s, s), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.8)
	local holder = bit(Vector3.new(0.5, 0.2, 0.5), Color3.new(1, 1, 1), false)
	holder.Transparency = 1
	holder.CFrame = CFrame.new(pos.X, WATER + 0.1, pos.Z)
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.Color = ColorSequence.new(Color3.fromRGB(235, 250, 255))
	e.Size = NumberSequence.new(0.22, 0.05)
	e.Transparency = NumberSequence.new(0.1, 1)
	e.Lifetime = NumberRange.new(0.4, 0.7)
	e.Speed = NumberRange.new(5, 9)
	e.SpreadAngle = Vector2.new(35, 35)
	e.Acceleration = Vector3.new(0, -45, 0)
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = holder
	e:Emit(big and 14 or 9)
	Debris:AddItem(holder, 1)
end

local function jump(from, dir)
	local st = FISH[math.random(#FISH)]
	local s = 0.9 + math.random() * 0.5
	local body = bit(Vector3.new(0.5, 0.6, 1.3) * s, st.body, true)
	local tail = bit(Vector3.new(0.08, 0.7, 0.5) * s, st.fin, false, "WedgePart")
	local fin = bit(Vector3.new(0.06, 0.35, 0.45) * s, st.fin, false, "WedgePart")
	local eyeL = bit(Vector3.new(0.12, 0.12, 0.12) * s, Color3.fromRGB(15, 15, 20), true)
	local eyeR = bit(Vector3.new(0.12, 0.12, 0.12) * s, Color3.fromRGB(15, 15, 20), true)
	local parts = { body, tail, fin, eyeL, eyeR }
	local L = 4.5 + math.random() * 3.5
	local H = 3.5 + math.random() * 3
	local T = 0.85 + math.random() * 0.35
	local start = Vector3.new(from.X, WATER - 0.4, from.Z)
	splash(start, false)
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local u = (os.clock() - t0) / T
		if u >= 1 then
			conn:Disconnect()
			splash(start + dir * L, true)
			for _, p in ipairs(parts) do p:Destroy() end
			return
		end
		local pos = start + dir * L * u + Vector3.new(0, H * 4 * u * (1 - u), 0)
		local vel = dir * L + Vector3.new(0, H * 4 * (1 - 2 * u), 0)
		local cf = CFrame.lookAt(pos, pos + vel)
		local wag = math.sin(os.clock() * 30) * 0.5
		local cfs = {
			cf,
			cf * CFrame.new(0, 0, 0.7 * s) * CFrame.Angles(0, wag, 0) * CFrame.Angles(0, math.pi, 0),
			cf * CFrame.new(0, 0.32 * s, 0.05 * s) * CFrame.Angles(0, math.pi, 0),
			cf * CFrame.new(0.2 * s, 0.1 * s, -0.4 * s),
			cf * CFrame.new(-0.2 * s, 0.1 * s, -0.4 * s),
		}
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end)
end

-- somewhere in open water ahead of or beside the scooter, near enough to notice
local function spot(chassis)
	local v = chassis.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
	local ahead = v.Magnitude > 2 and v.Unit or (chassis.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
	for _ = 1, 12 do
		local a = math.rad(math.random(-75, 75))
		local d = CFrame.fromAxisAngle(Vector3.yAxis, a):VectorToWorldSpace(ahead)
		local p = chassis.Position + d * (18 + math.random() * 35)
		local dir = CFrame.fromAxisAngle(Vector3.yAxis, math.random() * 6.28):VectorToWorldSpace(Vector3.zAxis)
		if openWater(p) and openWater(p + dir * 8) then return p, dir end
	end
end

local wait = GAP[1]
RunService.Heartbeat:Connect(function(dt)
	local chassis = myChassis()
	if not chassis or ((chassis.Position - ISLAND) * Vector3.new(1, 0, 1)).Magnitude > NEAR then return end
	wait -= dt
	if wait > 0 then return end
	wait = GAP[1] + math.random() * (GAP[2] - GAP[1])
	local p, dir = spot(chassis)
	if not p then return end
	jump(p, dir)
	if math.random() < PAIR then
		task.delay(0.35, function()
			local side = dir:Cross(Vector3.yAxis)
			local p2 = p + side * (1.5 + math.random() * 2) - dir * 1.5
			if openWater(p2) and openWater(p2 + dir * 8) then jump(p2, dir) end
		end)
	end
end)
