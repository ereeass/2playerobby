--=====================================================================
-- WatcherFx   (each player's own machine; looks only)
--
-- Brings The Watcher (ServerStorage.ScooterModels.WatcherScooter, the model with the Watcher
-- attribute) to life on every Watcher ridden near this player's camera. It only reads each
-- scooter's speed and changes colours, lights, transparencies, particle rates, trails and its
-- own hinges' Transforms (eyes, lids, rings, floating pieces, orbs, pendants, trail eyes) -
-- nothing here touches physics, the server, ownership or anyone's ride, and nothing is created.
--   Idle     the great eye looks slowly about (now and then at a nearby player) and blinks;
--            the orbs circle at their own paces, sometimes stopping to look around; the
--            rings turn slowly, the floating pieces drift, the symbols glow faintly
--   Moving   the eyes grow alert and watch the road, the rings and orbs speed up, the
--            pieces drift outward, the symbols brighten, gold streaks trail (ScooterFx runs
--            the ...Trail emitter)
--   Fast     near top speed (the scooters have no boost, so that is the boost) the pupils
--            narrow to slits, every eye wakes, symbols race across the body, the pieces part
--            further, and a short trail of eyes, stone fractures and gold lines drifts behind
--   Shift    now and then at top speed the world seems to bend: the rings snap into line,
--            the six pieces round the great eye lock into a turning hexagon, and every orb
--            turns to stare at the same point ahead - then it all slips back
-- Podium   the lobby podium's Watcher (ScooterPodiums: a still, visual-only copy with no
--          joints) runs the same animation, as if it were idling, then speeding up to top
--          speed (a shift included) and slowing again, round and round. The copy's parts
--          carry their joint's group and hinge as attributes (WGroup / WRoot / WHinge /
--          WKind / WJ_*, set on the model), so each group is moved here as one piece.
--=====================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local TOP_SPEED  = 20.8   -- studs/s at full throttle (ScooterFx's figure)
local RANGE      = 220    -- studs from the camera; farther scooters are left as they are
local BOOST_ON   = 0.86   -- share of top speed that counts as boosting...
local BOOST_OFF  = 0.7    -- ...and below which it stops
local BOOST_HOLD = 0.6    -- seconds held near top speed before it counts
local SHIFT_GAP  = { 6, 9 }              -- seconds between reality shifts at top speed
local SHIFT_IN, SHIFT_HOLD, SHIFT_OUT = 0.35, 0.8, 0.55
local WATCH_RANGE = 40    -- studs: how far the great eye notices other players
local SHOW_RANGE = 120    -- studs from the camera within which the podium's Watcher moves
local SHOW_CYCLE = 15     -- seconds: idle 6, speeding up 1.5, top speed 6, slowing 1.5

local RGB = Color3.fromRGB
local IRIS_DIM, IRIS_HOT = RGB(110, 58, 14), RGB(196, 118, 36)
local GLYPH_DIM, GLYPH_HOT = RGB(90, 62, 22), RGB(255, 206, 120)

local function approach(cur, target, rate, dt) return cur + (target - cur) * (1 - math.exp(-rate * dt)) end
local function smooth(x) x = math.clamp(x, 0, 1); return x * x * (3 - 2 * x) end
local function envelope(since, fin, hold, out)
	if since < 0 then return 0 end
	if since < fin then return smooth(since / fin) end
	if since < fin + hold then return 1 end
	if since < fin + hold + out then return 1 - smooth((since - fin - hold) / out) end
	return 0
end
local function rand(a, b) return a + (b - a) * math.random() end
local function frameOf(j) return j.Part0.CFrame * j.C0 end
-- a rotation whose -Z points along `dir` (given in the joint's own frame)
local function facing(dir)
	if dir.Magnitude < 1e-3 then return CFrame.identity end
	dir = dir.Unit
	local up = math.abs(dir.Y) > 0.98 and Vector3.zAxis or Vector3.yAxis
	return CFrame.lookAt(Vector3.zero, dir, up)
end

local scooters = workspace:WaitForChild("RideSystem"):WaitForChild("Scooters")
local states = {}   -- [scooter model] = state

local function weldedTo(part, root)
	local w = part:FindFirstChildOfClass("WeldConstraint")
	return w and (w.Part0 == root or w.Part1 == root)
end

-- one joint into the state's lists (a real Motor6D, or a podium copy's stand-in for one)
local function addJoint(st, d)
	if d:GetAttribute("Eye") then
		local e = st.eyeMem[d] or { yaw = 0, pitch = 0, ty = 0, tp = 0, nextLook = 0, nextBlink = os.clock() + rand(1, 4), blinkAt = -math.huge }
		st.eyeMem[d] = e
		e.j, e.idx, e.lids, e.wide, e.slit = d, d:GetAttribute("Eye"), {}, {}, {}
		st.eyes[e.idx] = e
	elseif d:GetAttribute("Lid") then table.insert(st.lidList, d)
	elseif d:GetAttribute("Ring") then
		local r = st.ringMem[d] or { angle = math.random() * 6 }
		st.ringMem[d] = r
		r.j, r.spin = d, d:GetAttribute("Spin") or 1
		r.tilt = CFrame.Angles(d:GetAttribute("TiltX") or 0, d:GetAttribute("TiltY") or 0, d:GetAttribute("TiltZ") or 0)
		table.insert(st.rings, r)
	elseif d:GetAttribute("Float") then
		table.insert(st.floats, { j = d, ph = d:GetAttribute("Float") * 1.73, form = d:GetAttribute("Form"),
			out = Vector3.new(d:GetAttribute("OutX") or 0, d:GetAttribute("OutY") or 0, d:GetAttribute("OutZ") or 0) })
	elseif d:GetAttribute("Orb") then
		local o = st.orbMem[d] or { angle = 0, pauseUntil = 0, nextPause = os.clock() + rand(3, 8) }
		st.orbMem[d] = o
		o.j, o.rx, o.ry, o.speed, o.phase = d, d:GetAttribute("Rx") or 1, d:GetAttribute("Ry") or 1, d:GetAttribute("Speed") or 0.5, d:GetAttribute("Phase") or 0
		table.insert(st.orbs, o)
	elseif d:GetAttribute("Pendant") then table.insert(st.pendants, { j = d, ph = d:GetAttribute("Pendant") * 1.9 })
	elseif d:GetAttribute("TrailEye") then table.insert(st.trail, { j = d, k = d:GetAttribute("TrailEye"), parts = {} }) end
end

local function collect(st)
	st.dirty = false
	local m = st.model
	st.eyes, st.rings, st.floats, st.orbs, st.pendants, st.trail, st.glyphs, st.irises, st.lines = {}, {}, {}, {}, {}, {}, {}, {}, {}
	st.light, st.fractures, st.centre = nil, nil, nil
	local parts = {}
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			if d.Name == "Glyph" then table.insert(st.glyphs, { part = d })
			elseif d.Name == "WatcherIris" or d.Name == "OrbIris" or d.Name == "WheelIris" then table.insert(st.irises, d) end
		elseif d:IsA("Motor6D") then
			addJoint(st, d)
		elseif d:IsA("PointLight") and d.Name == "EyeLight" then st.light = d
		elseif d:IsA("ParticleEmitter") and d.Name == "Fractures" then st.fractures = d
		elseif d:IsA("Trail") and d.Name == "WatcherLine" then table.insert(st.lines, d)
		elseif d:IsA("Attachment") and d.Name == "WatcherEyeCentre" then st.centre = d end
	end
	-- lids, pupils and trail-eye pieces belong to the eye / trail eye they hang from
	for _, l in ipairs(st.lidList) do local e = st.eyes[l:GetAttribute("Lid")]; if e then table.insert(e.lids, l) end end
	st.lidList = {}
	for _, p in ipairs(parts) do
		if p.Name == "PupilWide" or p.Name == "PupilSlit" then
			for _, e in pairs(st.eyes) do if weldedTo(p, e.j.Part1) then table.insert(p.Name == "PupilWide" and e.wide or e.slit, p) end end
		elseif p.Name == "TrailEye" then
			for _, te in ipairs(st.trail) do
				if p == te.j.Part1 or weldedTo(p, te.j.Part1) then table.insert(te.parts, { part = p, show = p:GetAttribute("ShowT") or 0.3 }) end
			end
		end
	end
	-- each symbol's place along the scooter, for the light racing across it
	local ch = m.PrimaryPart
	for _, g in ipairs(st.glyphs) do g.z = ch and ch.CFrame:PointToObjectSpace(g.part.Position).Z or 0 end
	table.sort(st.floats, function(a, b) return (a.form or 99) < (b.form or 99) end)
end

local function setup(model)
	if states[model] or not model:IsA("Model") or not model:GetAttribute("Watcher") then return end
	local st = { model = model, speed = 0, s = 0, b = 0, hold = 0, t = math.random() * 10, written = {},
		eyeMem = {}, ringMem = {}, orbMem = {}, lidList = {}, shiftAt = -math.huge, nextShift = 0 }
	collect(st)
	model.DescendantAdded:Connect(function() st.dirty = true end)   -- parts streaming in later, riders' welds
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

-- the nearest other player's head (not the riders of this scooter), if any is close enough
local function nearestHead(chassis, from)
	local best, bestD
	for _, p in ipairs(Players:GetPlayers()) do
		local head = p.Character and p.Character:FindFirstChild("Head")
		if head and (head.Position - chassis.Position).Magnitude > 5 then
			local d = (head.Position - from).Magnitude
			if d < WATCH_RANGE and (not bestD or d < bestD) then best, bestD = head, d end
		end
	end
	return best
end

local function update(st, chassis, dt, now)
	if st.dirty then collect(st) end
	st.t += dt
	local v = chassis.AssemblyLinearVelocity
	st.speed = approach(st.speed, Vector3.new(v.X, 0, v.Z).Magnitude, 10, dt)
	st.s = math.clamp(st.speed / TOP_SPEED, 0, 1)
	local s = st.s
	local wake = smooth((s - 0.15) / 0.85)
	if s >= BOOST_ON then st.hold += dt elseif s < BOOST_OFF then st.hold = 0 end
	local boosting = st.hold >= BOOST_HOLD
	st.b = approach(st.b, boosting and 1 or 0, boosting and 3 or 1.5, dt)
	local b = st.b

	-- the reality shift: only at top speed, now and then
	if b > 0.7 and now >= st.nextShift then
		if st.nextShift == 0 then st.nextShift = now + rand(2, 4) else st.shiftAt = now; st.nextShift = now + rand(SHIFT_GAP[1], SHIFT_GAP[2]) end
	elseif b < 0.3 then st.nextShift = 0 end
	local shift = envelope(now - st.shiftAt, SHIFT_IN, SHIFT_HOLD, SHIFT_OUT)
	local fwd = chassis.CFrame.LookVector
	local stare = (st.centre and st.centre.WorldPosition or chassis.Position) + fwd * 9 + Vector3.new(0, 3.5, 0)

	-- the eyes: wander and watch; more alert (smaller, quicker, forward glances) with speed
	for idx, e in pairs(st.eyes) do
		local frame = frameOf(e.j)
		if now >= e.nextLook then
			local alert = math.clamp(wake + b, 0, 1)
			e.nextLook = now + rand(1.2, 3.4) * (1 - 0.65 * alert)
			local target = (idx == 1 and alert < 0.5 and math.random() < 0.35) and nearestHead(chassis, frame.Position)
			if target then
				local d = frame:VectorToObjectSpace(target.Position - frame.Position)
				e.ty, e.tp = math.atan2(d.X, -d.Z), math.atan2(d.Y, math.sqrt(d.X * d.X + d.Z * d.Z))
			else
				local reach = 1 - 0.65 * alert
				e.ty, e.tp = math.rad(rand(-32, 32)) * reach, math.rad(rand(-18, 14)) * reach
			end
			local lim = idx == 1 and 1 or 0.7
			e.ty, e.tp = math.clamp(e.ty, -math.rad(36) * lim, math.rad(36) * lim), math.clamp(e.tp, -math.rad(24) * lim, math.rad(24) * lim)
		end
		if shift > 0 then   -- in a shift every eye stares at the same unseen point
			local d = frame:VectorToObjectSpace(stare - frame.Position)
			local ty, tp = math.atan2(d.X, -d.Z), math.atan2(d.Y, math.sqrt(d.X * d.X + d.Z * d.Z))
			e.ty, e.tp = e.ty + (math.clamp(ty, -0.6, 0.6) - e.ty) * shift, e.tp + (math.clamp(tp, -0.4, 0.4) - e.tp) * shift
		end
		local rate = 7 + 8 * wake
		e.yaw, e.pitch = approach(e.yaw, e.ty, rate, dt), approach(e.pitch, e.tp, rate, dt)
		local tremor = math.sin(st.t * 13 + idx) * math.rad(0.5)
		e.j.Transform = CFrame.Angles(0, -(e.yaw + tremor), 0) * CFrame.Angles(e.pitch, 0, 0)
		-- blinking
		if now >= e.nextBlink and shift == 0 then
			e.blinkAt = now
			e.nextBlink = now + rand(2.5, 6) * (1 + 0.6 * wake) * (math.random() < 0.15 and 0.15 or 1)   -- sometimes a double blink
		end
		local u = (now - e.blinkAt) / 0.22
		local shut = (u >= 0 and u <= 1) and math.sin(u * math.pi) or 0
		for _, l in ipairs(e.lids) do l.Transform = CFrame.Angles((l:GetAttribute("Swing") or 0) * shut, 0, 0) end
		-- the pupil narrows to a slit as it speeds up
		local slit = smooth((s - 0.55) / 0.4)
		for _, p in ipairs(e.wide) do set(st, p, "Transparency", slit, 0.02) end
		for _, p in ipairs(e.slit) do set(st, p, "Transparency", 1 - slit, 0.02) end
	end
	local pulse = 0.5 + 0.5 * math.sin(st.t * 1.3)
	local irisCol = IRIS_DIM:Lerp(IRIS_HOT, math.clamp(0.35 + 0.2 * pulse + 0.45 * wake + 0.3 * b, 0, 1))
	for _, ir in ipairs(st.irises) do set(st, ir, "Color", irisCol) end
	if st.light then set(st, st.light, "Brightness", 0.6 + 0.4 * pulse + 1.2 * wake + 1.2 * b, 0.05) end

	-- celestial rings: turning, faster with speed; in a shift they snap flat into line
	for _, r in ipairs(st.rings) do
		r.angle += dt * r.spin * (0.35 + 2.2 * s + 2.5 * b) * (1 - 0.8 * shift)
		local normal = r.tilt * CFrame.Angles(0, 0, r.angle)
		r.j.Transform = shift > 0 and normal:Lerp(CFrame.Angles(0, 0, r.angle * 0.15), shift) or normal
	end

	-- floating pieces: drifting, pushed outward with speed; in a shift six lock into a hexagon
	local eyeC = st.centre and st.centre.WorldCFrame
	local out = 0.05 + 0.12 * s + 0.2 * b
	for _, f in ipairs(st.floats) do
		local ph = f.ph
		local bob = Vector3.new(math.sin(st.t * 0.9 + ph) * 0.03, math.sin(st.t * 1.3 + ph * 1.7) * 0.05, math.cos(st.t * 0.7 + ph) * 0.03)
		local normal = CFrame.new(bob + f.out * out) * CFrame.Angles(math.sin(st.t * 0.5 + ph) * 0.2, st.t * (0.25 + 0.6 * s) + ph, math.cos(st.t * 0.4 + ph) * 0.15)
		if f.form and shift > 0 and eyeC then
			local a = (f.form - 1) * math.pi / 3 + st.t * 0.8
			local target = eyeC * CFrame.new(0, 0, -0.7) * CFrame.Angles(0, 0, a) * CFrame.new(0, 1.3, 0)
			local formed = frameOf(f.j):Inverse() * target * f.j.C1
			f.j.Transform = normal:Lerp(formed, shift)
		else
			f.j.Transform = normal
		end
	end

	-- the orbs: each on its own orbit and pace; sometimes one stops to look about
	for _, o in ipairs(st.orbs) do
		local frame = frameOf(o.j)
		if now >= o.nextPause and s < 0.45 and shift == 0 then
			o.pauseUntil = now + rand(0.8, 1.7)
			o.nextPause = now + rand(4, 9)
			o.pauseLook = (Vector3.new(rand(-1, 1), rand(-0.4, 0.6), rand(-1, 1))).Unit
		end
		local paused = now < o.pauseUntil
		if not paused then o.angle += dt * o.speed * (1 + 2.2 * s + 2 * b) * (1 - 0.7 * shift) end
		local a = o.angle + o.phase
		local wob = math.sin(st.t * 1.7 + o.phase) * 0.05
		local pos = Vector3.new(math.cos(a) * o.rx, math.sin(a) * o.ry, wob)
		-- where it looks (in the world): the road ahead blended with outward, a glance when paused,
		-- the shared point in a shift
		local worldPos = frame * pos
		local look = (fwd * (0.4 + 0.6 * wake) + (worldPos - frame.Position).Unit * 0.6)
		if paused then look = o.pauseLook end
		if shift > 0 then look = look:Lerp((stare - worldPos).Unit, shift) end
		o.look = o.look and o.look:Lerp(look, 1 - math.exp(-5 * dt)) or look
		o.j.Transform = CFrame.new(pos) * facing(frame:VectorToObjectSpace(o.look))
	end

	-- pendants swing back with speed
	for _, p in ipairs(st.pendants) do
		p.j.Transform = CFrame.Angles(-math.rad(25) * s + math.sin(st.t * (1.6 + 5 * s) + p.ph) * math.rad(3 + 6 * s), 0, math.sin(st.t * 1.1 + p.ph) * math.rad(3))
	end

	-- symbols: faint at rest, brighter with speed; at top speed light races along the body
	for _, g in ipairs(st.glyphs) do
		local wave = math.max(0, math.sin(st.t * 7 - g.z * 2.2)) ^ 3
		local k = math.clamp(0.08 + 0.1 * pulse + 0.55 * wake + 0.45 * b * wave, 0, 1)
		set(st, g.part, "Color", GLYPH_DIM:Lerp(GLYPH_HOT, k), 0.02)
	end

	-- the trail: fractures and gold lines with speed; floating eyes drifting out behind at top speed
	if st.fractures then set(st, st.fractures, "Rate", wake < 0.4 and 0 or (st.fractures:GetAttribute("Max") or 26) * (0.2 * wake * wake + 0.8 * b), 0.5) end
	local lines = s > 0.5
	for _, tr in ipairs(st.lines) do if tr.Enabled ~= lines then tr.Enabled = lines end end
	for _, te in ipairs(st.trail) do
		local u = ((st.t - te.k * 0.4) % 1.8) / 1.1
		local vis = (b > 0.5 and u <= 1) and math.sin(u * math.pi) * math.clamp((b - 0.5) * 2, 0, 1) or 0
		te.j.Transform = CFrame.new(math.sin(st.t * 2 + te.k) * 0.1, u * 0.4, -math.min(u, 1) * 2.4) * CFrame.Angles(0, math.sin(st.t + te.k) * 0.4, 0)
		for _, pp in ipairs(te.parts) do set(st, pp.part, "Transparency", 1 - (1 - pp.show) * vis, 0.02) end
	end
end

-- out of range: the loud parts switched off, the trail eyes hidden
local function rest(st)
	if st.resting then return end
	st.resting = true
	if st.fractures then set(st, st.fractures, "Rate", 0) end
	for _, tr in ipairs(st.lines) do tr.Enabled = false end
	for _, te in ipairs(st.trail) do for _, pp in ipairs(te.parts) do set(st, pp.part, "Transparency", 1) end end
end


---------------------------------------------------------------- the podium's Watcher
-- A stand-in for a joint on the podium copy: what update() reads of a Motor6D (Part0.CFrame,
-- C0, C1, attributes) and the Transform it writes, which place() then applies to its parts.
local Joint = {}
Joint.__index = Joint
function Joint:GetAttribute(k) return self.attrs[k] end

local shows = {}   -- [podium] = { display = the copy it was set up for, st = its state }

local function showState(display)
	local st = { model = display, podium = true, speed = 0, s = 0, b = 0, hold = 0, t = math.random() * 10, written = {},
		eyeMem = {}, ringMem = {}, orbMem = {}, lidList = {}, shiftAt = -math.huge, nextShift = 0, dirty = false }
	st.eyes, st.rings, st.floats, st.orbs, st.pendants, st.trail, st.glyphs, st.irises, st.lines = {}, {}, {}, {}, {}, {}, {}, {}, {}
	st.joints = {}
	local groups = {}
	for _, p in ipairs(display:GetDescendants()) do
		if p:IsA("BasePart") then
			local g = p:GetAttribute("WGroup")
			if g then
				groups[g] = groups[g] or { parts = {} }
				table.insert(groups[g].parts, p)
				if p:GetAttribute("WRoot") then groups[g].root = p end
			end
			if p.Name == "Glyph" then table.insert(st.glyphs, { part = p })
			elseif p.Name == "WatcherIris" or p.Name == "OrbIris" or p.Name == "WheelIris" then table.insert(st.irises, p) end
		end
	end
	for _, g in pairs(groups) do
		local r = g.root
		local rel = r and r:GetAttribute("WHinge")
		if r and typeof(rel) == "CFrame" then
			local attrs = {}
			for k, v in pairs(r:GetAttributes()) do local n = k:match("^WJ_(.+)"); if n then attrs[n] = v end end
			local j = setmetatable({ Name = r:GetAttribute("WKind"), Part0 = { CFrame = r.CFrame * rel }, C0 = CFrame.identity, C1 = rel,
				Part1 = r, Transform = CFrame.identity, attrs = attrs, offs = {} }, Joint)
			for _, p in ipairs(g.parts) do j.offs[p] = r.CFrame:ToObjectSpace(p.CFrame) end
			table.insert(st.joints, j)
			addJoint(st, j)
			if attrs.Eye == 1 then st.centre = { WorldPosition = j.Part0.CFrame.Position, WorldCFrame = j.Part0.CFrame } end
			if attrs.Eye then for _, p in ipairs(g.parts) do if p.Name == "PupilWide" then table.insert(st.eyes[attrs.Eye].wide, p) end end end
		end
	end
	for _, l in ipairs(st.lidList) do local e = st.eyes[l:GetAttribute("Lid")]; if e then table.insert(e.lids, l) end end
	st.lidList = {}
	table.sort(st.floats, function(a, b) return (a.form or 99) < (b.form or 99) end)
	st.pivot = display:GetPivot()
	for _, g in ipairs(st.glyphs) do g.z = st.pivot:PointToObjectSpace(g.part.Position).Z end
	return st
end

-- each group's parts follow its joint's Transform
local function place(st)
	for _, j in ipairs(st.joints) do
		local rootCF = j.Part0.CFrame * j.Transform * j.C1:Inverse()
		for p, off in pairs(j.offs) do p.CFrame = rootCF * off end
	end
end

-- the show's pace: idle, speeding up, top speed, slowing (as a share of top speed)
local function showSpeed(t)
	local u = t % SHOW_CYCLE
	if u < 6 then return 0 end
	if u < 7.5 then return smooth((u - 6) / 1.5) end
	if u < 13.5 then return 1 end
	return 1 - smooth((u - 13.5) / 1.5)
end

local nextScan = 0
local function scanPodiums(now)
	if now < nextScan then return end
	nextScan = now + 1
	for podium in pairs(shows) do
		if not podium.Parent or podium:GetAttribute("ScooterId") ~= "Watcher" then shows[podium] = nil end
	end
	for _, podium in ipairs(CollectionService:GetTagged("ScooterPodium")) do
		if podium:GetAttribute("ScooterId") == "Watcher" then
			local display = podium:FindFirstChild("Display")
			local sh = shows[podium]
			if display and (not sh or sh.display ~= display) then
				shows[podium] = { display = display, st = showState(display) }
			elseif not display then
				shows[podium] = nil
			end
		end
	end
end

local function showUpdate(dt, now, camPos)
	scanPodiums(now)
	for _, sh in pairs(shows) do
		local st = sh.st
		if sh.display.Parent and camPos and (st.pivot.Position - camPos).Magnitude < SHOW_RANGE then
			local fake = { CFrame = st.pivot, Position = st.pivot.Position, AssemblyLinearVelocity = st.pivot.LookVector * TOP_SPEED * showSpeed(st.t) }
			update(st, fake, dt, now)
			place(st)
		end
	end
end

RunService.RenderStepped:Connect(function(dt)
	dt = math.clamp(dt, 1 / 240, 1 / 20)
	local now = os.clock()
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position
	showUpdate(dt, now, camPos)
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
