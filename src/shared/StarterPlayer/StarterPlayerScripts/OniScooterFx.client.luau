--=====================================================================
-- OniScooterFx   (each player's own machine; looks only)
--
-- Brings the Cyber Oni scooter (ServerStorage.ScooterModels.OniScooter, the model with the
-- CyberOni attribute) to life on every Cyber Oni ridden near this player's camera. It only
-- reads each scooter's speed and changes colours, lights, particle rates, trails and the
-- talisman / chain / lantern hinges' Transforms - nothing here touches physics, the
-- server, ownership or anyone's ride. All it moves belongs to the scooter, so it goes
-- when the scooter does; nothing is created.
--   Idle     the eyes pulse now and then, the markings breathe faintly, the talismans and
--            lantern barely sway (the idle smoke and embers are the model's own emitters)
--   Moving   talismans flutter back, harder with speed; chains swing; the cursed smoke
--            stretches back (a ...Trail emitter, which ScooterFx runs with speed)
--   Waking   as speed builds the oni wakes: eyes brighten, markings and wheel lines glow,
--            aura smoke pours off the rear fins and red streaks trail from their tips
--   Boost    the scooters have no boost, so holding near top speed is the boost: the eyes
--            and markings flare hotter and the aura pours harder (the oni spirit that
--            used to rise here was taken off the model; its code waits for no parts)
--=====================================================================

local RunService = game:GetService("RunService")

local TOP_SPEED  = 20.8   -- studs/s at full throttle (ScooterFx's figure)
local RANGE      = 220    -- studs from the camera; farther scooters are left as they are
local BOOST_ON   = 0.86   -- share of top speed that counts as boosting...
local BOOST_OFF  = 0.7    -- ...and below which it stops
local BOOST_HOLD = 0.6    -- seconds held near top speed before it counts
local SPIRIT_GAP = 7      -- seconds between spirits
local SPIRIT_IN, SPIRIT_HOLD, SPIRIT_OUT = 0.4, 1.8, 0.8

local RGB = Color3.fromRGB
local DIM, HOT, WHITE_HOT = RGB(80, 4, 10), RGB(255, 34, 44), RGB(255, 175, 175)

local function approach(cur, target, rate, dt) return cur + (target - cur) * (1 - math.exp(-rate * dt)) end
local function smooth(x) x = math.clamp(x, 0, 1); return x * x * (3 - 2 * x) end
local function heat(k)   -- 0 dim .. 1 hot .. 2 white-hot
	if k <= 1 then return DIM:Lerp(HOT, math.max(k, 0)) end
	return HOT:Lerp(WHITE_HOT, math.min(k - 1, 1))
end

local scooters = workspace:WaitForChild("RideSystem"):WaitForChild("Scooters")
local states = {}   -- [scooter model] = state

local function collect(st)
	st.dirty = false
	st.eyes, st.marks, st.glows, st.talismans, st.chains, st.lanterns, st.spirit, st.streaks = {}, {}, {}, {}, {}, {}, {}, {}
	for _, d in ipairs(st.model:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name == "OniEye" or d.Name == "OniMouth" then table.insert(st.eyes, d)
			elseif d.Name == "OniMark" then table.insert(st.marks, d)
			elseif d.Name == "OniGlow" then table.insert(st.glows, d)
			elseif d:GetAttribute("SpiritT") then table.insert(st.spirit, { part = d, t = d:GetAttribute("SpiritT") }) end
		elseif d:IsA("Motor6D") then
			if d:GetAttribute("Talisman") then table.insert(st.talismans, { j = d, ph = d:GetAttribute("Talisman") * 1.37 + (d:GetAttribute("Swing") and 0.6 or 0), k = d:GetAttribute("Swing") or 1 })
			elseif d:GetAttribute("Chain") then table.insert(st.chains, { j = d, side = d:GetAttribute("Chain") })
			elseif d:GetAttribute("Lantern") then table.insert(st.lanterns, d) end
		elseif d:IsA("PointLight") and d.Name == "LanternLight" then st.light = d
		elseif d:IsA("Trail") and d.Name == "OniStreak" then table.insert(st.streaks, d)
		elseif d:IsA("ParticleEmitter") then
			if d.Name == "AuraSmoke" then st.aura = d elseif d.Name == "SpiritWisps" then st.wisps = d end
		end
	end
end

local function setup(model)
	if states[model] or not model:IsA("Model") or not model:GetAttribute("CyberOni") then return end
	local st = { model = model, speed = 0, s = 0, b = 0, hold = 0, t = math.random() * 10, spiritAt = -math.huge, alpha = 0, written = {} }
	collect(st)
	model.DescendantAdded:Connect(function() st.dirty = true end)   -- parts streaming in later
	states[model] = st
end
scooters.ChildAdded:Connect(function(m) task.defer(setup, m) end)
for _, m in ipairs(scooters:GetChildren()) do setup(m) end

-- a property is only written when it has really changed
local function set(st, obj, prop, value, eps)
	local key = st.written[obj]
	if not key then key = {}; st.written[obj] = key end
	local last = key[prop]
	if last ~= nil then
		if typeof(value) == "Color3" then
			if math.abs(last.R - value.R) + math.abs(last.G - value.G) + math.abs(last.B - value.B) < (eps or 0.015) then return end
		elseif last == value or (value ~= 0 and math.abs(last - value) < (eps or 0.01)) then return end
	end
	key[prop] = value
	obj[prop] = value
end

local function update(st, chassis, dt, now)
	if st.dirty then collect(st) end
	st.t += dt
	local v = chassis.AssemblyLinearVelocity
	st.speed = approach(st.speed, Vector3.new(v.X, 0, v.Z).Magnitude, 10, dt)
	st.s = math.clamp(st.speed / TOP_SPEED, 0, 1)
	local wake = smooth((st.s - 0.2) / 0.8)   -- the oni waking with speed

	-- boost: held near top speed; the spirit rises as it starts
	if st.s >= BOOST_ON then st.hold += dt elseif st.s < BOOST_OFF then st.hold = 0 end
	local boosting = st.hold >= BOOST_HOLD
	local wasBoost = st.b > 0.5
	st.b = approach(st.b, boosting and 1 or 0, boosting and 3 or 1.5, dt)
	if st.b > 0.5 and not wasBoost and now - st.spiritAt > SPIRIT_GAP then
		st.spiritAt = now
		if st.wisps then st.wisps:Emit(14) end
	end
	local since = now - st.spiritAt
	local alpha = 0
	if since < SPIRIT_IN then alpha = smooth(since / SPIRIT_IN)
	elseif since < SPIRIT_IN + SPIRIT_HOLD then alpha = 1
	elseif since < SPIRIT_IN + SPIRIT_HOLD + SPIRIT_OUT then alpha = 1 - smooth((since - SPIRIT_IN - SPIRIT_HOLD) / SPIRIT_OUT) end
	for _, sp in ipairs(st.spirit) do set(st, sp.part, "Transparency", 1 - alpha * (1 - sp.t), 0.01) end

	-- eyes: an idle pulse every few seconds, brighter as it wakes, blazing with the spirit
	local pulse = math.max(0, math.sin(st.t * 1.8)) ^ 6
	local eyeCol = heat(0.55 + 0.35 * pulse + 0.6 * wake + 0.8 * alpha)
	for _, e in ipairs(st.eyes) do set(st, e, "Color", eyeCol) end
	-- markings: a faint breath at rest, glowing as it wakes
	local markCol = heat(0.1 + 0.15 * pulse + 0.9 * wake + 0.4 * st.b)
	for _, mk in ipairs(st.marks) do set(st, mk, "Color", markCol) end
	local glowCol = heat(0.15 + 0.85 * wake + 0.3 * st.b)
	for _, g in ipairs(st.glows) do set(st, g, "Color", glowCol) end
	if st.light then set(st, st.light, "Brightness", 0.7 + 1.2 * wake + 0.8 * alpha, 0.05) end

	-- talismans flutter back: gently at rest, hard at speed, violently in the boost
	for _, tl in ipairs(st.talismans) do
		local back = -(math.rad(3) + math.rad(55) * st.s + math.rad(12) * st.b)
		local flutter = math.sin(st.t * (2.5 + 14 * st.s) + tl.ph) * math.rad(2 + 10 * st.s + 8 * st.b)
		local side = math.sin(st.t * (2 + 9 * st.s) + tl.ph * 1.7) * math.rad(1.5 + 5 * st.s)
		tl.j.Transform = CFrame.Angles((back + flutter) * tl.k, 0, side * tl.k)   -- Swing: the long bar chains move less
	end
	for _, j in ipairs(st.lanterns) do
		j.Transform = CFrame.Angles(-math.rad(25) * st.s + math.sin(st.t * (1.6 + 4 * st.s)) * math.rad(3 + 5 * st.s), 0, math.sin(st.t * 1.1) * math.rad(2))
	end
	-- chains sway, swinging out a little with speed
	for _, c in ipairs(st.chains) do
		c.j.Transform = CFrame.Angles(0, 0, -c.side * (math.rad(14) * st.s + math.sin(st.t * (1.4 + 5 * st.s) + c.side) * math.rad(3 + 6 * st.s)))
	end

	-- the aura and the streaks as it wakes
	if st.aura then set(st, st.aura, "Rate", wake < 0.1 and 0 or (st.aura:GetAttribute("Max") or 24) * (0.6 * wake * wake + 0.5 * st.b), 0.5) end
	local streak = wake > 0.7
	for _, tr in ipairs(st.streaks) do if tr.Enabled ~= streak then tr.Enabled = streak end end
end

-- out of range: the loud parts switched off so nothing pours out far away
local function rest(st)
	if st.resting then return end
	st.resting = true
	if st.aura then set(st, st.aura, "Rate", 0) end
	for _, tr in ipairs(st.streaks) do tr.Enabled = false end
	for _, sp in ipairs(st.spirit) do set(st, sp.part, "Transparency", 1) end
end

RunService.RenderStepped:Connect(function(dt)
	dt = math.clamp(dt, 1 / 240, 1 / 20)
	local now = os.clock()
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position
	for model, st in pairs(states) do
		local chassis = model.Parent and model.PrimaryPart
		if not model.Parent then
			states[model] = nil                        -- the ride is over: its parts went with it
		elseif chassis and camPos and (chassis.Position - camPos).Magnitude < RANGE then
			st.resting = false
			update(st, chassis, dt, now)
		else
			rest(st)
		end
	end
end)
