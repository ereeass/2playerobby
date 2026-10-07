--=====================================================================
-- DragonReactorFx   (each player's own machine; looks only)
--
-- Brings the Dragon Reactor scooter (ServerStorage.ScooterModels.DragonScooter, the model
-- with the DragonReactor attribute) to life, on every Dragon Reactor ridden near this
-- player's camera. It only reads each scooter's speed and changes colours, lights,
-- particle rates and the wing / tail joints' Transforms - nothing here touches physics,
-- the server, or anyone's ride. Everything it moves belongs to the scooter, so it all goes
-- when the scooter does, and nothing is ever created per frame.
--   Idle     the reactor pulses slowly, the eyes glow, a few heat embers rise, wings folded
--   Moving   the reactor brightens and its energy rings race faster, the wheels and eyes
--            glow harder, the tail sways (the exhaust flames are the model's ...Trail
--            emitters, which ScooterFx already runs with speed)
--   Boost    the scooters have no boost, so holding near top speed is the boost: after
--            BOOST_HOLD seconds the wings unfold (unlock, then open), the reactor goes white-
--            hot, the dragon breathes a short burst of fire, the exhaust roars and a fire
--            ribbon trails behind. Slowing down folds the wings away again.
--   Podium   the lobby podium's Dragon (a still copy with no joints: ScooterPodiums) puts on
--            a showcase on a loop - cruising, then a boost: wings unfold and beat, the
--            reactor goes white-hot, the eyes flare and it breathes fire, then it settles.
--            Its parts carry the model's markers (DragonWing / Hinge / OpenRot, TailIndex /
--            TailJoint, the skull's BreathAt), so the copy is moved part by part.
--=====================================================================

local RunService = game:GetService("RunService")

local TOP_SPEED   = 20.8   -- studs/s at full throttle (ScooterFx's figure)
local RANGE       = 220    -- studs from the camera; farther dragons are left as they are
local BOOST_ON    = 0.86   -- share of top speed that counts as boosting...
local BOOST_OFF   = 0.7    -- ...and below which it stops
local BOOST_HOLD  = 0.6    -- seconds held near top speed before the boost starts
local BREATH_GAP  = 4      -- seconds between fire breaths

local RGB = Color3.fromRGB
local CORE_DIM, CORE_HOT, CORE_MAX = RGB(150, 40, 6), RGB(255, 140, 30), RGB(255, 236, 170)
local GLOW_DIM, GLOW_HOT, GLOW_MAX = RGB(120, 26, 0), RGB(255, 72, 0), RGB(255, 190, 90)

local function approach(cur, target, rate, dt) return cur + (target - cur) * (1 - math.exp(-rate * dt)) end
local function smooth(x) x = math.clamp(x, 0, 1); return x * x * (3 - 2 * x) end
local function heat(dim, hot, max, k)   -- 0 dim .. 1 hot .. 2 white-hot
	if k <= 1 then return dim:Lerp(hot, math.max(k, 0)) end
	return hot:Lerp(max, math.min(k - 1, 1))
end

local scooters = workspace:WaitForChild("RideSystem"):WaitForChild("Scooters")
local dragons = {}   -- [scooter model] = state

-- the dragon's working pieces, found by name (again whenever more of it streams in)
local function collect(st)
	st.dirty = false
	st.cores, st.rings, st.glows, st.eyes, st.lights, st.wings, st.tail, st.boost = {}, {}, {}, {}, {}, {}, {}, {}
	for _, d in ipairs(st.model:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name == "ReactorCore" then table.insert(st.cores, d)
			elseif d.Name == "ReactorRing" then table.insert(st.rings, { part = d, i = d:GetAttribute("Index") or 1 })
			elseif d.Name == "Eye" or d.Name == "MouthGlow" then table.insert(st.eyes, d)
			elseif d.Name == "WheelGlow" or d.Name == "WingGlow" or d.Name == "TailGlow" or d.Name == "ExhaustGlow" or d.Name == "ReactorVent" then table.insert(st.glows, d) end
		elseif d:IsA("PointLight") then table.insert(st.lights, d)
		elseif d:IsA("Motor6D") then
			if d:GetAttribute("Open") then table.insert(st.wings, d)
			elseif d:GetAttribute("TailIndex") then table.insert(st.tail, d) end
		elseif d:IsA("ParticleEmitter") then
			if d:GetAttribute("Max") then table.insert(st.boost, d)
			elseif d.Name == "BreathFire" then st.breath = d end
		elseif d:IsA("Trail") and d.Name == "DragonTrail" then st.ribbon = d end
	end
end

local function setup(model)
	if dragons[model] or not model:IsA("Model") or not model:GetAttribute("DragonReactor") then return end
	local st = { model = model, speed = 0, s = 0, b = 0, hold = 0, wing = 0, t = math.random() * 10, ring = 0,
		breathAt = -math.huge, breathUntil = 0, written = {} }
	collect(st)
	-- parts streaming in later are picked up on the next frame (the connection goes with the model)
	model.DescendantAdded:Connect(function() st.dirty = true end)
	dragons[model] = st
end
scooters.ChildAdded:Connect(function(m) task.defer(setup, m) end)
for _, m in ipairs(scooters:GetChildren()) do setup(m) end

-- a property is only written when it has really changed, so a cruising dragon costs little
local function set(st, obj, prop, value, eps)
	local key = st.written[obj]
	if not key then key = {}; st.written[obj] = key end
	local last = key[prop]
	if last ~= nil then
		if typeof(value) == "Color3" then
			if math.abs(last.R - value.R) + math.abs(last.G - value.G) + math.abs(last.B - value.B) < (eps or 0.02) then return end
		elseif last == value or (value ~= 0 and math.abs(last - value) < (eps or 0.02)) then return end   -- 0 always lands
	end
	key[prop] = value
	obj[prop] = value
end

local function update(st, chassis, dt, now)
	if st.dirty then collect(st) end
	st.t += dt
	-- speed, as ScooterFx measures it
	local v = chassis.AssemblyLinearVelocity
	st.speed = approach(st.speed, Vector3.new(v.X, 0, v.Z).Magnitude, 10, dt)
	st.s = math.clamp(st.speed / TOP_SPEED, 0, 1)

	-- boost: held near top speed for a moment; ends once it slows down
	if st.s >= BOOST_ON then st.hold += dt elseif st.s < BOOST_OFF then st.hold = 0 end
	local boosting = st.hold >= BOOST_HOLD
	local wasBoost = st.b > 0.5
	st.b = approach(st.b, boosting and 1 or 0, boosting and 2.5 or 1.6, dt)
	if st.b > 0.5 and not wasBoost and now - st.breathAt > BREATH_GAP then
		st.breathAt, st.breathUntil = now, now + 0.45   -- the dragon breathes fire as the boost lights
		if st.breath then st.breath:Emit(18) end
	end

	-- reactor: a slow pulse at rest, faster and brighter with speed, white-hot in a boost
	local pulse = 0.5 + 0.5 * math.sin(st.t * (2 + 5 * st.s + 7 * st.b))
	local power = 0.25 + 0.55 * st.s + 0.9 * st.b + 0.2 * pulse      -- 0.25 .. ~1.9
	local coreCol = heat(CORE_DIM, CORE_HOT, CORE_MAX, power)
	for _, c in ipairs(st.cores) do set(st, c, "Color", coreCol) end
	-- the energy rings: a wave racing along the reactor, faster with speed
	st.ring += dt * (1.5 + 9 * st.s + 12 * st.b)
	for _, r in ipairs(st.rings) do
		local k = 0.5 + 0.5 * math.sin(st.ring - r.i * 1.25)
		set(st, r.part, "Color", heat(GLOW_DIM, GLOW_HOT, GLOW_MAX, (0.3 + 0.7 * k) * (0.6 + 0.4 * st.s + 0.9 * st.b)))
	end
	for _, l in ipairs(st.lights) do
		if l.Name == "ReactorLight" then
			set(st, l, "Brightness", 0.6 + 1.4 * power, 0.05)
			set(st, l, "Range", 4 + 3 * math.min(power, 1.6), 0.1)
		else
			set(st, l, "Brightness", 0.7 + 1.2 * st.s + 2 * st.b, 0.05)
		end
	end
	-- eyes and mouth: glow with speed, flare in the boost and as it breathes
	local breathing = now < st.breathUntil
	local eyeK = 0.7 + 0.3 * st.s + 0.8 * st.b + (breathing and 0.5 or 0) + 0.08 * pulse
	local eyeCol = heat(GLOW_DIM, GLOW_HOT, GLOW_MAX, eyeK)
	for _, e in ipairs(st.eyes) do set(st, e, "Color", eyeCol) end
	-- wheels, wing edges, tail line, nozzles
	local glowCol = heat(GLOW_DIM, GLOW_HOT, GLOW_MAX, 0.55 + 0.45 * st.s + 0.7 * st.b)
	for _, g in ipairs(st.glows) do set(st, g, "Color", glowCol) end
	if st.breath then set(st, st.breath, "Rate", breathing and 70 or 0, 1) end

	-- wings: a mechanical unfold - the lock gives a little first, then they swing open
	st.wing = approach(st.wing, st.b > 0.35 and 1 or 0, st.b > 0.35 and 2.2 or 2.8, dt)
	local w = st.wing
	local open = smooth((w - 0.12) / 0.88)
	local unlock = (w > 0.01 and w < 0.2) and math.sin(w / 0.2 * math.pi) * 0.05 or 0
	for _, j in ipairs(st.wings) do
		local side = j:GetAttribute("Side") or 1
		local flap = open > 0.95 and math.rad(4) * math.sin(st.t * 5) or 0   -- a slow beat once open
		j.Transform = CFrame.identity:Lerp(j:GetAttribute("Open"), open) * CFrame.Angles(0, 0, (unlock + flap) * side)
	end

	-- tail: a lazy sway that quickens and widens with speed
	local amp = math.rad(3 + 7 * st.s)
	for _, j in ipairs(st.tail) do
		local i = j:GetAttribute("TailIndex")
		j.Transform = CFrame.Angles(math.rad(1.5) * math.sin(st.t * 1.3 + i), amp * math.sin(st.t * (1.6 + 2 * st.s) - i * 0.7), 0)
	end

	-- boost fire and the ribbon
	for _, e in ipairs(st.boost) do set(st, e, "Rate", st.b < 0.03 and 0 or (e:GetAttribute("Max") or 0) * st.b, 1) end
	if st.ribbon then
		local on = st.b > 0.4
		if st.ribbon.Enabled ~= on then st.ribbon.Enabled = on end
	end
end

-- out of range: the boost's fire switched off, so nothing roars on far away
local function rest(st)
	if st.resting then return end
	st.resting = true
	for _, e in ipairs(st.boost) do set(st, e, "Rate", 0, 0) end
	if st.breath then set(st, st.breath, "Rate", 0, 0) end
	if st.ribbon then st.ribbon.Enabled = false end
end

---------------------------------------------------------------- the lobby podium's Dragon
local CollectionService = game:GetService("CollectionService")
local SHOW, SHOW_BOOST_AT, SHOW_BOOST_END = 9, 3, 6.5   -- seconds per loop; the boost's part of it
local SHOW_RANGE = 150
local SHOW_FLAP  = math.rad(8)                        -- a fuller beat than on the road
local SHOW_OPEN  = 0.42                                -- wings open this far, so they stay inside the glass case
local displays = {}   -- [Display model] = state

local function breathEmitter(skull)
	local att = Instance.new("Attachment")
	att.Name = "BreathAtt"
	att.CFrame = skull:GetAttribute("BreathAt")
	att.Parent = skull
	local e = Instance.new("ParticleEmitter")
	e.Name = "BreathFire"
	e.Texture = "rbxasset://textures/particles/fire_main.dds"
	e.Rate = 0
	e.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, RGB(255, 200, 60)), ColorSequenceKeypoint.new(0.5, RGB(255, 90, 0)), ColorSequenceKeypoint.new(1, RGB(190, 24, 0)) })
	e.LightEmission = 0.55
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0.9) })
	e.Transparency = NumberSequence.new(0.1, 1)
	e.Lifetime = NumberRange.new(0.25, 0.4)
	e.Speed = NumberRange.new(10, 14)
	e.SpreadAngle = Vector2.new(12, 12)
	e.EmissionDirection = Enum.NormalId.Front
	e.RotSpeed = NumberRange.new(-120, 120)
	e.Rotation = NumberRange.new(0, 360)
	e.Drag = 3
	e.Parent = att
	return e
end

local function setupDisplay(display)
	if displays[display] or not display:IsA("Model") then return end
	local podium = display.Parent
	if not (podium and podium:GetAttribute("ScooterId") == "Dragon") then return end
	local st = { model = display, t = 0, s = 0.65, b = 0, wing = 0, ring = 0, written = {}, breathUntil = 0,
		still = podium:GetAttribute("Still") == true,
		cores = {}, rings = {}, glows = {}, eyes = {}, wings = {}, tail = {}, moving = {}, cframes = {} }
	for _, d in ipairs(display:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name == "ReactorCore" then table.insert(st.cores, d)
			elseif d.Name == "ReactorRing" then table.insert(st.rings, { part = d, i = d:GetAttribute("Index") or 1 })
			elseif d.Name == "Eye" or d.Name == "MouthGlow" then table.insert(st.eyes, d)
			elseif d.Name == "WheelGlow" or d.Name == "WingGlow" or d.Name == "TailGlow" or d.Name == "ExhaustGlow" or d.Name == "ReactorVent" then table.insert(st.glows, d) end
			if d:GetAttribute("DragonWing") then
				table.insert(st.wings, { part = d, base = d.CFrame, hinge = d.CFrame * d:GetAttribute("Hinge"),
					open = d:GetAttribute("OpenRot"), side = d:GetAttribute("Side") or 1 })
			end
			local ti = d:GetAttribute("TailIndex")
			if ti then
				st.tail[ti] = st.tail[ti] or { joint = d.CFrame * d:GetAttribute("TailJoint"), parts = {} }
				table.insert(st.tail[ti].parts, { part = d, base = d.CFrame })
			end
			if d:GetAttribute("BreathAt") and not st.breath then st.breath = breathEmitter(d) end
		end
	end
	if #st.wings == 0 then return end   -- not all here yet: tried again when it is
	displays[display] = st
end

local function watchPodium(podium)
	podium.ChildAdded:Connect(function(c) if c.Name == "Display" then task.defer(setupDisplay, c) end end)
	local d = podium:FindFirstChild("Display")
	if d then task.defer(setupDisplay, d) end
end
CollectionService:GetInstanceAddedSignal("ScooterPodium"):Connect(watchPodium)
for _, p in ipairs(CollectionService:GetTagged("ScooterPodium")) do watchPodium(p) end

local function showcase(st, dt, now)
	st.t += dt
	local phase = st.t % SHOW
	local boosting = phase >= SHOW_BOOST_AT and phase < SHOW_BOOST_END
	local wasBoost = st.b > 0.5
	st.b = approach(st.b, boosting and 1 or 0, boosting and 2.5 or 1.6, dt)
	if st.b > 0.5 and not wasBoost then
		st.breathUntil = now + 0.45
		if st.breath then st.breath:Emit(18) end
	end
	local breathing = now < st.breathUntil
	if st.breath then set(st, st.breath, "Rate", breathing and 70 or 0, 1) end

	-- the same glow as on the road
	local pulse = 0.5 + 0.5 * math.sin(st.t * (2 + 5 * st.s + 7 * st.b))
	local power = 0.25 + 0.55 * st.s + 0.9 * st.b + 0.2 * pulse
	local coreCol = heat(CORE_DIM, CORE_HOT, CORE_MAX, power)
	for _, c in ipairs(st.cores) do set(st, c, "Color", coreCol) end
	st.ring += dt * (1.5 + 9 * st.s + 12 * st.b)
	for _, r in ipairs(st.rings) do
		local k = 0.5 + 0.5 * math.sin(st.ring - r.i * 1.25)
		set(st, r.part, "Color", heat(GLOW_DIM, GLOW_HOT, GLOW_MAX, (0.3 + 0.7 * k) * (0.6 + 0.4 * st.s + 0.9 * st.b)))
	end
	local eyeCol = heat(GLOW_DIM, GLOW_HOT, GLOW_MAX, 0.7 + 0.3 * st.s + 0.8 * st.b + (breathing and 0.5 or 0) + 0.08 * pulse)
	for _, e in ipairs(st.eyes) do set(st, e, "Color", eyeCol) end
	local glowCol = heat(GLOW_DIM, GLOW_HOT, GLOW_MAX, 0.55 + 0.45 * st.s + 0.7 * st.b)
	for _, g in ipairs(st.glows) do set(st, g, "Color", glowCol) end

	-- moving parts: only on a still podium (a turning one is moved by ScooterPodiumSpin)
	if not st.still then return end
	table.clear(st.moving); table.clear(st.cframes)
	-- wings: unlock, unfold, then beat while open
	st.wing = approach(st.wing, st.b > 0.35 and 1 or 0, st.b > 0.35 and 2.2 or 2.8, dt)
	local w = st.wing
	local open = smooth((w - 0.12) / 0.88)
	local unlock = (w > 0.01 and w < 0.2) and math.sin(w / 0.2 * math.pi) * 0.05 or 0
	local flap = SHOW_FLAP * open * math.sin(st.t * 4.5)
	for _, wp in ipairs(st.wings) do
		local rot = CFrame.identity:Lerp(wp.open, open * SHOW_OPEN) * CFrame.Angles(0, 0, (unlock + flap) * wp.side)
		table.insert(st.moving, wp.part)
		table.insert(st.cframes, wp.hinge * rot * wp.hinge:Inverse() * wp.base)
	end
	-- tail: each segment swings from its joint, carrying the ones after it
	local amp = math.rad(3 + 7 * st.s)
	local M = CFrame.identity
	for i = 1, #st.tail do
		local seg = st.tail[i]
		if not seg then break end
		local r = CFrame.Angles(math.rad(1.5) * math.sin(st.t * 1.3 + i), amp * math.sin(st.t * (1.6 + 2 * st.s) - i * 0.7), 0)
		M = M * seg.joint * r * seg.joint:Inverse()
		for _, tp in ipairs(seg.parts) do
			table.insert(st.moving, tp.part)
			table.insert(st.cframes, M * tp.base)
		end
	end
	workspace:BulkMoveTo(st.moving, st.cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

RunService.RenderStepped:Connect(function(dt)
	dt = math.clamp(dt, 1 / 240, 1 / 20)
	local now = os.clock()
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position
	for display, st in pairs(displays) do
		if not display.Parent then
			displays[display] = nil                    -- replaced or streamed out
		elseif camPos and (display:GetPivot().Position - camPos).Magnitude < SHOW_RANGE then
			showcase(st, dt, now)
		end
	end
	for model, st in pairs(dragons) do
		local chassis = model.Parent and model.PrimaryPart
		if not model.Parent then
			dragons[model] = nil                       -- the ride is over: its parts went with it
		elseif chassis and camPos and (chassis.Position - camPos).Magnitude < RANGE then
			st.resting = false
			update(st, chassis, dt, now)
		else
			rest(st)
		end
	end
end)
