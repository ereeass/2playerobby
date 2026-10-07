-- How a ridden scooter stays upright (never onto its side) while its pitch behaves naturally.
--
-- Every scooter's Chassis has two AlignOrientations:
--
--   RollLock       added at spawn (AddRollLock): keeps the chassis's RIGHT axis level, so the
--                  scooter can never tip onto its left or right side. It is ALWAYS on - on the
--                  ground, in the air, falling, crashing - the one deliberately unrealistic
--                  rule. (Only a hazard that ends the run - a landmine, hammer or sliding block -
--                  lets go of it, on the server, when it throws the scooter.)
--   UprightAssist  pitch only (its up axis to world up). Off whenever the wheels are on the
--                  ground, so the pitch follows the ground: slopes, kerbs, bumps, ledges. Only
--                  away from the ground does it step in, playing the riders' part:
--     air / drop   in the air, or with a wheel out over a drop at speed: a GENTLE pull toward
--                  level, capped just under the scooter's own weight x ASSIST_ARM - so the
--                  nose still dips off a ledge and a take-off still carries its angle, but a
--                  ledge at speed does not turn into a nose-dive (the riders are massless, so
--                  on its own the scooter pitches far faster than a loaded one would). Slow
--                  over a lip it stays off: the scooter tips over the edge and rolls down,
--                  instead of balancing on it.
--     guard        a wheel on the ground but the chassis pitched more than PITCH_LIMIT away
--                  from that ground (ramming something nose-first tips it up over the front
--                  wheel): held level at full strength before it can cartwheel onto its back.
--     right        on its nose, tail or back (up axis more than ~70 degrees from vertical):
--                  full strength, to put it back on its wheels.
--
-- Step-up (StepUp): the riders' part at a kerb. The wheels are 0.8 in radius and only the rear
-- one is driven, so on their own they get up about half a stud when slow: the rear wheel jams
-- against anything taller, and a front wheel meeting a step at an angle is turned along it and
-- slides. So when a wheel is driven into a small step - a near-vertical face right ahead of it,
-- its top STEP_MIN..STEP_MAX above the ground that wheel is on, flat, at least STEP_DEPTH deep
-- (a thin rail or fence is not a step), STEP_HEADROOM clear above, met within STEP_ANGLE of
-- head-on, the scooter slower than STEP_MAX_SPEED - that wheel is lifted straight up at
-- LIFT_SPEED (a force-limited LinearVelocity at its axle) until it clears the top, and the
-- motor rolls it on. The rear follows the front up at almost any angle (STEP_ANGLE_WIDE).
-- A wheel HANGING off an edge while the other is still on the level above (the front wheel
-- over a road's side, the deck on the lip) is lifted back over the lip the same way when the
-- riders drive back towards it, from up to STEP_RECOVER below it. And with one wheel up a
-- step, the other short of it and the scooter going nowhere for STALL_TIME (the deck caught
-- on the step's edge between the wheels - met at an angle, or steering), that wheel is lifted
-- up to the other one's level too, if that level carries on ahead of it (STALL_LIFTS tries,
-- until it moves again). A part with a NoStepUp attribute (true) or tag is never climbed this
-- way. Taller steps, walls and glancing kerbs stop or deflect the scooter as before.
--
-- Bump damping (Damp): the riders soaking up a bump with their legs. Rigid wheels at speed
-- leave the ground over every bump and small step (they cannot follow its shape), so above
-- DAMP_MIN_SPEED a wheel that is already above the ground under it AND the ground just ahead
-- (never one rolling up a step), within DAMP_REACH of it (never a real jump or a fall), and
-- still rising faster than that ground does, is held from rising any further by a
-- force-limited LinearVelocity at its axle. (The wheels' ElasticityWeight in the scooter
-- models keeps them from rebounding off the ground in the first place.)
--
-- The switching (Balance.new / :Step) has to run where the scooter is simulated - the
-- Driver's machine (RiderAttach gives the Driver network ownership) - every frame before
-- physics: StarterPlayerScripts.ScooterBalance. If it ever does not run, UprightAssist simply
-- stays on at full strength, as the scooter was built.

local PhysicsService    = game:GetService("PhysicsService")
local CollectionService = game:GetService("CollectionService")

local Balance = {}

-- A wheel is ON the ground within LAND of it. A wheel off the ground is out over a DROP
-- when its ground is more than DROP below the ground the other wheel is on - a ledge,
-- never a slope (that is one surface under both wheels). Both wheels more than DROP up:
-- in the air.
local DROP  = 1.0
local LAND  = 0.3
local REACH = 6       -- studs below a wheel to look for ground
local SCOOTER_GROUP = "ScooterBody"   -- CollisionGroups.Body: what scooters collide with
local PITCH_LIMIT = 28   -- degrees the scooter may pitch away from the ground under its wheels
                         -- before it is held level: climbing a kerb or following a slope stays
                         -- well inside this, a crash nosing it over (or rearing it up) goes past
local RIGHT_BELOW = 0.35 -- chassis up . world up below this (~70 degrees over): put it back on its wheels

-- The riders' part in the air / over a drop: a pull toward level of at most the scooter's
-- weight x ASSIST_ARM studs. Just under what it takes to hold the nose up with the front
-- wheel hanging out over a ledge (~2.2 x weight), so the nose dips there; with nothing
-- holding the scooter (in the air) it slowly brings it back toward level.
local ASSIST_ARM            = 2.1
local ASSIST_RESPONSIVENESS = 5
local ASSIST_MIN_SPEED      = 8    -- studs/s: slower than this a wheel out over a drop just tips

-- Step-up
local STEP_MIN        = 0.2    -- studs: lower than this the wheels roll up on their own
local STEP_MAX        = 1.1    -- studs: the tallest step a wheel is lifted up
local STEP_RECOVER    = 1.6    -- studs: how far below a lip a hanging wheel is lifted back up from
local STEP_ANGLE      = 55     -- degrees off head-on: more glancing than this, a kerb is ridden along
local STEP_ANGLE_WIDE = 85     -- ...but a wheel following the other one up, or back over a lip, at almost any
local STEP_DEPTH      = 1.5    -- studs of flat top a step needs
local STEP_HEADROOM   = 1.8    -- studs clear above its top
local STEP_MAX_SPEED  = 12     -- studs/s: faster than this the scooter gets up on its own momentum
local STEP_DRIVE_MIN  = 1      -- studs/s the wheels have to be driving at, towards the step
local LIFT_SPEED      = 5      -- studs/s a wheel is lifted at
local LIFT_FORCE      = 1.5    -- x the scooter's weight, at most
local LIFT_CLEAR      = 0.08   -- studs above the top at which the lift lets go
local LIFT_TIMEOUT    = 0.8    -- seconds: a lift that has not cleared the step by then gives up...
local LIFT_COOLDOWN   = 0.4    -- ...and that wheel waits this long before another
local STALL_SPEED     = 0.5    -- studs/s: slower than this, driven, the scooter is going nowhere
local STALL_TIME      = 0.3    -- seconds going nowhere before a wheel short of the step is lifted
local STALL_LIFTS     = 2      -- such lifts in a row at most...
local STALL_RESET     = 0.5    -- ...until it has been moving again this long
local NO_STEP_UP      = "NoStepUp"   -- attribute (true) or CollectionService tag: never climbed this way

-- Bump damping
local DAMP_MIN_SPEED  = 8      -- studs/s: slower than this nothing bounces
local DAMP_REACH      = 2.5    -- studs: a wheel higher than this above the ground is jumping or falling
local DAMP_SLACK      = 0.5    -- studs/s a wheel may rise faster than its ground before it is held
local DAMP_FORCE      = 2.5    -- x the scooter's weight, at most, per wheel
local DAMP_LOOKAHEAD  = 0.08   -- seconds ahead the ground is checked too (a wheel rolling up a step is not bouncing)

-- Server, at spawn: the roll lock beside the scooter's UprightAssist.
function Balance.AddRollLock(scooter)
	local chassis = scooter.PrimaryPart
	local upright = chassis and chassis:FindFirstChild("UprightAssist")
	if not upright or chassis:FindFirstChild("RollLock") then return end
	local att = Instance.new("Attachment")
	att.Name = "RollAtt"   -- unrotated: its primary axis is the chassis's right
	att.Parent = chassis
	local lock = Instance.new("AlignOrientation")
	lock.Name = "RollLock"
	lock.Mode = Enum.OrientationAlignmentMode.OneAttachment
	lock.Attachment0 = att
	lock.PrimaryAxisOnly = true
	lock.AlignType = Enum.AlignType.Perpendicular   -- the right axis square to...
	lock.CFrame = upright.CFrame                     -- ...this goal's primary axis: world up
	lock.MaxTorque = upright.MaxTorque
	lock.MaxAngularVelocity = upright.MaxAngularVelocity
	lock.Responsiveness = upright.Responsiveness
	lock.Parent = chassis
end

---------------------------------------------------------------- the switch (client)
local Follower = {}
Follower.__index = Follower

-- a wheel is a cylinder along its X: its radius is across Y / Z
local function wheelRadius(wheel)
	return math.min(wheel.Size.Y, wheel.Size.Z) / 2
end

-- Switches `chassis`'s UprightAssist for as long as :Step is called. nil while the
-- scooter is missing a piece (not streamed in yet, or no roll lock): UprightAssist is
-- then left alone.
function Balance.new(chassis)
	local scooter = chassis.Parent
	local wheels  = scooter and scooter:FindFirstChild("Wheels")
	local front   = wheels and wheels:FindFirstChild("FrontWheel")
	local rear    = wheels and wheels:FindFirstChild("RearWheel")
	local upright = chassis:FindFirstChild("UprightAssist")
	local lock    = chassis:FindFirstChild("RollLock")
	if not (front and rear and upright and lock) then return nil end

	-- the ground only: never a scooter (this one or any other) and never a character
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { scooter.Parent }
	params.RespectCanCollide = true
	if PhysicsService:IsCollisionGroupRegistered(SCOOTER_GROUP) then
		params.CollisionGroup = SCOOTER_GROUP
	end

	-- the whole scooter's weight (the riders are massless); the wheels and the fork are
	-- assemblies of their own, joined to the chassis by hinges
	local mass, seen = 0, {}
	for _, p in ipairs(scooter:GetDescendants()) do
		if p:IsA("BasePart") then
			local root = p.AssemblyRootPart
			if root and not seen[root] then
				seen[root] = true
				mass += root.AssemblyMass
			end
		end
	end

	local weight = mass * workspace.Gravity
	local self = setmetatable({
		Chassis = chassis, Upright = upright, Lock = lock,
		Front = front, Rear = rear, Params = params,
		-- full strength, as built (guard / right)
		StrongTorque = upright.MaxTorque, StrongResponsiveness = upright.Responsiveness,
		AssistTorque = ASSIST_ARM * weight,
		Mode = "ground",
		Wheel = {},                -- [wheel] = { Radius, Lift, Damper, Cool, T, Top }: StepUp and Damp
		StallFor = 0, MovingFor = 0, StallLifts = 0,
		Gaps = {}, Hits = {},      -- [wheel] = this frame's Gap, reused every frame
		Made = {},                 -- what this follower added to the scooter; Release takes it away
	}, Follower)
	for _, wheel in ipairs({ front, rear }) do
		self.Wheel[wheel] = {
			Radius = wheelRadius(wheel),
			Lift   = self:AddMover(wheel, "StepLift", LIFT_FORCE * weight),
			Damper = self:AddMover(wheel, "BumpDamper", DAMP_FORCE * weight),
			Cool = 0, T = 0, Top = 0,
		}
	end
	return self
end

-- A vertical-only LinearVelocity at a wheel's axle, off until StepUp / Damp switch it on.
-- Made on the machine that simulates the scooter (the Driver's), removed again by Release.
function Follower:AddMover(wheel, name, maxForce)
	local att = Instance.new("Attachment")
	att.Name = name .. "Att"   -- at the wheel's centre: its axle
	att.Parent = wheel
	local mover = Instance.new("LinearVelocity")
	mover.Name = name
	mover.Attachment0 = att
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	mover.LineDirection = Vector3.yAxis
	mover.MaxForce = maxForce
	mover.Enabled = false
	mover.Parent = wheel
	table.insert(self.Made, mover)
	table.insert(self.Made, att)
	return mover
end

-- The ground below this wheel, and how far it is, measured square to that ground so a
-- slope reads the same as the flat. math.huge (and no hit) if there is none within REACH.
function Follower:Gap(wheel)
	local r = wheel.Size.Y / 2
	local hit = workspace:Raycast(wheel.Position, Vector3.new(0, -(r + REACH), 0), self.Params)
	if not hit then return math.huge end
	return (wheel.Position - hit.Position):Dot(hit.Normal) - r, hit
end

-- wheel A (off the ground) is out over a drop from the ground wheel B is on
local function overDrop(gapA, hitA, hitB)
	if gapA < LAND then return false end
	if not hitA then return true end
	return (hitB.Position - hitA.Position):Dot(hitB.Normal) > DROP
end

-- the slope of the ground under both wheels, in degrees (0 unless both have ground)
local function slopeUnder(frontHit, rearHit)
	if not (frontHit and rearHit) then return 0 end
	local d = frontHit.Position - rearHit.Position
	local run = Vector3.new(d.X, 0, d.Z).Magnitude
	if run <= 0.5 then return 0 end
	return math.deg(math.atan2(d.Y, run))
end

function Follower:Step(dt)
	dt = dt or 1 / 60
	local front, frontHit = self:Gap(self.Front)
	local rear, rearHit = self:Gap(self.Rear)
	local chassis = self.Chassis
	local cf = chassis.CFrame
	local vel = chassis.AssemblyLinearVelocity
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude

	local mode
	if cf.UpVector.Y < RIGHT_BELOW then
		mode = "right"
	elseif front > DROP and rear > DROP then
		mode = "air"
	elseif (front < LAND and overDrop(rear, rearHit, frontHit)) or (rear < LAND and overDrop(front, frontHit, rearHit)) then
		mode = (speed >= ASSIST_MIN_SPEED) and "drop" or "ground"
	elseif front < LAND or rear < LAND then
		-- Pitched much further than the ground under its wheels - ramming something nose-first
		-- tips it over the front wheel, and the wheel still on the ground made that look like
		-- a slope - so hold it level before it can cartwheel onto its back.
		local pitch = math.deg(math.asin(math.clamp(cf.LookVector.Y, -1, 1)))
		mode = (math.abs(pitch - slopeUnder(frontHit, rearHit)) > PITCH_LIMIT) and "guard" or "ground"
	else
		-- just off the ground: carry on as it was (but never stay "righting" once it is back up)
		mode = (self.Mode == "right") and "ground" or self.Mode
	end
	self.Mode = mode

	local up = self.Upright
	if mode == "ground" then
		if up.Enabled then up.Enabled = false end
	else
		local strong = (mode == "guard" or mode == "right")
		local torque = strong and self.StrongTorque or self.AssistTorque
		local resp = strong and self.StrongResponsiveness or ASSIST_RESPONSIVENESS
		if up.MaxTorque ~= torque then up.MaxTorque = torque end
		if up.Responsiveness ~= resp then up.Responsiveness = resp end
		if not up.Enabled then up.Enabled = true end
	end

	-- never onto its side, whatever it is doing
	if not self.Lock.Enabled then self.Lock.Enabled = true end

	-- the riders' part at kerbs, edges and bumps
	self.Gaps[self.Front], self.Hits[self.Front] = front, frontHit
	self.Gaps[self.Rear], self.Hits[self.Rear] = rear, rearHit
	self:StepUp(dt, cf, vel)
	self:Damp(vel)
end

---------------------------------------------------------------- step-up
-- How fast (studs/s, + forward) the wheels are trying to drive the scooter along the ground.
function Follower:Drive(cf)
	local w0 = self.Chassis.AssemblyAngularVelocity
	local sum = 0
	for _, wheel in ipairs({ self.Front, self.Rear }) do
		local spin = wheel.AssemblyAngularVelocity - w0
		local r = math.min(wheel.Size.Y, wheel.Size.Z) / 2
		sum += spin:Cross(cf.UpVector):Dot(cf.LookVector) * r
	end
	return sum / 2
end

local STEP_COS      = math.cos(math.rad(STEP_ANGLE))
local STEP_COS_WIDE = math.cos(math.rad(STEP_ANGLE_WIDE))
local TYRE_SLICE    = Vector3.new(0.3, 0.5, 0.05)   -- the shape swept ahead of a wheel: across, up, along

local function noStepUp(part)
	return part:GetAttribute(NO_STEP_UP) == true or CollectionService:HasTag(part, NO_STEP_UP)
end

-- The height of the top of the step whose face was hit going `dir`, if a wheel may be lifted
-- onto it: its top lo..hi above `bottom` (and at `level`, if given), flat, at least STEP_DEPTH
-- deep, with STEP_HEADROOM clear above, met within the angle whose cosine is `minCos`.
function Follower:StepTop(face, dir, bottom, lo, hi, level, minCos)
	local n = face.Normal
	if math.abs(n.Y) > 0.35 or noStepUp(face.Instance) then return nil end   -- a slope or a ramp, not a face
	local into = -Vector3.new(n.X, 0, n.Z).Unit
	if into:Dot(dir) < minCos then return nil end                               -- too glancing: ride along it
	local function topAt(depth)
		local p = face.Position + into * depth
		return workspace:Raycast(Vector3.new(p.X, bottom + hi + 0.3, p.Z), Vector3.new(0, -(hi + 0.5), 0), self.Params)
	end
	local top = topAt(0.3)
	if not top or top.Normal.Y < 0.8 or noStepUp(top.Instance) then return nil end
	local y = top.Position.Y
	if y - bottom < lo or y - bottom > hi then return nil end
	if level and math.abs(y - level) > 0.3 then return nil end
	local far = topAt(STEP_DEPTH)                                               -- a real ledge, not a thin rail
	if not far or math.abs(far.Position.Y - y) > 0.25 then return nil end
	if workspace:Raycast(top.Position + Vector3.new(0, 0.05, 0), Vector3.new(0, STEP_HEADROOM, 0), self.Params) then
		return nil
	end
	return y
end

-- The other wheel's level carrying on just ahead of `wheel` (going `dir`), with room above it:
-- its height, or nil. For a wheel held short of a step by the deck resting on its edge.
function Follower:LevelAhead(wheel, radius, dir, level)
	local p = wheel.Position + dir * (radius + 1.2)
	local hit = workspace:Raycast(Vector3.new(p.X, level + 0.5, p.Z), Vector3.new(0, -1, 0), self.Params)
	if not hit or hit.Normal.Y < 0.8 or math.abs(hit.Position.Y - level) > 0.3 or noStepUp(hit.Instance) then return nil end
	if workspace:Raycast(hit.Position + Vector3.new(0, 0.05, 0), Vector3.new(0, STEP_HEADROOM, 0), self.Params) then return nil end
	return hit.Position.Y
end

-- A step right ahead of `wheel` (going `dir`) that it may be lifted onto: its top's height, or
-- nil. Looked for low on the tyre (a kerb) and at the axle (a lip above a hanging wheel).
function Follower:FindStep(wheel, radius, dir, bottom, lo, hi, level, minCos)
	for _, y in ipairs({ bottom + 0.35, wheel.Position.Y }) do
		local from = Vector3.new(wheel.Position.X, y, wheel.Position.Z)
		local face = workspace:Blockcast(CFrame.lookAt(from, from + dir), TYRE_SLICE, dir * (radius + 0.25), self.Params)
		if face then
			local top = self:StepTop(face, dir, bottom, lo, hi, level, minCos)
			if top then return top end
		end
	end
	return nil
end

function Follower:StepUp(dt, cf, vel)
	local drive = self:Drive(cf)
	local flat = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	local driving = math.abs(drive) >= STEP_DRIVE_MIN and flat.Magnitude > 0.1
	local dir = driving and flat.Unit * math.sign(drive) or nil   -- the way the wheels are driving it
	local gaps, hits = self.Gaps, self.Hits
	-- driven but going nowhere, and for how long
	if driving and vel:Dot(dir) < STALL_SPEED then
		self.StallFor += dt
		self.MovingFor = 0
	else
		self.StallFor = 0
		self.MovingFor += dt
		if self.MovingFor >= STALL_RESET then self.StallLifts = 0 end
	end
	for wheel, w in pairs(self.Wheel) do
		w.Cool = math.max(0, w.Cool - dt)
		if w.Lift.Enabled then
			-- lifting: let go once the tyre is clear of the top (the motor rolls it on), or give up
			w.T += dt
			if wheel.Position.Y - w.Radius >= w.Top + LIFT_CLEAR or w.T > LIFT_TIMEOUT or not driving then
				w.Lift.Enabled = false
				w.Cool = LIFT_COOLDOWN
			end
		elseif driving and w.Cool <= 0 and vel:Dot(dir) <= STEP_MAX_SPEED and wheel.AssemblyLinearVelocity.Y < LIFT_SPEED
			and self.Mode ~= "guard" and self.Mode ~= "right" then
			local other = (wheel == self.Front) and self.Rear or self.Front
			local hit, otherHit = hits[wheel], hits[other]
			local otherDown = otherHit ~= nil and gaps[other] < LAND
			local top
			if hit and gaps[wheel] < LAND then
				-- on its ground, a kerb ahead; following the other wheel up onto its level, at almost any angle
				local following = otherDown and otherHit.Position.Y - hit.Position.Y >= STEP_MIN
					and otherHit.Position.Y - hit.Position.Y <= STEP_MAX
				top = self:FindStep(wheel, w.Radius, dir, hit.Position.Y, STEP_MIN, STEP_MAX,
					following and otherHit.Position.Y or nil, following and STEP_COS_WIDE or STEP_COS)
				if not top and following and self.StallFor >= STALL_TIME and self.StallLifts < STALL_LIFTS then
					-- not at the step's face yet, but going nowhere: the deck is caught on its edge
					top = self:LevelAhead(wheel, w.Radius, dir, otherHit.Position.Y)
					if top then self.StallLifts += 1 end
				end
			elseif otherDown and gaps[wheel] >= LAND then
				-- hanging off an edge, driven back towards the level the other wheel is still on
				top = self:FindStep(wheel, w.Radius, dir, wheel.Position.Y - w.Radius, 0.05, STEP_RECOVER,
					otherHit.Position.Y, STEP_COS_WIDE)
			end
			if top then
				w.Top, w.T = top, 0
				w.Lift.LineVelocity = LIFT_SPEED
				w.Lift.Enabled = true
			end
		end
	end
end

---------------------------------------------------------------- bump damping
function Follower:Damp(vel)
	local flatVel = Vector3.new(vel.X, 0, vel.Z)
	local fast = flatVel.Magnitude >= DAMP_MIN_SPEED and self.Mode ~= "guard" and self.Mode ~= "right"
	for wheel, w in pairs(self.Wheel) do
		local hold = false
		local here = self.Hits[wheel]
		if fast and here and not w.Lift.Enabled then
			-- the higher of the ground under the wheel and just ahead of it: rolling up onto a step
			-- is not a bounce
			local groundY = here.Position.Y
			local ahead = workspace:Raycast(wheel.Position + flatVel * DAMP_LOOKAHEAD, Vector3.new(0, -(w.Radius + REACH), 0), self.Params)
			if ahead and ahead.Position.Y > groundY then groundY = ahead.Position.Y end
			local clearance = wheel.Position.Y - w.Radius - groundY
			if clearance > 0.05 and clearance < DAMP_REACH then
				local wv = wheel.AssemblyLinearVelocity
				local n = here.Normal
				local rise = (n.Y > 0.3) and -(n.X * wv.X + n.Z * wv.Z) / n.Y or 0   -- how fast its ground rises under it
				if wv.Y > rise + DAMP_SLACK then
					-- held at the ground's own speed: on a downhill that's falling (never frozen at
					-- 0, which held the wheel up while the road dropped away - bouncing all the way down)
					w.Damper.LineVelocity = rise
					hold = true
				end
			end
		end
		if w.Damper.Enabled ~= hold then w.Damper.Enabled = hold end
	end
end

-- Back to how the scooter was built (this player got off it, or died).
function Follower:Release()
	for _, made in ipairs(self.Made) do
		if made.Parent then made:Destroy() end
	end
	table.clear(self.Made)
	local up = self.Upright
	if up.Parent then
		if up.MaxTorque ~= self.StrongTorque then up.MaxTorque = self.StrongTorque end
		if up.Responsiveness ~= self.StrongResponsiveness then up.Responsiveness = self.StrongResponsiveness end
		if not up.Enabled then up.Enabled = true end
	end
	if self.Lock.Parent and not self.Lock.Enabled then
		self.Lock.Enabled = true
	end
end

return Balance
