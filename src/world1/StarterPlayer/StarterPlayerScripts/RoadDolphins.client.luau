-- Dolphins leaping alongside Road 1 and Road 2 (the open-water stretch after the Checkpoint 1
-- Parking Lot), on THIS machine only and only while this player rides a scooter (driver or
-- motor rider) along them - like the crab island fish (CrabIslandFish), just bigger. Every
-- few seconds a pair (now and then one, or three) jumps out of open water beside the road,
-- heading the same way as the riders, with a big splash in and out. Decoration only.

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris       = game:GetService("Debris")

local WATER = 181.06
local GAP   = { 5, 9 }        -- seconds between jumps
local MARGIN = 45             -- studs beside the roads where the dolphins show
local ROADS = { "Road1", "Road2" }
local GREY, BELLY, DARK = Color3.fromRGB(122, 140, 160), Color3.fromRGB(214, 222, 230), Color3.fromRGB(20, 24, 30)

local player = Players.LocalPlayer
local roads = workspace:WaitForChild("Roads")
local blockers = RaycastParams.new()
blockers.FilterType = Enum.RaycastFilterType.Exclude

local function myChassis()
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local weld = root and root:FindFirstChild("ScooterRiderWeld")
	return weld and weld.Part0
end

-- is the scooter on Road 1 / Road 2? (inside their box, plus a margin)
local boxes = {}
local function onRoads(p)
	if #boxes == 0 then
		for _, n in ipairs(ROADS) do
			local r = roads:FindFirstChild(n)
			if r and r:IsA("Model") then local cf, s = r:GetBoundingBox() table.insert(boxes, { cf = cf, h = s / 2 }) end
		end
	end
	for _, b in ipairs(boxes) do
		local l = b.cf:PointToObjectSpace(p)
		if math.abs(l.X) < b.h.X + 10 and math.abs(l.Z) < b.h.Z + 10 and math.abs(l.Y) < b.h.Y + 20 then return true end
	end
	return false
end

local function bit(size, col, round, cls)
	local p = Instance.new(cls or "Part")
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
	p.Size, p.Color, p.Material = size, col, Enum.Material.SmoothPlastic
	if round then local m = Instance.new("SpecialMesh") m.MeshType = Enum.MeshType.Sphere m.Parent = p end
	p.Parent = workspace.CurrentCamera
	return p
end

local function openWater(p)
	blockers.FilterDescendantsInstances = { workspace.CurrentCamera, player.Character }
	return workspace:Raycast(Vector3.new(p.X, WATER + 80, p.Z), Vector3.new(0, -79, 0), blockers) == nil
end

local function splash(pos, size)
	local ring = bit(Vector3.new(0.15, 2, 2), Color3.new(1, 1, 1))
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.2
	ring.CFrame = CFrame.new(pos.X, WATER + 0.08, pos.Z) * CFrame.Angles(0, 0, math.pi / 2)
	TweenService:Create(ring, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.15, size, size), Transparency = 1 }):Play()
	Debris:AddItem(ring, 1)
	local holder = bit(Vector3.new(1.5, 0.2, 1.5), Color3.new(1, 1, 1))
	holder.Transparency = 1
	holder.CFrame = CFrame.new(pos.X, WATER + 0.1, pos.Z)
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.Color = ColorSequence.new(Color3.fromRGB(235, 250, 255))
	e.Size = NumberSequence.new(0.4, 0.08)
	e.Transparency = NumberSequence.new(0.05, 1)
	e.Lifetime = NumberRange.new(0.5, 0.9)
	e.Speed = NumberRange.new(7, 13)
	e.SpreadAngle = Vector2.new(30, 30)
	e.Acceleration = Vector3.new(0, -50, 0)
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = holder
	e:Emit(22)
	Debris:AddItem(holder, 1.2)
end

local function jump(from, dir, delay)
	task.delay(delay or 0, function()
		local s = 0.9 + math.random() * 0.25
		local pieces = {
			{ bit(Vector3.new(1.35, 1.3, 4.8) * s, GREY, true), CFrame.new() },
			{ bit(Vector3.new(1.05, 0.8, 3.8) * s, BELLY, true), CFrame.new(0, -0.3 * s, -0.2 * s) },
			{ bit(Vector3.new(0.5, 0.45, 1.3) * s, GREY, true), CFrame.new(0, -0.15 * s, -2.6 * s) },
			{ bit(Vector3.new(0.14, 0.14, 0.14) * s, DARK, true), CFrame.new(0.45 * s, 0.1 * s, -1.8 * s) },
			{ bit(Vector3.new(0.14, 0.14, 0.14) * s, DARK, true), CFrame.new(-0.45 * s, 0.1 * s, -1.8 * s) },
			{ bit(Vector3.new(0.14, 0.9, 1.1) * s, GREY, false, "WedgePart"), CFrame.new(0, 0.95 * s, 0.2 * s) * CFrame.Angles(0, math.pi, 0) },
			{ bit(Vector3.new(0.12, 0.7, 0.9) * s, GREY, false, "WedgePart"), CFrame.new(0.65 * s, -0.4 * s, -0.8 * s) * CFrame.Angles(0, math.pi, math.rad(-60)) },
			{ bit(Vector3.new(0.12, 0.7, 0.9) * s, GREY, false, "WedgePart"), CFrame.new(-0.65 * s, -0.4 * s, -0.8 * s) * CFrame.Angles(0, math.pi, math.rad(60)) },
		}
		local fluke = bit(Vector3.new(2.1, 0.14, 0.8) * s, GREY, true)
		local all = { fluke }
		for _, pc in ipairs(pieces) do table.insert(all, pc[1]) end
		local L = 10 + math.random() * 4
		local H = 5 + math.random() * 3
		local T = 1.4 + math.random() * 0.4
		local start = Vector3.new(from.X, WATER - 1, from.Z)
		splash(start, 6)
		local t0 = os.clock()
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local u = (os.clock() - t0) / T
			if u >= 1 then
				conn:Disconnect()
				splash(start + dir * L, 8)
				for _, p in ipairs(all) do p:Destroy() end
				return
			end
			local pos = start + dir * L * u + Vector3.new(0, H * 4 * u * (1 - u), 0)
			local vel = dir * L + Vector3.new(0, H * 4 * (1 - 2 * u), 0)
			local cf = CFrame.lookAt(pos, pos + vel)
			local list, cfs = {}, {}
			for _, pc in ipairs(pieces) do list[#list + 1] = pc[1] cfs[#cfs + 1] = cf * pc[2] end
			list[#list + 1] = fluke
			cfs[#cfs + 1] = cf * CFrame.new(0, 0, 2.5 * s) * CFrame.Angles(math.sin(os.clock() * 10) * 0.35, 0, 0) * CFrame.new(0, 0, 0.3 * s)
			workspace:BulkMoveTo(list, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end)
	end)
end

-- open water to one side of the road, a little ahead; they swim the way the riders go
local function spot(chassis)
	local v = chassis.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
	local ahead = v.Magnitude > 2 and v.Unit or (chassis.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
	local side = ahead:Cross(Vector3.yAxis)
	for _ = 1, 14 do
		local p = chassis.Position + ahead * (8 + math.random() * 30) + side * (math.random() < 0.5 and -1 or 1) * (16 + math.random() * (MARGIN - 16))
		local dir = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(math.random(-20, 20))):VectorToWorldSpace(ahead)
		if openWater(p) and openWater(p + dir * 14) then return p, dir, side end
	end
end

local wait = 2
RunService.Heartbeat:Connect(function(dt)
	local chassis = myChassis()
	if not chassis or not onRoads(chassis.Position) then return end
	wait -= dt
	if wait > 0 then return end
	wait = GAP[1] + math.random() * (GAP[2] - GAP[1])
	local p, dir, side = spot(chassis)
	if not p then wait = 0.5 return end
	local count = (math.random() < 0.15) and 1 or ((math.random() < 0.15) and 3 or 2)
	for i = 1, count do
		local off = side * ((i - 1) * 2.8) - dir * ((i - 1) * 1.2)
		if i == 1 or (openWater(p + off) and openWater(p + off + dir * 14)) then jump(p + off, dir, (i - 1) * 0.18) end
	end
end)
