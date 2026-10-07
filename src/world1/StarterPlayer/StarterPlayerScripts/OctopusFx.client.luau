-- The StiltHut octopus comes alive on each player's screen (only while the camera is near):
--   body       bobs and sways gently in the water, breathing
--   tentacles  the parts reaching across the water undulate; squeezing ripples run up the
--              coils round each stilt; the curled tips curl and uncurl
--   eyes       the pupils look towards you, and it blinks now and then
-- Only this screen moves it; the model itself never changes.

local RunService = game:GetService("RunService")

local NEAR = 260          -- camera distance at which it animates
local RATE = 1 / 30       -- updates a second (it's a lot of parts)

local hut = workspace:WaitForChild("StiltHut")

local rig
local function build()
	local oct = hut:FindFirstChild("Octopus")
	local body = oct and oct:FindFirstChild("Body")
	local tents = oct and oct:FindFirstChild("Tentacles")
	local eyes = oct and oct:FindFirstChild("Eyes")
	if not (body and tents and eyes) then return nil end
	-- the map streams in: wait until every part of it is here
	local have = 0
	for _, p in ipairs(oct:GetDescendants()) do if p:IsA("BasePart") then have += 1 end end
	if have < (oct:GetAttribute("PartCount") or 0) then return nil end
	local r = { oct = oct, centre = oct:GetAttribute("Centre"), body = {}, eyes = {}, tents = {} }
	for _, p in ipairs(body:GetChildren()) do
		if p:IsA("BasePart") and p.Name ~= "Foam" then table.insert(r.body, { p = p, rest = p.CFrame }) end
	end
	for _, e in ipairs(eyes:GetChildren()) do
		local eye = { parts = {} }
		for _, p in ipairs(e:GetChildren()) do
			if p:IsA("BasePart") then eye.parts[p.Name] = { p = p, rest = p.CFrame } end
		end
		if eye.parts.White and eye.parts.Pupil then table.insert(r.eyes, eye) end
	end
	for _, t in ipairs(tents:GetChildren()) do
		local tent = { stilt = t:GetAttribute("Stilt"), tipBase = t:GetAttribute("TipBase"), reach = t:GetAttribute("ReachLen") or 10,
			phase = t:GetAttribute("Phase") or 0, parts = {} }
		local maxS = 0
		for _, p in ipairs(t:GetChildren()) do
			if p:IsA("BasePart") then
				local s = p:GetAttribute("S") or 0
				maxS = math.max(maxS, s)
				table.insert(tent.parts, { p = p, rest = p.CFrame, s = s, stage = p:GetAttribute("Stage") })
			end
		end
		-- where the tip starts, to curl the tip about
		local tipStart = math.huge
		for _, e in ipairs(tent.parts) do if e.stage == "tip" then tipStart = math.min(tipStart, e.s) end end
		tent.tipStart, tent.maxS = tipStart, maxS
		table.insert(r.tents, tent)
	end
	return r
end

local list, cfs = {}, {}
local t, acc = 0, 0
local blinkAt, blinkT = 3, -1
local settled = true

RunService.Heartbeat:Connect(function(dt)
	t += dt
	acc += dt
	if acc < RATE then return end
	acc = 0
	if rig and not rig.oct.Parent then rig = nil end
	if not rig then rig = build() if not rig then return end end
	local cam = workspace.CurrentCamera.CFrame.Position
	if (cam - rig.centre).Magnitude > NEAR then
		if not settled then
			-- put it back as built when nobody near is watching
			table.clear(list) table.clear(cfs)
			for _, e in ipairs(rig.body) do list[#list + 1] = e.p cfs[#cfs + 1] = e.rest end
			for _, eye in ipairs(rig.eyes) do for _, e in pairs(eye.parts) do list[#list + 1] = e.p cfs[#cfs + 1] = e.rest end end
			for _, tent in ipairs(rig.tents) do for _, e in ipairs(tent.parts) do list[#list + 1] = e.p cfs[#cfs + 1] = e.rest end end
			workspace:BulkMoveTo(list, cfs, Enum.BulkMoveMode.FireCFrameChanged)
			settled = true
		end
		return
	end
	settled = false
	table.clear(list) table.clear(cfs)

	-- BODY: bob + gentle sway about the centre
	local C = rig.centre
	local bob = math.sin(t * 0.9) * 0.35
	local sway = CFrame.new(C) * CFrame.Angles(math.sin(t * 0.7) * 0.05, math.sin(t * 0.4) * 0.06, math.sin(t * 0.8 + 1) * 0.04) * CFrame.new(-C)
	local bodyCF = CFrame.new(0, bob, 0) * sway
	for _, e in ipairs(rig.body) do list[#list + 1] = e.p cfs[#cfs + 1] = bodyCF * e.rest end

	-- EYES: pupils look at the camera, blink every few seconds
	blinkAt -= RATE
	if blinkAt <= 0 then blinkT, blinkAt = 0, 2.5 + math.random() * 3.5 end
	local lid = 0
	if blinkT >= 0 then
		blinkT += RATE
		lid = math.sin(math.min(1, blinkT / 0.28) * math.pi)
		if blinkT > 0.28 then blinkT = -1 end
	end
	for _, eye in ipairs(rig.eyes) do
		local white = eye.parts.White.rest.Position
		local pupilRest = eye.parts.Pupil.rest
		local fwd = (pupilRest.Position - white).Unit
		local toCam = (cam - white).Unit
		local shift = (toCam - fwd * toCam:Dot(fwd))
		if shift.Magnitude > 0.35 then shift = shift.Unit * 0.35 end
		for name, e in pairs(eye.parts) do
			local cf = e.rest
			if name == "Pupil" or name == "Shine" then cf = cf + shift
			elseif name == "Brow" then cf = cf - Vector3.new(0, lid * 1.15, 0) end
			list[#list + 1] = e.p
			cfs[#cfs + 1] = bodyCF * cf
		end
	end

	-- TENTACLES
	for _, tent in ipairs(rig.tents) do
		local ph = tent.phase
		local tipAxis
		if tent.tipBase then
			local radial = ((tent.tipBase - tent.stilt) * Vector3.new(1, 0, 1)).Unit
			tipAxis = radial:Cross(Vector3.yAxis)
		end
		local curl = math.sin(t * 1.3 + ph) * 0.7
		for _, e in ipairs(tent.parts) do
			local cf = e.rest
			local pos = cf.Position
			if e.stage == "reach" then
				-- undulate up and down; the root follows the body
				local u = math.clamp(e.s / tent.reach, 0, 1)
				local wave = math.sin(t * 1.8 - e.s * 0.55 + ph) * 0.45 * math.sin(u * math.pi)
				local follow = (bodyCF * pos - pos) * (1 - u)
				cf = cf + follow + Vector3.new(0, wave, 0)
			elseif e.stage == "spiral" then
				-- squeezing ripples running up the coil
				local radial = ((pos - tent.stilt) * Vector3.new(1, 0, 1))
				if radial.Magnitude > 0.01 then
					local squeeze = math.sin(t * 2.4 - e.s * 0.45 + ph)
					cf = cf + radial.Unit * squeeze * 0.22 + Vector3.new(0, squeeze * 0.08, 0)
				end
			elseif e.stage == "tip" and tipAxis then
				-- the tip curls and uncurls about where it leaves the stilt
				local k = math.clamp((e.s - tent.tipStart) / math.max(tent.maxS - tent.tipStart, 0.1), 0, 1)
				local rot = CFrame.fromAxisAngle(tipAxis, curl * (0.4 + k))
				local rel = pos - tent.tipBase
				cf = CFrame.new(tent.tipBase + rot:VectorToWorldSpace(rel)) * rot * cf.Rotation
			end
			list[#list + 1] = e.p
			cfs[#cfs + 1] = cf
		end
	end
	workspace:BulkMoveTo(list, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end)
