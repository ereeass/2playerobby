--=====================================================================
-- FinishCutscene / Scene
--
-- The cinematic's copy of the ride: this player's actual scooter and the actual avatars
-- riding it, copied the moment the line is crossed, so nothing that happens to the real
-- ones afterwards (the scooter removed, a rider leaving) can touch it. It exists only on
-- this machine, in Workspace.FinishCinematic, and only while the cutscene plays.
--
--   The scooter  moved by script, never by physics: its rigid bodies (Chassis,
--                SteerColumn, the wheels - whatever its hinges join) are anchored and
--                placed every frame from the hinge attachments themselves, so the fork
--                turns with the road and each wheel rolls exactly the distance travelled;
--                everything welded to them follows. Nothing on it collides or touches,
--                and no script, sound (bar its hum), prompt or tag comes across.
--   The riders   each rider's own character - clothes, accessories, body - welded where
--                they ride and posed by the very IK they ride with (RiderPose's
--                IKControls, re-aimed at the copy's rig points), so they stand exactly as
--                they do in the game. The back rider's hands go back to holding the
--                driver (in the game they follow the motor).
--=====================================================================

local RS = game:GetService("ReplicatedStorage")

local Steering = require(RS:WaitForChild("ScooterSystem"):WaitForChild("Shared"):WaitForChild("Steering"))

local Scene = {}
Scene.__index = Scene

local TOP_SPEED = 20.8   -- studs/s at full throttle (ScooterFx's figure): scales the hum and the trails

---------------------------------------------------------------- copying
-- where `inst` sits under `root`, as (name, which of its same-named siblings) steps, so
-- the same instance can be found again in a copy of `root`
local function pathOf(inst, root)
	local steps = {}
	while inst ~= root do
		local parent = inst.Parent
		if not parent then return nil end
		local n = 0
		for _, sib in ipairs(parent:GetChildren()) do
			if sib.Name == inst.Name then n += 1 end
			if sib == inst then break end
		end
		table.insert(steps, 1, { inst.Name, n })
		inst = parent
	end
	return steps
end

local function follow(root, steps)
	local cur = root
	for _, step in ipairs(steps) do
		local n, found = 0, nil
		for _, child in ipairs(cur:GetChildren()) do
			if child.Name == step[1] then
				n += 1
				if n == step[2] then found = child break end
			end
		end
		if not found then return nil end
		cur = found
	end
	return cur
end

-- ref (something of the real scooter's) -> the same thing in the copy
local function mapper(real, copy)
	return function(ref)
		if not ref then return nil end
		if ref == real then return copy end
		if not ref:IsDescendantOf(real) then return nil end
		local steps = pathOf(ref, real)
		return steps and follow(copy, steps)
	end
end

local function copyOf(inst)
	local was = inst.Archivable
	inst.Archivable = true   -- player characters aren't, by default (this changes only this machine's flag)
	local ok, copy = pcall(inst.Clone, inst)
	inst.Archivable = was
	return ok and copy or nil
end

-- A copy must never act: no scripts, no sounds of its own (bar `keep`), no forces, no
-- prompts, no name tags, none of the tags other scripts look for, and nothing on it
-- collides, touches or gets in a ray's way.
local function quiet(model, keep)
	for _, d in ipairs(model:GetDescendants()) do
		if d ~= keep then
			if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("BodyMover") or d:IsA("ForceField")
				or d:IsA("BillboardGui") or d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
				d:Destroy()
			else
				for _, tag in ipairs(d:GetTags()) do d:RemoveTag(tag) end
				if d:IsA("BasePart") then
					d.CanCollide, d.CanTouch, d.CanQuery = false, false, false
					d.LocalTransparencyModifier = 0
				elseif d:IsA("Decal") then
					d.LocalTransparencyModifier = 0
				end
			end
		end
	end
	for _, tag in ipairs(model:GetTags()) do model:RemoveTag(tag) end
end

local function wheelRadius(p)
	if p:IsA("Part") and p.Shape == Enum.PartType.Cylinder then
		return math.min(p.Size.Y, p.Size.Z) / 2   -- a cylinder's axis is its X
	end
	return math.max(p.Size.Y, p.Size.Z) / 2
end

---------------------------------------------------------------- build
-- ride: { Scooter, Chassis, Riders = { { Character, Role, Player } } }. The copy, not in
-- the world yet (Show puts it there), or nil and why.
function Scene.Build(ride)
	local real = ride.Scooter
	local model = copyOf(real)
	if not (model and model.PrimaryPart) then return nil, "the scooter could not be copied" end
	model.Name = "CinematicScooter"
	local chassis = model.PrimaryPart
	local map = mapper(real, model)
	local base = chassis.CFrame

	local self = setmetatable({
		Model = model, Chassis = chassis, Riders = {}, Wheels = {}, Trails = {}, Flutter = {},
		flap = 0, clock = 0, Wheelbase = 4.5,
	}, Scene)
	local v = ride.Chassis.AssemblyLinearVelocity
	self.RideSpeed = math.max(Vector3.new(v.X, 0, v.Z).Magnitude, 4)

	-- the hinges say how the scooter's bodies hang together (read before they go)
	local servo, motors = nil, {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("HingeConstraint") and d.Attachment0 and d.Attachment1 then
			if d.ActuatorType == Enum.ActuatorType.Servo then
				servo = servo or d
			elseif d.ActuatorType == Enum.ActuatorType.Motor then
				table.insert(motors, d)
			end
		end
	end
	if servo and servo.Attachment0.Parent == chassis and servo.Attachment1.Parent:IsA("BasePart") then
		self.Column = {
			Part = servo.Attachment1.Parent,
			A0 = servo.Attachment0.CFrame, A1inv = servo.Attachment1.CFrame:Inverse(),
			Sign = Steering.Sign(servo, base),   -- which way of the hinge is a right turn
		}
	end
	local straight = self.Column and (base * self.Column.A0 * self.Column.A1inv)   -- the fork dead ahead
	for _, m in ipairs(motors) do
		local wheel, holder = m.Attachment1.Parent, m.Attachment0.Parent
		local onColumn = self.Column ~= nil and holder == self.Column.Part
		if wheel:IsA("BasePart") and (holder == chassis or onColumn) then
			-- which way it spins to roll forward, worked out as ScooterController does
			local axis = (onColumn and straight or base):VectorToWorldSpace(m.Attachment0.Axis)
			local push = -(axis:Cross(-base.UpVector))
			table.insert(self.Wheels, {
				Part = wheel, OnColumn = onColumn,
				A0 = m.Attachment0.CFrame, A1inv = m.Attachment1.CFrame:Inverse(),
				Radius = wheelRadius(wheel),
				Sign = (push:Dot(base.LookVector) >= 0) and 1 or -1,
			})
		end
	end
	if #self.Wheels >= 2 then
		self.Wheelbase = math.max((self.Wheels[1].Part.Position - self.Wheels[2].Part.Position).Magnitude, 1)
	end

	-- no physics at all: whatever moves it goes, and its bodies are held by script
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Constraint") or d:IsA("BodyMover") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = false
		end
	end
	chassis.Anchored = true
	if self.Column then self.Column.Part.Anchored = true end
	for _, w in ipairs(self.Wheels) do w.Part.Anchored = true end

	-- its hum (the MotorHum ScooterFx plays), quiet at this pace; its trails keep going
	-- gently; anything else that emits (brake sparks, honey pictures) stays off
	local hum = chassis:FindFirstChild("MotorHum")
	self.Hum = (hum and hum:IsA("Sound")) and hum or nil
	self.HumMax = self.Hum and self.Hum.Volume or 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("ParticleEmitter") then
			local att = d.Parent
			if att and att:IsA("Attachment") and att.Name:sub(-5) == "Trail" and d.Rate > 0 then
				table.insert(self.Trails, { Emitter = d, Rate = d.Rate, Now = d.Rate })
			else
				d.Enabled = false
			end
		elseif d:IsA("Motor6D") and (d:GetAttribute("Flutter") or d:GetAttribute("Sway")) then
			table.insert(self.Flutter, d)   -- a bee scooter's wings and antennae
		end
	end
	quiet(model, self.Hum)

	-- the riders
	for _, r in ipairs(ride.Riders) do
		local copy = copyOf(r.Character)
		local hum_ = copy and copy:FindFirstChildOfClass("Humanoid")
		local root = copy and copy:FindFirstChild("HumanoidRootPart")
		if hum_ and root then
			copy.Name = "Cinematic" .. (r.Player and r.Player.Name or r.Character.Name)
			-- everything that held or aimed at the real scooter now holds / aims at the copy
			for _, d in ipairs(copy:GetDescendants()) do
				if d:IsA("IKControl") then
					if d.Target and not d.Target:IsDescendantOf(copy) then
						local t = map(d.Target)
						if t then d.Target = t else d.Enabled = false end
					end
					if d.Pole and not d.Pole:IsDescendantOf(copy) then d.Pole = map(d.Pole) end
				elseif d:IsA("JointInstance") or d:IsA("WeldConstraint") then
					if d.Part0 and not d.Part0:IsDescendantOf(copy) then d.Part0 = map(d.Part0) end
					if d.Part1 and not d.Part1:IsDescendantOf(copy) then d.Part1 = map(d.Part1) end
				end
			end
			-- carried, never walking or falling, never dying, never showing a name
			hum_.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			hum_.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			hum_.BreakJointsOnDeath = false
			hum_.RequiresNeck = false
			hum_.PlatformStand = true
			pcall(function() hum_.EvaluateStateMachine = false end)
			for _, d in ipairs(copy:GetDescendants()) do
				if d:IsA("BasePart") then d.Anchored, d.Massless = false, true end
			end
			-- the back rider: both hands back on the driver
			if r.Role == "Passenger" then
				local function aim(ikName, pointName)
					local ik, point = hum_:FindFirstChild(ikName), chassis:FindFirstChild(pointName)
					if ik and ik:IsA("IKControl") and point then ik.Target = point end
				end
				aim("ScooterArmL", "__RearHoldL")
				aim("ScooterArmR", "__RearHoldR")
				aim("ScooterHandL", "__RearHandHoldL")
				aim("ScooterHandR", "__RearHandHoldR")
			end
			quiet(copy)
			local weld = root:FindFirstChild("ScooterRiderWeld")
			table.insert(self.Riders, {
				Model = copy, Humanoid = hum_, Root = root, Role = r.Role, Player = r.Player,
				Source = r.Character,
				Weld = (weld and weld:IsA("Weld") and weld.Part0 == chassis) and weld or nil,
			})
		elseif copy then
			copy:Destroy()
		end
	end
	return self
end

---------------------------------------------------------------- in the world
function Scene:Show()
	local folder = Instance.new("Folder")
	folder.Name = "FinishCinematic"
	self.Model.Parent = folder
	for _, r in ipairs(self.Riders) do r.Model.Parent = folder end
	folder.Parent = workspace
	self.Folder = folder
	-- a loose piece (held to none of the moving bodies) rides on the chassis
	local held = { [self.Chassis] = true }
	if self.Column then held[self.Column.Part] = true end
	for _, w in ipairs(self.Wheels) do held[w.Part] = true end
	for _, d in ipairs(self.Model:GetDescendants()) do
		if d:IsA("BasePart") and not d.Anchored and not held[d.AssemblyRootPart] then
			local wc = Instance.new("WeldConstraint")
			wc.Part0, wc.Part1 = self.Chassis, d
			wc.Parent = d
		end
	end
	-- ...and so does a rider whose hold didn't come across, where they stand
	for _, r in ipairs(self.Riders) do
		if not r.Weld then
			local wc = Instance.new("WeldConstraint")
			wc.Part0, wc.Part1 = self.Chassis, r.Root
			wc.Parent = r.Root
		end
	end
	if self.Hum then
		self.Hum.Volume = 0
		self.Hum:Play()
	end
end

-- chassisCF: where the chassis goes. travelled: studs rolled so far (the wheels turn
-- with it). steer: the fork's angle to the right, in radians.
function Scene:Place(chassisCF, travelled, steer)
	self.Chassis.CFrame = chassisCF
	local column, columnCF = self.Column, nil
	if column then
		columnCF = chassisCF * column.A0 * CFrame.Angles(column.Sign * steer, 0, 0) * column.A1inv
		column.Part.CFrame = columnCF
	end
	for _, w in ipairs(self.Wheels) do
		local holder = w.OnColumn and columnCF or chassisCF
		w.Part.CFrame = holder * w.A0 * CFrame.Angles(w.Sign * travelled / w.Radius, 0, 0) * w.A1inv
	end
end

-- the scooter's life at this speed: its hum, its trails, a bee's wings (as ScooterFx does)
function Scene:Update(dt, speed)
	local s = math.clamp(speed / TOP_SPEED, 0, 1)
	if self.Hum then
		self.Hum.Volume = self.HumMax * (0.08 + 0.62 * s)
		self.Hum.PlaybackSpeed = 0.75 + 0.5 * s
	end
	for _, tr in ipairs(self.Trails) do
		local rate = tr.Rate * math.clamp(speed / self.RideSpeed, 0.15, 1)
		if math.abs(rate - tr.Now) > 0.5 then
			tr.Now = rate
			tr.Emitter.Rate = rate
		end
	end
	if #self.Flutter > 0 then
		self.clock += dt
		self.flap = (self.flap + (0.8 + 13 * s) * dt * 2 * math.pi) % (2 * math.pi)
		local flap = math.rad(2 + 16 * s) * math.sin(self.flap)
		for _, m in ipairs(self.Flutter) do
			local side = m:GetAttribute("Flutter")
			if side then
				m.Transform = CFrame.Angles(0, 0, flap * side)
			else
				local ph = m:GetAttribute("Sway") or 0
				m.Transform = CFrame.Angles(math.rad(3) * math.sin(self.clock * 0.9 * 2 * math.pi + ph), 0, 0)
			end
		end
	end
end

function Scene:Destroy()
	if self.Hum then pcall(function() self.Hum:Stop() end) end
	if self.Folder then self.Folder:Destroy() end
	self.Model:Destroy()
	for _, r in ipairs(self.Riders) do r.Model:Destroy() end
end

return Scene
