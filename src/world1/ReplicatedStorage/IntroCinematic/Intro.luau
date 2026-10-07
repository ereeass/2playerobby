--=====================================================================
-- IntroCinematic / Intro   *** WORLD 1 ONLY *** (on each player's own machine)
--
-- The intro: YOU (your own avatar) in the Driver booth and a bacon-hair in the
-- Motor booth -> the two of you on the scooter leaving Checkpoint 1's lot -> one flight over
-- the course -> the Ice Atlas screams and whips his head toward the lobby -> the camera
-- flies back and lands on your own character, exactly where your normal camera takes over.
--
-- Everything here is this player's own: local copies of the riders and the scooter, sounds
-- only they hear, their camera only. Nothing is sent to the server except "seen it".
--
--   Intro.IsThisWorld()             true only in World 1 (Config.PlaceId)
--   Intro.ShouldAutoPlay()          first join: has this player never seen it? (asks the server)
--   Intro.Prepare()                 loads what it needs (models, sounds, the far map) - safe to repeat
--   Intro.Play({ First, HandOff })  plays it (yields until done or skipped). First = the automatic
--                                   first-join play (marks it seen); HandOff(eye, focus) = the
--                                   loading screen's own camera hand-off
--   Intro.CanReplay()               ok, reason   (Settings > Replay Intro: lobby only)
--   Intro.Replay()                  plays it again; the saved "seen" never changes
--
-- It reuses the other cutscenes' own pieces: FinishCutscene.Fade (the black bars, same size
-- and scaling as every cutscene), FinishCutscene.Lock (controls, HUD) and RiderPose (the
-- riders' ride pose, the same IK the real ride uses).
--=====================================================================

local Players              = game:GetService("Players")
local RunService           = game:GetService("RunService")
local ContentProvider      = game:GetService("ContentProvider")
local ContextActionService = game:GetService("ContextActionService")
local TweenService         = game:GetService("TweenService")
local UserInputService     = game:GetService("UserInputService")
local SoundService         = game:GetService("SoundService")
local Lighting             = game:GetService("Lighting")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")

local folder    = script.Parent
local Config    = require(folder:WaitForChild("Config"))
local RiderPose = require(folder:WaitForChild("RiderPose"))
local remotes   = folder:WaitForChild("Remotes")

local player = Players.LocalPlayer
local Intro  = {}

local CAMERA_STEP = Enum.RenderPriority.Camera.Value + 1
local STEP, BLEND = "IntroCinematic", "IntroCinematicBlend"
local SKIP_ACTION = "IntroCinematicSkip"
local END_ZOOM, END_PITCH = 12.5, math.rad(15)   -- Roblox's default camera (as the loading fly-down)
local KNEE_ANGLE = 160                            -- RiderAttach's knee bend

local playing = false

---------------------------------------------------------------- small helpers
local function smooth(a, b, x)
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

local function lerp(a, b, k) return a + (b - a) * k end

-- Catmull-Rom through keys at uneven times (Barry-Goldman): smooth in position AND speed
local function cr(p0, p1, p2, p3, t0, t1, t2, t3, t)
	local a1 = p0 * ((t1 - t) / (t1 - t0)) + p1 * ((t - t0) / (t1 - t0))
	local a2 = p1 * ((t2 - t) / (t2 - t1)) + p2 * ((t - t1) / (t2 - t1))
	local a3 = p2 * ((t3 - t) / (t3 - t2)) + p3 * ((t - t2) / (t3 - t2))
	local b1 = a1 * ((t2 - t) / (t2 - t0)) + a2 * ((t - t0) / (t2 - t0))
	local b2 = a2 * ((t3 - t) / (t3 - t1)) + a3 * ((t - t1) / (t3 - t1))
	return b1 * ((t2 - t) / (t2 - t1)) + b2 * ((t - t1) / (t2 - t1))
end

local function liveRoot()
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local root = hum and hum.RootPart
	if root and hum.Health > 0 then return root, hum end
	return nil
end

-- the point Roblox's camera looks at on a character (as LoadingClient)
local function subjectPosition(hum, root)
	local offset
	if hum.RigType == Enum.HumanoidRigType.R15 then
		offset = hum.AutomaticScalingEnabled and Vector3.new(0, 1.5 + (root.Size.Y - 2) / 2, 0) or Vector3.new(0, 2, 0)
	else
		offset = Vector3.new(0, 1.5, 0)
	end
	return root.CFrame:PointToWorldSpace(offset + hum.CameraOffset)
end

-- where the player's own camera will be the moment it takes over: behind them, Roblox's
-- default distance and tilt (the loading fly-down lands on the same spot)
local function gameplayView()
	local root, hum = liveRoot()
	if not root then return nil end
	local focus = subjectPosition(hum, root)
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = flat.Magnitude > 1e-3 and flat.Unit or Vector3.zAxis
	local zoom = math.clamp(END_ZOOM, player.CameraMinZoomDistance, player.CameraMaxZoomDistance)
	local back = -flat * math.cos(END_PITCH) + Vector3.new(0, math.sin(END_PITCH), 0)
	return focus + back * zoom, focus, hum
end

local function riding()
	local root = liveRoot()
	return root ~= nil and root:FindFirstChild("ScooterRiderWeld") ~= nil
end

---------------------------------------------------------------- the server
function Intro.IsThisWorld()
	return game.PlaceId == Config.PlaceId
end

-- first join: true only when the server says this player has never seen it
function Intro.ShouldAutoPlay()
	if not Intro.IsThisWorld() then return false end
	local fn = remotes:FindFirstChild("IntroState")
	if not fn then return false end
	local ok, seen = pcall(fn.InvokeServer, fn)
	return ok and seen == false
end

---------------------------------------------------------------- building the cast
local function stripForShow(model)
	local drop = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("Tool") or d:IsA("ForceField") then
			table.insert(drop, d)
		elseif d:IsA("BasePart") then
			d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
			d.Anchored = false
			d.Massless = true
		end
	end
	for _, d in ipairs(drop) do d:Destroy() end
end

-- a local copy of a character to act with
local function actor(source, name)
	if not source then return nil end
	local was = source.Archivable
	source.Archivable = true
	local ok, c = pcall(source.Clone, source)
	source.Archivable = was
	if not ok or not c then return nil end
	c.Name = name
	-- the cheer of this avatar's own animation pack, read before the Animate script goes
	local cheerId
	local animate = c:FindFirstChild("Animate")
	local cheer = animate and animate:FindFirstChild("cheer")
	local anim = cheer and cheer:FindFirstChildWhichIsA("Animation")
	if anim and anim.AnimationId ~= "" then cheerId = anim.AnimationId end
	local walkId
	local walk = animate and animate:FindFirstChild("walk")
	local wanim = walk and walk:FindFirstChildWhichIsA("Animation")
	if wanim and wanim.AnimationId ~= "" then walkId = wanim.AnimationId end
	local idleId
	local idle = animate and animate:FindFirstChild("idle")
	local ianim = idle and (idle:FindFirstChild("Animation1") or idle:FindFirstChildWhichIsA("Animation"))
	if ianim and ianim.AnimationId ~= "" then idleId = ianim.AnimationId end
	stripForShow(c)
	local hum = c:FindFirstChildOfClass("Humanoid")
	local root = c:FindFirstChild("HumanoidRootPart")
	if not (hum and root) then c:Destroy() return nil end
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false
	for _, s in ipairs({ Enum.HumanoidStateType.Dead, Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll }) do
		hum:SetStateEnabled(s, false)
	end
	root.Anchored = true
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = hum
	return { Model = c, Humanoid = hum, Root = root, Animator = animator, CheerId = cheerId, WalkId = walkId, IdleId = idleId }
end

-- a huge excited grin: the face picture on a classic head, the same expression pulled on a
-- moving (dynamic) head
local FACE_POSE = {
	JawDrop = 0.75, LeftLipCornerPuller = 1, RightLipCornerPuller = 1, LeftCheekRaiser = 0.8, RightCheekRaiser = 0.8,
	LeftUpperLidRaiser = 1, RightUpperLidRaiser = 1, LeftInnerBrowRaiser = 1, RightInnerBrowRaiser = 1,
	LeftOuterBrowRaiser = 1, RightOuterBrowRaiser = 1, LipsTogether = 0, LeftLipStretcher = 0.5, RightLipStretcher = 0.5,
}
local function excite(a)
	local head = a.Model:FindFirstChild("Head")
	if not head then return end
	local fc = head:FindFirstChildOfClass("FaceControls")
	if fc then
		for prop, v in pairs(FACE_POSE) do pcall(function() fc[prop] = v end) end
	end
	local face = head:FindFirstChild("face")
	if face and face:IsA("Decal") then face.Texture = Config.Face end
end

local function rootHeight(a)
	local hum, root = a.Humanoid, a.Root
	if hum.RigType == Enum.HumanoidRigType.R15 then return hum.HipHeight + root.Size.Y / 2 end
	return 3
end

---------------------------------------------------------------- prepare
local prepared, preparing

local function rayParams(ignore)
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	local list = { ignore }
	for _, plr in ipairs(Players:GetPlayers()) do if plr.Character then table.insert(list, plr.Character) end end
	local ride = workspace:FindFirstChild("RideSystem")
	if ride then
		for _, n in ipairs({ "Scooters", "CapsuleStations" }) do
			if ride:FindFirstChild(n) then table.insert(list, ride[n]) end
		end
	end
	p.FilterDescendantsInstances = list
	return p
end

-- the first solid, visible surface below a point (sensors and invisible zones are passed through)
local function groundBelow(origin, params, depth)
	for _ = 1, 8 do
		local hit = workspace:Raycast(origin, Vector3.new(0, -(depth or 60), 0), params)
		if not hit then return nil end
		local p = hit.Instance
		if p.CanCollide and p.Transparency < 0.9 then return hit.Position.Y end
		origin = hit.Position - Vector3.new(0, 0.05, 0)
	end
	return nil
end

local function makeSound(name, def, parent)
	if not def or def.Id == "" or (def.Volume or 1) <= 0 then return nil end
	local s = Instance.new("Sound")
	s.Name = "Intro" .. name
	s.SoundId = def.Id
	s.Volume = def.Volume or 0.5
	s.PlaybackSpeed = def.Speed or 1
	-- SettingsController puts it in the SFX group (the soundtrack scales with the music volume by hand)
	s:SetAttribute("AudioCategory", "SFX")
	s.Parent = parent
	return s
end

-- Loads everything the intro shows and plays. Returns the scene, or nil if it can't be built.
function Intro.Prepare()
	if prepared then return prepared end
	if preparing then
		local t0 = os.clock()
		while preparing and os.clock() - t0 < 15 do task.wait() end
		return prepared
	end
	preparing = true
	local ok, scene = pcall(function()
		local root = liveRoot()
		if not root then return nil end
		-- the avatar's clothes and accessories first (a first join may still be putting them on)
		local t0 = os.clock()
		while not player:HasAppearanceLoaded() and os.clock() - t0 < 3 do task.wait() end

		local S = { Sounds = {}, Hidden = {} }
		S.Folder = Instance.new("Model")
		S.Folder.Name = "IntroCinematic"

		-- the cast: two of each (booth + scooter), so the scooter pair is posed before it is seen
		local bacon = folder:WaitForChild("Bacon", 5)
		S.DriverBooth = actor(player.Character, "DriverBooth")
		S.Driver      = actor(player.Character, "Driver")
		S.MotorBooth  = actor(bacon, "MotorBooth")
		S.Motor       = actor(bacon, "Motor")
		if not (S.DriverBooth and S.Driver) then error("couldn't copy the player's avatar") end
		for _, a in ipairs({ S.DriverBooth, S.Driver, S.MotorBooth, S.Motor }) do
			if a then a.Model.Parent = S.Folder end
		end
		for _, a in ipairs({ S.DriverBooth, S.Driver }) do   -- (the bacon keeps its classic smile)
			if a then excite(a) end
		end

		-- the scooter (a still copy of the default scooter: no hinges, wheels turned by hand)
		S.Scooter = folder:WaitForChild("Scooter"):Clone()
		S.Scooter.Parent = S.Folder
		S.Chassis = S.Scooter:WaitForChild("Chassis")
		local box, size = S.Scooter:GetBoundingBox()
		S.RideUp = S.Chassis.Position.Y - (box.Position.Y - size.Y / 2)   -- chassis height over the ground
		S.Wheels = {}
		for _, w in ipairs(S.Scooter:WaitForChild("Wheels"):GetChildren()) do
			if w:IsA("BasePart") then
				local att = w:FindFirstChildWhichIsA("Attachment")
				local axis = att and S.Chassis.CFrame:VectorToObjectSpace(w.CFrame:VectorToWorldSpace(att.Axis)) or Vector3.xAxis
				if axis.X < 0 then axis = -axis end
				table.insert(S.Wheels, {
					Part = w, Rel = S.Chassis.CFrame:ToObjectSpace(w.CFrame), Axis = axis,
					Radius = math.max(w.Size.Y, w.Size.Z) / 2,
				})
			end
		end
		S.Engine = S.Chassis:FindFirstChild("MotorHum")

		-- sounds (on this machine only)
		S.SoundFolder = Instance.new("Folder")
		S.SoundFolder.Name = "IntroCinematicSounds"
		for name, def in pairs(Config.Sounds) do
			local s = makeSound(name, def, def.OnScooter and S.Chassis or S.SoundFolder)
			if s then
				if def.OnScooter then
					s.RollOffMode = Enum.RollOffMode.InverseTapered
					s.RollOffMinDistance = 12
					s.RollOffMaxDistance = 220
				end
				S.Sounds[name] = { Sound = s, Def = def }
			end
		end
		S.Wind = makeSound("Wind", Config.Wind, S.SoundFolder)
		if S.Wind then S.Wind.Looped = true end

		-- the scooter's run: out of the lot to the start gate, then along the road's own line
		-- (Road1's centre line), smoothed so it steers round the bends; the lot's height from
		-- the ground itself (from just above it: never the start gate's arch overhead)
		local params = rayParams(S.Folder)
		local startY = root.Position.Y
		local lotY = groundBelow(Vector3.new(Config.RideStart.X, startY + 5, Config.RideStart.Z), params) or (startY - 3)
		local nodes = { Vector3.new(Config.RideStart.X, lotY, Config.RideStart.Z) }   -- (the road points are its deck tops already)
		for _, v in ipairs(Config.RideVia or {}) do table.insert(nodes, Vector3.new(v.X, lotY, v.Z)) end
		for _, p in ipairs(require(folder:WaitForChild("RidePath"))) do table.insert(nodes, p) end
		local function chaikin(list, passes)   -- rounds every corner off
			for _ = 1, passes do
				local out = { list[1] }
				for i = 1, #list - 1 do
					local a, b = list[i], list[i + 1]
					table.insert(out, a:Lerp(b, 0.25))
					table.insert(out, a:Lerp(b, 0.75))
				end
				table.insert(out, list[#list])
				list = out
			end
			return list
		end
		nodes = chaikin(nodes, 3)
		-- steer round the traffic cones on the road (never through one), then smooth again
		local cones = {}
		for _, c in ipairs(workspace:GetChildren()) do
			if c.Name == "Cone" then
				local ok, cf = pcall(function() return c:IsA("Model") and c:GetPivot() or c.CFrame end)
				if ok and cf then table.insert(cones, cf.Position) end
			end
		end
		local CLEAR = 3.5
		for i = 2, #nodes do
			local p = nodes[i]
			for _, c in ipairs(cones) do
				local flat = Vector3.new(p.X - c.X, 0, p.Z - c.Z)
				if flat.Magnitude < CLEAR and math.abs(p.Y - c.Y) < 6 then
					local away = flat.Magnitude > 0.05 and flat.Unit or Vector3.xAxis
					p = Vector3.new(c.X, p.Y, c.Z) + away * CLEAR
				end
			end
			nodes[i] = p
		end
		nodes = chaikin(nodes, 2)
		S.Path, S.PathLen = {}, {}
		local total = 0
		for i, p in ipairs(nodes) do
			S.Path[i] = p
			if i > 1 then total += (S.Path[i] - S.Path[i - 1]).Magnitude end
			S.PathLen[i] = total
		end

		-- the far side of the course, asked for now so nothing pops in mid-flight
		local streams = 0
		for _, p in ipairs(Config.StreamPoints) do
			streams += 1
			task.spawn(function()
				pcall(player.RequestStreamAroundAsync, player, p, Config.StreamWait)
				streams -= 1
			end)
		end

		-- the models' meshes and textures, the sounds, the face and the cheers
		local list = { S.Folder, S.SoundFolder }
		local face = Instance.new("Decal"); face.Texture = Config.Face; table.insert(list, face)
		for _, a in ipairs({ S.DriverBooth, S.MotorBooth }) do
			if a and a.CheerId then
				local anim = Instance.new("Animation"); anim.AnimationId = a.CheerId
				a.CheerAnim = anim
				table.insert(list, anim)
			end
			if a and a.WalkId then
				local anim = Instance.new("Animation"); anim.AnimationId = a.WalkId
				a.WalkAnim = anim
				table.insert(list, anim)
			end
			if a and a.IdleId then
				local anim = Instance.new("Animation"); anim.AnimationId = a.IdleId
				a.IdleAnim = anim
				table.insert(list, anim)
			end
		end
		local loaded = false
		task.spawn(function()
			pcall(ContentProvider.PreloadAsync, ContentProvider, list)
			loaded = true
		end)
		local t1 = os.clock()
		while (not loaded or streams > 0) and os.clock() - t1 < 4 do task.wait() end
		return S
	end)
	preparing = false
	if not ok then warn("[Intro] couldn't prepare:", scene) return nil end
	prepared = scene
	return scene
end

---------------------------------------------------------------- scene 1: the booths
local function placeInBooths(S)
	local stations = workspace:FindFirstChild("RideSystem") and workspace.RideSystem:FindFirstChild("CapsuleStations")
	local st = stations and stations:FindFirstChild(Config.Station)
	if not st then return end
	local params = rayParams(S.Folder)
	local facing = Config.BoothFacing
	local function stand(a, boothName)
		local booth = a and st:FindFirstChild(boothName)
		if not booth then return end
		local floorY = groundBelow(booth.Position, params, 12) or (booth.Position.Y - booth.Size.Y / 2)
		local okBody, body = pcall(RiderPose.MeasureBody, a.Model)
		local up = (okBody and body.SoleDepth and body.SoleDepth > 0) and body.SoleDepth or rootHeight(a)
		local base = Vector3.new(booth.Position.X, floorY + up, booth.Position.Z)
		a.Home = CFrame.lookAt(base, base + facing)
		a.Root.CFrame = a.Home
	end
	stand(S.DriverBooth, Config.DriverBooth)
	stand(S.MotorBooth, Config.MotorBooth)
	S.BoothMid = st:GetPivot().Position
end

-- walks in from outside the booth (facing in), turns round to face out and stands there,
-- feet on the floor; returns "walk" or "stand"
local function boothMove(a, t, offset)
	if not (a and a.Home) then return nil end
	local W = Config.WalkIn
	local tt = t - offset
	if tt < W.To then
		local k = math.clamp((tt - W.From) / (W.To - W.From), 0, 1)
		local out = a.Home.LookVector * W.Distance * (1 - k)
		a.Root.CFrame = CFrame.new(out) * a.Home * CFrame.Angles(0, math.pi, 0)
		return "walk"
	end
	local turn = smooth(W.To, W.To + W.Turn, tt)
	a.Root.CFrame = a.Home * CFrame.Angles(0, math.pi * (1 - turn), 0)
	return "stand"
end

---------------------------------------------------------------- scene 2: the ride
local function mount(S, a, role, driverHandle)
	if not a then return nil end
	local foot = S.Chassis:FindFirstChild(role == "Driver" and "DriverPosition" or "PassengerPosition")
	if not foot then return nil end
	local body = RiderPose.MeasureBody(a.Model)
	local bend = (body.Rig == "R15") and RiderPose.HipDropForKnee(body, KNEE_ANGLE) or 0
	local hold = Instance.new("Attachment")
	hold.Name = role .. "Hold"
	hold.CFrame = foot.CFrame * CFrame.new(0, body.SoleDepth - bend, 0)
	hold.Parent = S.Chassis
	a.Root.Anchored = false
	a.Root.CFrame = S.Chassis.CFrame * hold.CFrame
	local weld = Instance.new("Weld")
	weld.Part0, weld.Part1 = S.Chassis, a.Root
	weld.C0 = hold.CFrame
	weld.Parent = a.Root
	local handle = { Role = role, Scooter = S.Scooter, Humanoid = a.Humanoid, Character = a.Model,
		Root = a.Root, Hold = hold, Body = body, Released = false }
	RiderPose.Apply(handle, driverHandle)
	return handle
end

-- the point `d` studs along the scooter's run
local function pathAt(S, d)
	local P, L = S.Path, S.PathLen
	if d <= 0 then return P[1] + (P[2] - P[1]).Unit * d end   -- (behind the start: straight back)
	d = math.min(d, L[#L])
	local i = 1
	while i < #P - 1 and L[i + 1] < d do i += 1 end
	local seg = L[i + 1] - L[i]
	return P[i]:Lerp(P[i + 1], seg > 0 and (d - L[i]) / seg or 0)
end

-- the scooter `d` studs along its run: on the road under both wheels, pointing along it
local function scooterAt(S, d)
	local pb, pf = pathAt(S, d - 1.6), pathAt(S, d + 1.6)
	local mid = (pb + pf) / 2 + Vector3.new(0, S.RideUp, 0)
	local dir = pf - pb
	if dir.Magnitude < 1e-3 then dir = Config.RideDir end
	return CFrame.lookAt(mid, mid + dir)
end

local function rideDistance(t)
	if t <= Config.RideGo then return 0 end
	return Config.RideDistance(t - Config.RideGo)
end

local function placeScooter(S, t)
	local d = rideDistance(t)
	local cf = scooterAt(S, d)
	S.Chassis.CFrame = cf
	for _, w in ipairs(S.Wheels) do
		local spin = CFrame.fromAxisAngle(w.Axis, -d / w.Radius)
		local pos = w.Rel.Position
		w.Part.CFrame = cf * CFrame.new(pos) * spin * CFrame.new(-pos) * w.Rel
	end
	return cf
end

---------------------------------------------------------------- Atlas
local function atlasRig()
	local statue = workspace:FindFirstChild("Ice Atlas Statue")
	local atlas = statue and statue:FindFirstChild("Atlas")
	if not atlas then return nil end
	local heads, neck = {}, {}
	for _, p in ipairs(atlas:GetChildren()) do
		if p:IsA("BasePart") then
			if p.Name == "Head" or p.Name == "Jaw" or p.Name == "Nose" or p.Name == "EyeSocket" or p.Name == "EyeGlow"
				or p.Name == "EyeCore" or p.Name == "Brow" or p.Name == "Ear" then table.insert(heads, p)
			elseif p.Name == "Neck" then table.insert(neck, p) end
		end
	end
	local nose, jaw = atlas:FindFirstChild("Nose"), atlas:FindFirstChild("Jaw")
	local skull
	for _, p in ipairs(heads) do if p.Name == "Head" then skull = p break end end
	if not (skull and nose and jaw and #neck > 0) then return nil end
	local hc, nc = skull.Position, neck[1].Position
	local r = { Statue = statue, parts = {}, eyes = {}, jaw = jaw }
	r.pivot = nc:Lerp(hc, 0.55)
	local face = (nose.Position - hc).Unit
	r.faceFlat = (face * Vector3.new(1, 0, 1)).Unit
	r.restPitch = math.asin(face.Y)
	for _, p in ipairs(heads) do
		table.insert(r.parts, { p = p, rest = p.CFrame, w = 1, jaw = (p == jaw) })
		if p.Name == "EyeGlow" or p.Name == "EyeCore" then table.insert(r.eyes, { p = p, size = p.Size, color = p.Color }) end
	end
	local hair = statue:FindFirstChild("HairAndBeard")
	if hair then for _, p in ipairs(hair:GetDescendants()) do if p:IsA("BasePart") then table.insert(r.parts, { p = p, rest = p.CFrame, w = 1 }) end end end
	for _, p in ipairs(neck) do table.insert(r.parts, { p = p, rest = p.CFrame, w = 0.4 }) end
	local ice = statue:FindFirstChild("IceFeatures")
	if ice then
		local icicles = {}
		for _, p in ipairs(ice:GetDescendants()) do
			if p:IsA("BasePart") and p.Name == "Icicle" and (p.Position - hc).Magnitude < 18 and r.faceFlat:Dot(p.Position - r.pivot) > 2 then
				table.insert(icicles, p) table.insert(r.parts, { p = p, rest = p.CFrame, w = 1, ice = true })
			end
		end
		for _, p in ipairs(ice:GetDescendants()) do
			if p:IsA("BasePart") and p.Name == "IcicleTip" then
				for _, ic in ipairs(icicles) do
					if ((p.Position - ic.Position) * Vector3.new(1, 0, 1)).Magnitude < 0.6 then table.insert(r.parts, { p = p, rest = p.CFrame, w = 1, ice = true }) break end
				end
			end
		end
	end
	-- the jaw hinges at its top-back edge
	local js = jaw.Size
	r.hinge = jaw.CFrame * CFrame.new(0, js.Y / 2, js.Z / 2)
	-- the scream: a huge open mouth on his face under his nose (his real jaw is hidden behind
	-- his beard), just in front of the face; it stretches open as he screams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { statue }
	local below = nose.Position + Vector3.new(0, -Config.Atlas.MouthBelow, 0)
	local hit = workspace:Raycast(below + r.faceFlat * 40, -r.faceFlat * 60, params)
	local at = (hit and hit.Position or (below + r.faceFlat * 4)) + r.faceFlat * Config.Atlas.MouthOut   -- out past the icicles
	local mouth = Instance.new("Part")
	mouth.Name = "IntroAtlasMouth"
	mouth.Anchored, mouth.CanCollide, mouth.CanQuery, mouth.CanTouch = true, false, false, false
	mouth.CastShadow = false
	mouth.Transparency = 1
	mouth.Size = Vector3.new(Config.Atlas.MouthSize.X, 0.2, 0.05)
	mouth.CFrame = CFrame.lookAt(at, at + r.faceFlat)
	local picture = Instance.new("Decal")
	picture.Face = Enum.NormalId.Front
	picture.Texture = Config.Atlas.Mouth
	picture.Transparency = 1
	picture.Parent = mouth
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(120, 220, 255)
	glow.Range = 14
	glow.Brightness = 0
	glow.Parent = mouth
	r.mouth, r.mouthPicture, r.mouthGlow = mouth, picture, glow
	r.mouthRest = mouth.CFrame
	table.insert(r.parts, { p = mouth, rest = r.mouthRest, w = 1 })
	-- where he will turn to: the lobby
	local l = Config.Atlas.Lobby - r.pivot
	local flat = (l * Vector3.new(1, 0, 1)).Unit
	r.lobbyYaw = math.clamp(math.atan2(r.faceFlat:Cross(flat).Y, r.faceFlat:Dot(flat)), -math.rad(75), math.rad(75))
	r.lobbyPitch = math.clamp(math.asin(math.clamp(l.Unit.Y, -1, 1)) - r.restPitch, -math.rad(30), math.rad(20))
	return r
end

local function poseAtlas(r, yaw, pitch, roll, jawOpen, jawDrop)
	local P = r.pivot
	local right = r.faceFlat:Cross(Vector3.yAxis)
	local function turned(w)
		local yawed = CFrame.fromAxisAngle(Vector3.yAxis, yaw * w)
		local ax = yawed:VectorToWorldSpace(right)
		local fwd = yawed:VectorToWorldSpace(r.faceFlat)
		return CFrame.new(P) * CFrame.fromAxisAngle(fwd, roll * w) * CFrame.fromAxisAngle(ax, pitch * w) * yawed * CFrame.new(-P)
	end
	local full, part = turned(1), turned(0.4)
	-- the jaw swings down about its hinge (in his rest pose), then turns with the head
	local h = r.hinge
	local open = h * CFrame.Angles(-jawOpen, 0, 0) * h:Inverse() * CFrame.new(0, -jawDrop, 0)
	local list, cfs = {}, {}
	for _, e in ipairs(r.parts) do
		if e.p.Parent then
			list[#list + 1] = e.p
			local base = e.jaw and (open * e.rest) or e.rest
			cfs[#cfs + 1] = (e.w >= 1 and full or part) * base
		end
	end
	workspace:BulkMoveTo(list, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

local function restoreAtlas(r)
	if not r then return end
	local list, cfs = {}, {}
	for _, e in ipairs(r.parts) do
		if e.p.Parent and e.p ~= r.mouth then list[#list + 1] = e.p; cfs[#cfs + 1] = e.rest end
	end
	workspace:BulkMoveTo(list, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	for _, e in ipairs(r.eyes) do
		if e.p.Parent then e.p.Size = e.size; e.p.Color = e.color end
	end
	for _, e in ipairs(r.parts) do
		if e.ice and e.p.Parent then e.p.LocalTransparencyModifier = 0 end
	end
	r.mouth:Destroy()
	if r.burst then r.burst:Destroy() end
	if r.Statue.Parent then r.Statue:SetAttribute("IntroHold", nil) end
end

-- the scream's ice blast: shards and snow out of his mouth
local function screamFx(r)
	-- emitters on a small invisible part facing out of his face: they shoot along its front
	local holder = Instance.new("Part")
	holder.Name = "IntroScreamFx"
	holder.Anchored, holder.CanCollide, holder.CanQuery, holder.CanTouch = true, false, false, false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.CFrame = CFrame.lookAt(r.mouthRest.Position + r.faceFlat * 4, r.mouthRest.Position + r.faceFlat * 5)
	local function emitter(props)
		local e = Instance.new("ParticleEmitter")
		e.Enabled = false
		e.EmissionDirection = Enum.NormalId.Front
		e.LightEmission = 0.6
		for k, v in pairs(props) do e[k] = v end
		e.Parent = holder
		return e
	end
	local shards = emitter({
		Color = ColorSequence.new(Color3.fromRGB(210, 245, 255), Color3.fromRGB(110, 200, 255)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0.2) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(30, 55), SpreadAngle = Vector2.new(35, 35),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-400, 400), Drag = 3,
	})
	local snow = emitter({
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 7) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.4, 0.7), Speed = NumberRange.new(15, 30), SpreadAngle = Vector2.new(40, 40), Drag = 4,
	})
	holder.Parent = workspace
	r.burst = holder
	return function()
		shards:Emit(70)
		snow:Emit(40)
	end
end

---------------------------------------------------------------- the camera path
local function buildFlight(S, rideCam)
	local keys = {}
	-- where the scooter shot ends (and a moment before, so the speed carries on)
	for _, t in ipairs({ Config.FlightStart - 0.1, Config.FlightStart }) do
		local pos, look, fov = rideCam(t)
		table.insert(keys, { t = t, pos = pos, look = look, fov = fov })
	end
	for _, k in ipairs(Config.Flight) do
		table.insert(keys, { t = k.t, pos = k.pos, look = k.look or S.EndFocus, fov = k.fov, LookAtPlayer = k.look == nil })
	end
	-- just behind the player, then exactly the gameplay camera, then a held phantom for the spline
	local back = (S.EndEye - S.EndFocus).Unit
	table.insert(keys, { t = Config.Duration - 0.12, pos = S.EndEye + back * 9 + Vector3.new(0, 5, 0), look = S.EndFocus, fov = S.BaseFov + 4 })
	table.insert(keys, { t = Config.Duration, pos = S.EndEye, look = S.EndFocus, fov = S.BaseFov })
	table.insert(keys, { t = Config.Duration + 0.3, pos = S.EndEye, look = S.EndFocus, fov = S.BaseFov })
	return keys
end

local function sampleFlight(keys, t)
	local n = #keys
	local i = 2
	while i < n - 1 and keys[i + 1].t <= t do i += 1 end
	local k0, k1, k2, k3 = keys[i - 1], keys[i], keys[i + 1], keys[math.min(i + 2, n)]
	if k3 == k2 then k3 = { t = k2.t + 0.3, pos = k2.pos, look = k2.look, fov = k2.fov } end
	local tt = math.clamp(t, k1.t, k2.t)
	return cr(k0.pos, k1.pos, k2.pos, k3.pos, k0.t, k1.t, k2.t, k3.t, tt),
		cr(k0.look, k1.look, k2.look, k3.look, k0.t, k1.t, k2.t, k3.t, tt),
		cr(k0.fov, k1.fov, k2.fov, k3.fov, k0.t, k1.t, k2.t, k3.t, tt)
end

---------------------------------------------------------------- skip button
local function skipButton(onSkip)
	local gui = Instance.new("ScreenGui")
	gui.Name = "IntroSkip"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10001
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	local btn = Instance.new("TextButton")
	btn.Name = "Skip"
	btn.AnchorPoint = Vector2.new(1, 1)
	btn.Position = UDim2.new(1, -16, 1, -16)   -- bottom-right corner, inside the safe area
	btn.Size = UDim2.fromOffset(92, 36)
	btn.BackgroundColor3 = Color3.fromRGB(10, 12, 20)
	btn.BackgroundTransparency = 1
	btn.AutoButtonColor = false
	btn.Text = "SKIP"
	btn.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json")
	btn.TextSize = 18
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.TextXAlignment = Enum.TextXAlignment.Center
	btn.TextYAlignment = Enum.TextYAlignment.Center
	btn.TextTransparency = 1
	btn.Parent = gui
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(1, 0); corner.Parent = btn
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 1.5
	stroke.Transparency = 1
	stroke.Parent = btn
	local scale = Instance.new("UIScale"); scale.Parent = btn
	local function fit()
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		scale.Scale = math.clamp(math.min(vp.X, vp.Y) / 720, 0.8, 1.3)
	end
	fit()
	local conn = workspace.CurrentCamera and workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	local function pad()
		btn.Text = UserInputService:GetLastInputType().Name:find("Gamepad") and "SKIP (B)" or "SKIP"
	end
	pad()
	btn.MouseEnter:Connect(function() btn.BackgroundTransparency = 0.25 end)
	btn.MouseLeave:Connect(function() btn.BackgroundTransparency = 0.45 end)
	btn.Activated:Connect(onSkip)
	ContextActionService:BindActionAtPriority(SKIP_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then onSkip() end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 300, Enum.KeyCode.ButtonB, Enum.KeyCode.ButtonStart)
	gui.Parent = player:WaitForChild("PlayerGui")
	-- a quiet fade in, a moment after it starts
	task.delay(0.35, function()
		if not gui.Parent then return end
		pad()
		local ti = TweenInfo.new(0.3)
		TweenService:Create(btn, ti, { BackgroundTransparency = 0.45, TextTransparency = 0.1 }):Play()
		TweenService:Create(stroke, ti, { Transparency = 0.55 }):Play()
	end)
	return function()
		ContextActionService:UnbindAction(SKIP_ACTION)
		if conn then conn:Disconnect() end
		gui:Destroy()
	end
end

---------------------------------------------------------------- hiding other players (booths and lot, a moment)
local function hideOthersNear(S, points, radius)
	for _, plr in ipairs(Players:GetPlayers()) do
		local ch = plr ~= player and plr.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		if root then
			local near = false
			for _, p in ipairs(points) do
				if ((root.Position - p) * Vector3.new(1, 0.3, 1)).Magnitude < radius then near = true break end
			end
			if near then
				for _, d in ipairs(ch:GetDescendants()) do
					if (d:IsA("BasePart") or d:IsA("Decal")) and S.Hidden[d] == nil then
						S.Hidden[d] = d.LocalTransparencyModifier
						d.LocalTransparencyModifier = 1
					end
				end
			end
		end
	end
end

local function unhideOthers(S)
	for d, was in pairs(S.Hidden) do
		if d.Parent then d.LocalTransparencyModifier = was end
	end
	table.clear(S.Hidden)
end

---------------------------------------------------------------- play
-- opts.First   the automatic first-join play: marks the intro seen
-- opts.HandOff (eye, focus) -> gives the camera back (the loading screen's own hand-off);
--              without it the camera is handed back here
function Intro.Play(opts)
	opts = opts or {}
	if playing or not Intro.IsThisWorld() then return false end
	playing = true
	if opts.First then
		local seen = remotes:FindFirstChild("IntroSeen")
		if seen then seen:FireServer() end   -- counts as seen from here on, finished or skipped
	end

	-- until it starts, the view holds exactly where it is (nothing else is steering it)
	local cam = workspace.CurrentCamera
	local holdCF = cam.CFrame
	RunService:BindToRenderStep(STEP, CAMERA_STEP, function()
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = holdCF
	end)

	local S = prepared
	if not S then
		local done = false
		task.spawn(function() Intro.Prepare(); done = true end)
		local t0 = os.clock()
		while not done and os.clock() - t0 < Config.PrepareWait + (opts.First and 0 or 4) do task.wait() end
		S = prepared
	end
	prepared = nil   -- one use: the next replay builds a fresh one
	local eye0, focus0, hum = gameplayView()
	pcall(function() RunService:UnbindFromRenderStep(STEP) end)
	if not (S and eye0) then
		playing = false
		if S then S.Folder:Destroy(); S.SoundFolder:Destroy() end
		if opts.HandOff and eye0 then
			opts.HandOff(eye0, focus0)
		else
			cam.CameraType = Enum.CameraType.Custom
			if hum then cam.CameraSubject = hum end
		end
		return false
	end

	local playerGui = player:WaitForChild("PlayerGui")
	local cutscene = player:WaitForChild("PlayerScripts"):WaitForChild("FinishCutscene")
	local Fade = require(cutscene:WaitForChild("Fade"))
	local Lock = require(cutscene:WaitForChild("Lock"))
	local HIDE_CORE = require(cutscene:WaitForChild("Config")).HideCoreGui

	S.BaseFov = opts.First and 70 or cam.FieldOfView
	S.EndEye, S.EndFocus = eye0, focus0
	local fovBefore = cam.FieldOfView

	-- everything taken is handed to the session with how to give it back
	local undo = {}
	local session = { Add = function(_, _, fn) table.insert(undo, fn) end }
	local function undoAll()
		for i = #undo, 1, -1 do pcall(undo[i]) end
		table.clear(undo)
	end

	-- Everything below until the camera loop is running is set up under a pcall: if any of it
	-- errors, all the intro has taken so far (controls, HUD, letterbox, cast, music) is given
	-- back and the camera handed over as if it had been skipped - never left half-locked.
	local finished, removeSkip = false, nil
	local setupOk, setupErr = pcall(function()
		local fade = Fade.new(playerGui, Config.Letterbox)
		fade.Gui.Name = "IntroCinematicFx"
		session:Add("screen", function() fade:Destroy() end)
		-- the pointer stays visible for the SKIP button
		pcall(Lock.Controls, session, { ShowPointer = true })
		pcall(Lock.Hud, session, playerGui, fade.Gui, HIDE_CORE)

		-- the stage
		placeInBooths(S)
		S.Folder.Parent = workspace
		S.SoundFolder.Parent = SoundService
		session:Add("stage", function() S.Folder:Destroy() end)
		session:Add("sounds", function() S.SoundFolder:Destroy() end)
		placeScooter(S, 0)
		local driverHandle = mount(S, S.Driver, "Driver")
		local motorHandle = mount(S, S.Motor, "Passenger", driverHandle)
		-- the Motor punches a fist in the air as they go
		local fist
		if motorHandle and motorHandle.Pose and motorHandle.Pose.Arms.R and motorHandle.Body.Shoulder.R then
			local up = motorHandle.Hold.CFrame * (motorHandle.Body.Shoulder.R + Vector3.new(0.35, 1.8, -0.1))
			fist = Instance.new("Attachment")
			fist.Name = "__IntroFist"
			fist.Position = up
			fist.Parent = S.Chassis
			motorHandle.Pose.Arms.R.Target = fist
			if motorHandle.Pose.Hands.R then motorHandle.Pose.Hands.R.Target = fist end
			S.FistRest = up
		end

		-- walking into the booths, then standing (the avatar's own walk and idle)
		local tracks = {}
		local function loadTrack(a, anim)
			if not anim then return nil end
			local ok, tr = pcall(a.Animator.LoadAnimation, a.Animator, anim)
			if ok and tr then tr.Looped = true; table.insert(tracks, tr); return tr end
			return nil
		end
		for _, a in ipairs({ S.DriverBooth, S.MotorBooth }) do
			if a then
				a.WalkTrack = loadTrack(a, a.WalkAnim)
				a.IdleTrack = loadTrack(a, a.IdleAnim)
				if a.WalkTrack then a.WalkTrack:Play(0.05, 1, 1.1) end
			end
		end
		session:Add("booth animations", function() for _, tr in ipairs(tracks) do pcall(tr.Stop, tr, 0) end end)

		hideOthersNear(S, { S.BoothMid or Vector3.zero, Config.RideStart + Vector3.new(0, 214, 12) }, 26)
		session:Add("others", function() unhideOthers(S) end)

		-- Atlas holds still for us (StarterPlayerScripts.AtlasHeadFx rests his head and waits)
		local statue = workspace:FindFirstChild("Ice Atlas Statue")
		if statue then statue:SetAttribute("IntroHold", true) end
		RunService.Heartbeat:Wait(); RunService.Heartbeat:Wait()
		local atlas = atlasRig()
		if atlas then
			atlas.mouth.Parent = workspace
			session:Add("atlas", function() restoreAtlas(atlas) end)
		elseif statue then
			session:Add("atlas", function() statue:SetAttribute("IntroHold", nil) end)
		end
		local blast = atlas and screamFx(atlas)

		-- screen effects: a motion blur for the whips, a flash for the scream
		local blur = Instance.new("BlurEffect"); blur.Name = "IntroBlur"; blur.Size = 0; blur.Parent = cam
		local flash = Instance.new("ColorCorrectionEffect"); flash.Name = "IntroFlash"; flash.Parent = Lighting
		session:Add("effects", function() blur:Destroy(); flash:Destroy() end)

		-- music: the game's own music steps aside for the soundtrack
		local musicGroup = SoundService:FindFirstChild("Music")
		local musicWas = musicGroup and musicGroup:IsA("SoundGroup") and musicGroup.Volume
		local track = S.Sounds.Soundtrack
		if track then
			local ok, Settings = pcall(function()
				return require(ReplicatedStorage:WaitForChild("SettingsSystem"):WaitForChild("SettingsController"))
			end)
			local vol = ok and Settings:Get("MusicVolume") or 1
			track.Sound.Volume = track.Def.Volume * vol
			track.Base = track.Sound.Volume
			if musicWas then
				musicGroup.Volume = 0
				session:Add("music", function() if musicGroup.Parent then musicGroup.Volume = musicWas end end)
			end
		end

		-- the camera paths
		local function rideCam(t)
			local a, b = Config.RideCam[1], Config.RideCam[2]
			local hold = Config.RideHold or math.huge
			local tc = math.min(t, hold)
			local k = smooth(a.t, b.t, tc)
			local cf = scooterAt(S, rideDistance(tc))
			local pos, look, fov = cf * a.pos:Lerp(b.pos, k), cf * a.look:Lerp(b.look, k), lerp(a.fov, b.fov, k)
			if t > hold then
				-- the camera stops and watches it drive away down Road1, closing in a little
				local now = scooterAt(S, rideDistance(t)).Position + Vector3.new(0, 1.5, 0)
				look = look:Lerp(now, smooth(hold, hold + 0.6, t))
				fov = fov - 14 * smooth(hold, Config.FlightStart, t)
			end
			return pos, look, fov
		end
		local function boothCam(t)
			local a, b = Config.BoothCam[1], Config.BoothCam[2]
			local k = smooth(a.t, b.t, t)
			return a.pos:Lerp(b.pos, k), a.look:Lerp(b.look, k), lerp(a.fov, b.fov, k)
		end
		local keys = buildFlight(S, rideCam)
		local W = Config.Whip
		local A = Config.Atlas
		local shake = Config.Shake
		local seed = math.random() * 100

		local fired = {}
		local function fire(name, t, fn)
			if not fired[name] and t >= 0 then fired[name] = true; fn() end
		end

		finished = false
		local t0
		local lastEye, lastFocus = eye0, focus0
		removeSkip = nil

		local function finish(skipped)
			if finished then return end
			finished = true
			pcall(function() RunService:UnbindFromRenderStep(STEP) end)
			if removeSkip then removeSkip() end
			-- the player's real view, exactly where the flight lands
			local eye, focus, h = gameplayView()
			eye, focus = eye or lastEye, focus or lastFocus
			for _, s in pairs(S.Sounds) do pcall(s.Sound.Stop, s.Sound) end
			if S.Wind then S.Wind:Stop() end
			undoAll()
			playing = false
			-- onboarding analytics only (IntroCinematicServer -> ScooterSystem.Funnels): the first-join
			-- intro is over, watched or skipped. Protected: it can never stop or change the intro.
			if opts.First then
				pcall(function()
					local done = remotes:FindFirstChild("IntroDone")
					if done then done:FireServer() end
				end)
			end
			if opts.HandOff then
				opts.HandOff(eye, focus)
			else
				cam.FieldOfView = fovBefore
				cam.CFrame, cam.Focus = CFrame.lookAt(eye, focus), CFrame.new(focus)
				if h then cam.CameraSubject = h end
				cam.CameraType = Enum.CameraType.Custom
				-- ease into Roblox's own camera, as the loading fly-down does
				local from, tb = cam.CFrame, os.clock()
				RunService:BindToRenderStep(BLEND, CAMERA_STEP, function()
					local a = math.min((os.clock() - tb) / 0.3, 1)
					if a < 1 then cam.CFrame = from:Lerp(cam.CFrame, smooth(0, 1, a))
					else pcall(function() RunService:UnbindFromRenderStep(BLEND) end) end
				end)
			end
			if skipped then print("[Intro] skipped") end
		end

		removeSkip = skipButton(function() finish(true) end)
		fade:Bars(true, Config.BarsIn)
		task.delay(Config.Watchdog / (Config.TimeScale or 1), function() if not finished then warn("[Intro] watchdog: handing the camera back") finish(true) end end)

		RunService:BindToRenderStep(STEP, CAMERA_STEP, function()
			local ok, err = pcall(function()
				local now = os.clock()
				t0 = t0 or (now - (Config.TestFrom or 0) / (Config.TimeScale or 1))
				local t = math.min((now - t0) * (Config.TimeScale or 1), Config.Duration)
				if cam.CameraType ~= Enum.CameraType.Scriptable then cam.CameraType = Enum.CameraType.Scriptable end

				-- sounds on their marks
				for name, s in pairs(S.Sounds) do fire("snd" .. name, t - s.Def.At, function() s.Sound:Play() end) end

				-- scene 1: the booths
				if t < W.To + 0.1 then
					for i, a in ipairs({ S.DriverBooth, S.MotorBooth }) do
						if a and boothMove(a, t, (i - 1) * 0.08) == "stand" and not a.Standing then
							a.Standing = true
							if a.WalkTrack then a.WalkTrack:Stop(0.2) end
							if a.IdleTrack then a.IdleTrack:Play(0.2) end
						end
					end
				elseif not fired.boothGone then
					fired.boothGone = true
					for _, a in ipairs({ S.DriverBooth, S.MotorBooth }) do if a then a.Model:Destroy() end end
				end
				if t > Config.FlightStart then fire("unhide", 0, function() unhideOthers(S) end) end

				-- scene 2: the scooter (it keeps rolling out of shot)
				if t < Config.FlightStart + 0.8 then
					placeScooter(S, t)
					if fist and S.FistRest then
						fist.Position = S.FistRest + Vector3.new(0, math.abs(math.sin(t * 9)) * 0.35, 0)
					end
					if S.Engine then
						local r = Config.EngineRev
						if t >= r.From and t < r.To then
							if not S.Engine.IsPlaying then S.Engine:Play() end
							S.Engine.PlaybackSpeed = lerp(r.Speed[1], r.Speed[2], smooth(r.From, r.To, t))
						elseif S.Engine.IsPlaying then S.Engine:Stop() end
					end
				elseif not fired.rideGone then
					fired.rideGone = true
					if S.Engine then S.Engine:Stop() end
					S.Scooter:Destroy()
					for _, a in ipairs({ S.Driver, S.Motor }) do if a then a.Model:Destroy() end end
				end

				-- camera
				local pos, look, fov
				if t < W.From then
					pos, look, fov = boothCam(t)
				elseif t < W.To then
					local k = smooth(W.From, W.To, t)
					local p1, l1, f1 = boothCam(t)
					local p2, l2, f2 = rideCam(t)
					-- the swish arcs up over the cliff between the booths and the lot
					-- (highest late, while it crosses the lot's back wall, then straight down onto the scooter)
					local lift = Vector3.new(0, W.Lift * math.sin(math.pi * k ^ 2.5), 0)
					pos, look, fov = p1:Lerp(p2, k) + lift, l1:Lerp(l2, k), lerp(f1, f2, k) - 8 * math.sin(math.pi * k)
				elseif t < Config.FlightStart then
					pos, look, fov = rideCam(t)
				else
					pos, look, fov = sampleFlight(keys, t)
				end
				-- the whip's and the flight's motion blur
				local whip = math.sin(math.pi * math.clamp((t - W.From) / (W.To - W.From), 0, 1))
				blur.Size = W.Blur * whip + (t > Config.FlightStart and t < A.RearBackAt - 0.1 and 3 or 0)
					+ (t > A.TurnEnd and t < A.TurnEnd + 0.7 and 6 * math.sin(math.pi * (t - A.TurnEnd) / 0.7) or 0)

				-- Atlas: rears back, SCREAMS, whips his head round to the lobby
				if atlas then
					local rear = smooth(A.RearBackAt, A.ScreamAt, t) * (1 - smooth(A.ScreamAt, A.ScreamAt + 0.12, t))
					local scream = smooth(A.ScreamAt - 0.04, A.ScreamAt + 0.06, t) * (1 - smooth(A.ScreamEnd, A.ScreamEnd + 0.12, t))
					local turn = smooth(A.TurnAt, A.TurnEnd, t)
					local shakeYaw = math.sin(t * 80) * math.rad(A.ShakeDeg) * scream
					local yaw = atlas.lobbyYaw * turn + shakeYaw
					local pitch = math.rad(A.RearBack) * rear + math.rad(4) * scream + atlas.lobbyPitch * turn
					local roll = math.sin(t * 55) * math.rad(3) * scream
					poseAtlas(atlas, yaw, pitch, roll, math.rad(A.JawOpen) * scream, A.JawDrop * scream)
					atlas.mouthGlow.Brightness = 1.5 * scream
					local ms = Config.Atlas.MouthSize
					atlas.mouth.Size = Vector3.new(ms.X * (0.7 + 0.3 * scream), 0.2 + ms.Y * scream, 0.05)
					atlas.mouthPicture.Transparency = scream > 0.02 and 0 or 1
					local grow = 1 + (A.EyeGrow - 1) * scream
					for _, e in ipairs(atlas.eyes) do
						if e.p.Parent then
							e.p.Size = e.size * grow
						end
					end
					fire("blast", t - A.ScreamAt, function()
						if blast then blast() end
						for _, e in ipairs(atlas.parts) do if e.ice and e.p.Parent then e.p.LocalTransparencyModifier = 1 end end
					end)
				end
				local flashK = math.max(0, 1 - math.abs(t - (A.ScreamAt + 0.03)) / 0.12)
				flash.Brightness = 0.12 * flashK
				flash.Contrast = 0.25 * flashK

				-- the scream's camera shake
				local sk = (t < shake.Peak and smooth(shake.From, shake.Peak, t) or (1 - smooth(shake.Peak, shake.To, t)))
				local shakeCF = CFrame.identity
				if sk > 0 then
					local n = t * 38
					shakeCF = CFrame.new(math.noise(n, seed) * shake.Studs * sk, math.noise(seed, n) * shake.Studs * sk, 0)
						* CFrame.Angles(math.noise(n, seed + 3) * math.rad(shake.Degrees) * sk,
							math.noise(seed + 5, n) * math.rad(shake.Degrees) * sk,
							math.noise(n, n + seed) * math.rad(shake.Degrees) * 0.6 * sk)
					fov = fov - 6 * sk
				end

				-- wind under the flight
				if S.Wind then
					local D = Config.Duration
					local w = smooth(Config.FlightStart - 0.1, Config.FlightStart + 0.25, t) * (1 - smooth(A.RearBackAt - 0.2, A.RearBackAt + 0.05, t))
						+ smooth(A.TurnAt + 0.15, A.TurnAt + 0.45, t) * (1 - smooth(D - 0.2, D, t))
					if w > 0.01 and not S.Wind.IsPlaying then S.Wind:Play() end
					S.Wind.Volume = Config.Wind.Volume * w
				end

				-- the soundtrack fades out as it lands
				if track and track.Base then
					track.Sound.Volume = track.Base * (1 - smooth(Config.Duration - (Config.SoundtrackFade or 0.8), Config.Duration, t))
				end

				-- the bars slide away as it lands
				fire("barsOut", t - Config.BarsOutAt, function() fade:Bars(false, Config.BarsOut) end)

				-- the player's real view is where the flight lands: keep the landing spot on them
				if t > A.TurnEnd + 0.05 then
					local e, f = gameplayView()
					if e then
						S.EndEye, S.EndFocus = e, f
						keys[#keys].pos, keys[#keys].look = e, f
						keys[#keys - 1].pos, keys[#keys - 1].look = e, f
						local back = (e - f).Unit
						keys[#keys - 2].pos, keys[#keys - 2].look = e + back * 9 + Vector3.new(0, 5, 0), f
						for _, k in ipairs(keys) do if k.LookAtPlayer then k.look = f end end
					end
				end

				cam.CFrame = CFrame.lookAt(pos, look) * shakeCF
				cam.Focus = CFrame.new(look)
				cam.FieldOfView = math.clamp(fov, 20, 110)
				lastEye, lastFocus = pos, look

				if t >= Config.Duration then finish(false) end
			end)
			if not ok then
				warn("[Intro] stopped:", err)
				finish(true)
			end
		end)
	end)
	if not setupOk then
		warn("[Intro] couldn't start:", setupErr)
		finished = true   -- (the watchdog, if it was set, then does nothing)
		pcall(function() RunService:UnbindFromRenderStep(STEP) end)
		if removeSkip then pcall(removeSkip) end
		for _, s in pairs(S.Sounds) do pcall(s.Sound.Stop, s.Sound) end
		undoAll()
		pcall(function() S.Folder:Destroy() end)
		pcall(function() S.SoundFolder:Destroy() end)
		playing = false
		local eye, focus, h = gameplayView()
		eye, focus = eye or eye0, focus or focus0
		if opts.HandOff then
			opts.HandOff(eye, focus)
		else
			cam.FieldOfView = fovBefore
			cam.CFrame, cam.Focus = CFrame.lookAt(eye, focus), CFrame.new(focus)
			if h then cam.CameraSubject = h end
			cam.CameraType = Enum.CameraType.Custom
		end
		return false
	end

	while not finished do task.wait() end
	return true
end

---------------------------------------------------------------- replay (Settings > Replay Intro)
function Intro.CanReplay()
	if not Intro.IsThisWorld() then return false, "Only in World 1." end
	if playing then return false, "It's already playing." end
	if not liveRoot() then return false, "Wait until you've spawned." end
	if riding() then return false, "Only in the lobby." end
	local cin = ReplicatedStorage:FindFirstChild("ScooterSystem") and ReplicatedStorage.ScooterSystem:FindFirstChild("Cinematic")
	if cin then
		local ok, C = pcall(require, cin)
		if ok and C.IsActive() then return false, "Only in the lobby." end
	end
	return true
end

function Intro.Replay()
	local ok = Intro.CanReplay()
	if not ok then return false end
	return Intro.Play({ First = false })
end

return Intro
