-- Pirate ship cannons (Workspace > Pirate Ships, Models tagged "ShipCannon"): each ship's broadside
-- fires iron cannonballs across the dock road, over and over. A ball that hits a scooter (or one of
-- its riders) ends that run in the death popup (ScooterSystem.DeathManager: SKIP / REVIVE); a player
-- on foot it hits just dies. It bursts on the first other thing it hits, or drops into the sea.
-- (A copy of ServerScriptService.LavaCannons with iron cannonballs.)
-- Per-cannon attributes (on the Model):
--   Interval  seconds between shots          (default 2.8)
--   Offset    seconds before its first shot  (default 0; staggers the cannons)
--   Speed     ball speed, studs per second   (default 55)
--   Range     studs a ball flies at most     (default 50)
-- The ball leaves from the Muzzle part, in the direction it faces (-Z).
-- Before every shot the barrel flashes red (faster and faster) for WARN seconds, with a red glow
-- at the muzzle, so riders can see which cannon is about to fire. Interval includes the warning.

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

local BALL = 2.6
local WARN = 1.0   -- seconds of red flashing before each shot
local WARN_RED = Color3.fromRGB(255, 35, 25)
local LAVA = Color3.fromRGB(255, 96, 16)
local HOT  = Color3.fromRGB(255, 170, 40)
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local balls = Instance.new("Folder")
balls.Name = "Cannonballs"
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
	b.Name = "Cannonball"; b.Shape = Enum.PartType.Ball; b.Size = Vector3.one * BALL
	b.Material = Enum.Material.Metal; b.Color = Color3.fromRGB(30, 30, 34); b.Reflectance = 0.1
	b.Anchored = true; b.CanCollide = false; b.CanTouch = false; b.CanQuery = false; b.CastShadow = false
	b.CFrame = cf
	local crust = Instance.new("Part")   -- (a glowing hot spot on the ball; moves with it)
	crust.Name = "Hot"; crust.Shape = Enum.PartType.Ball; crust.Size = Vector3.one * (BALL * 0.35)
	crust.Material = Enum.Material.Neon; crust.Color = Color3.fromRGB(255, 150, 60); crust.Transparency = 0.6
	crust.Anchored = true; crust.CanCollide = false; crust.CanTouch = false; crust.CanQuery = false; crust.CastShadow = false
	crust.CFrame = cf; crust.Parent = b
	local trail = Instance.new("ParticleEmitter")
	trail.Texture = SMOKE; trail.Color = ColorSequence.new(Color3.fromRGB(200, 196, 190))
	trail.Transparency = NumberSequence.new(0.5, 1); trail.Size = NumberSequence.new(1.2, 3)
	trail.Lifetime = NumberRange.new(0.5, 0.9); trail.Rate = 40; trail.Speed = NumberRange.new(0.5, 1.5)
	trail.SpreadAngle = Vector2.new(20, 20); trail.Parent = b
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

	-- the warning: the barrel flashes red, faster and faster, with a red glow at the muzzle
	local looks = {}
	for p in pairs(rest) do looks[p] = { color = p.Color, material = p.Material } end
	local glow = muzzle:FindFirstChild("WarnGlow") or Instance.new("PointLight")
	glow.Name, glow.Color, glow.Range, glow.Brightness, glow.Shadows = "WarnGlow", WARN_RED, 12, 0, false
	glow.Parent = muzzle
	local function lit(on, k)
		for p, look in pairs(looks) do
			p.Color = on and WARN_RED or look.color
			p.Material = on and Enum.Material.Neon or look.material
		end
		glow.Brightness = on and (2 + 4 * k) or 0
	end
	local function warnUp()
		local t0 = os.clock()
		while cannon.Parent do
			local t = os.clock() - t0
			if t >= WARN then break end
			local k = t / WARN
			lit(math.sin(t * (10 + 30 * k)) > -0.2, k)
			RunService.Heartbeat:Wait()
		end
		lit(false, 0)
	end

	local function fire()
		local dir = muzzle.CFrame.LookVector
		recoil()
		Sfx.Play("ShipCannon", muzzle)
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
			local ok, err = pcall(warnUp)
			if ok then ok, err = pcall(fire) end
			if not ok then warn("[ShipCannons] " .. cannon:GetFullName() .. ": " .. tostring(err)) end
			task.wait(math.max(0.2, (cannon:GetAttribute("Interval") or 2.8) - (os.clock() - started)))
		end
	end)
end

CollectionService:GetInstanceAddedSignal("ShipCannon"):Connect(arm)
for _, c in ipairs(CollectionService:GetTagged("ShipCannon")) do task.spawn(arm, c) end
