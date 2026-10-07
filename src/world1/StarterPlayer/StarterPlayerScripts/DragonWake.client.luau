-- The Lighthouse Dragon wakes up for riders, on THIS machine only and only while this player
-- rides a scooter (driver or motor rider) near it - like the other critters. As they come
-- close its head slowly turns to follow their scooter (the neck bends along behind it), its
-- eyes brighten to a hot orange with a warm glow, and smoke puffs from its nostrils. When
-- they leave it eases back and settles. Only this screen moves it: the real (server) dragon
-- never moves, so the kill zone is unchanged.

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local WAKE      = 230                    -- studs from the head (the rotten bridge and beach lot are ~165-190)
local NECK      = 30                     -- neck parts this close to the head bend along
local MAX_YAW   = math.rad(65)
local MAX_PITCH = math.rad(28)
local TURN      = math.rad(28)           -- degrees a second, so it turns slowly
local S         = 2.4                    -- the head's build scale
local HOT       = Color3.fromRGB(255, 120, 20)

local player = Players.LocalPlayer
local dragon = workspace:WaitForChild("Lighthouse Dragon")

local function myChassis()
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local weld = root and root:FindFirstChild("ScooterRiderWeld")
	return weld and weld.Part0
end

local rig            -- the parts that move, with where they rest
local headPos        -- where the head is (remembered once found)
local yaw, pitch, glow = 0, 0, 0

local function build()
	local head = dragon:FindFirstChild("Head")
	if not head then return nil end
	local snout
	for _, p in ipairs(head:GetChildren()) do
		if p:IsA("Part") and (p.Size - Vector3.new(3.6, 2.3, 5) * S).Magnitude < 0.05 then snout = p end
	end
	if not snout then return nil end
	local H = snout.CFrame * CFrame.new(0, -0.15 * S, 3.1 * S)     -- the head's own frame (back of the skull)
	local r = { H = H, parts = {}, eyes = {}, nostrils = {} }
	for _, p in ipairs(head:GetChildren()) do
		if p:IsA("BasePart") then
			table.insert(r.parts, { p = p, rest = p.CFrame, w = 1 })
			if p.Material == Enum.Material.Neon then table.insert(r.eyes, { p = p, color = p.Color, size = p.Size }) end
		end
	end
	for _, g in ipairs({ "Body", "Belly", "Spines", "Legs" }) do
		local m = dragon:FindFirstChild(g)
		if m then for _, p in ipairs(m:GetChildren()) do
			local d = p:IsA("BasePart") and (p.Position - H.Position).Magnitude
			if d and d < NECK then table.insert(r.parts, { p = p, rest = p.CFrame, w = (1 - d / NECK) ^ 1.6 }) end
		end end
	end
	-- smoke from the nostrils, and a warm glow between the eyes (local parts)
	for _, k in ipairs({ -1, 1 }) do
		local holder = Instance.new("Part")
		holder.Anchored, holder.CanCollide, holder.CanTouch, holder.CanQuery = true, false, false, false
		holder.Transparency, holder.Size = 1, Vector3.new(0.5, 0.5, 0.5)
		holder.Parent = workspace.CurrentCamera
		local e = Instance.new("ParticleEmitter")
		e.Rate = 0
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Color = ColorSequence.new(Color3.fromRGB(120, 116, 110), Color3.fromRGB(190, 186, 180))
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 5) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(1.4, 2.2)
		e.Speed = NumberRange.new(4, 7)
		e.SpreadAngle = Vector2.new(15, 15)
		e.Acceleration = Vector3.new(0, 3, 0)
		e.Drag = 1.5
		e.RotSpeed = NumberRange.new(-40, 40)
		e.Rotation = NumberRange.new(0, 360)
		e.EmissionDirection = Enum.NormalId.Front
		e.Parent = holder
		-- rest place: at the nostril, facing out of the snout
		table.insert(r.nostrils, { p = holder, e = e, rest = H * CFrame.new(k * 0.75 * S, 1.05 * S, -6.3 * S) })
	end
	local lamp = Instance.new("Part")
	lamp.Anchored, lamp.CanCollide, lamp.CanTouch, lamp.CanQuery = true, false, false, false
	lamp.Transparency, lamp.Size = 1, Vector3.new(0.5, 0.5, 0.5)
	lamp.Parent = workspace.CurrentCamera
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness, light.Shadows = HOT, 16, 0, false
	light.Parent = lamp
	r.lamp, r.light, r.lampRest = lamp, light, H * CFrame.new(0, 1.3 * S, -2.2 * S)
	r.nextPuff = 1
	return r
end

local function restore()
	if not rig then return end
	for _, e in ipairs(rig.parts) do if e.p.Parent then e.p.CFrame = e.rest end end
	for _, e in ipairs(rig.eyes) do if e.p.Parent then e.p.Color, e.p.Size = e.color, e.size end end
	for _, n in ipairs(rig.nostrils) do n.p:Destroy() end
	rig.lamp:Destroy()
	rig = nil
end

local list, cfs = {}, {}
RunService.Heartbeat:Connect(function(dt)
	local chassis = myChassis()
	local awake = false
	if chassis then
		local d = (chassis.Position - (headPos or dragon:GetPivot().Position)).Magnitude
		if not rig and d < (headPos and WAKE or WAKE + 120) then
			rig = build()
			if rig then headPos = rig.H.Position end
		end
		awake = rig and (chassis.Position - rig.H.Position).Magnitude < WAKE
	end
	if not rig then return end
	-- where to look: the scooter, within the neck's reach
	local H = rig.H
	local wantYaw, wantPitch = 0, 0
	if awake then
		local l = H:PointToObjectSpace(chassis.Position)
		wantYaw = math.clamp(math.atan2(-l.X, -l.Z), -MAX_YAW, MAX_YAW)
		wantPitch = math.clamp(math.atan2(l.Y, math.sqrt(l.X * l.X + l.Z * l.Z)), -MAX_PITCH, MAX_PITCH)
	end
	local step = TURN * dt
	yaw += math.clamp(wantYaw - yaw, -step, step)
	pitch += math.clamp(wantPitch - pitch, -step, step)
	glow += math.clamp((awake and 1 or 0) - glow, -dt * 0.8, dt * 0.8)
	-- fully asleep and settled: put everything back and stop
	if not awake and math.abs(yaw) < 0.002 and math.abs(pitch) < 0.002 and glow < 0.01 then
		yaw, pitch, glow = 0, 0, 0
		restore()
		return
	end
	local P = H.Position
	local up, right = H.UpVector, H.RightVector
	local function turned(w) return CFrame.new(P) * CFrame.fromAxisAngle(up, yaw * w) * CFrame.fromAxisAngle(right, pitch * w) * CFrame.new(-P) end
	local full = turned(1)
	table.clear(list) table.clear(cfs)
	for _, e in ipairs(rig.parts) do
		if e.p.Parent then
			list[#list + 1] = e.p
			cfs[#cfs + 1] = (e.w >= 1 and full or turned(e.w)) * e.rest
		end
	end
	for _, n in ipairs(rig.nostrils) do list[#list + 1] = n.p cfs[#cfs + 1] = full * n.rest end
	list[#list + 1] = rig.lamp cfs[#cfs + 1] = full * rig.lampRest
	workspace:BulkMoveTo(list, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	-- eyes heat up and glow; a slow breathing pulse while awake
	local pulse = 0.85 + math.sin(os.clock() * 2.2) * 0.15
	for _, e in ipairs(rig.eyes) do
		if e.p.Parent then
			e.p.Color = e.color:Lerp(HOT, glow)
			e.p.Size = e.size * (1 + 0.15 * glow)
		end
	end
	rig.light.Brightness = 3 * glow * pulse
	-- smoke puffs every few seconds while awake
	if awake then
		rig.nextPuff -= dt
		if rig.nextPuff <= 0 then
			rig.nextPuff = 2 + math.random() * 1.8
			for _, n in ipairs(rig.nostrils) do n.e:Emit(math.random(5, 8)) end
		end
	end
end)
