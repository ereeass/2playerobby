--=====================================================================
-- FinishCutscene / Celebration
--
-- The riders celebrate on the cinematic copy:
--   the DRIVER throws both arms up (Config.RaiseArmsAt, over RaiseArmsTime, with a
--     little overshoot) and pumps both fists, harder for a moment at the line
--   the BACK RIDER (Config.PassengerCheers) keeps a hand on the driver and punches the
--     other one up as they reach the line
-- Made with the riders' own ride IK: the arm IKControls that hold the grips in the game
-- (RiderPose's ScooterArm / ScooterHand) are just given new targets above the
-- shoulders, worked out from each avatar's own joints - so any avatar, R15 or R6, any
-- size, gets arms that fit, and the legs stay planted on the deck the whole time.
-- With Config.CelebrationAnimationId set, the driver plays that animation instead (arm
-- IK off, legs still planted); if it never loads, the pose above is used.
--=====================================================================

local Celebration = {}
Celebration.__index = Celebration

local PUMP_BOOST = 0.9   -- the fists pump this much harder for a moment at the line

-- where every part rests relative to the HumanoidRootPart, from the joints alone (so it
-- doesn't matter what pose the body is in), and the joints by name. Reads Motor6D rigs
-- and the newer AnimationConstraint ones, as RiderPose.MeasureBody does.
local function restPose(char)
	local root = char:FindFirstChild("HumanoidRootPart")
	local links, byName = {}, {}
	for _, d in ipairs(char:GetDescendants()) do
		local link
		if d:IsA("Motor6D") and d.Part0 and d.Part1 then
			link = { p0 = d.Part0, p1 = d.Part1, c0 = d.C0, c1 = d.C1 }
		elseif d:IsA("AnimationConstraint") and d.Attachment0 and d.Attachment1 then
			link = { p0 = d.Attachment0.Parent, p1 = d.Attachment1.Parent, c0 = d.Attachment0.CFrame, c1 = d.Attachment1.CFrame }
		end
		if link then
			table.insert(links, link)
			byName[d.Name] = link
		end
	end
	local rest = { [root] = CFrame.identity }
	local grew = true
	while grew do
		grew = false
		for _, l in ipairs(links) do
			if rest[l.p0] and not rest[l.p1] then
				rest[l.p1] = rest[l.p0] * l.c0 * l.c1:Inverse()
				grew = true
			end
		end
	end
	return rest, byName
end

local function jointAt(rest, link)
	return link and rest[link.p0] and (rest[link.p0] * link.c0).Position or nil
end

-- an arm's shoulder (root space) and length, R15 or R6
local function armOf(rest, joints, side)
	local shoulder = joints[side .. "Shoulder"]
	if shoulder then
		local sh = jointAt(rest, shoulder)
		local el, wr = jointAt(rest, joints[side .. "Elbow"]), jointAt(rest, joints[side .. "Wrist"])
		if sh and el and wr then return sh, (el - sh).Magnitude + (wr - el).Magnitude end
		return sh, 1.6
	end
	return jointAt(rest, joints[side .. " Shoulder"]), 2   -- R6: an arm is 2 long
end

local function backOut(x)   -- eases out past the end and settles back
	local c = 1.2
	return 1 + (c + 1) * (x - 1) ^ 3 + c * (x - 1) ^ 2
end

-- scene: the Scene. crossAt: when they reach the line. celebrant: the real character of
-- the rider who throws both arms up (the driver; or this player if nobody drives).
function Celebration.new(scene, cfg, crossAt, celebrant)
	local self = setmetatable({ cfg = cfg, crossAt = crossAt, arms = {}, made = {}, chassis = scene.Chassis }, Celebration)
	local lead, back
	for _, r in ipairs(scene.Riders) do
		if r.Source == celebrant then lead = r
		elseif r.Role == "Passenger" and not back then back = r end
	end
	if lead then
		self:_arms(lead, { "Left", "Right" }, 0, true)
		self:_animation(lead)
	end
	if back and back ~= lead and cfg.PassengerCheers then
		-- up just before they reach the line
		self:_arms(back, { "Right" }, crossAt - 0.35 - cfg.RaiseArmsAt, false)
	end
	return self
end

function Celebration:_point(name, pos)
	local a = Instance.new("Attachment")
	a.Name = name
	a.Position = pos
	a.Parent = self.chassis
	table.insert(self.made, a)
	return a
end

-- give these arms of `rider` targets above their shoulders, raised `delay` after the
-- driver's; `lead`: the rider an animation would take over
function Celebration:_arms(rider, sides, delay, lead)
	local hum, chassis = rider.Humanoid, self.chassis
	local rest, joints = restPose(rider.Model)
	-- where the rider's root is held on the chassis (their ride weld), else where it is now
	local weld = rider.Weld
	local rootOnChassis = weld and (weld.C0 * weld.C1:Inverse()) or chassis.CFrame:ToObjectSpace(rider.Root.CFrame)
	for _, side in ipairs(sides) do
		local s = side:sub(1, 1)
		local arm = hum:FindFirstChild("ScooterArm" .. s)
		local shoulder, length = armOf(rest, joints, side)
		if arm and arm:IsA("IKControl") and arm.Target and arm.Enabled and shoulder then
			local sign = (s == "L") and -1 or 1
			local sh = rootOnChassis * shoulder
			local up = sh + Vector3.new(sign * 0.42, length * 0.84, -0.12)   -- a V, a touch forward
			local from = chassis.CFrame:PointToObjectSpace(arm.Target.WorldPosition)
			local tag = "__Cheer" .. rider.Role .. s
			local wrist = self:_point(tag .. "Wrist", from)
			local aim = self:_point(tag .. "Hand", from + Vector3.new(0, 1.2, 0))
			local elbow = self:_point(tag .. "Elbow", sh + Vector3.new(sign * 1.6, 0.1, 0.9))   -- elbows out and back
			arm.Target, arm.Pole, arm.SmoothTime = wrist, elbow, 0
			local hand = hum:FindFirstChild("ScooterHand" .. s)
			if hand and hand:IsA("IKControl") then
				hand.Target, hand.SmoothTime = aim, 0.05   -- fists to the sky
			else
				hand = nil
			end
			table.insert(self.arms, {
				wrist = wrist, aim = aim, from = from, up = up, sign = sign, delay = delay,
				ik = arm, hand = hand, lead = lead,
			})
		end
	end
end

-- Config.CelebrationAnimationId for the lead rider, if there is one and it can play here
function Celebration:_animation(rider)
	local id = self.cfg.CelebrationAnimationId
	if type(id) ~= "string" or id == "" then return end
	if rider.Humanoid.RigType ~= Enum.HumanoidRigType.R15 then return end
	local animator = rider.Humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local ok, track = pcall(animator.LoadAnimation, animator, anim)
	if ok and track then
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Action4
		self.track = track
	else
		warn("[FinishCutscene] the celebration animation " .. id .. " can't be used (" .. tostring(track) .. "); using the built-in pose")
	end
end

function Celebration:Update(t)
	local cfg = self.cfg
	-- the animation, once it has loaded, takes the lead rider's arms
	if self.track and not self.playing and t >= cfg.RaiseArmsAt then
		if self.track.Length > 0 then
			self.playing = true
			self.track:Play(0.25)
			for _, a in ipairs(self.arms) do
				if a.lead then
					a.ik.Enabled = false
					if a.hand then a.hand.Enabled = false end
				end
			end
		elseif t >= cfg.RaiseArmsAt + 1 then
			warn("[FinishCutscene] the celebration animation didn't load; using the built-in pose")
			self.track = nil
		end
	end
	local boost = 1 + PUMP_BOOST * math.exp(-((t - self.crossAt) / 0.35) ^ 2)
	for _, a in ipairs(self.arms) do
		local start = cfg.RaiseArmsAt + a.delay
		local k = math.clamp((t - start) / cfg.RaiseArmsTime, 0, 1)
		local pos = a.from:Lerp(a.up, k > 0 and backOut(k) or 0)
		if k >= 1 then
			local since = t - start - cfg.RaiseArmsTime
			pos += Vector3.new(0, math.sin(since * cfg.FistPumpRate * 2 * math.pi) * cfg.FistPumpSize * boost, 0)
		end
		a.wrist.Position = pos
		a.aim.Position = pos + Vector3.new(a.sign * 0.15, 1.2, -0.1)
	end
end

function Celebration:Destroy()
	if self.track then pcall(function() self.track:Stop(0) end) end
	for _, a in ipairs(self.made) do a:Destroy() end
	table.clear(self.arms)
end

return Celebration
