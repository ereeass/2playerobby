-- Lava cannons (Workspace > Lava Cannons, Models tagged "LavaCannon"): each fires a flaming lava
-- ball across the road, over and over. A ball that hits a scooter (or one of its riders) ends that
-- run in the death popup (ScooterSystem.DeathManager: SKIP / REVIVE), like the laser gates; a player
-- on foot it hits just dies. It bursts on the first other thing it hits, or drops into the sea.
-- Per-cannon attributes (on the Model):
--   Interval  seconds between shots          (default 2.8)
--   Offset    seconds before its first shot  (default 0; staggers the cannons)
--   Speed     ball speed, studs per second   (default 55)
--   Range     studs a ball flies at most     (default 50)
-- The ball leaves from the Muzzle part, in the direction it faces (-Z).

local Sfx = require(game:GetService("ReplicatedStorage"):WaitForChild("ObstacleSfx"))   -- obstacle sound effects
local CollectionService   = game:GetService("CollectionService")
local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local TweenService        = game:GetService("TweenService")
local Debris              = game:GetService("Debris")
local ServerScriptService = game:GetService("ServerScriptService")

local ScooterSystem = ServerScriptService:WaitForChild("ScooterSystem")
local RideManager   = require(ScooterSystem:WaitForChild("RideManager"))
local DeathManager  = require(ScooterSystem:WaitForChild("DeathManager"))
local scooters      = workspace:WaitForChild("RideSystem"):WaitForChild("Scooters")

local BALL = 3.2
local LAVA = Color3.fromRGB(255, 96, 16)
local HOT  = Color3.fromRGB(255, 170, 40)
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local balls = Instance.new("Folder")
balls.Name = "LavaBalls"
balls.Parent = workspace

local function whoHit(hit)
	local model = hit:FindFirstAncestorOfClass("Model")
	while model do
		if model.Parent == scooters then return RideManager.Rides[model], nil end
		local plr = Players:GetPlayerFromCharacter(model)
		if plr then return RideManager.PlayerRide[plr], plr end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil, nil
end

local function strike(hit)
	local ride, plr = whoHit(hit)
	if ride then
		if not ride._ended and not ride.Down then DeathManager.Hit(ride) end
		return true
	elseif plr and plr.Character then
		local hum = plr.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then hum.Health = 0 end
		return true
	end
	return false
end

-- a one-off burst of particles at `cf`
local function burst(cf, count, props)
	local holder = Instance.new("Part")
	holder.Anchored = true; holder.CanCollide = false; holder.CanTouch = false; holder.CanQuery = false
	holder.Transparency = 1; holder.Size = Vector3.new(1, 1, 1); holder.CFrame = cf
	holder.Parent = balls
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	for k, v in pairs(props) do e[k] = v end
	e.Parent = holder
	e:Emit(count)
	Debris:AddItem(holder, 3)
end

local function splash(at)
	burst(CFrame.new(at), 30, {
		Texture = FIRE, Color = ColorSequence.new(HOT, LAVA), LightEmission = 0.8,
		Size = NumberSequence.new(2.2, 0.4), Lifetime = NumberRange.new(0.4, 0.9),
		Speed = NumberRange.new(10, 22), SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, -30, 0),
	})
	burst(CFrame.new(at), 8, {
		Texture = SMOKE, Color = ColorSequence.new(Color3.fromRGB(70, 64, 64)), Transparency = NumberSequence.new(0.4, 1),
		Size = NumberSequence.new(3, 7), Lifetime = NumberRange.new(1, 1.6), Speed = NumberRange.new(2, 5),
		SpreadAngle = Vector2.new(180, 180),
	})
end

local function newBall(cf)
	local b = Instance.new("Part")
	b.Name = "LavaBall"; b.Shape = Enum.PartType.Ball; b.Size = Vector3.one * BALL
	b.Material = Enum.Material.Neon; b.Color = LAVA
	b.Anchored = true; b.CanCollide = false; b.CanTouch = false; b.CanQuery = false; b.CastShadow = false
	b.CFrame = cf
	local crust = Instance.new("Part")   -- a dark cracked shell round the glow
	crust.Name = "Crust"; crust.Shape = Enum.PartType.Ball; crust.Size = Vector3.one * (BALL * 0.92)
	crust.Material = Enum.Material.CrackedLava; crust.Color = Color3.fromRGB(80, 36, 26); crust.Transparency = 0.25
	crust.Anchored = true; crust.CanCollide = false; crust.CanTouch = false; crust.CanQuery = false; crust.CastShadow = false
	crust.CFrame = cf; crust.Parent = b
	local f = Instance.new("Fire"); f.Size = 4; f.Heat = 3; f.Color = LAVA; f.SecondaryColor = Color3.fromRGB(255, 40, 0); f.Parent = b
	local l = Instance.new("PointLight"); l.Range = 16; l.Brightness = 2; l.Color = LAVA; l.Parent = b
	b.Parent = balls
	return b, crust
end

local function arm(cannon)
	if not cannon:IsA("Model") then return end
	local muzzle = cannon:WaitForChild("Muzzle", 5)
	local barrel = cannon:WaitForChild("Barrel", 5)
	if not (muzzle and barrel) then return end
	local rest = {}
	for _, p in ipairs(barrel:GetDescendants()) do if p:IsA("BasePart") then rest[p] = p.CFrame end end

	local function recoil()
		local back = muzzle.CFrame.LookVector * -0.9
		for p, cf in pairs(rest) do
			p.CFrame = cf + back
			TweenService:Create(p, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = cf }):Play()
		end
	end

	local function fire()
		local dir = muzzle.CFrame.LookVector
		recoil()
		Sfx.Play("LavaCannon", muzzle)
		burst(muzzle.CFrame, 12, {
			Texture = FIRE, Color = ColorSequence.new(HOT, LAVA), LightEmission = 1,
			Size = NumberSequence.new(2.5, 0.5), Lifetime = NumberRange.new(0.15, 0.3),
			Speed = NumberRange.new(8, 16), SpreadAngle = Vector2.new(30, 30), EmissionDirection = Enum.NormalId.Front,
		})
		burst(muzzle.CFrame, 6, {
			Texture = SMOKE, Color = ColorSequence.new(Color3.fromRGB(90, 84, 84)), Transparency = NumberSequence.new(0.3, 1),
			Size = NumberSequence.new(2, 6), Lifetime = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(3, 6),
			SpreadAngle = Vector2.new(35, 35), EmissionDirection = Enum.NormalId.Front,
		})
		local pos = muzzle.Position
		local ball, crust = newBall(CFrame.new(pos))
		local speed = cannon:GetAttribute("Speed") or 55
		local range = cannon:GetAttribute("Range") or 50
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { cannon, balls }
		local flown, spin = 0, 0
		while flown < range and ball.Parent do
			local dt = RunService.Heartbeat:Wait()
			local step = math.min(speed * dt, range - flown)
			local res = workspace:Spherecast(pos, BALL / 2, dir * step, params)
			if res then
				strike(res.Instance)
				splash(res.Position)
				ball:Destroy()
				return
			end
			pos += dir * step
			flown += step
			spin += dt * 8
			ball.CFrame = CFrame.new(pos) * CFrame.Angles(spin, 0, 0)
			crust.CFrame = ball.CFrame
		end
		-- out of range: it drops into the sea and fizzles
		if ball.Parent then
			local t = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			TweenService:Create(ball, t, { CFrame = ball.CFrame + dir * 20 + Vector3.new(0, -30, 0), Transparency = 1 }):Play()
			TweenService:Create(crust, t, { CFrame = ball.CFrame + dir * 20 + Vector3.new(0, -30, 0), Transparency = 1 }):Play()
			Debris:AddItem(ball, 0.9)
		end
	end

	task.spawn(function()
		task.wait(cannon:GetAttribute("Offset") or 0)
		while cannon.Parent do
			local started = os.clock()
			local ok, err = pcall(fire)
			if not ok then warn("[LavaCannons] " .. cannon:GetFullName() .. ": " .. tostring(err)) end
			task.wait(math.max(0.2, (cannon:GetAttribute("Interval") or 2.8) - (os.clock() - started)))
		end
	end)
end

CollectionService:GetInstanceAddedSignal("LavaCannon"):Connect(arm)
for _, c in ipairs(CollectionService:GetTagged("LavaCannon")) do task.spawn(arm, c) end
