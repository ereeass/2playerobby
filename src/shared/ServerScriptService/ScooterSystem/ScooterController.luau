-- The ONLY thing that touches the scooter's motor and steering servo.
--
-- ONE forward direction: the Chassis (PrimaryPart) LookVector. Nothing in here
-- reads a world axis, the camera, or a character's orientation, so the scooter
-- can never strafe and never drives relative to where anyone is looking.
--
-- Sign conventions are DERIVED from the hinge geometry, so a rebuilt or
-- re-oriented scooter still drives and steers the right way.
--
-- One instance per ride. No module-level mutable state, so two teams can never
-- share a controller.

local RS       = game:GetService("ReplicatedStorage")
local Shared   = RS:WaitForChild("ScooterSystem"):WaitForChild("Shared")
local Config   = require(Shared:WaitForChild("Config"))
local Steering = require(Shared:WaitForChild("Steering"))
local SpinInPlace = require(script.Parent:WaitForChild("SpinInPlace"))

local ScooterController = {}
ScooterController.__index = ScooterController

function ScooterController.new(scooter)
	local self = setmetatable({}, ScooterController)
	self.Scooter = scooter
	self.Root    = scooter.PrimaryPart
	assert(self.Root, "scooter has no PrimaryPart - cannot establish a forward direction")

	self.Motors, self.Servos = {}, {}
	for _, d in ipairs(scooter:GetDescendants()) do
		if d:IsA("HingeConstraint") then
			if d.ActuatorType == Enum.ActuatorType.Motor then
				table.insert(self.Motors, d)
			elseif d.ActuatorType == Enum.ActuatorType.Servo then
				table.insert(self.Servos, d)
			end
		end
	end

	self.Steer    = 0           -- what the Driver asks for: -1 left .. +1 right
	self.SteerNow = 0           -- where the fork is heading: follows Steer over Config.SteerRampSeconds
	self.Mode     = "coast"     -- "forward" | "reverse" | "brake" | "coast"
	self.TargetAV = 0
	self:DeriveSigns()
	self:MeasureWheels()
	return self
end

-- Work out from geometry alone which way a positive motor/servo value pushes.
function ScooterController:DeriveSigns()
	local cf  = self.Root.CFrame
	local fwd = cf.LookVector
	local up  = cf.UpVector

	self.DriveSign, self.SteerSign = {}, {}

	for _, m in ipairs(self.Motors) do
		local a0   = m.Attachment0
		local axis = a0 and a0.WorldAxis or Vector3.xAxis
		-- The contact patch sits at the bottom of the wheel. For a positive angular
		-- velocity it travels along (axis x -up), and the chassis is pushed the
		-- opposite way.
		local push = -(axis:Cross(-up))
		self.DriveSign[m] = (push:Dot(fwd) >= 0) and 1 or -1
	end

	for _, s in ipairs(self.Servos) do
		self.SteerSign[s] = Steering.Sign(s, cf)   -- the reasoning lives in Shared.Steering
	end
end

-- Each driven wheel gets its OWN target spin, so the two motors never fight each other
-- through the ground. (That fight was a constant scrub force at the front tyre, acting
-- off-centre on its flat face, and it pushed the fork off centre: the scooter weaving on
-- its own.)
--   wheel size  TargetAV is the spin of the smallest driven wheel; a bigger wheel spins
--               that much slower to roll at the same speed (the rear is 1.616 across,
--               the front 1.600)
--   steering    in a turn the front wheel runs round a wider circle than the rear, by
--               1 / cos(the fork's angle on the ground), so it spins that much faster
local function wheelRadius(p)
	if p:IsA("Part") and p.Shape == Enum.PartType.Cylinder then
		return math.min(p.Size.Y, p.Size.Z) / 2   -- a cylinder's axis is its X
	end
	return p.Size.Y / 2
end

function ScooterController:MeasureWheels()
	local up = self.Root.CFrame.UpVector
	self.WheelRadius, self.WheelServo, self.CosRake = {}, {}, {}
	local smallest = math.huge
	for _, m in ipairs(self.Motors) do
		local wheel = m.Attachment1 and m.Attachment1.Parent
		local r = (wheel and wheel:IsA("BasePart")) and wheelRadius(wheel) or nil
		self.WheelRadius[m] = r
		if r then smallest = math.min(smallest, r) end
		-- a wheel whose axle hangs off a servo's fork turns with that fork
		for _, s in ipairs(self.Servos) do
			if m.Attachment0 and s.Attachment1 and m.Attachment0.Parent == s.Attachment1.Parent then
				self.WheelServo[m] = s
				-- the steering axis leans back (rake), so the wheel turns a little less on the ground than the fork does
				self.CosRake[m] = s.Attachment0 and math.abs(s.Attachment0.WorldAxis:Dot(up)) or 1
			end
		end
	end
	self.RefRadius = (smallest < math.huge) and smallest or nil
end

-- How much faster (or slower) than TargetAV this motor has to spin its wheel.
function ScooterController:WheelScale(m)
	local k = 1
	local r = self.WheelRadius[m]
	if r and self.RefRadius then k = self.RefRadius / r end
	local s = self.WheelServo[m]
	if s then
		local fork = math.rad(math.clamp(s.CurrentAngle, -60, 60))
		local onGround = math.atan(math.tan(fork) * (self.CosRake[m] or 1))
		k = k / math.max(math.cos(onGround), 0.5)
	end
	return k
end

function ScooterController:Describe()
	local d = self.Motors[1] and self.DriveSign[self.Motors[1]] or 0
	local s = self.Servos[1] and self.SteerSign[self.Servos[1]] or 0
	local f = self.Root.CFrame.LookVector
	return ("forward=%.2f,%.2f,%.2f  driveSign=%+d  steerSign=%+d  motors=%d servos=%d")
		:format(f.X, f.Y, f.Z, d, s, #self.Motors, #self.Servos)
end

-- How far the fork may turn at the scooter's current speed along its OWN forward
-- axis, either direction: full lock when slow, easing off towards top speed.
function ScooterController:SteerLimit()
	return Steering.Limit(self.Root.AssemblyLinearVelocity:Dot(self.Root.CFrame.LookVector))
end

-- Coasting: the wheel speed a hill lets the scooter creep at. Positive rolls it forward
-- (nose pointing downhill), negative back (nose uphill), 0 on the flat. Gravity is the
-- one world axis this controller reads.
function ScooterController:RollGoal()
	local slope = math.deg(math.asin(math.clamp(self.Root.CFrame.LookVector.Y, -1, 1)))
	if math.abs(slope) < Config.RollMinSlopeDeg then return 0 end
	return -math.clamp(slope * Config.RollPerSlopeDeg, -Config.RollMaxAngularVelocity, Config.RollMaxAngularVelocity)
end

function ScooterController:ApplySteer()
	local angle = Steering.Angle(self.SteerNow, self.Root.AssemblyLinearVelocity:Dot(self.Root.CFrame.LookVector))
	for _, s in ipairs(self.Servos) do
		s.TargetAngle = self.SteerSign[s] * angle
	end
end

-- steer: -1 = left, 0 = straight, +1 = right. Driver only. The fork follows it over
-- Config.SteerRampSeconds (Step). The Driver's own machine turns the fork itself the
-- moment the key goes down (StarterGui.RideGui.Controller); this is the server's copy,
-- which steers whenever the server is the one simulating the scooter.
function ScooterController:SetSteer(steer)
	self.Steer = math.clamp(tonumber(steer) or 0, -1, 1)
end

-- mode: "forward" (W) | "reverse" (S) | "brake" (Space) | "coast". Rear player only.
-- "go" is accepted as an alias for "forward"; anything unknown means coast.
function ScooterController:SetThrottle(mode)
	if mode == "go" then mode = "forward" end
	if mode ~= "forward" and mode ~= "reverse" and mode ~= "brake" then mode = "coast" end
	self.Mode = mode
end

-- Ramps the commanded wheel speed toward whatever the current mode wants. Driven
-- once per Heartbeat by RideManager; this is the throttle model, not a physics
-- workaround, and it never writes a CFrame.
--
-- TargetAV is SIGNED along the scooter's own forward axis: positive rolls it
-- forward, negative rolls it backward. DriveSign turns that into the wheel's
-- direction, so reverse needs no world axis either. Pressing the opposite way while
-- still rolling first slows at BrakeRate, then builds up the new direction.
function ScooterController:Step(dt)
	local goal, rate
	if self.Mode == "forward" then
		goal = Config.MaxAngularVelocity
		rate = (self.TargetAV < 0) and Config.BrakeRate or Config.AccelRate
	elseif self.Mode == "reverse" then
		goal = -Config.MaxReverseAngularVelocity
		rate = (self.TargetAV > 0) and Config.BrakeRate or Config.ReverseAccelRate
	elseif self.Mode == "brake" then
		goal, rate = 0, Config.BrakeRate
	else
		-- faster than the hill would roll it (or the wrong way): bleed that off as before;
		-- slower: the hill picks it up, gently
		goal = self:RollGoal()
		local pickingUp = (goal > 0 and self.TargetAV >= 0 and self.TargetAV < goal)
			or (goal < 0 and self.TargetAV <= 0 and self.TargetAV > goal)
		rate = pickingUp and Config.RollAccelRate or Config.CoastRate
	end

	if self.TargetAV < goal then
		self.TargetAV = math.min(goal, self.TargetAV + rate * dt)
	else
		self.TargetAV = math.max(goal, self.TargetAV - rate * dt)
	end

	-- each wheel at its own spin (MeasureWheels), rounded so a steady cruise does not
	-- re-send the same value every frame
	for _, m in ipairs(self.Motors) do
		m.AngularVelocity = math.round(self.DriveSign[m] * self.TargetAV * self:WheelScale(m) * 100) / 100
	end

	-- the fork swings toward the Driver's steer, and the lock depends on speed, so it
	-- follows the scooter every frame
	self.SteerNow = Steering.Ramp(self.SteerNow, self.Steer, dt)
	self:ApplySteer()

	SpinInPlace.Step(self)   -- spin on the spot when standing still (delete this line to remove it)
end

function ScooterController:Stop()
	self:SetSteer(0)
	self.SteerNow = 0
	self:ApplySteer()
	self.Mode, self.TargetAV = "coast", 0
	for _, m in ipairs(self.Motors) do m.AngularVelocity = 0 end
	SpinInPlace.Step(self)   -- no steer now, so this switches the spin off
end

function ScooterController:Destroy()
	self:Stop()
	self.Motors, self.Servos = {}, {}
end

return ScooterController
