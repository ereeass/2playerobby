--=====================================================================
-- Motion
--
-- The house motion helpers (the same maths as InviteClient and SettingsUI)
-- and the two things the whole checkpoint selector shares:
--   fader   fades a window as one. Every transparency is recorded once (its
--           "base") and drawn as base faded by the window's alpha, so hover
--           effects and the fade never fight: animate through setBase.
--   button  the pressable feel: a sprung scale (hover swell, press squash,
--           rebound), a face that lifts off its lip on hover and sinks into
--           it while held, a soft shine, a glare sweep, and the sounds.
--=====================================================================

local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Motion = {}

function Motion.approach(cur, target, rate, dt)
	return cur + (target - cur) * (1 - math.exp(-rate * dt))
end

function Motion.spring(cur, vel, target, stiffness, damping, dt)
	vel += ((target - cur) * stiffness - vel * damping) * dt
	return cur + vel * dt, vel
end

function Motion.isTouch()
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

function Motion.isGamepad()
	return UserInputService:GetLastInputType().Name:find("Gamepad") ~= nil
end

-- the glare across a frame that holds a "SweepGradient"
local sweeps = {}
function Motion.sweep(frame, dur)
	local grad = frame and frame:FindFirstChild("SweepGradient")
	if not grad then return end
	if sweeps[frame] then sweeps[frame]:Cancel() end
	frame.Visible = true
	grad.Offset = Vector2.new(-1.3, 0)
	local tw = TweenService:Create(grad,
		TweenInfo.new(dur or 0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Offset = Vector2.new(1.3, 0) })
	sweeps[frame] = tw
	tw:Play()
	tw.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed then frame.Visible = false end
	end)
end

--------------------------------------------------------------------- fader
local Fader = {}
Fader.__index = Fader

local function fadeProps(o)
	if o:IsA("CanvasGroup") then return { "GroupTransparency" } end
	if o:IsA("TextLabel") or o:IsA("TextButton") then return { "BackgroundTransparency", "TextTransparency" } end
	if o:IsA("ImageLabel") or o:IsA("ImageButton") or o:IsA("ViewportFrame") then return { "BackgroundTransparency", "ImageTransparency" } end
	if o:IsA("ScrollingFrame") then return { "BackgroundTransparency", "ScrollBarImageTransparency" } end
	if o:IsA("GuiObject") then return { "BackgroundTransparency" } end
	if o:IsA("UIStroke") then return { "Transparency" } end
	return nil
end

-- groupOf(obj) may name a group whose own alpha applies too (a staggered reveal)
function Motion.fader(groupOf)
	return setmetatable({ recs = {}, of = {}, groupOf = groupOf, alpha = 0, groups = {} }, Fader)
end

function Fader:applyRec(rec)
	local a = self.alpha
	if rec.group then a *= self.groups[rec.group] or 1 end
	rec.obj[rec.prop] = 1 - (1 - rec.base) * a
end

function Fader:track(obj)
	local props = fadeProps(obj)
	if not props then return end
	local group = self.groupOf and self.groupOf(obj)
	self.of[obj] = self.of[obj] or {}
	for _, prop in ipairs(props) do
		local rec = { obj = obj, prop = prop, base = obj[prop], group = group }
		self.recs[rec] = true
		self.of[obj][prop] = rec
		self:applyRec(rec)
	end
end

-- skip(obj) true leaves that object and everything under it alone
function Fader:trackTree(root, skip)
	if skip and skip(root) then return end
	self:track(root)
	for _, child in ipairs(root:GetChildren()) do self:trackTree(child, skip) end
end

function Fader:untrack(obj)
	local m = self.of[obj]
	if not m then return end
	for _, rec in pairs(m) do self.recs[rec] = nil end
	self.of[obj] = nil
end

function Fader:untrackTree(root)
	self:untrack(root)
	for _, d in ipairs(root:GetDescendants()) do self:untrack(d) end
end

function Fader:setBase(obj, prop, value)
	local rec = self.of[obj] and self.of[obj][prop]
	if not rec then obj[prop] = value return end
	if math.abs(rec.base - value) < 1e-4 then return end
	rec.base = value
	self:applyRec(rec)
end

-- redraws only when the window's (or a group's) alpha actually moved
function Fader:set(alpha, groups)
	local changed = math.abs(alpha - self.alpha) > 1e-4
	self.alpha = alpha
	for k, a in pairs(groups) do
		if math.abs((self.groups[k] or 1) - a) > 1e-4 then changed = true end
		self.groups[k] = a
	end
	if changed then
		for rec in pairs(self.recs) do self:applyRec(rec) end
	end
end

--------------------------------------------------------------------- button
local Button = {}
Button.__index = Button

-- holder: a Frame with a UIScale "Scale" and a TextButton "Face" (the face may
-- hold "Shine", "Sweep" and "Chevron"). opts: fader, sfx, onActivate, and the
-- feel: hover / press (scale), lift / sink (px), nudge (px the chevron is pushed)
function Motion.button(holder, opts)
	local face = holder:WaitForChild("Face")
	local self = setmetatable({
		holder = holder, face = face, opts = opts,
		scaleObj = holder:WaitForChild("Scale"),
		shine = face:FindFirstChild("Shine"),
		sweepFrame = face:FindFirstChild("Sweep"),
		chevron = face:FindFirstChild("Chevron"),
		home = face.Position,
		hover = false, pressed = false, enabled = true,
		s = 1, sv = 0, x = 0, y = 0, glow = 0, shakeT = 0,
	}, Button)
	self.chevronHome = self.chevron and self.chevron.Position
	local sfx = opts.sfx

	local function hoverOn()
		if not self.enabled then return end
		self.hover = true
		sfx:play("Hover")
		Motion.sweep(self.sweepFrame, 0.5)
	end

	face.MouseEnter:Connect(function()
		if not Motion.isTouch() then hoverOn() end
	end)
	face.MouseLeave:Connect(function()
		self.hover, self.pressed = false, false
	end)
	face.MouseButton1Down:Connect(function()
		if not self.enabled then return end
		self.pressed = true
		if Motion.isTouch() then self.hover = true end
		sfx:play("Click")
	end)
	-- covers drag-off and touch release, which MouseButton1Up alone misses
	face.InputEnded:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			self.pressed = false
			if Motion.isTouch() then self.hover = false end
		end
	end)
	face.SelectionGained:Connect(hoverOn)
	face.SelectionLost:Connect(function() self.hover = false end)
	face.Activated:Connect(function(input)
		if not self.enabled then return end
		local kind = input and input.UserInputType
		if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
			-- keyboard / gamepad never hold it down: give them the click and the pop anyway
			sfx:play("Click")
			self:kick()
		end
		if opts.onActivate then opts.onActivate() end
	end)
	return self
end

-- a quick press-and-rebound, for presses that don't hold the button down
function Button:kick()
	self.sv -= 2.2
	if self.chevron then self.x = self.opts.nudge or 0 end
end

-- a quick side-to-side "no": the button can't do that right now
function Button:shake()
	self.shakeT = 1
end

function Button:reset()
	self.hover, self.pressed = false, false
end

function Button:update(dt)
	local o = self.opts
	local target = 1
	if self.pressed then
		target = o.press or 0.93
	elseif self.hover then
		target = o.hover or 1.05
	end
	self.s, self.sv = Motion.spring(self.s, self.sv, target, 330, 20, dt)
	self.scaleObj.Scale = math.max(self.s, 0.01)

	-- the face lifts off its lip on hover and sinks into it while held
	local lift = 0
	if self.pressed then lift = o.sink or 0 elseif self.hover then lift = -(o.lift or 0) end
	self.y = Motion.approach(self.y, lift, 24, dt)
	self.shakeT = math.max(self.shakeT - dt * 3, 0)
	local sx = math.sin(os.clock() * 55) * 6 * self.shakeT
	self.face.Position = self.home + UDim2.fromOffset(sx, self.y)

	-- an arrow's chevron is pushed the way it points while held
	if self.chevron then
		self.x = Motion.approach(self.x, self.pressed and (o.nudge or 0) or 0, 18, dt)
		self.chevron.Position = self.chevronHome + UDim2.fromOffset(self.x, 0)
	end

	self.glow = Motion.approach(self.glow, self.hover and 1 or 0, 14, dt)
	if self.shine then
		o.fader:setBase(self.shine, "BackgroundTransparency", 1 - 0.16 * self.glow)
	end
end

return Motion
