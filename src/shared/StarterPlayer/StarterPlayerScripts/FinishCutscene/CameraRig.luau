--=====================================================================
-- FinishCutscene / CameraRig
--
-- Takes this player's camera for the cinematic and gives it back exactly as it was.
--   Take()      Scriptable: Roblox's camera stops following and takes no input. Its
--               type, subject and field of view are noted first.
--   Shot(...)   frames the ride: Config.Camera's keyframes in the scooter's own level
--               frame, glided through smoothly in position and in speed, a hint of
--               hand-held drift, pulled in front of anything in the world that gets
--               between it and the riders, the lens tightening for a beat at the line
--   Restore()   type, subject (the player's CURRENT character if theirs has changed) and
--               field of view back - or just the lens, if the death popup has taken the
--               camera meanwhile (it gives it back itself)
--=====================================================================

local Players              = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer

local DEATH_HOLD = "DeathCameraNoControls"   -- DeathClient's camera hold (StarterGui.DeathGui)

local CameraRig = {}
CameraRig.__index = CameraRig

-- A smooth curve through keyframes (Hermite; each key's slope from its neighbours, in
-- time), flat at both ends so the camera eases in and out.
local function curve(keys, t, field, zero)
	local n = #keys
	if t <= keys[1].t then return keys[1][field] end
	if t >= keys[n].t then return keys[n][field] end
	local i = 1
	while keys[i + 1].t < t do i += 1 end
	local k0, k1 = keys[i], keys[i + 1]
	local h = k1.t - k0.t
	local u = (t - k0.t) / h
	local function slope(j)
		if j <= 1 or j >= n then return zero end
		return (keys[j + 1][field] - keys[j - 1][field]) / (keys[j + 1].t - keys[j - 1].t)
	end
	local u2, u3 = u * u, u * u * u
	return k0[field] * (2 * u3 - 3 * u2 + 1) + slope(i) * (h * (u3 - 2 * u2 + u))
		+ k1[field] * (-2 * u3 + 3 * u2) + slope(i + 1) * (h * (u3 - u2))
end

-- The shots are framed for a 16:9 screen. Roblox's field of view is the VERTICAL one, so a
-- narrower screen (an iPad's 4:3) would see less of each side and crop the ride: there the
-- lens widens just enough to keep the 16:9 width (never past MAX_WIDEN). Wider screens
-- (phones) keep the same height and simply see a little more at the sides.
local DESIGN_ASPECT, MAX_WIDEN = 16 / 9, 1.4
local function fitWidth(cam, fov)
	local vp = cam.ViewportSize
	if vp.X < 1 or vp.Y < 1 then return fov end
	local aspect = vp.X / vp.Y
	if aspect >= DESIGN_ASPECT then return fov end
	local wide = math.deg(2 * math.atan(math.tan(math.rad(fov) / 2) * DESIGN_ASPECT / aspect))
	return math.min(wide, fov * MAX_WIDEN, 110)
end

-- ignore: what the camera's line of sight looks past (the scene, scooters, characters)
function CameraRig.new(cfg, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	params.IgnoreWater = true
	return setmetatable({ cfg = cfg, keys = cfg.Camera, side = (cfg.CameraSide == -1) and -1 or 1, pull = 1, params = params }, CameraRig)
end

-- The side the camera swings round: the configured one, unless the world is in the way
-- there and not on the other. frameAt(t): the scooter's level frame at scene time t.
function CameraRig:ChooseSide(frameAt)
	local function clear(side)
		for _, k in ipairs(self.keys) do
			local frame = frameAt(k.t)
			local focus = frame * Vector3.new(k.look.X * side, k.look.Y, k.look.Z)
			local pos = frame * Vector3.new(k.pos.X * side, k.pos.Y, k.pos.Z)
			if workspace:Raycast(focus, pos - focus, self.params) then return false end
		end
		return true
	end
	if not clear(self.side) and clear(-self.side) then self.side = -self.side end
end

function CameraRig:Take()
	local cam = workspace.CurrentCamera
	self.saved = { Type = cam.CameraType, Subject = cam.CameraSubject, Fov = cam.FieldOfView }
	cam.CameraType = Enum.CameraType.Scriptable
end

-- t: scene time. frame: the scooter's level frame. crossAt: when they reach the line.
function CameraRig:Shot(t, frame, dt, crossAt)
	local cam = workspace.CurrentCamera
	if not cam then return end
	if cam.CameraType ~= Enum.CameraType.Scriptable then cam.CameraType = Enum.CameraType.Scriptable end
	local side = self.side
	local p = curve(self.keys, t, "pos", Vector3.zero)
	local l = curve(self.keys, t, "look", Vector3.zero)
	local fov = curve(self.keys, t, "fov", 0)
	p = Vector3.new(p.X * side, p.Y, p.Z)
	l = Vector3.new(l.X * side, l.Y, l.Z)
	local shake = self.cfg.CameraShake or 0
	if shake > 0 then
		p += Vector3.new(math.noise(t * 0.55, 1.7), math.noise(t * 0.5, 7.3), math.noise(t * 0.45, 13.1)) * (shake * 2)
		l += Vector3.new(math.noise(t * 0.5, 21.5), math.noise(t * 0.55, 31.9), 0) * shake
	end
	local focus, want = frame * l, frame * p
	-- the world between it and the riders: it comes in front of it (fast), and eases back out
	local offset = want - focus
	local hit = offset.Magnitude > 0.1 and workspace:Raycast(focus, offset, self.params)
	local target = hit and math.clamp((hit.Distance - 0.5) / offset.Magnitude, 0.15, 1) or 1
	self.pull += (target - self.pull) * (1 - math.exp(-(target < self.pull and 18 or 3) * dt))
	local pos = focus + offset * self.pull
	-- the lens tightens for a beat as they cross
	local punch = (self.cfg.CrossPunch or 0) * math.exp(-(((t - crossAt) - 0.12) / 0.32) ^ 2)
	cam.CFrame = CFrame.lookAt(pos, focus)
	cam.Focus = CFrame.new(focus)
	cam.FieldOfView = fitWidth(cam, fov - punch)
end

function CameraRig:Restore()
	local cam, saved = workspace.CurrentCamera, self.saved
	self.saved = nil
	if not (cam and saved) then return end
	cam.FieldOfView = saved.Fov
	-- the death popup has the camera: it hands it back to the player itself
	if next(ContextActionService:GetBoundActionInfo(DEATH_HOLD)) ~= nil then return end
	local subject = saved.Subject
	if not (subject and subject.Parent) then
		subject = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	end
	if subject then cam.CameraSubject = subject end
	cam.CameraType = (saved.Type ~= Enum.CameraType.Scriptable) and saved.Type or Enum.CameraType.Custom
end

return CameraRig
