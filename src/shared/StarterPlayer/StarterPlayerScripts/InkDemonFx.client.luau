--=====================================================================
-- InkDemonFx   (each player's own machine; looks only)
--
-- Brings the Ink Demon scooter (ServerStorage.ScooterModels.InkDemonScooter, the model with
-- the InkDemon attribute) to life on every Ink Demon ridden near this player's camera. It
-- only reads each scooter's speed and changes colours, lights, transparencies, particle
-- rates, trails and the tendril / talisman / drip hinges' Transforms - nothing here touches
-- physics, the server, ownership or anyone's ride, and nothing is left on the map: every
-- mark it makes is a particle or trail that fades in under half a second.
--   Idle     the eyes pulse, tendrils stir, drops of ink slide down the drips and fall,
--            sketch lines now and then flicker as if being redrawn (the falling droplets
--            under the deck are the model's own emitter)
--   Moving   the ink stretches back: tendrils stream behind, drips run backwards, ink
--            splatters off the rear wheel (a ...Trail emitter ScooterFx runs with speed),
--            brush strokes and sketch marks fly off the back, splashes kick up at the wheels
--            and the brush trail paints a quick streak behind
--   Fast     near top speed (the scooters have no boost, so that is the boost) the eyes
--            blaze, the tendrils thrash, sketch lines redraw frantically, the strokes and
--            splashes pour, and bits of the demon flicker as if being redrawn in ink
--=====================================================================

local RunService = game:GetService("RunService")

local TOP_SPEED  = 20.8   -- studs/s at full throttle (ScooterFx's figure)
local RANGE      = 220    -- studs from the camera; farther scooters are left as they are
local BOOST_ON   = 0.86   -- share of top speed that counts as boosting...
local BOOST_OFF  = 0.7    -- ...and below which it stops
local BOOST_HOLD = 0.6    -- seconds held near top speed before it counts
local DRIP_TIME  = 2.4    -- seconds for one drop to slide down and fall (at rest)

local RGB = Color3.fromRGB
local EYE_DIM, EYE_HOT = RGB(150, 150, 158), RGB(255, 255, 255)
local REDRAW = RGB(96, 94, 100)   -- the flash of a part being redrawn

local function approach(cur, target, rate, dt) return cur + (target - cur) * (1 - math.exp(-rate * dt)) end
local function smooth(x) x = math.clamp(x, 0, 1); return x * x * (3 - 2 * x) end

local scooters = workspace:WaitForChild("RideSystem"):WaitForChild("Scooters")
local states = {}   -- [scooter model] = state

local function collect(st)
	st.dirty = false
	st.eyes, st.tendrils, st.talismans, st.drips, st.sketch, st.body, st.trails = {}, {}, {}, {}, {}, {}, {}
	st.light, st.brush, st.marks, st.splashes = nil, nil, nil, {}
	for _, d in ipairs(st.model:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name == "InkEye" then table.insert(st.eyes, d)
			elseif d.Name == "SketchLine" then
				-- its drawn look is remembered the first time it is seen: a re-collect (a rider's
				-- welds arriving) can happen while a line is blinked out or a part mid-flash
				if st.origT[d] == nil then st.origT[d] = d.Transparency end
				table.insert(st.sketch, { part = d, base = st.origT[d], until_ = 0, next = math.random() * 4 })
			elseif d.Name == "InkBody" or d.Name == "InkHorn" or d.Name == "InkTendril" then
				if st.origC[d] == nil then st.origC[d] = d.Color end
				table.insert(st.body, { part = d, color = st.origC[d], until_ = 0 })
			end
		elseif d:IsA("Motor6D") then
			if d:GetAttribute("Tendril") then table.insert(st.tendrils, { j = d, ph = d:GetAttribute("Tendril") * 1.9, rear = d:GetAttribute("Kind") == "rear" })
			elseif d:GetAttribute("Talisman") then table.insert(st.talismans, { j = d, ph = d:GetAttribute("Talisman") * 1.37 })
			elseif d:GetAttribute("Drip") then table.insert(st.drips, { j = d, part = d.Part1, ph = d:GetAttribute("Drip") * 0.37, u = (d:GetAttribute("Drip") * 0.37) % 1 }) end
		elseif d:IsA("PointLight") and d.Name == "EyeLight" then st.light = d
		elseif d:IsA("Trail") and d.Name == "InkBrushTrail" then table.insert(st.trails, d)
		elseif d:IsA("ParticleEmitter") then
			if d.Name == "BrushStroke" then st.brush = d
			elseif d.Name == "SketchMarks" then st.marks = d
			elseif d.Name == "WheelSplash" then table.insert(st.splashes, d) end
		end
	end
end

local function setup(model)
	if states[model] or not model:IsA("Model") or not model:GetAttribute("InkDemon") then return end
	local st = { model = model, speed = 0, s = 0, b = 0, hold = 0, t = math.random() * 10, redrawAcc = 0, written = {}, origT = {}, origC = {} }
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
	local wake = smooth((st.s - 0.15) / 0.85)   -- the ink coming alive with speed
	if st.s >= BOOST_ON then st.hold += dt elseif st.s < BOOST_OFF then st.hold = 0 end
	local boosting = st.hold >= BOOST_HOLD
	st.b = approach(st.b, boosting and 1 or 0, boosting and 3 or 1.5, dt)

	-- eyes: a slow pulse at rest, burning white as it speeds up, blazing near top speed
	local pulse = 0.5 + 0.5 * math.sin(st.t * 1.7)
	local eye = math.clamp(0.25 + 0.35 * pulse + 0.6 * wake, 0, 1)
	local eyeCol = EYE_DIM:Lerp(EYE_HOT, eye)
	for _, e in ipairs(st.eyes) do set(st, e, "Color", eyeCol) end
	if st.light then
		set(st, st.light, "Brightness", 0.4 + 0.5 * pulse + 1.6 * wake + 2.5 * st.b, 0.05)
		set(st, st.light, "Range", 4 + 4 * st.b, 0.1)
	end

	-- tendrils: stirring at rest, streaming back with speed, thrashing near top speed
	local wild = 1 + 1.5 * st.b
	for _, td in ipairs(st.tendrils) do
		local f = (1.4 + 6 * st.s + 5 * st.b)
		local wave = math.sin(st.t * f + td.ph) * math.rad(4 + 8 * st.s) * wild
		local whip = math.sin(st.t * f * 0.7 + td.ph * 1.3) * math.rad(3 + 7 * st.s) * wild
		if td.rear then
			-- they trail behind already: lift a little and lash side to side
			td.j.Transform = CFrame.Angles(-math.rad(8) * st.s + wave, whip, 0)
		else
			-- they hang beside the column: blown back with speed
			td.j.Transform = CFrame.Angles(-math.rad(34) * st.s - math.rad(10) * st.b + wave, 0, whip * 0.6)
		end
	end
	-- talismans flutter back with speed
	for _, tl in ipairs(st.talismans) do
		local back = -(math.rad(3) + math.rad(50) * st.s + math.rad(12) * st.b)
		local flutter = math.sin(st.t * (2.5 + 14 * st.s) + tl.ph) * math.rad(2 + 10 * st.s + 8 * st.b)
		local side = math.sin(st.t * (2 + 9 * st.s) + tl.ph * 1.7) * math.rad(1.5 + 5 * st.s)
		tl.j.Transform = CFrame.Angles(back + flutter, 0, side)
	end

	-- drips: a drop slides down, swells, falls and vanishes; at speed it runs back as it falls
	local dripRate = (1 + 1.5 * st.s) / DRIP_TIME
	for _, dr in ipairs(st.drips) do
		dr.u = (dr.u + dt * dripRate) % 1
		local u = dr.u
		local fall = u < 0.55 and 0.08 * (u / 0.55) or 0.08 + 0.7 * ((u - 0.55) / 0.45) ^ 2
		dr.j.Transform = CFrame.new(0, -fall, fall * 1.6 * st.s)
		set(st, dr.part, "Transparency", u < 0.75 and 0 or (u - 0.75) / 0.25, 0.04)
	end

	-- sketch lines: now and then a line blinks out and is redrawn; frantic at speed
	local flips = 0.25 + 1.5 * wake + 2.5 * st.b   -- redraws per line per second
	local gone = 1 / (1 + 2 * wake)                  -- quicker redraws at speed, so the lines stay mostly drawn
	for _, sl in ipairs(st.sketch) do
		if now >= sl.next then
			sl.until_ = now + (0.05 + math.random() * 0.1) * gone
			sl.next = now + (0.5 + math.random()) / flips
		end
		set(st, sl.part, "Transparency", now < sl.until_ and 1 or sl.base, 0.01)
	end
	-- near top speed bits of the demon flash grey, as if the ink is being redrawn
	st.redrawAcc += dt * (wake > 0.6 and (6 * wake + 18 * st.b) or 0)
	while st.redrawAcc >= 1 and #st.body > 0 do
		st.redrawAcc -= 1
		local bp = st.body[math.random(1, #st.body)]
		bp.until_ = now + 0.05 + math.random() * 0.06
	end
	for _, bp in ipairs(st.body) do set(st, bp.part, "Color", now < bp.until_ and REDRAW or bp.color, 0.01) end

	-- the giant brush: strokes and sketch marks off the back, splashes at the wheels, the trail
	if st.brush then set(st, st.brush, "Rate", wake < 0.2 and 0 or (st.brush:GetAttribute("Max") or 40) * (0.35 * wake * wake + 0.65 * st.b), 0.5) end
	if st.marks then set(st, st.marks, "Rate", wake < 0.25 and 0 or (st.marks:GetAttribute("Max") or 24) * (0.5 * wake + 0.5 * st.b), 0.5) end
	for _, sp in ipairs(st.splashes) do
		set(st, sp, "Rate", st.s < 0.25 and 0 or (sp:GetAttribute("Max") or 30) * (0.3 * wake + 0.7 * st.b), 0.5)
	end
	local painting = st.s > 0.35
	for _, tr in ipairs(st.trails) do
		if tr.Enabled ~= painting then tr.Enabled = painting end
		set(st, tr, "Lifetime", 0.25 + 0.2 * st.b, 0.02)
	end
end

-- out of range: the loud parts switched off, everything back as drawn
local function rest(st)
	if st.resting then return end
	st.resting = true
	if st.brush then set(st, st.brush, "Rate", 0) end
	if st.marks then set(st, st.marks, "Rate", 0) end
	for _, sp in ipairs(st.splashes) do set(st, sp, "Rate", 0) end
	for _, tr in ipairs(st.trails) do tr.Enabled = false end
	for _, bp in ipairs(st.body) do bp.until_ = 0; set(st, bp.part, "Color", bp.color) end
	for _, sl in ipairs(st.sketch) do set(st, sl.part, "Transparency", sl.base) end
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
