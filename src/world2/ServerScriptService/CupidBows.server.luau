-- Cupid bows (Workspace > Cupid Bows): every Model tagged "CupidBow" draws its string and
-- shoots a heart-tipped arrow across the road, over and over. An arrow that hits a scooter
-- (or one of its riders) ends that run in the death popup (ScooterSystem.DeathManager: SKIP /
-- REVIVE), like the laser gates; a player on foot it hits just dies. It stops at the first
-- other thing it hits (the road, a wall...) and fades.
-- Per-bow attributes (on the Model):
--   Interval  seconds between shots          (default 2.6)
--   Offset    seconds before its first shot  (default 0; staggers the bows)
--   Speed     arrow speed, studs per second  (default 70)
--   Range     studs an arrow flies at most   (default 60)
-- The bow aims where its Grip part looks (-Z). Its Grip holds attachments TipTop, TipBottom
-- (the string's ends) and Nock (where the string rests).

local Sfx = require(game:GetService("ReplicatedStorage"):WaitForChild("ObstacleSfx"))   -- obstacle sound effects
local CollectionService   = game:GetService("CollectionService")
local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local TweenService        = game:GetService("TweenService")
local ServerScriptService = game:GetService("ServerScriptService")

local ScooterSystem = ServerScriptService:WaitForChild("ScooterSystem")
local RideManager   = require(ScooterSystem:WaitForChild("RideManager"))
local DeathManager  = require(ScooterSystem:WaitForChild("DeathManager"))
local scooters      = workspace:WaitForChild("RideSystem"):WaitForChild("Scooters")

local ARROW_SCALE = 1.6                     -- arrows sized to match the (1.6x) bows
local DRAW_TIME, DRAW_BACK = 0.55, 1.8 * ARROW_SCALE     -- how long / how far the string is pulled back
local ARROW_LEN, HIT_RADIUS = 4.2 * ARROW_SCALE, 0.7 * ARROW_SCALE
local GOLD  = Color3.fromRGB(255, 196, 64)
local RED   = Color3.fromRGB(222, 32, 64)
local PINK  = Color3.fromRGB(255, 120, 170)

local arrows = Instance.new("Folder")
arrows.Name = "CupidArrows"
arrows.Parent = workspace

-- the ride (or on-foot player) behind whatever an arrow touched (same as KillGates)
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

local function part(model, size, col, shape)
	local p = Instance.new("Part")
	p.Size = size; p.Color = col; p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true; p.CanCollide = false; p.CanTouch = false; p.CanQuery = false; p.CastShadow = false
	if shape then p.Shape = shape end
	p.Parent = model
	return p
end

-- an arrow: gold shaft, red heart head, pink fletching. Returns the model and each part's
-- offset from the arrow's frame (-Z forward, the frame at the shaft's middle).
local function newArrow()
	local m = Instance.new("Model")
	m.Name = "CupidArrow"
	local parts = {}
	local function add(p, rel) table.insert(parts, { p, rel }) end
	add(part(m, Vector3.new(ARROW_LEN, 0.18 * ARROW_SCALE, 0.18 * ARROW_SCALE), GOLD, Enum.PartType.Cylinder), CFrame.Angles(0, math.pi / 2, 0))
	local head = CFrame.new(0, 0, -ARROW_LEN / 2 - 0.2 * ARROW_SCALE) * CFrame.Angles(math.pi / 2, 0, 0)   -- heart point forward
	local r = 0.33 * ARROW_SCALE
	add(part(m, Vector3.new(0.2 * ARROW_SCALE, r * 2, r * 2), RED, Enum.PartType.Cylinder), head * CFrame.new(-r * 0.72, r * 0.55, 0) * CFrame.Angles(0, math.pi / 2, 0))
	add(part(m, Vector3.new(0.2 * ARROW_SCALE, r * 2, r * 2), RED, Enum.PartType.Cylinder), head * CFrame.new(r * 0.72, r * 0.55, 0) * CFrame.Angles(0, math.pi / 2, 0))
	add(part(m, Vector3.new(r * 2, r * 2, 0.2 * ARROW_SCALE), RED), head * CFrame.new(0, -r * 0.25, 0) * CFrame.Angles(0, 0, math.pi / 4))
	for _, a in ipairs({ 0, math.pi / 2 }) do
		add(part(m, Vector3.new(0.05, 0.7, 0.9) * ARROW_SCALE, PINK), CFrame.new(0, 0, ARROW_LEN / 2 - 0.45 * ARROW_SCALE) * CFrame.Angles(0, 0, a))
	end
	return m, parts
end

local function place(parts, cf)
	for _, pr in ipairs(parts) do pr[1].CFrame = cf * pr[2] end
end

local function fade(m)
	for _, p in ipairs(m:GetChildren()) do
		TweenService:Create(p, TweenInfo.new(0.6), { Transparency = 1 }):Play()
	end
	task.delay(0.7, function() m:Destroy() end)
end

local function arm(bow)
	if not bow:IsA("Model") then return end
	local grip = bow:WaitForChild("Grip", 5)
	if not grip then return end
	local tipTop, tipBot, nock = grip:WaitForChild("TipTop"), grip:WaitForChild("TipBottom"), grip:WaitForChild("Nock")
	local sTop, sBot = bow:WaitForChild("StringTop"), bow:WaitForChild("StringBottom")

	-- the string from each tip to the nock point, pulled `back` studs toward the archer
	local function string(back)
		local n = grip.CFrame * (nock.Position + Vector3.new(0, 0, back))
		for _, pr in ipairs({ { sTop, tipTop.WorldPosition }, { sBot, tipBot.WorldPosition } }) do
			local a = pr[2]
			pr[1].Size = Vector3.new(0.12, 0.12, (n - a).Magnitude)
			pr[1].CFrame = CFrame.lookAt((a + n) / 2, n)
		end
		return n
	end
	string(0)

	local function shoot()
		local dir = grip.CFrame.LookVector
		local arrow, parts = newArrow()
		arrow.Parent = arrows
		-- draw: the arrow sits on the string and comes back with it
		local t0 = os.clock()
		while os.clock() - t0 < DRAW_TIME do
			local k = (os.clock() - t0) / DRAW_TIME
			local n = string(DRAW_BACK * (1 - (1 - k) ^ 2))
			place(parts, CFrame.lookAt(n + dir * (ARROW_LEN / 2), n + dir * ARROW_LEN))
			RunService.Heartbeat:Wait()
		end
		-- release: the string snaps back, the arrow flies
		local pos = string(DRAW_BACK) + dir * (ARROW_LEN / 2)
		string(0)
		Sfx.Play("CupidBow", grip)
		local speed = bow:GetAttribute("Speed") or 70
		local range = bow:GetAttribute("Range") or 60
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { bow, arrows }
		local flown = 0
		while flown < range and arrow.Parent do
			local dt = RunService.Heartbeat:Wait()
			local step = math.min(speed * dt, range - flown)
			local tip = pos + dir * (ARROW_LEN / 2)
			local res = workspace:Spherecast(tip, HIT_RADIUS, dir * step, params)
			if res then
				place(parts, CFrame.lookAt(res.Position - dir * (ARROW_LEN / 2), res.Position + dir))
				if strike(res.Instance) then arrow:Destroy() else fade(arrow) end
				return
			end
			pos += dir * step
			flown += step
			place(parts, CFrame.lookAt(pos, pos + dir))
		end
		fade(arrow)
	end

	task.spawn(function()
		task.wait(bow:GetAttribute("Offset") or 0)
		while bow.Parent do
			local started = os.clock()
			local ok, err = pcall(shoot)
			if not ok then warn("[CupidBows] " .. bow:GetFullName() .. ": " .. tostring(err)) end
			task.wait(math.max(0.2, (bow:GetAttribute("Interval") or 2.6) - (os.clock() - started)))
		end
	end)
end

CollectionService:GetInstanceAddedSignal("CupidBow"):Connect(arm)
for _, bow in ipairs(CollectionService:GetTagged("CupidBow")) do task.spawn(arm, bow) end
