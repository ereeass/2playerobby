-- The fork maths, shared by the server (ServerScriptService.ScooterSystem.ScooterController)
-- and the Driver's own machine (StarterGui.RideGui.Controller), so both turn the fork the
-- exact same way. The Driver's machine simulates the scooter, so it applies its own steer
-- straight away; the server does the same whenever it is the one simulating.

local Config = require(script.Parent:WaitForChild("Config"))

local Steering = {}

-- Which sign of TargetAngle turns this servo's fork to the scooter's RIGHT (steer +1),
-- derived from the hinge geometry. A positive hinge angle rotates the fork by the
-- right-hand rule about the hinge axis; with that axis pointing up, positive swings the
-- fork LEFT, so a LEFT steer input (-1) has to produce a POSITIVE target angle.
-- Verified on ScooterVehicle with both wheels on the ground: TargetAngle +30 at 6 studs/s
-- gave +41 deg/s yaw (left); A and D mirror each other.
function Steering.Sign(servo, chassisCFrame)
	local a0   = servo.Attachment0
	local axis = a0 and a0.WorldAxis or Vector3.yAxis
	return (axis:Dot(chassisCFrame.UpVector) >= 0) and -1 or 1
end

-- How far the fork may turn at `speed` (studs/s along the scooter's own nose, either
-- direction): full lock when slow, easing off towards top speed.
function Steering.Limit(speed)
	local a = math.clamp((math.abs(speed) - Config.SteerFullLockBelow)
		/ (Config.SteerEasedAbove - Config.SteerFullLockBelow), 0, 1)
	return Config.SteerAngleDeg + (Config.SteerAngleAtSpeedDeg - Config.SteerAngleDeg) * a
end

-- Moves the steer (-1 .. +1) toward `goal`. A and D are on/off keys, so the fork swings
-- over Config.SteerRampSeconds from straight to full lock rather than snapping there.
function Steering.Ramp(current, goal, dt)
	local seconds = Config.SteerRampSeconds or 0
	if seconds <= 0 then return goal end
	local step = dt / seconds
	return current + math.clamp(goal - current, -step, step)
end

-- The fork angle (degrees, before a servo's Sign) for a steer at a speed. Half-degree
-- steps, so a steady speed does not re-send the same angle every frame.
function Steering.Angle(steer, speed)
	return math.round(steer * Steering.Limit(speed) * 2) / 2
end

return Steering
