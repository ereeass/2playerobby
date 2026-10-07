-- Spin on the spot: a scooter standing still (slower than Config.SpinInPlaceBelow along
-- its nose, GO/reverse not held) with the Driver holding A or D turns round where it
-- stands, at Config.SpinInPlaceRate.
--
-- It is its own AngularVelocity on the Chassis ("SpinInPlace"), switched on only while
-- that is happening and off the rest of the time, so it changes nothing else about how
-- the scooter drives: the motors, steering servo, balance and collisions are untouched.
--
-- Called once per step from ScooterController:Step (one line there).
-- To switch it off: Config.SpinInPlace = false. To remove it: delete this module and
-- the SpinInPlace line in ScooterController:Step.

local RS     = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("ScooterSystem"):WaitForChild("Shared"):WaitForChild("Config"))

local SpinInPlace = {}

local function spinner(root)
	local av = root:FindFirstChild("SpinInPlace")
	if av then return av end
	local att = root:FindFirstChild("SpinInPlaceAtt") or Instance.new("Attachment")
	att.Name = "SpinInPlaceAtt"
	att.Parent = root
	av = Instance.new("AngularVelocity")
	av.Name = "SpinInPlace"
	av.Attachment0 = att
	av.RelativeTo = Enum.ActuatorRelativeTo.World
	av.MaxTorque = 1e6
	av.AngularVelocity = Vector3.zero
	av.Enabled = false
	av.Parent = root
	return av
end

function SpinInPlace.Step(controller)
	local root = controller.Root
	if not root or not root.Parent then return end
	local existing = root:FindFirstChild("SpinInPlace")
	if not Config.SpinInPlace then
		if existing and existing.Enabled then existing.Enabled = false end
		return
	end
	local speed = math.abs(root.AssemblyLinearVelocity:Dot(root.CFrame.LookVector))
	local pedal = controller.Mode == "forward" or controller.Mode == "reverse"
	local steer = controller.Steer or 0
	local spin = steer ~= 0 and not pedal and speed < (Config.SpinInPlaceBelow or 1.5)
	if spin then
		local av = spinner(root)
		-- right (+1) turns clockwise seen from above: negative about world up
		local goal = Vector3.new(0, -steer * (Config.SpinInPlaceRate or 2.2), 0)
		if av.AngularVelocity ~= goal then av.AngularVelocity = goal end
		if not av.Enabled then av.Enabled = true end
	elseif existing and existing.Enabled then
		existing.Enabled = false
	end
end

return SpinInPlace
