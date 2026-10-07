--=====================================================================
-- TrolledUI   (StarterGui.TrolledGui)
--
-- What a rider sees when a troll is bought onto THEIR scooter. Only the two riders of that
-- scooter ever get this: the server tells only them (Remotes.TrollAlert, Kind "Trolled"), and
-- this player must really be welded to that scooter (RiderAttach) or nothing happens.
--   the banner  YOU HAVE BEEN TROLLED! / <buyer> Has Purchased ROCKET LAUNCH! (that troll's
--               name, and its picture when TrollFx.Effects gives it a BannerImage)
--   the screen  every other part of their HUD is put away for the whole show - the finish
--               cutscene's own Lock (FinishCutscene.Lock): the HUD and the same core bits,
--               the ride's controls (Cinematic), keys, pointer, touch controls, menus - so
--               it plays like a cutscene
--   the camera  behind the scooter, following that troll's show - rising after it for a
--               rocket, creeping in for an explosion - shaking with it, then the explosion
--               (its clock from ReplicatedStorage.TrollFx.Timelines: the same one every
--               screen uses)
-- It all comes back the moment the death popup opens (DeathState), and the popup takes the
-- camera from there, exactly as after any crash. If the ride ends some other way (the other
-- rider left), it all comes back at once; and never later than a few seconds after the end.
--=====================================================================

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local RS           = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui       = script.Parent
local banner    = gui:WaitForChild("Banner")
local fit       = banner:WaitForChild("Fit")
local body      = banner:WaitForChild("Body")
local pop       = body:WaitForChild("Pop")
local sweep     = body:WaitForChild("Card"):WaitForChild("Sweep")
local face      = body:WaitForChild("Face")
local icon      = body:WaitForChild("Icon")
local sub       = body:WaitForChild("Sub")
local sting     = gui:WaitForChild("Sting")

local Remotes  = RS:WaitForChild("ScooterSystem"):WaitForChild("Remotes")
local Motion   = require(RS:WaitForChild("CheckpointSelector"):WaitForChild("Motion"))
local Timelines = require(RS:WaitForChild("TrollFx"):WaitForChild("Timelines"))
local Effects   = require(RS:WaitForChild("TrollFx"):WaitForChild("Effects"))
local cutscene = player:WaitForChild("PlayerScripts"):WaitForChild("FinishCutscene")
local Lock     = require(cutscene:WaitForChild("Lock"))
local HIDE_CORE = require(cutscene:WaitForChild("Config")).HideCoreGui

local CAM_STEP   = "TrolledCamera"
local BLEND_IN   = 0.5      -- seconds from where their camera was into the show's
local REGROW     = 3        -- rate the camera backs out again once a wall is gone
local NEAR       = 5        -- a wall never pulls it nearer than this
local BASE_W     = banner.Size.X.Offset
local BASE_H     = banner.Size.Y.Offset
local ICON_ROT   = icon.Rotation
local ICON_IMAGE = icon.Image
local iconRot    = ICON_ROT      -- the showing troll's
local FACE_ROT   = face.Rotation

---------------------------------------------------------------- session
-- Everything the show takes registers how to give it back; given back once, in reverse.
-- (The same contract FinishCutscene's Lock works with.)
local Session = {}
Session.__index = Session
function Session.new() return setmetatable({ tasks = {}, alive = true }, Session) end
function Session:Add(name, fn) table.insert(self.tasks, { name = name, fn = fn }) end
function Session:Finish()
	if not self.alive then return end
	self.alive = false
	for i = #self.tasks, 1, -1 do
		local ok, err = pcall(self.tasks[i].fn)
		if not ok then warn("[Trolled] putting back '" .. self.tasks[i].name .. "' failed: " .. tostring(err)) end
	end
end

local current   -- the session of the show playing on this player, if any

---------------------------------------------------------------- the banner
local function updateFit()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local vp = cam.ViewportSize
	if vp.X < 1 or vp.Y < 1 then return end
	fit.Scale = math.min(1, vp.X * 0.9 / (BASE_W + 60), vp.Y * 0.3 / BASE_H)
end
updateFit()
local function bindCamera()
	local c = workspace.CurrentCamera
	if c then c:GetPropertyChangedSignal("ViewportSize"):Connect(updateFit) end
end
bindCamera()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function() bindCamera(); updateFit() end)

local function escape(s)
	return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function showBanner(by, name, effectId, revenge)
	-- that troll's picture (the rocket keeps the banner's own)
	local def
	for _, d in ipairs(Effects) do if d.Id == effectId then def = d end end
	icon.Image = def and def.BannerImage or ICON_IMAGE
	iconRot = def and def.BannerImage and (def.BannerRotation or 0) or ICON_ROT
	if revenge then
		sub.Text = ('<font color="#FFE45C">%s</font> got REVENGE on you!'):format(escape(by))
	else
		sub.Text = ('<font color="#FFE45C">%s</font> Has Purchased %s!'):format(escape(by), escape(string.upper(name)))
	end
	updateFit()
	banner.Visible = true
	pop.Scale = 0.15
	TweenService:Create(pop, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	sting.TimePosition = 0
	sting:Play()
	task.delay(0.4, function() if banner.Visible then Motion.sweep(sweep, 0.7) end end)
end

local function hideBanner()
	local tw = TweenService:Create(pop, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0.01 })
	tw:Play()
	tw.Completed:Once(function()
		if not current then banner.Visible = false end
	end)
end

-- the troll face grins and wobbles, the rocket bobs
RunService.RenderStepped:Connect(function()
	if not banner.Visible then return end
	local t = os.clock()
	face.Rotation = FACE_ROT + math.sin(t * 5) * 6
	icon.Rotation = iconRot + math.sin(t * 3.2) * 5
	icon.Position = UDim2.new(1, -46, 0.5, math.sin(t * 4.1) * 4)
end)

---------------------------------------------------------------- the camera
-- `dead`: the death popup has the camera now (it holds it where it is) - leave it be
local function takeCamera(session, scooter, start, T)
	local cam = workspace.CurrentCamera
	local base = scooter:GetAttribute("TrollBase")
	if not cam or typeof(base) ~= "CFrame" then return end
	local saved = { Type = cam.CameraType, Subject = cam.CameraSubject, Fov = cam.FieldOfView }
	local from = cam.CFrame
	local t0 = os.clock()
	-- what it sees through: the scooters, everybody, the show's own pieces
	local function seeThrough()
		local skip = { scooter }
		local sys = workspace:FindFirstChild("RideSystem")
		if sys and sys:FindFirstChild("Scooters") then table.insert(skip, sys.Scooters) end
		local mine = workspace:FindFirstChild("TrollFxLocal")
		if mine then table.insert(skip, mine) end
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then table.insert(skip, p.Character) end
		end
		return skip
	end
	-- the side with room for it (never inside the cliff beside a parking bay)
	local side = T.BestSide(base, seeThrough(), 0, 1)
	local room = 1
	cam.CameraType = Enum.CameraType.Scriptable
	RunService:BindToRenderStep(CAM_STEP, Enum.RenderPriority.Camera.Value + 1, function(dt)
		local c = workspace.CurrentCamera
		if not c then return end
		local t = math.max(workspace:GetServerTimeNow() - start, 0)
		local chassis = scooter.Parent and scooter.PrimaryPart
		local target = chassis and (chassis.Position + Vector3.new(0, 2, 0))
			or (base.Position + Vector3.new(0, T.Rise(math.min(t, T.EXPLODE)) + 2, 0))
		local eye, look, fovAdd = T.Camera(base, target, t, 0, side)
		-- a wall in the way pulls it in at once; it backs out again gently
		local _, share = T.Clear(eye, look, seeThrough(), NEAR)
		if share < room then room = share else room += (share - room) * (1 - math.exp(-REGROW * math.min(dt, 1 / 20))) end
		eye = T.Pulled(eye, look, room)
		local cf = CFrame.lookAt(eye, look)
		local s = T.Shake(t)
		if s > 0 then
			local n = os.clock() * 24
			cf = cf * CFrame.new(math.noise(n, 3.1) * s * 0.9, math.noise(n, 8.7) * s * 0.9, 0)
				* CFrame.Angles(0, 0, math.noise(n, 5.3) * s * 0.05)
		end
		local k = math.clamp((os.clock() - t0) / BLEND_IN, 0, 1)
		k = k * k * (3 - 2 * k)
		c.CFrame = from:Lerp(cf, k)
		c.FieldOfView = saved.Fov + fovAdd * k
	end)
	session:Add("camera", function()
		RunService:UnbindFromRenderStep(CAM_STEP)
		local c = workspace.CurrentCamera
		if not c then return end
		c.FieldOfView = saved.Fov
		if session.dead then return end
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		c.CameraSubject = hum or saved.Subject
		c.CameraType = (saved.Type ~= Enum.CameraType.Scriptable) and saved.Type or Enum.CameraType.Custom
	end)
end

---------------------------------------------------------------- the show
-- this player really is riding that scooter (welded to its chassis by RiderAttach)
local function ridingOn(scooter)
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local weld = root and root:FindFirstChild("ScooterRiderWeld")
	return weld ~= nil and scooter.PrimaryPart ~= nil and weld.Part0 == scooter.PrimaryPart
end

local levelAfter = false   -- the show ended on the death popup: level the camera once they're back

local function stop(reason)
	local s = current
	if not s then return end
	current = nil
	s.dead = reason == "death"
	levelAfter = s.dead
	s:Finish()
	hideBanner()
end

-- Back in the lobby after the popup: the popup gives Roblox's camera back pointing wherever the
-- show's camera last looked (up at the explosion), so it starts again level, behind them.
-- (A revive places its own camera behind the new scooter: nothing to do then.)
player.CharacterAdded:Connect(function(char)
	if not levelAfter then return end
	levelAfter = false
	local root = char:WaitForChild("HumanoidRootPart", 10)
	if not root then return end
	local t0 = os.clock()
	while os.clock() - t0 < 6 do
		local c = workspace.CurrentCamera
		if c and c.CameraType == Enum.CameraType.Custom and c.CameraSubject and c.CameraSubject:IsDescendantOf(char) then break end
		task.wait(0.05)
	end
	local c = workspace.CurrentCamera
	if not c or c.CameraType ~= Enum.CameraType.Custom or current then return end
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = look.Magnitude > 0.05 and look.Unit or Vector3.new(0, 0, -1)
	c.CFrame = CFrame.lookAt(root.Position - look * 12 + Vector3.new(0, 4, 0), root.Position + Vector3.new(0, 1.5, 0))
end)

Remotes:WaitForChild("TrollAlert").OnClientEvent:Connect(function(info)
	if type(info) ~= "table" or info.Kind ~= "Trolled" then return end
	local scooter = info.Scooter
	if typeof(scooter) ~= "Instance" or type(info.Start) ~= "number" then return end
	if not ridingOn(scooter) then return end
	if current then stop("again") end
	local s = Session.new()
	current = s
	Lock.Controls(s)                           -- controls, keys, pointer, touch controls, menus
	Lock.Hud(s, playerGui, gui, HIDE_CORE)     -- every other screen away; this banner stays
	showBanner(info.By or "Someone", info.Name or "Rocket Launch", info.Effect, info.Revenge == true)
	local T = Timelines[info.Effect] or Timelines.Rocket   -- that troll's clock
	-- the scooter's own attributes can land a moment after this message
	local t0 = os.clock()
	while current == s and typeof(scooter:GetAttribute("TrollBase")) ~= "CFrame" and os.clock() - t0 < 2 do
		task.wait()
	end
	if current ~= s then return end
	takeCamera(s, scooter, info.Start, T)
	-- never left in the show: at the latest a few seconds after its end
	task.delay(math.max(info.Start + T.END + 6 - workspace:GetServerTimeNow(), 1), function()
		if current == s then stop("timeout") end
	end)
end)

-- the death popup opens: it all comes back, and the popup has the camera
Remotes:WaitForChild("DeathState").OnClientEvent:Connect(function(state)
	if type(state) ~= "table" then return end
	if state.Active and current then stop("death") end
	if state.Revived then levelAfter = false end   -- the revive puts the camera behind the new scooter
end)

-- the ride ended some other way (the other rider left): it all comes back now
Remotes:WaitForChild("StateChanged").OnClientEvent:Connect(function(state)
	local phase = type(state) == "table" and state.Phase or "None"
	if (phase == "None" or phase == "Empty") and current then stop("ended") end
end)
