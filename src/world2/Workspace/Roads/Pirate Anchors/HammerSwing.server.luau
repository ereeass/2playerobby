-- Road3's swinging hammers. Each Hammer model swings across the road about its PivotCF
-- attribute, out to +-SwingDeg: it swings from one side to the other in SwingTime
-- seconds, holds still at the top for PauseTime seconds, swings back, holds again. Its
-- Phase (0..1, a fraction of that whole cycle) keeps the three out of step. A hammer HEAD hitting a scooter throws it sideways off the road - the same way
-- a landmine throws one (the server takes the scooter over for a moment) - and it falls
-- into the water, which ends the run as usual. If it hasn't gone into the water after
-- DEATH_BACKUP seconds the run is ended anyway. Someone on foot is knocked flying too.
-- Tuning: SwingDeg / SwingTime / PauseTime attributes on this model, Phase on each hammer.

local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local Debris              = game:GetService("Debris")
local ServerScriptService = game:GetService("ServerScriptService")

local ScooterSystem = ServerScriptService:WaitForChild("ScooterSystem")
local RideManager   = require(ScooterSystem:WaitForChild("RideManager"))
local DeathManager  = require(ScooterSystem:WaitForChild("DeathManager"))
local scooters      = workspace:WaitForChild("RideSystem"):WaitForChild("Scooters")

local model = script.Parent
local THROW_SIDE   = 60     -- studs/s sideways
local THROW_UP     = 55     -- studs/s up
local SPIN         = 8      -- rad/s of tumble
local HOLD         = 0.15   -- seconds the throw is kept up while the server takes the scooter over
local DEATH_BACKUP = 3

local hammers = {}
for _, h in ipairs(model:GetChildren()) do
	if h:IsA("Model") and h:GetAttribute("PivotCF") then
		local head = h:FindFirstChild("Head")
		-- where every part sits relative to the pivot, so the whole hammer turns as one
		local pivot = h:GetAttribute("PivotCF")
		local parts = {}
		for _, p in ipairs(h:GetDescendants()) do
			if p:IsA("BasePart") then table.insert(parts, { part = p, rel = pivot:ToObjectSpace(p.CFrame) }) end
		end
		table.insert(hammers, { model = h, pivot = pivot, parts = parts, head = head, phase = h:GetAttribute("Phase") or 0, angle = 0, speed = 0 })
	end
end

local thrown = setmetatable({}, { __mode = "k" })   -- [ride or player] = os.clock()

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

local function hitBy(h, dir)
	for _, p in ipairs(workspace:GetPartBoundsInBox(h.head.CFrame, h.head.Size + Vector3.new(1.6, 0.6, 0.6), params)) do
		-- a scooter on a ride?
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

-- angle and angular speed at time `t` into the cycle: swing across, pause, swing back, pause
local function motion(t, swing, sw, pause)
	local cycle = 2 * (sw + pause)
	t = t % cycle
	if t < sw then
		local u = math.pi * t / sw
		return -swing * math.cos(u), swing * math.pi / sw * math.sin(u)
	elseif t < sw + pause then
		return swing, 0
	elseif t < 2 * sw + pause then
		local u = math.pi * (t - sw - pause) / sw
		return swing * math.cos(u), -swing * math.pi / sw * math.sin(u)
	end
	return -swing, 0
end

local t0 = os.clock()
RunService.Heartbeat:Connect(function()
	local swing = math.rad(model:GetAttribute("SwingDeg") or 60)
	local sw = math.max(0.2, model:GetAttribute("SwingTime") or 1.2)
	local pause = math.max(0, model:GetAttribute("PauseTime") or 1.5)
	local now = os.clock() - t0
	for _, h in ipairs(hammers) do
		-- a PauseTime on the hammer itself overrides the model's, so they drift in and out of step
		local hp = math.max(0, h.model:GetAttribute("PauseTime") or pause)
		local cycle = 2 * (sw + hp)
		local a
		a, h.speed = motion(now + h.phase * cycle, swing, sw, hp)
		-- "Swinging" goes true at the start of each swing (HammerWhoosh plays a sound off it)
		local swinging = h.speed ~= 0
		if swinging ~= h.swinging then
			h.swinging = swinging
			h.model:SetAttribute("Swinging", swinging)
		end
		local cf = h.pivot * CFrame.Angles(0, 0, a)
		for _, e in ipairs(h.parts) do e.part.CFrame = cf * e.rel end
		if math.abs(h.speed) > 0.3 and h.head then
			-- the head moves along the pivot's right vector turned by the angle
			local dir = (cf.RightVector * (h.speed > 0 and 1 or -1))
			dir = Vector3.new(dir.X, 0, dir.Z)
			if dir.Magnitude > 0.1 then hitBy(h, dir.Unit) end
		end
	end
end)
