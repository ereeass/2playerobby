--=====================================================================
-- ReaperScooterFx   (each player's own machine; looks only)
--
-- Brings the Death Reaper scooter (ServerStorage.ScooterModels.ReaperScooter, the model with
-- the DeathReaper attribute) to life on every Death Reaper ridden near this player's camera.
-- It only reads each scooter's speed and changes colours, lights, particle rates, trails,
-- transparencies and the cloth / chain / hand hinges' Transforms - nothing here touches
-- physics, the server, ownership or anyone's ride. All it moves belongs to the scooter, so it
-- goes when the scooter does; nothing is created.
--   Idle     the eyes glow softly, the cloth stirs, the lantern flickers (the idle mist and
--            lantern sparks are the model's own emitters)
--   Moving   the torn cloth streams back, the chains swing back, purple mist and small souls
--            trail behind (...Trail emitters, which ScooterFx runs with speed)
--   Waking   as speed builds: the eyes, scythe edge, runes and wheel rings burn brighter,
--            the scythe crackles with energy and violet streaks trail off the rear
--   Boost    the scooters have no boost, so holding near top speed is the boost: the eyes
--            blaze, a great soul stream pours off the rear, the cloth thrashes and spectral
--            hands reach up out of the trail
--=====================================================================

local RunService = game:GetService("RunService")

local TOP_SPEED  = 20.8   -- studs/s at full throttle (ScooterFx's figure)
local RANGE      = 220    -- studs from the camera; farther scooters are left as they are
local BOOST_ON   = 0.86   -- share of top speed that counts as boosting...
local BOOST_OFF  = 0.7    -- ...and below which it stops
local BOOST_HOLD = 0.6    -- seconds held near top speed before it counts
local HAND_GAP   = 2.6    -- seconds between hands reaching out while boosting
local HAND_TIME  = 1.3    -- one reach, up and back down

local RGB = Color3.fromRGB
local DIM, HOT, WHITE_HOT = RGB(60, 20, 110), RGB(170, 80, 255), RGB(236, 214, 255)

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
	st.eyes, st.edges, st.runes, st.wheels, st.cloth, st.chains, st.hands, st.handParts, st.streaks = {}, {}, {}, {}, {}, {}, {}, {}, {}
	st.light, st.gaze, st.lantern, st.soul, st.stream, st.energy = nil, nil, nil, nil, nil, nil
	for _, d in ipairs(st.model:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name == "ReaperEye" then table.insert(st.eyes, d)
			elseif d.Name == "ScytheEdge" then table.insert(st.edges, d)
			elseif d.Name == "ReaperRune" then table.insert(st.runes, d)
			elseif d.Name == "ReaperWheel" then table.insert(st.wheels, d)
			elseif d.Name == "SoulLantern" then st.lantern = d
			elseif d.Name == "LanternSoul" then st.soul = d
			elseif d:GetAttribute("HandT") then table.insert(st.handParts, { part = d, t = d:GetAttribute("HandT"), hand = nil }) end
		elseif d:IsA("Motor6D") then
			if d:GetAttribute("Cloth") then table.insert(st.cloth, { j = d, ph = d:GetAttribute("Cloth") * 1.37, len = d:GetAttribute("Len") or 1.5 })
			elseif d.Name == "ChainHinge" then table.insert(st.chains, { j = d, ph = d:GetAttribute("Phase") or 0 })
			elseif d:GetAttribute("Hand") then st.hands[d:GetAttribute("Hand")] = { j = d, at = -math.huge } end
		elseif d:IsA("PointLight") then
			if d.Name == "LanternLight" then st.light = d elseif d.Name == "GazeLight" then st.gaze = d end
		elseif d:IsA("Trail") and d.Name == "ReaperStreak" then table.insert(st.streaks, d)
		elseif d:IsA("ParticleEmitter") then
			if d.Name == "SoulStream" then st.stream = d elseif d.Name == "ScytheEnergy" then st.energy = d end
		end
	end
	-- which hand each hand part belongs to: the one whose palm it is, or is welded to
	for _, hp in ipairs(st.handParts) do
		for k, h in pairs(st.hands) do
			local palm = h.j.Part1
			local w = hp.part:FindFirstChildOfClass("WeldConstraint")
			if hp.part == palm or (w and (w.Part0 == palm or w.Part1 == palm)) then hp.hand = k end
		end
	end
end

local function setup(model)
	if states[model] or not model:IsA("Model") or not model:GetAttribute("DeathReaper") then return end
	local st = { model = model, speed = 0, s = 0, b = 0, hold = 0, t = math.random() * 10, handAt = -math.huge, nextHand = 1, written = {} }
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
	local wake = smooth((st.s - 0.2) / 0.8)   -- the reaper waking with speed

	-- boost: held near top speed; hands reach out of the trail while it lasts
	if st.s >= BOOST_ON then st.hold += dt elseif st.s < BOOST_OFF then st.hold = 0 end
	local boosting = st.hold >= BOOST_HOLD
	st.b = approach(st.b, boosting and 1 or 0, boosting and 3 or 1.5, dt)
	if boosting and now - st.handAt > HAND_GAP then
		st.handAt = now
		local h = st.hands[st.nextHand]
		if h then h.at = now end
		st.nextHand = st.nextHand % 2 + 1
	end
	for k, h in pairs(st.hands) do
		local u = (now - h.at) / HAND_TIME
		local rise = (u >= 0 and u <= 1) and math.sin(u * math.pi) or 0
		h.rise = rise
		h.j.Transform = CFrame.new(0, -2.6 * (1 - rise), 0) * CFrame.Angles(-0.5 * (1 - rise), 0, math.sin(st.t * 9 + k) * 0.08 * rise)
	end
	for _, hp in ipairs(st.handParts) do
		local h = hp.hand and st.hands[hp.hand]
		local r = h and h.rise or 0
		set(st, hp.part, "Transparency", 1 - r * (1 - hp.t), 0.01)
	end

	-- eyes: a slow glow at rest, brighter as it wakes, blazing in the boost
	local pulse = 0.5 + 0.5 * math.sin(st.t * 1.6)
	local eyeCol = heat(0.55 + 0.25 * pulse + 0.5 * wake + 0.8 * st.b)
	for _, e in ipairs(st.eyes) do set(st, e, "Color", eyeCol) end
	if st.gaze then set(st, st.gaze, "Brightness", 0.4 + 0.3 * pulse + 1.2 * wake + 1.5 * st.b, 0.05) end
	-- the scythe edge, deck runes and wheel rings
	local edgeCol = heat(0.35 + 0.15 * pulse + 0.7 * wake + 0.8 * st.b)
	for _, e in ipairs(st.edges) do set(st, e, "Color", edgeCol) end
	local runeCol = heat(0.3 + 0.1 * pulse + 0.8 * wake + 0.3 * st.b)
	for _, r in ipairs(st.runes) do set(st, r, "Color", runeCol) end
	for _, w in ipairs(st.wheels) do set(st, w, "Color", runeCol) end
	if st.energy then set(st, st.energy, "Rate", wake < 0.3 and 0 or (st.energy:GetAttribute("Max") or 40) * (0.3 * wake * wake + 0.7 * st.b), 0.5) end

	-- the soul lantern flickers
	local flick = 0.75 + 0.25 * math.sin(st.t * 11) * math.sin(st.t * 7.3 + 1) + 0.1 * math.random()
	if st.light then set(st, st.light, "Brightness", (0.9 + 0.8 * wake + 0.8 * st.b) * flick, 0.05) end
	if st.soul then set(st, st.soul, "Transparency", 0.15 + 0.35 * (1 - flick), 0.03) end

	-- torn cloth: stirs at rest, streams back with speed, thrashes in the boost
	for _, c in ipairs(st.cloth) do
		local k = 1.5 / c.len   -- shorter rags flick faster
		local back = -(math.rad(2) + math.rad(34) * st.s + math.rad(10) * st.b)   -- capped so the rags stop short of the driver
		local flutter = math.sin(st.t * (2 + 13 * st.s + 6 * st.b) * k + c.ph) * math.rad(3 + 9 * st.s + 12 * st.b)
		local side = math.sin(st.t * (1.5 + 8 * st.s) * k + c.ph * 1.7) * math.rad(2 + 5 * st.s + 6 * st.b)
		c.j.Transform = CFrame.Angles(back + flutter, 0, side)
	end
	-- chains swing back with speed and jangle
	for _, c in ipairs(st.chains) do
		c.j.Transform = CFrame.Angles(-math.rad(22) * st.s + math.sin(st.t * (1.6 + 5 * st.s) + c.ph) * math.rad(3 + 6 * st.s), 0, math.sin(st.t * 1.2 + c.ph) * math.rad(3))
	end

	-- the soul stream and the streaks
	if st.stream then set(st, st.stream, "Rate", wake < 0.15 and 0 or (st.stream:GetAttribute("Max") or 30) * (0.2 * wake * wake + 0.8 * st.b), 0.5) end
	local streak = wake > 0.7
	for _, tr in ipairs(st.streaks) do if tr.Enabled ~= streak then tr.Enabled = streak end end
end

-- out of range: the loud parts switched off so nothing pours out far away
local function rest(st)
	if st.resting then return end
	st.resting = true
	if st.stream then set(st, st.stream, "Rate", 0) end
	if st.energy then set(st, st.energy, "Rate", 0) end
	for _, tr in ipairs(st.streaks) do tr.Enabled = false end
	for _, hp in ipairs(st.handParts) do set(st, hp.part, "Transparency", 1) end
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
