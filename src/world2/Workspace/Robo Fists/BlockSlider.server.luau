-- Narrow Dirt Road's sliding blocks. Each SlidingBlock's yellow Block rests beside the road
-- (ClosedCF + OpenOffset), slides across to shut the road (ClosedCF), holds, then slides back
-- to its spot. Closed, it's a solid wall: a scooter just bumps into it and waits. A scooter
-- (or someone on foot) caught while a block is CLOSING is shoved off the road the way
-- Road3's hammers throw one (the server takes the scooter over for a moment); it falls, and
-- if the run hasn't ended after DEATH_BACKUP seconds it is ended anyway.
-- Tuning: OpenTime / SlideTime / ClosedTime on this model, Phase (seconds) on each block.
-- Wind-up: for the last WARN seconds before each punch the fist pulls back (WINDUP studs),
-- shakes harder and harder, its Light flashes red faster and faster, and a red strip flashes on
-- the road where it will land (StrikeWarning, made here). Looks only: the punch keeps its timing.
local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local Debris       = game:GetService("Debris")
local ScooterSystem = game:GetService("ServerScriptService"):WaitForChild("ScooterSystem")
local RideManager  = require(ScooterSystem:WaitForChild("RideManager"))
local DeathManager = require(ScooterSystem:WaitForChild("DeathManager"))
local scooters = workspace:WaitForChild("RideSystem"):WaitForChild("Scooters")

local THROW_SIDE   = 45     -- studs/s sideways, the way the block is moving
local THROW_UP     = 30     -- studs/s up
local SPIN         = 6      -- rad/s of tumble
local HOLD         = 0.15   -- seconds the throw is kept up while the server takes the scooter over
local DEATH_BACKUP = 3
local WARN         = 1.5    -- seconds of wind-up before each punch
local WINDUP       = 3      -- studs the fist pulls back by the end of it
local SHAKE        = 0.35   -- studs of shake at the very end
local WARN_RED     = Color3.fromRGB(255, 40, 30)

local model = script.Parent
local blocks = {}
for _, p in ipairs(model:GetChildren()) do
	local block = p:FindFirstChild("Block")
	if block and p:GetAttribute("ClosedCF") then
		-- decoration parts inside the Block ride along with it
		local deco = {}
		for _, d in ipairs(block:GetDescendants()) do
			if d:IsA("BasePart") then table.insert(deco, { part = d, rel = block.CFrame:ToObjectSpace(d.CFrame) }) end
		end
		-- the slide sound, played from the block as it starts moving (heard nearby only)
		local snd = block:FindFirstChild("SlideSound") or Instance.new("Sound")
		snd.Name = "SlideSound"; snd.SoundId = "rbxassetid://71824935334971"; snd.Volume = 0.35
		snd.RollOffMode = Enum.RollOffMode.InverseTapered; snd.RollOffMinDistance = 8; snd.RollOffMaxDistance = 70
		snd.Parent = block
		-- the red strip on the road under where the fist lands
		local closed = p:GetAttribute("ClosedCF")
		local strip = p:FindFirstChild("StrikeWarning") or Instance.new("Part")
		strip.Name = "StrikeWarning"
		strip.Anchored, strip.CanCollide, strip.CanQuery, strip.CanTouch, strip.CastShadow = true, false, false, false, false
		strip.Material, strip.Color, strip.Transparency = Enum.Material.Neon, WARN_RED, 1
		strip.Size = Vector3.new(block.Size.X, 0.08, block.Size.Z)
		strip.CFrame = closed * CFrame.new(0, -block.Size.Y / 2 + 0.06, 0)
		strip.Parent = p
		local light = block:FindFirstChild("Light")
		table.insert(blocks, { fist = p, part = block, deco = deco, closed = closed, open = p:GetAttribute("OpenOffset"), phase = p:GetAttribute("Phase") or 0, sound = snd, k = nil,
			strip = strip, light = light, lightColor = light and light.Color, lightMat = light and light.Material })
	end
end

local thrown = setmetatable({}, { __mode = "k" })   -- [ride or player] = true

local function throwScooter(ride, dir, life)
	local chassis = ride.Scooter and ride.Scooter.PrimaryPart
	if not chassis then return end
	if ride.Controller then
		pcall(function() ride.Controller:SetSteer(0); ride.Controller:SetThrottle("coast") end)
	end
	pcall(function() chassis:SetNetworkOwner(nil) end)
	for _, name in ipairs({ "UprightAssist", "RollLock" }) do
		local c = chassis:FindFirstChild(name)
		if c then c.Enabled = false end
	end
	local throw = dir * THROW_SIDE + Vector3.new(0, THROW_UP, 0)
	local spin = chassis.CFrame.LookVector * SPIN * (dir:Dot(chassis.CFrame.RightVector) >= 0 and -1 or 1)
	local t, conn = 0, nil
	conn = RunService.Heartbeat:Connect(function(dt)
		t += dt
		if not chassis.Parent or t > HOLD then conn:Disconnect() return end
		chassis.AssemblyLinearVelocity = throw - Vector3.new(0, workspace.Gravity * t, 0)
		chassis.AssemblyAngularVelocity = spin
	end)
	chassis.AssemblyLinearVelocity = throw
	chassis.AssemblyAngularVelocity = spin
	for _, handle in pairs(ride.Riders or {}) do
		handle.KeepOnDeath = true
		if handle.Humanoid then handle.Humanoid.BreakJointsOnDeath = false end
	end
	-- (the life it was thrown in: a revive since then starts a new one, which this can't end)
	task.delay(DEATH_BACKUP, function() DeathManager.Hit(ride, model, life) end)
end

local function throwCharacter(character, dir)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local att = Instance.new("Attachment") att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.MaxForce = math.huge
	lv.VectorVelocity = dir * THROW_SIDE + Vector3.new(0, THROW_UP, 0)
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = root
	Debris:AddItem(lv, 0.2)
	Debris:AddItem(att, 0.2)
end

local params = OverlapParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = { model }

local function shove(b, dir)
	for _, p in ipairs(workspace:GetPartBoundsInBox(b.part.CFrame, b.part.Size + Vector3.new(0.8, 0.4, 0.6), params)) do
		local m = p:FindFirstAncestorOfClass("Model")
		while m and m.Parent ~= scooters do m = m:FindFirstAncestorOfClass("Model") end
		local ride = m and RideManager.Rides[m]
		if not ride then
			local c = p:FindFirstAncestorOfClass("Model")
			while c and not Players:GetPlayerFromCharacter(c) do c = c:FindFirstAncestorOfClass("Model") end
			local plr = c and Players:GetPlayerFromCharacter(c)
			ride = plr and RideManager.PlayerRide[plr]
			if not ride and plr and not thrown[plr] then
				thrown[plr] = true
				task.delay(1, function() thrown[plr] = nil end)
				throwCharacter(c, dir)
			end
		end
		-- once per life of the ride (a revive starts a new one): DeathManager.Claim
		local life = ride and DeathManager.Claim(ride)
		if life then throwScooter(ride, dir, life) end
	end
end

-- how far closed (0 open .. 1 shut) at `t`, whether it's closing right now, and while open,
-- how many seconds are left before the next punch
local function motion(t, openT, slide, closedT)
	local cycle = openT + closedT + 2 * slide
	t = t % cycle
	if t < openT then return 0, false, openT - t end
	t -= openT
	if t < slide then return (1 - math.cos(math.pi * t / slide)) / 2, true end
	t -= slide
	if t < closedT then return 1, false end
	t -= closedT
	return (1 + math.cos(math.pi * t / slide)) / 2, false
end

local t0 = os.clock()
RunService.Heartbeat:Connect(function()
	local openT   = math.max(0, model:GetAttribute("OpenTime") or 2.5)
	local slide   = math.max(0.2, model:GetAttribute("SlideTime") or 1)
	local closedT = math.max(0, model:GetAttribute("ClosedTime") or 1.5)
	local now = os.clock() - t0
	for _, b in ipairs(blocks) do
		-- OpenTime / ClosedTime on the fist itself override the model's, so they drift in and out of step
		local k, closing, left = motion(now + b.phase, b.fist:GetAttribute("OpenTime") or openT, slide, b.fist:GetAttribute("ClosedTime") or closedT)
		-- starting to move (from fully open or fully shut): the slide sound
		if b.k ~= nil and (b.k == 0 or b.k == 1) and k ~= b.k then b.sound:Play() end
		b.k = k
		local cf = b.closed + b.open * (1 - k)
		-- wind-up: pull back, shake, flash (0 = not yet, 1 = about to punch)
		local w = (left and left < WARN) and (1 - left / WARN) or 0
		if w > 0 then
			local back = b.open.Unit * WINDUP * (1 - (1 - w) ^ 2)
			local s = SHAKE * w * w
			local shake = Vector3.new(math.random() * 2 - 1, math.random() * 2 - 1, math.random() * 2 - 1) * s
			cf = cf + back + shake
			local on = math.sin(now * (8 + 28 * w)) > 0
			b.strip.Transparency = on and (0.55 - 0.3 * w) or 0.85
			if b.light then
				b.light.Color = on and WARN_RED or b.lightColor
				b.light.Material = Enum.Material.Neon
			end
		elseif closing then
			-- the punch starts from the pulled-back spot, so there's no jump
			cf = cf + b.open.Unit * WINDUP * (1 - k)
			b.strip.Transparency = 0.25
			if b.light then b.light.Color, b.light.Material = WARN_RED, Enum.Material.Neon end
		elseif b.strip.Transparency ~= 1 then
			b.strip.Transparency = 1
			if b.light then b.light.Color, b.light.Material = b.lightColor, b.lightMat end
		end
		b.part.CFrame = cf
		for _, d in ipairs(b.deco) do d.part.CFrame = cf * d.rel end
		if closing and k < 0.98 then shove(b, -b.open.Unit) end
	end
end)
