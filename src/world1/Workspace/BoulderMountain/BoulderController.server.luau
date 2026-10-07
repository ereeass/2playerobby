-- Boulder mountain: big stud boulders tumble down the Slope and come to rest
-- on the Lane (the BoulderCatcher stops them going over the edge). The TrafficLights over the road run the show:
--   GREEN   no rocks. Any boulders left from the last fall fade away.
--   YELLOW  a short warning.
--   RED     boulders come down. Nothing stops you driving through on red,
--           but a boulder that hits you ends the run.
-- A boulder hitting a scooter ends that run in the death popup
-- (ScooterSystem.DeathManager: SKIP / REVIVE), like the water, landmines and gates.
-- Someone on foot just dies.
--
-- Tuning: attributes on the BoulderMountain model (all optional)
--   GreenTime    seconds of green                         (default 7)
--   YellowTime   seconds of yellow                        (default 1.5)
--   RedTime      seconds of red (rocks fall during it)    (default 6)
--   MinBoulders / MaxBoulders   rocks per red light       (default 3 / 5)
--   MinSize / MaxSize           boulder size in studs     (default 10 / 15)

local Players             = game:GetService("Players")
local TweenService        = game:GetService("TweenService")
local ServerScriptService = game:GetService("ServerScriptService")

local model   = script.Parent
local spawnAt = model:WaitForChild("BoulderSpawn")
local lane    = model:WaitForChild("Road"):WaitForChild("Lane")
local lightsM = model:WaitForChild("TrafficLights")

local ok, RideManager, DeathManager = pcall(function()
	local ss = ServerScriptService:WaitForChild("ScooterSystem", 10)
	return require(ss.RideManager), require(ss.DeathManager)
end)
if not ok then RideManager, DeathManager = nil, nil end
local scooters = workspace:FindFirstChild("RideSystem") and workspace.RideSystem:FindFirstChild("Scooters")

local ROCK_COLORS = {
	Color3.fromRGB(88, 86, 92),
	Color3.fromRGB(105, 102, 104),
	Color3.fromRGB(75, 74, 80),
}

local function attr(name, default) return model:GetAttribute(name) or default end

-- Boulders stay on the road: an invisible BoulderCatcher runs along the far edge of the
-- Lane. It only collides with the Boulders group - scooters, riders and players go
-- straight through it and can still fall off the edge.
local PhysicsService = game:GetService("PhysicsService")
local function setupGroups()
	for _, g in ipairs({ "Boulders", "BoulderCatcher" }) do
		if not PhysicsService:IsCollisionGroupRegistered(g) then PhysicsService:RegisterCollisionGroup(g) end
	end
	for _, g in ipairs(PhysicsService:GetRegisteredCollisionGroups()) do
		PhysicsService:CollisionGroupSetCollidable("BoulderCatcher", g.name, g.name == "Boulders")
	end
end
pcall(setupGroups)
task.delay(5, function() pcall(setupGroups) end)   -- catch groups other scripts make at startup

---------------------------------------------------------------- killing
local function whoHit(hit)
	local m = hit:FindFirstAncestorOfClass("Model")
	while m do
		if scooters and m.Parent == scooters and RideManager then
			return RideManager.Rides[m], nil
		end
		local plr = Players:GetPlayerFromCharacter(m)
		if plr then
			return RideManager and RideManager.PlayerRide[plr], plr
		end
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

---------------------------------------------------------------- boulders
local live = {}   -- every boulder dropped since the last green

local function makeBoulder()
	local minS, maxS = attr("MinSize", 10), attr("MaxSize", 15)
	local size = minS + math.random() * (maxS - minS)
	local color = ROCK_COLORS[math.random(#ROCK_COLORS)]
	-- keep big rocks between the ridges (slope is 40 wide) and clear of the cliff behind
	local spread = math.max(0, 20 - size / 2 - 1)
	local cf = spawnAt.CFrame * CFrame.new((math.random() * 2 - 1) * spread, size * 0.6, -size * 0.35)
		* CFrame.Angles(math.random() * 6.28, math.random() * 6.28, math.random() * 6.28)

	local function piece(sz, offset)
		local p = Instance.new("Part")
		p.Name = "Boulder"
		p.Size = sz
		p.CFrame = cf * offset
		p.Color = color
		p.Material = Enum.Material.Plastic
		p.MaterialVariant = "Studs"
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CustomPhysicalProperties = PhysicalProperties.new(3, 0.35, 0.15)
		p.CollisionGroup = "Boulders"
		return p
	end
	-- a chunky main block with two lumps welded on, so it reads as a rock
	local main = piece(Vector3.one * size, CFrame.identity)
	local rock = Instance.new("Model")
	rock.Name = "Boulder"
	main.Parent = rock
	for _, lump in ipairs({
		piece(Vector3.one * size * 0.7, CFrame.new(size * 0.3, size * 0.25, 0)),
		piece(Vector3.one * size * 0.6, CFrame.new(-size * 0.2, -size * 0.1, size * 0.3)),
	}) do
		lump.Parent = rock
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = main, lump
		w.Parent = lump
	end
	rock.PrimaryPart = main
	rock.Parent = model

	for _, p in ipairs(rock:GetChildren()) do
		if p:IsA("BasePart") then
			p.Touched:Connect(function(hit)
				if hit:IsDescendantOf(model) or rock:GetAttribute("Fading") then return end
				if main.AssemblyLinearVelocity.Magnitude > 3 then crush(hit) end
			end)
		end
	end
	pcall(function() main:SetNetworkOwner(nil) end)
	-- a shove down the slope and a tumble
	main.AssemblyLinearVelocity = spawnAt.CFrame.LookVector * (12 + math.random() * 8)
	main.AssemblyAngularVelocity = spawnAt.CFrame.RightVector * -(4 + math.random() * 3)
	live[rock] = true
end

-- on green: every boulder from the last fall fades out (and stops being deadly)
local function fadeAll()
	for rock in pairs(live) do
		live[rock] = nil
		if rock.Parent then
			rock:SetAttribute("Fading", true)
			for _, p in ipairs(rock:GetChildren()) do
				if p:IsA("BasePart") then
					p.CanCollide = false
					p.CanTouch = false
					p.Anchored = true
					TweenService:Create(p, TweenInfo.new(1.2, Enum.EasingStyle.Quad), { Transparency = 1 }):Play()
				end
			end
			task.delay(1.3, function() rock:Destroy() end)
		end
	end
end

-- boulders that roll off the edge are removed once they're well out of sight
task.spawn(function()
	while model.Parent do
		task.wait(1)
		for rock in pairs(live) do
			local main = rock.PrimaryPart
			if not rock.Parent or not main or lane.CFrame:PointToObjectSpace(main.Position).Y < -150 then
				live[rock] = nil
				rock:Destroy()
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
	local n = math.random(attr("MinBoulders", 3), attr("MaxBoulders", 5))
	for _ = 1, n do
		makeBoulder()
		task.wait(0.5 + math.random() * 0.8)
	end
	task.wait(math.max(0, redEnds - os.clock()))
end
