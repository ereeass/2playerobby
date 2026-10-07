-- The Ice Atlas Statue's head comes alive, on THIS machine only (each player sees their own):
--   riding on Road 3      he turns towards your scooter and tilts his head curiously side to side
--   riding the ice stairs  close to his face (the Atlas Spiral Road), he stares right at your
--                          scooter and follows it
--   not paired up yet      (in the lobby / queue) random head moves to build excitement: tilt
--                          left, tilt right, a double tilt, a nod, a slow shake, a look up at
--                          the globe, or a long stare at you
-- The head (skull, jaw, nose, eyes, brow, ears, hair and beard, the icicles on his face) turns
-- about the top of the neck, the neck bending part way. Only this screen moves it; the real
-- (server) statue never moves, so its kill zone is unchanged.

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local STARE_NEAR = 60      -- studs from his head: "on the ice stairs next to his face"
local ROAD3_PAD  = 25      -- studs round Road 3's box that count as on Road 3
local SPEED      = math.rad(45)   -- how fast he turns, per second

local player = Players.LocalPlayer
local statue = workspace:WaitForChild("Ice Atlas Statue")
local road3 = workspace:WaitForChild("Roads"):WaitForChild("Road3")

local function myChassis()
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local weld = root and root:FindFirstChild("ScooterRiderWeld")
	return weld and weld.Part0
end

local rig
local function build()
	local atlas = statue:FindFirstChild("Atlas")
	if not atlas then return nil end
	local heads, neck = {}, {}
	for _, p in ipairs(atlas:GetChildren()) do
		if p:IsA("BasePart") then
			if p.Name == "Head" or p.Name == "Jaw" or p.Name == "Nose" or p.Name == "EyeSocket" or p.Name == "EyeGlow" or p.Name == "EyeCore" or p.Name == "Brow" or p.Name == "Ear" then table.insert(heads, p)
			elseif p.Name == "Neck" then table.insert(neck, p) end
		end
	end
	local nose = atlas:FindFirstChild("Nose")
	local skull
	for _, p in ipairs(heads) do if p.Name == "Head" then skull = p break end end
	if not skull or not nose or #neck == 0 then return nil end
	local hc, nc = skull.Position, neck[1].Position
	local r = { parts = {} }
	r.pivot = nc:Lerp(hc, 0.55)                            -- top of the neck
	local face = (nose.Position - hc).Unit
	r.faceFlat = (face * Vector3.new(1, 0, 1)).Unit
	r.restPitch = math.asin(face.Y)
	for _, p in ipairs(heads) do table.insert(r.parts, { p = p, rest = p.CFrame, w = 1 }) end
	local hair = statue:FindFirstChild("HairAndBeard")
	if hair then for _, p in ipairs(hair:GetDescendants()) do if p:IsA("BasePart") then table.insert(r.parts, { p = p, rest = p.CFrame, w = 1 }) end end end
	for _, p in ipairs(neck) do table.insert(r.parts, { p = p, rest = p.CFrame, w = 0.4 }) end
	-- the icicles hanging off his face/beard (and their tips)
	local ice = statue:FindFirstChild("IceFeatures")
	if ice then
		local icicles = {}
		for _, p in ipairs(ice:GetDescendants()) do
			if p:IsA("BasePart") and p.Name == "Icicle" and (p.Position - hc).Magnitude < 18 and r.faceFlat:Dot(p.Position - r.pivot) > 2 then
				table.insert(icicles, p) table.insert(r.parts, { p = p, rest = p.CFrame, w = 1 })
			end
		end
		for _, p in ipairs(ice:GetDescendants()) do
			if p:IsA("BasePart") and p.Name == "IcicleTip" then
				for _, ic in ipairs(icicles) do
					if ((p.Position - ic.Position) * Vector3.new(1, 0, 1)).Magnitude < 0.6 then table.insert(r.parts, { p = p, rest = p.CFrame, w = 1 }) break end
				end
			end
		end
	end
	local cf, s = road3:GetBoundingBox()
	r.road = { cf = cf, h = s / 2 }
	return r
end

-- yaw/pitch that would point his face at a spot (relative to how he rests)
local function aimAt(p)
	local l = p - rig.pivot
	local flat = l * Vector3.new(1, 0, 1)
	if flat.Magnitude < 0.1 then return 0, 0 end
	flat = flat.Unit
	local yaw = math.atan2(rig.faceFlat:Cross(flat).Y, rig.faceFlat:Dot(flat))
	local pitch = math.asin(math.clamp(l.Unit.Y, -1, 1)) - rig.restPitch
	return yaw, pitch
end

local function onRoad3(p)
	local l = rig.road.cf:PointToObjectSpace(p)
	local h = rig.road.h
	return math.abs(l.X) < h.X + ROAD3_PAD and math.abs(l.Z) < h.Z + ROAD3_PAD and math.abs(l.Y) < h.Y + 40
end

-- the "not paired up yet" show: a random move every few seconds
local MOVES = { "tiltL", "tiltR", "double", "nod", "shake", "up", "stare", "stare" }
local move, moveT, moveLen = "rest", 0, 2

local cur = { yaw = 0, pitch = 0, roll = 0 }
local tiltSide, tiltT = 1, 0
local list, cfs = {}, {}
local t = 0

RunService.Heartbeat:Connect(function(dt)
	t += dt
	if not rig then
		rig = build()
		if not rig then return end
	end
	-- World 1's intro cinematic (ReplicatedStorage.IntroCinematic) is moving his head itself:
	-- put it back at rest and wait (it sets IntroHold on the statue, on this machine only)
	if statue:GetAttribute("IntroHold") then
		if cur.yaw ~= 0 or cur.pitch ~= 0 or cur.roll ~= 0 then
			cur.yaw, cur.pitch, cur.roll = 0, 0, 0
			table.clear(list) table.clear(cfs)
			for _, e in ipairs(rig.parts) do
				if e.p.Parent then list[#list + 1] = e.p; cfs[#cfs + 1] = e.rest end
			end
			workspace:BulkMoveTo(list, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end
		return
	end
	local chassis = myChassis()
	local want = { yaw = 0, pitch = 0, roll = 0 }
	local speed = SPEED
	if chassis then
		local d = (chassis.Position - rig.pivot).Magnitude
		if d < STARE_NEAR then
			-- right next to his face: a hard stare that follows them
			local y, p = aimAt(chassis.Position)
			want.yaw, want.pitch = math.clamp(y, -math.rad(70), math.rad(70)), math.clamp(p, -math.rad(40), math.rad(45))
			speed = SPEED * 1.4
		elseif onRoad3(chassis.Position) then
			-- watching them on Road 3, tilting his head this way and that
			local y, p = aimAt(chassis.Position)
			want.yaw, want.pitch = math.clamp(y, -math.rad(40), math.rad(40)), math.clamp(p, -math.rad(25), math.rad(25))
			tiltT -= dt
			if tiltT <= 0 then tiltT = 2.5 + math.random() * 2 tiltSide = (math.random() < 0.8) and -tiltSide or 0 end
			want.roll = tiltSide * math.rad(20)
		end
	else
		-- not riding (lobby / queue): the excitement show
		moveT += dt
		if moveT >= moveLen then
			moveT = 0
			if move ~= "rest" and math.random() < 0.4 then move, moveLen = "rest", 1 + math.random() * 1.5
			else move = MOVES[math.random(#MOVES)] moveLen = (move == "stare") and (3 + math.random() * 2) or (2.2 + math.random()) end
		end
		local k = moveT / moveLen
		if move == "tiltL" then want.roll = math.rad(24)
		elseif move == "tiltR" then want.roll = -math.rad(24)
		elseif move == "double" then want.roll = (k < 0.5 and 1 or -1) * math.rad(22)
		elseif move == "nod" then want.pitch = -math.abs(math.sin(k * math.pi * 3)) * math.rad(16) speed = SPEED * 2
		elseif move == "shake" then want.yaw = math.sin(k * math.pi * 4) * math.rad(18) speed = SPEED * 1.6
		elseif move == "up" then want.pitch = math.rad(35)
		elseif move == "stare" then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root then
				local y, p = aimAt(root.Position)
				want.yaw, want.pitch = math.clamp(y, -math.rad(60), math.rad(60)), math.clamp(p, -math.rad(35), math.rad(35))
				want.roll = math.rad(8)
			end
		end
	end
	local step = speed * dt
	local moved = false
	for _, key in ipairs({ "yaw", "pitch", "roll" }) do
		local diff = want[key] - cur[key]
		if math.abs(diff) > 1e-4 then moved = true end
		-- ease in: slow down near the target
		cur[key] += math.clamp(diff * math.min(1, dt * 4), -step, step)
	end
	if not moved and math.abs(cur.yaw) + math.abs(cur.pitch) + math.abs(cur.roll) < 1e-4 then return end
	local P = rig.pivot
	local right = rig.faceFlat:Cross(Vector3.yAxis)
	local function turned(w)
		local yawed = CFrame.fromAxisAngle(Vector3.yAxis, cur.yaw * w)
		local ax = yawed:VectorToWorldSpace(right)
		local fwd = yawed:VectorToWorldSpace(rig.faceFlat)
		return CFrame.new(P) * CFrame.fromAxisAngle(fwd, cur.roll * w) * CFrame.fromAxisAngle(ax, cur.pitch * w) * yawed * CFrame.new(-P)
	end
	local full, half = turned(1), turned(0.4)
	table.clear(list) table.clear(cfs)
	for _, e in ipairs(rig.parts) do
		if e.p.Parent then
			list[#list + 1] = e.p
			cfs[#cfs + 1] = (e.w >= 1 and full or half) * e.rest
		end
	end
	workspace:BulkMoveTo(list, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end)
