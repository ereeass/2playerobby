--=====================================================================
-- IceScooterFx   (each player's own machine; looks only)
--
-- The Ice Scooter's premium look reacting to speed, on every Ice Scooter (the model with
-- the IcePremium attribute) ridden near this player's camera. It only reads each
-- scooter's speed and changes colours, transparency, mesh scales, trails and particle
-- rates - nothing here touches physics, the server, ownership or anyone's ride. All it
-- moves belongs to the scooter, so it goes when the scooter does; nothing is created.
--   Moving      frost streaks behind the tyres (the snow dust and ice chips off them are
--               ...Trail emitters, which ScooterFx already runs with speed)
--   Speed       it becomes supercooled: frost spreads over the body (FrostSpread), the
--               crystal cores and gems brighten, the rear crystals grow (GrowCrystal) and
--               cold mist streams off the back; slowing down undoes it all
--   Boost       the scooters have no boost, so holding near top speed is the boost: a
--               burst of freezing mist, ice shards sweeping back, a snow swirl, a longer
--               frozen streak and a crystalline shimmer across the ice
--=====================================================================

local RunService = game:GetService("RunService")

local TOP_SPEED  = 20.8   -- studs/s at full throttle (ScooterFx's figure)
local RANGE      = 220    -- studs from the camera; farther scooters are left as they are
local BOOST_ON   = 0.86   -- share of top speed that counts as boosting...
local BOOST_OFF  = 0.7    -- ...and below which it stops
local BOOST_HOLD = 0.6    -- seconds held near top speed before it counts
local BURST_GAP  = 4      -- seconds between boost bursts
local SHIMMER    = 0.6    -- seconds the crystalline shimmer lasts

local RGB = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)

local function approach(cur, target, rate, dt) return cur + (target - cur) * (1 - math.exp(-rate * dt)) end
local function smooth(x) x = math.clamp(x, 0, 1); return x * x * (3 - 2 * x) end

local scooters = workspace:WaitForChild("RideSystem"):WaitForChild("Scooters")
local states = {}   -- [scooter model] = state

local function collect(st)
	st.dirty = false
	st.frost, st.grow, st.shine, st.streaks, st.burst = {}, {}, {}, {}, {}
	for _, d in ipairs(st.model:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name == "FrostSpread" then table.insert(st.frost, d)
			elseif d.Name == "GrowCrystal" then
				local mesh = d:FindFirstChildOfClass("SpecialMesh")
				if mesh then table.insert(st.grow, { mesh = mesh, len = d:GetAttribute("GrowLength") or 0.4, w = d:GetAttribute("GrowWidth") or 0.1, size = d.Size.X }) end
			elseif d.Name == "IceCore" or (d.Name == "Gem" and d.Material == Enum.Material.Neon) then
				table.insert(st.shine, { part = d, color = d.Color, t = d.Transparency })
			end
		elseif d:IsA("Trail") and d.Name == "FrostStreak" then table.insert(st.streaks, d)
		elseif d:IsA("ParticleEmitter") then
			if d.Name == "SpeedMist" then st.speedMist = d
			elseif d.Name == "BurstMist" or d.Name == "BurstShards" or d.Name == "SnowSwirl" then st.burst[d.Name] = d end
		end
	end
end

local function setup(model)
	if states[model] or not model:IsA("Model") or not model:GetAttribute("IcePremium") then return end
	local st = { model = model, speed = 0, s = 0, b = 0, hold = 0, burstAt = -math.huge, shimmerUntil = 0, written = {} }
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
		elseif typeof(value) == "Vector3" then
			if (last - value).Magnitude < (eps or 0.01) then return end
		elseif last == value or (value ~= 0 and math.abs(last - value) < (eps or 0.01)) then return end
	end
	key[prop] = value
	obj[prop] = value
end

local function update(st, chassis, dt, now)
	if st.dirty then collect(st) end
	local v = chassis.AssemblyLinearVelocity
	st.speed = approach(st.speed, Vector3.new(v.X, 0, v.Z).Magnitude, 10, dt)
	st.s = math.clamp(st.speed / TOP_SPEED, 0, 1)
	local cold = smooth((st.s - 0.25) / 0.75)   -- 0 until a quarter of top speed, 1 at top speed

	-- boost: held near top speed for a moment
	if st.s >= BOOST_ON then st.hold += dt elseif st.s < BOOST_OFF then st.hold = 0 end
	local boosting = st.hold >= BOOST_HOLD
	local wasBoost = st.b > 0.5
	st.b = approach(st.b, boosting and 1 or 0, boosting and 3 or 1.5, dt)
	if st.b > 0.5 and not wasBoost and now - st.burstAt > BURST_GAP then
		st.burstAt, st.shimmerUntil = now, now + SHIMMER
		if st.burst.BurstMist then st.burst.BurstMist:Emit(14) end
		if st.burst.BurstShards then st.burst.BurstShards:Emit(16) end
		if st.burst.SnowSwirl then st.burst.SnowSwirl:Emit(26) end
	end
	local shimmer = now < st.shimmerUntil and math.sin((1 - (st.shimmerUntil - now) / SHIMMER) * math.pi) or 0

	-- frost spreading over the body with speed
	local frostT = 1 - 0.65 * cold - 0.1 * st.b
	for _, f in ipairs(st.frost) do set(st, f, "Transparency", math.clamp(frostT, 0.25, 1)) end
	-- crystal cores and gems: brighter with speed, a flash of white in the shimmer
	for _, sh in ipairs(st.shine) do
		set(st, sh.part, "Color", sh.color:Lerp(WHITE, math.clamp(0.35 * cold + 0.65 * shimmer, 0, 1)))
		set(st, sh.part, "Transparency", math.clamp(sh.t - 0.25 * cold - 0.2 * shimmer, 0, 1))
	end
	-- the rear crystals grow as it gets colder, and shrink back as it slows
	local k = 0.15 + 0.85 * cold + 0.15 * st.b
	for _, g in ipairs(st.grow) do
		local len, w = g.len * k, g.w * (0.6 + 0.4 * k)
		set(st, g.mesh, "Scale", Vector3.new(w / g.size, len / g.size, w / g.size))
		set(st, g.mesh, "Offset", Vector3.new(0, len / 2, 0))
	end
	-- supercooled mist off the back
	if st.speedMist then set(st, st.speedMist, "Rate", cold < 0.05 and 0 or (st.speedMist:GetAttribute("Max") or 12) * (cold * cold + 0.6 * st.b), 0.5) end
	-- frost streaks behind the tyres: longer for a moment in the boost
	local moving = st.s > 0.12
	for _, tr in ipairs(st.streaks) do
		if tr.Enabled ~= moving then tr.Enabled = moving end
		set(st, tr, "Lifetime", 0.45 + 0.8 * st.b, 0.05)
	end
end

-- out of range or gone: nothing left streaming on far away
local function rest(st)
	if st.resting then return end
	st.resting = true
	if st.speedMist then set(st, st.speedMist, "Rate", 0) end
	for _, tr in ipairs(st.streaks) do tr.Enabled = false end
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
