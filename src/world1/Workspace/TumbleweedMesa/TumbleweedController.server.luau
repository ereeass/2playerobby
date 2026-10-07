-- Tumbleweed mesa: big tumbleweeds bounce and roll down the Slope (the dune), across the
-- Lane and off the far edge of the map. (Road.BoulderCatcher is switched off so they can
-- fall; set its CanCollide back on to make them stop on the Lane again.) The TrafficLights run the show, like
-- the BoulderMountain:
--   GREEN   no tumbleweeds. Any left from the last lot fade away.
--   YELLOW  a short warning.
--   RED     tumbleweeds come down. Nothing stops you driving through on red, but one
--           that hits you ends the run (death popup: ScooterSystem.DeathManager, SKIP /
--           REVIVE), like the water. Someone on foot just dies.
-- Tuning: attributes on this model (GreenTime, YellowTime, RedTime, MinTumbleweeds,
-- MaxTumbleweeds, MinSize, MaxSize).

local Players             = game:GetService("Players")
local TweenService        = game:GetService("TweenService")
local PhysicsService      = game:GetService("PhysicsService")
local ServerScriptService = game:GetService("ServerScriptService")

local model   = script.Parent
local spawnAt = model:WaitForChild("TumbleweedSpawn")
local lane    = model:WaitForChild("Road"):WaitForChild("Lane")
local lightsM = model:WaitForChild("TrafficLights")

local ok, RideManager, DeathManager = pcall(function()
	local ss = ServerScriptService:WaitForChild("ScooterSystem", 10)
	return require(ss.RideManager), require(ss.DeathManager)
end)
if not ok then RideManager, DeathManager = nil, nil end
local scooters = workspace:FindFirstChild("RideSystem") and workspace.RideSystem:FindFirstChild("Scooters")

local TWIGS = { Color3.fromRGB(160, 120, 70), Color3.fromRGB(139, 100, 58), Color3.fromRGB(180, 140, 86), Color3.fromRGB(120, 88, 52), Color3.fromRGB(196, 164, 110) }

local function attr(name, default) return model:GetAttribute(name) or default end

-- the catcher only ever stops tumbleweeds
local function setupGroups()
	for _, g in ipairs({ "Boulders", "BoulderCatcher" }) do
		if not PhysicsService:IsCollisionGroupRegistered(g) then PhysicsService:RegisterCollisionGroup(g) end
	end
	for _, g in ipairs(PhysicsService:GetRegisteredCollisionGroups()) do
		PhysicsService:CollisionGroupSetCollidable("BoulderCatcher", g.name, g.name == "Boulders")
	end
end
pcall(setupGroups)
task.delay(5, function() pcall(setupGroups) end)

---------------------------------------------------------------- killing
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

---------------------------------------------------------------- traffic lights
local lamps = { Red = {}, Yellow = {}, Green = {} }
for _, p in ipairs(lightsM:GetDescendants()) do
	if p:IsA("BasePart") and lamps[p.Name] then table.insert(lamps[p.Name], p) end
end
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

---------------------------------------------------------------- tumbleweeds
local live = {}

local function makeTumbleweed()
	local size = attr("MinSize", 9) + math.random() * (attr("MaxSize", 13) - attr("MinSize", 9))
	local R = size / 2
	local spread = math.max(0, 20 - R - 1)
	local cf = spawnAt.CFrame * CFrame.new((math.random() * 2 - 1) * spread, size * 0.6, -size * 0.35)

	local weed = Instance.new("Model")
	weed.Name = "Tumbleweed"
	-- the ball that rolls and bounces: light and springy, invisible
	local core = Instance.new("Part")
	core.Name = "Core"
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.one * size
	core.CFrame = cf
	core.Transparency = 1
	core.CastShadow = false
	core.CustomPhysicalProperties = PhysicalProperties.new(0.25, 0.4, 0.45, 1, 1)
	core.CollisionGroup = "Boulders"
	core.Parent = weed
	-- the look: a tangle of twigs round a sphere, welded to the ball
	for k = 1, 75 do
		local u, v = math.random() * 2 - 1, math.random() * math.pi * 2
		local r = R * (0.5 + math.random() * 0.4)
		local dirv = Vector3.new(math.sqrt(1 - u * u) * math.cos(v), u, math.sqrt(1 - u * u) * math.sin(v))
		local twig = Instance.new("Part")
		twig.Name = "Twig"
		twig.Size = Vector3.new(0.375, 0.375, size * (0.3 + math.random() * 0.25))
		twig.CFrame = CFrame.lookAt(cf.Position + dirv * r, cf.Position + dirv * r + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)) * CFrame.Angles(0, 0, math.random() * 6.28)
		twig.Color = TWIGS[math.random(#TWIGS)]
		twig.Material = Enum.Material.Plastic
		twig.MaterialVariant = "Studs"
		twig.CanCollide = false twig.CanTouch = false twig.CanQuery = false
		twig.Massless = true
		twig.Parent = weed
		local w = Instance.new("WeldConstraint") w.Part0 = core w.Part1 = twig w.Parent = twig
	end
	weed.PrimaryPart = core
	weed.Parent = model

	core.Touched:Connect(function(hit)
		if hit:IsDescendantOf(model) or weed:GetAttribute("Fading") then return end
		if core.AssemblyLinearVelocity.Magnitude > 3 then crush(hit) end
	end)
	pcall(function() core:SetNetworkOwner(nil) end)
	core.AssemblyLinearVelocity = spawnAt.CFrame.LookVector * (14 + math.random() * 8) + Vector3.new(0, 6, 0)
	core.AssemblyAngularVelocity = spawnAt.CFrame.RightVector * -(3 + math.random() * 3)
	live[weed] = true
end

-- on green: every tumbleweed from the last lot fades out (and stops being deadly)
local function fadeAll()
	for weed in pairs(live) do
		live[weed] = nil
		if weed.Parent then
			weed:SetAttribute("Fading", true)
			for _, p in ipairs(weed:GetChildren()) do
				if p:IsA("BasePart") then
					p.CanCollide = false p.CanTouch = false p.Anchored = true
					if p.Name == "Twig" then TweenService:Create(p, TweenInfo.new(1.2, Enum.EasingStyle.Quad), { Transparency = 1 }):Play() end
				end
			end
			task.delay(1.3, function() weed:Destroy() end)
		end
	end
end

-- any that roll off somewhere are removed once well out of sight
task.spawn(function()
	while model.Parent do
		task.wait(1)
		for weed in pairs(live) do
			local core = weed.PrimaryPart
			if not weed.Parent or not core or lane.CFrame:PointToObjectSpace(core.Position).Y < -150 then
				live[weed] = nil
				weed:Destroy()
			end
		end
	end
end)

---------------------------------------------------------------- the loop
while model.Parent do
	setLight("Green")
	fadeAll()
	task.wait(attr("GreenTime", 7))

	setLight("Yellow")
	task.wait(attr("YellowTime", 1.5))

	setLight("Red")
	local redEnds = os.clock() + attr("RedTime", 6)
	local n = math.random(attr("MinTumbleweeds", 3), attr("MaxTumbleweeds", 5))
	for _ = 1, n do
		makeTumbleweed()
		task.wait(0.5 + math.random() * 0.8)
	end
	task.wait(math.max(0, redEnds - os.clock()))
end
