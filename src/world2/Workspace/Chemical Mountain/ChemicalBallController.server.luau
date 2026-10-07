-- Chemical Mountain (World 2, the lab road): two sections, each with its own traffic light and
-- slope, and a resting spot between them. A copy of the Chocolate Mountain's controller; only the
-- balls are different (big glass balls of glowing chemicals instead of chocolate truffles).
-- Built on the Boulder Mountain's logic, per section:
--   GREEN   no boulders (any left from the last fall fade away)
--   YELLOW  a short warning
--   RED     chemical balls roll down that section's slope, across the road and off its
--           far edge into the sea, where they disappear. A moving boulder that hits a
--           scooter ends the run (DeathManager: SKIP / REVIVE); someone on foot just dies.
-- Every section runs its own clock (its GreenTime / YellowTime / RedTime / Phase attributes,
-- all different), so the three lights never line up the same way twice.
-- Also per section: MinBoulders / MaxBoulders, MinSize / MaxSize.

local Sfx = require(game:GetService("ReplicatedStorage"):WaitForChild("ObstacleSfx"))   -- obstacle sound effects
local Players             = game:GetService("Players")
local TweenService        = game:GetService("TweenService")
local PhysicsService      = game:GetService("PhysicsService")
local ServerScriptService = game:GetService("ServerScriptService")

local model = script.Parent
local SEA   = model:GetAttribute("SeaLevel") or 133

local ok, RideManager, DeathManager = pcall(function()
	local ss = ServerScriptService:WaitForChild("ScooterSystem", 10)
	return require(ss.RideManager), require(ss.DeathManager)
end)
if not ok then RideManager, DeathManager = nil, nil end
local scooters = workspace:FindFirstChild("RideSystem") and workspace.RideSystem:FindFirstChild("Scooters")

pcall(function()
	if not PhysicsService:IsCollisionGroupRegistered("Boulders") then PhysicsService:RegisterCollisionGroup("Boulders") end
end)

local COLORS = { Color3.fromRGB(110, 255, 60), Color3.fromRGB(190, 70, 255), Color3.fromRGB(60, 230, 200) }
local GLASS  = Color3.fromRGB(220, 245, 255)
local BAND   = Color3.fromRGB(70, 76, 84)

local function whoHit(hit)
	local m = hit:FindFirstAncestorOfClass("Model")
	while m do
		if scooters and m.Parent == scooters and RideManager then return RideManager.Rides[m], nil end
		local plr = Players:GetPlayerFromCharacter(m)
		if plr then return RideManager and RideManager.PlayerRide[plr], plr end
		m = m:FindFirstAncestorOfClass("Model")
	end
end

local function crush(hit)
	local ride, plr = whoHit(hit)
	if ride then
		if DeathManager and not ride._ended and not ride.Down then DeathManager.Hit(ride) end
	elseif plr and plr.Character then
		local hum = plr.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then hum.Health = 0 end
	end
end

local function fade(rock, time)
	if not rock.Parent or rock:GetAttribute("Fading") then return end
	rock:SetAttribute("Fading", true)
	for _, p in ipairs(rock:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CanCollide, p.CanTouch, p.Anchored = false, false, true
			TweenService:Create(p, TweenInfo.new(time, Enum.EasingStyle.Quad), { Transparency = 1 }):Play()
		end
	end
	task.delay(time + 0.1, function() rock:Destroy() end)
end

local function runSection(sec)
	local spawnAt = sec:WaitForChild("BoulderSpawn")
	local lamps = { Red = {}, Yellow = {}, Green = {} }
	for _, p in ipairs(sec:WaitForChild("TrafficLights"):GetDescendants()) do
		if p:IsA("BasePart") and lamps[p.Name] then table.insert(lamps[p.Name], p) end
	end
	local function attr(n, d) return sec:GetAttribute(n) or d end
	local function setLight(which)
		for name, list in pairs(lamps) do
			local on = name == which
			for _, lamp in ipairs(list) do
				local c = lamp:GetAttribute("OnColor") or lamp.Color
				lamp.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
				lamp.Color = on and c or c:Lerp(Color3.new(0, 0, 0), 0.75)
				local light = lamp:FindFirstChildOfClass("PointLight")
				if light then light.Enabled = on end
			end
		end
	end

	local live = {}
	-- a big chemical ball: a glass sphere (the only part that collides, so it rolls) full of
	-- glowing liquid, a metal band round it and a few bubbles inside
	local function makeBoulder()
		local size = attr("MinSize", 6) + math.random() * (attr("MaxSize", 8.5) - attr("MinSize", 6))
		local color = COLORS[math.random(#COLORS)]
		local spread = math.max(0, spawnAt.Size.X / 2 - size * 0.6)
		local cf = spawnAt.CFrame * CFrame.new((math.random() * 2 - 1) * spread, size * 0.6, 0)
		local rock = Instance.new("Model")
		rock.Name = "ChemicalBall"
		local function piece(shape, sz, offset, col, solid, mat, t)
			local p = Instance.new("Part")
			p.Name = "Boulder"
			p.Shape = shape
			p.Size = sz
			p.CFrame = cf * offset
			p.Color = col
			p.Material = mat
			p.Transparency = t or 0
			p.CastShadow = false
			p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
			p.CollisionGroup = "Boulders"
			if solid then
				p.CustomPhysicalProperties = PhysicalProperties.new(3, 0.5, 0.1)
			else
				p.CanCollide = false
				p.Massless = true
			end
			p.Parent = rock
			return p
		end
		local main = piece(Enum.PartType.Ball, Vector3.one * size, CFrame.identity, GLASS, true, Enum.Material.Glass, 0.45)
		local extras = {
			piece(Enum.PartType.Ball, Vector3.one * size * 0.82, CFrame.identity, color, false, Enum.Material.Neon, 0.1),
			piece(Enum.PartType.Cylinder, Vector3.new(size * 0.16, size * 1.02, size * 1.02), CFrame.Angles(0, 0, math.rad(20)), BAND, false, Enum.Material.Metal),
		}
		for _ = 1, 4 do
			local dir = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit
			local s = size * (0.1 + math.random() * 0.08)
			table.insert(extras, piece(Enum.PartType.Ball, Vector3.one * s, CFrame.new(dir * size * 0.3), color:Lerp(Color3.new(1, 1, 1), 0.5), false, Enum.Material.Neon))
		end
		local glow = Instance.new("PointLight")
		glow.Color = color; glow.Range = size * 1.4; glow.Brightness = 1.5
		glow.Parent = main
		for _, x in ipairs(extras) do
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = main, x
			w.Parent = x
		end
		rock.PrimaryPart = main
		rock.Parent = model
		Sfx.Play("ChemicalBall", main)
		for _, p in ipairs(rock:GetChildren()) do
			if p:IsA("BasePart") then
				p.Touched:Connect(function(hit)
					if hit:IsDescendantOf(model) or rock:GetAttribute("Fading") then return end
					if main.AssemblyLinearVelocity.Magnitude > 3 then crush(hit) end
				end)
			end
		end
		pcall(function() main:SetNetworkOwner(nil) end)
		main.AssemblyLinearVelocity = spawnAt.CFrame.LookVector * (16 + math.random() * 8)
		main.AssemblyAngularVelocity = spawnAt.CFrame.RightVector * -(4 + math.random() * 3)
		live[rock] = true
	end

	-- a boulder that reaches the sea disappears; one that stops somewhere fades on the next green
	task.spawn(function()
		while sec.Parent do
			task.wait(0.2)
			for rock in pairs(live) do
				local main = rock.PrimaryPart
				if not rock.Parent or not main then
					live[rock] = nil
				elseif main.Position.Y < SEA + 1.5 then
					live[rock] = nil
					fade(rock, 0.35)
				end
			end
		end
	end)

	task.wait(attr("Phase", 0))
	while sec.Parent do
		setLight("Green")
		for rock in pairs(live) do live[rock] = nil fade(rock, 1) end
		task.wait(attr("GreenTime", 5))
		setLight("Yellow")
		task.wait(attr("YellowTime", 1.2))
		setLight("Red")
		local redEnds = os.clock() + attr("RedTime", 4)
		for _ = 1, math.random(attr("MinBoulders", 2), attr("MaxBoulders", 4)) do
			if os.clock() >= redEnds - 1 then break end
			makeBoulder()
			task.wait(0.6 + math.random() * 0.8)
		end
		task.wait(math.max(0, redEnds - os.clock()))
	end
end

for _, sec in ipairs(model:GetChildren()) do
	if sec:IsA("Model") and sec.Name:match("^Section") then task.spawn(runSection, sec) end
end
