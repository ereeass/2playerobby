--=====================================================================
-- SettingsUI
--
-- The gear button in the top bar and the Settings window it opens.
--
-- Built on the same motion system as InviteClient: every animated
-- property is COMPOSED each frame from independent sources instead of
-- being tweened directly, scale and rotation run on springs (press pop,
-- entrance overshoot), and the glare is the same UIGradient sweep. The
-- hover and click sounds are the Invite button's own.
--
-- The values live in ReplicatedStorage.SettingsSystem.SettingsController,
-- which applies them (volumes, shadows) and saves them to the player's
-- account. This script only draws and animates.
--=====================================================================

local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local GuiService        = game:GetService("GuiService")
local Lighting          = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Settings = require(ReplicatedStorage:WaitForChild("SettingsSystem"):WaitForChild("SettingsController"))
local HudSync  = require(ReplicatedStorage:WaitForChild("HudSync"))
local Menus    = require(ReplicatedStorage:WaitForChild("UITemplates"):WaitForChild("Menus"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- top-bar button
local gui        = script.Parent
local container  = gui:WaitForChild("Container")
local scaleObj   = container:WaitForChild("Scale")
local hint       = container:WaitForChild("Hint")
local hintStroke = hint:WaitForChild("UIStroke")
local btn        = container:WaitForChild("SettingsButton")
local stroke     = btn:WaitForChild("Edge")
local gear       = btn:WaitForChild("Gear")
local gearScale  = gear:WaitForChild("GearScale")
local btnSweep   = btn:WaitForChild("Sweep")

local sfxHover   = gui:WaitForChild("SfxHover")
local sfxPress   = gui:WaitForChild("SfxPress")

-- window (its own ScreenGui, so the dim and the blur cover the whole screen)
local winGui     = playerGui:WaitForChild("SettingsWindow")
local dim        = winGui:WaitForChild("Dim")
local window     = winGui:WaitForChild("Window")
local winScale   = window:WaitForChild("Scale")
local panel      = window:WaitForChild("Panel")
local panelSweep = panel:WaitForChild("Sweep")
local closeBtn   = panel:WaitForChild("CloseButton")
local closeScale = closeBtn:WaitForChild("Scale")
local cross      = closeBtn:WaitForChild("Cross")
local rowsFrame  = panel:WaitForChild("Rows")
local footer     = panel:WaitForChild("Footer")

--------------------------------------------------------------------- consts
local LOCAL_SIZE = 44                                -- unscaled button size, for ripple maths

local STROKE_COLOR   = stroke.Color
local ACCENT         = Color3.fromRGB(255, 205, 64)  -- the window's yellow accent
local REST_STROKE_T,  REST_STROKE_W  = stroke.Transparency, stroke.Thickness
local HOVER_STROKE_T, HOVER_STROKE_W = 0.45, 1.8
local OPEN_STROKE_T,  OPEN_STROKE_W  = 0.1, 2

local BG_REST = btn.BackgroundColor3
local BG_OPEN = BG_REST:Lerp(Color3.fromRGB(70, 86, 128), 0.45)

local DIM_MAX     = 0.25                             -- how far the world behind darkens (0..1)
local BLUR_MAX    = 0                                -- 0 = no blur: the world shows through the panel
local ROW_HOVER_T = 0.4                              -- row outline on hover

local SAVE_TEXT = {
	loading = "Loading your settings...",
	saving  = "Saving...",
	saved   = "Saved to your account.",
	offline = "Saved for this visit only.",
	failed  = "Couldn't reach your account right now.",
}

--------------------------------------------------------------------- helpers
local function approach(cur, target, rate, dt)
	return cur + (target - cur) * (1 - math.exp(-rate * dt))
end

local function springStep(cur, vel, target, stiffness, damping, dt)
	vel += ((target - cur) * stiffness - vel * damping) * dt
	return cur + vel * dt, vel
end

local function isTouch()
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

local function isGamepad()
	return UserInputService:GetLastInputType().Name:find("Gamepad") ~= nil
end

local function pointer()
	return UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
end

-- slider detents: the hover blip again, pitched by the value
local tick = sfxHover:Clone()
tick.Name = "SfxTick"
tick.Volume = sfxHover.Volume * 0.8
tick.Parent = gui

local function playPress(speed)
	sfxPress.PlaybackSpeed = speed or 1
	sfxPress:Play()
end

--------------------------------------------------------------------- effects
local sweeps = {}
local function playSweep(frame, dur)
	local grad = frame:FindFirstChild("SweepGradient")
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

local function ripple(parent, x, y, size)
	local r = Instance.new("Frame")
	r.Name = "Ripple"
	r.AnchorPoint = Vector2.new(0.5, 0.5)
	r.Position = UDim2.fromOffset(x, y)
	r.Size = UDim2.fromOffset(0, 0)
	r.BackgroundColor3 = Color3.new(1, 1, 1)
	r.BackgroundTransparency = 0.70
	r.BorderSizePixel = 0
	r.ZIndex = 4
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = r
	r.Parent = parent
	TweenService:Create(r, TweenInfo.new(0.46, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
	}):Play()
	task.delay(0.5, function() r:Destroy() end)
end

local blur
local function ensureBlur()
	if BLUR_MAX <= 0 or (blur and blur.Parent) then return end
	blur = Instance.new("BlurEffect")
	blur.Name = "SettingsBlur"
	blur.Size = 0
	blur.Enabled = false
	blur.Parent = Lighting
end

--------------------------------------------------------------------- responsive
local BASE_W, BASE_H = window.Size.X.Offset, window.Size.Y.Offset
local ROWS_SIZE      = rowsFrame.Size     -- the rows' full height (they scroll when the window is shorter)
local READABLE       = 0.75               -- never shrunk smaller than this to fit a short screen
local rootScale = 1

local function updateScale()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local vp = cam.ViewportSize
	if vp.X < 1 or vp.Y < 1 then return end
	local minAxis = math.min(vp.X, vp.Y)
	local s = minAxis / 720
	if isTouch() and minAxis < 500 then s *= 1.15 end
	s = math.clamp(s, 0.75, 1.3)
	-- never wider than the screen
	s = math.min(s, vp.X * 0.94 / BASE_W)
	-- never taller than it either: shrunk to fit, but not below READABLE - on a shorter screen
	-- (a phone on its side) the window keeps that size and gets shorter, its rows scrolling
	rootScale = math.max(math.min(s, vp.Y * 0.9 / BASE_H), math.min(s, READABLE))
	local h = math.min(BASE_H, math.floor(vp.Y * 0.9 / rootScale))
	window.Size = UDim2.fromOffset(BASE_W, h)
	rowsFrame.Size = UDim2.new(ROWS_SIZE.X.Scale, ROWS_SIZE.X.Offset, 0, ROWS_SIZE.Y.Offset - (BASE_H - h))
end

updateScale()
local function bindCamera()
	local c = workspace.CurrentCamera
	if c then c:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale) end
end
bindCamera()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	bindCamera(); updateScale()
end)

--------------------------------------------------------------------- rows
local rows = {}
local rowA = {}
local ROW_NAMES = { "SfxRow", "MusicRow", "ShadowsRow", "BugRow" }
if rowsFrame:FindFirstChild("TutorialRow") then table.insert(ROW_NAMES, "TutorialRow") end   -- the booth tutorial again
for i, name in ipairs(ROW_NAMES) do
	local f = rowsFrame:WaitForChild(name)
	local edge = f:WaitForChild("Edge")
	rows[i] = { frame = f, edge = edge, scale = f:WaitForChild("RowScale"), restT = edge.Transparency,
		hover = false, h = 0, want = 0 }
	rowA[i] = 0
end

--------------------------------------------------------------------- fade
-- The window fades as one: every transparency in it is recorded once (its
-- "base") and drawn as base faded by the window's alpha and, inside a row,
-- that row's own reveal alpha. Anything animated calls setBase instead of
-- writing the property, so hover effects and the fade never fight.
local fades  = {}
local fadeOf = {}
local winA   = 0

local rowOf = {}
for i, r in ipairs(rows) do rowOf[r.frame] = i end
local function rowIndex(o)
	while o and o ~= window do
		if rowOf[o] then return rowOf[o] end
		o = o.Parent
	end
	return 0
end

local function alphaFor(rec)
	return winA * (rec.row > 0 and rowA[rec.row] or 1)
end

local function applyFade(rec)
	rec.obj[rec.prop] = 1 - (1 - rec.base) * alphaFor(rec)
end

local function track(obj, prop)
	local rec = { obj = obj, prop = prop, base = obj[prop], row = rowIndex(obj) }
	table.insert(fades, rec)
	fadeOf[obj] = fadeOf[obj] or {}
	fadeOf[obj][prop] = rec
end

for _, o in ipairs(window:GetDescendants()) do
	if o:IsA("GuiObject") then
		track(o, "BackgroundTransparency")
		if o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox") then track(o, "TextTransparency") end
		if o:IsA("ImageLabel") or o:IsA("ImageButton") then track(o, "ImageTransparency") end
	elseif o:IsA("UIStroke") then
		track(o, "Transparency")
	end
end

local function setBase(obj, prop, value)
	local rec = fadeOf[obj] and fadeOf[obj][prop]
	if not rec then obj[prop] = value return end
	if math.abs(rec.base - value) < 1e-4 then return end
	rec.base = value
	applyFade(rec)
end

for _, rec in ipairs(fades) do applyFade(rec) end

--------------------------------------------------------------------- sliders
local sliders = {}
local activeDrag, dragInput
local lastTick = 0

local function makeSlider(rowIdx, key)
	local r      = rows[rowIdx]
	local root   = r.frame:WaitForChild("Slider")
	local trackF = root:WaitForChild("Track")
	local handle = root:WaitForChild("Handle")
	local v      = Settings:Get(key)
	local sl = {
		key = key, hit = root:WaitForChild("Hit"), track = trackF, fill = trackF:WaitForChild("Fill"),
		handle = handle, handleScale = handle:WaitForChild("HandleScale"), halo = root:WaitForChild("Halo"),
		label = r.frame:WaitForChild("Value"),
		target = v, shown = v, step = math.floor(v * 20 + 1e-6),
		hovering = false, dragging = false, hsCur = 1, hsVel = 0, haloA = 0,
	}
	sl.label.Text = math.round(v * 100) .. "%"
	table.insert(sliders, sl)
end
makeSlider(1, "SfxVolume")
makeSlider(2, "MusicVolume")

local function setValue(sl, v)
	v = math.clamp(math.round(v * 100) / 100, 0, 1)
	if v == 0 then v = 0 end                          -- never -0 (it would show as "-0%")
	if v == sl.target then return end
	local step = math.floor(v * 20 + 1e-6)           -- a detent every 5%
	if step ~= sl.step then
		sl.step = step
		local now = os.clock()
		if now - lastTick > 0.035 then
			lastTick = now
			tick.PlaybackSpeed = 0.85 + v * 0.7
			tick:Play()
		end
	end
	sl.target = v
	sl.label.Text = math.round(v * 100) .. "%"
	Settings:Set(sl.key, v)                           -- heard at once; saved on release
end

local function valueAt(sl, x)
	local left  = sl.track.AbsolutePosition.X
	local width = math.max(sl.track.AbsoluteSize.X, 1)
	return (x - left) / width
end

local function endDrag()
	local sl = activeDrag
	if not sl then return end
	activeDrag, dragInput = nil, nil
	sl.dragging = false
	Settings:Set(sl.key, sl.target, true)
end

--------------------------------------------------------------------- toggle
local toggle      = rows[3].frame:WaitForChild("Toggle")
local knob        = toggle:WaitForChild("Knob")
local toggleSweep = toggle:WaitForChild("Sweep")
local TRACK_OFF   = toggle.BackgroundColor3
local TRACK_ON    = toggle:GetAttribute("OnColor") or Color3.fromRGB(76, 196, 88)
local TOGGLE_W    = toggle.Size.X.Offset
local KNOB_W      = knob.Size.X.Offset
local KNOB_INSET  = 4

--------------------------------------------------------------------- report a bug
-- the text goes to the server (ServerScriptService.BugReports), which posts it on
local bugRow    = rows[4].frame
local bugBox    = bugRow:WaitForChild("Box")
local bugSend   = bugRow:WaitForChild("Send")
local bugScale  = bugSend:WaitForChild("Scale")
local bugLabel  = bugSend:WaitForChild("Label")
local bugDesc   = bugRow:WaitForChild("Desc")
local BUG_DESC  = bugDesc.Text
local BUG_MAX   = 500
local BUG_LINES = 5          -- the box shows this many lines; typing stops once they're full
local bugRemote = ReplicatedStorage:WaitForChild("BugReport")
local bugBusy, bugHover, bugPressed = false, false, false
local bCur, bVel = 1, 0

local shadowsOn  = Settings:Get("Shadows")
local kCur, kVel = shadowsOn and 1 or 0, 0
local colA       = kCur
local squash     = 0
local tPressed   = false

--------------------------------------------------------------------- state
local hovering, pressed = false, false
local ready    = false
local isOpen   = false

-- smoothed / sprung values
local sCur,   sVel   = 0.32, 2.2              -- entrance starts small and springs up
local rotCur, rotVel = 0, 0
local gearRot        = 0
local gearHover      = 1
local strT,   strW   = REST_STROKE_T, REST_STROKE_W
local hintA          = 0
local openA          = 0
local wantGear, revGear = 0, 0

local menu                                    -- the window's slide (UITemplates.Menus)
local refusal = Menus.refusal(hint)           -- a refused open shakes the gear and says why
local cCur,  cVel    = 1, 0                   -- close button scale spring
local crossRot       = 0
local closeHover, closePressed = false, false

--------------------------------------------------------------------- open / close
local function snapValues()
	for _, sl in ipairs(sliders) do sl.shown = sl.target end
	kCur, kVel = shadowsOn and 1 or 0, 0
	colA = kCur
end

local function open()
	if isOpen then return end
	if not menu:open() then refusal:trigger(); return end   -- a blocking screen is up (UITemplates.Menus)
	isOpen = true
	updateScale()
	footer.Text = SAVE_TEXT[Settings:GetSaveState()] or SAVE_TEXT.saved
	ensureBlur()
	if winA < 0.05 then
		-- a fresh open: pop in from small and stagger the rows in
		snapValues()
		for i, r in ipairs(rows) do
			r.want, rowA[i] = 0, 0
			task.delay(0.05 + i * 0.05, function() if isOpen then r.want = 1 end end)
		end
		task.delay(0.24, function() if isOpen then playSweep(panelSweep, 0.75) end end)
	else
		for _, r in ipairs(rows) do r.want = 1 end   -- reopened mid-close: just turn around
	end
	window.Visible, dim.Visible = true, true
	if isGamepad() then GuiService.SelectedObject = sliders[1].hit end
end

local function close()
	if not isOpen then return end
	isOpen = false
	menu:close()
	endDrag()
	if bugBox:IsFocused() then bugBox:ReleaseFocus() end
	tPressed, closePressed, closeHover = false, false, false
	local sel = GuiService.SelectedObject
	if sel and sel:IsDescendantOf(winGui) then GuiService.SelectedObject = nil end
	-- the frame loop hides the window once it has faded out
end

menu = Menus.new(window, { dim = dim, onReplace = close })

--------------------------------------------------------------------- entrance
local gearParts = {}
for _, d in ipairs(gear:GetDescendants()) do
	if d:IsA("Frame") and d.BackgroundTransparency < 1 then
		table.insert(gearParts, { obj = d, prop = "BackgroundTransparency" })
	elseif d:IsA("UIStroke") then
		table.insert(gearParts, { obj = d, prop = "Transparency" })
	end
end
for _, p in ipairs(gearParts) do p.obj[p.prop] = 1 end

-- Shown from the frame loop, in the same pass that writes its first scale, so
-- it neither flashes one frame at full size nor beats the Invite and Scooters
-- tiles (they come in from their frame loops too).
local entering = false
local function playEntrance()
	sCur, sVel = 0.32, 2.2
	wantGear, revGear = 0, 0
	entering = true
	task.delay(0.12, function() wantGear = 1 end)
	task.delay(0.34, function()
		ready = true
		playSweep(btnSweep, 0.6)
	end)
end

--------------------------------------------------------------------- frame loop
local t = 0
local lastWinA, lastRowA = -1, {}

RunService.RenderStepped:Connect(function(dt)
	dt = math.min(dt, 1 / 30)
	t += dt

	---------------------------------------------- top-bar button
	-- scale: one spring covers entrance overshoot, hover swell and press pop
	local sTarget = 1
	if pressed then sTarget = 0.93
	elseif hovering then sTarget = 1.06 end
	sCur, sVel = springStep(sCur, sVel, sTarget, 250, 19, dt)
	scaleObj.Scale = math.max(sCur, 0.01)
	if entering and not container.Visible then container.Visible = true end

	local wig, refusing = refusal:update(dt, hintA)
	rotCur, rotVel = springStep(rotCur, rotVel, (pressed and 1.8 or 0) + wig, 320, 17, dt)
	btn.Rotation = rotCur

	openA = approach(openA, isOpen and 1 or 0, 10, dt)

	-- the gear turns an eighth on hover and a quarter while the window is open
	-- (8 teeth: every stop looks the same, so it only ever reads as motion)
	gearRot = approach(gearRot, (hovering and 45 or 0) + (isOpen and 90 or 0), 9, dt)
	gear.Rotation = gearRot + math.sin(t * 1.15) * 1.2
	gearHover = approach(gearHover, hovering and 1.06 or 1, 12, dt)
	gearScale.Scale = gearHover + math.sin(t * 0.9) * 0.014

	if revGear < 1 then
		revGear = approach(revGear, wantGear, 11, dt)
		if revGear > 0.998 then revGear = 1 end
		for _, p in ipairs(gearParts) do p.obj[p.prop] = 1 - revGear end
	end

	-- stroke: breathes at rest, brightens on hover, turns accent yellow while open
	local restT = REST_STROKE_T + math.sin(t * 1.9) * 0.05
	local baseT = hovering and HOVER_STROKE_T or restT
	local baseW = hovering and HOVER_STROKE_W or REST_STROKE_W
	strT = approach(strT, baseT + (OPEN_STROKE_T - baseT) * openA, 11, dt)
	strW = approach(strW, baseW + (OPEN_STROKE_W - baseW) * openA, 11, dt)
	stroke.Transparency = strT
	stroke.Thickness    = strW
	stroke.Color        = STROKE_COLOR:Lerp(ACCENT, openA)
	btn.BackgroundColor3 = BG_REST:Lerp(BG_OPEN, openA)

	-- hover hint pill: hover / gamepad selection only, never while the window is up
	-- (and the reason an open was refused)
	local hintTarget = (refusing or (hovering and not isOpen)) and 1 or 0
	hintA = approach(hintA, hintTarget, 14, dt)
	hint.Position               = UDim2.new(1, 0, 1 + (2 + 6 * hintA) / LOCAL_SIZE, 0)
	hint.BackgroundTransparency = 1 - 0.86 * hintA
	hint.TextTransparency       = 1 - hintA
	hintStroke.Transparency     = 1 - 0.75 * hintA

	---------------------------------------------- window
	if not window.Visible then return end

	-- slides in from above and back up (UITemplates.Menus); the fade and the dim follow it
	winScale.Scale = rootScale
	winA = menu:alpha()

	local moved = math.abs(winA - lastWinA) > 1e-4
	for i, r in ipairs(rows) do
		rowA[i] = approach(rowA[i], r.want, 12, dt)
		if math.abs(rowA[i] - (lastRowA[i] or -1)) > 1e-4 then moved = true end
		r.h = approach(r.h, r.hover and 1 or 0, 14, dt)
		-- scale, not position: sub-pixel smooth (see InviteClient)
		r.scale.Scale = (0.94 + 0.06 * rowA[i]) * (1 + 0.012 * r.h)
	end
	if moved then
		lastWinA = winA
		for i = 1, #rows do lastRowA[i] = rowA[i] end
		for _, rec in ipairs(fades) do applyFade(rec) end
	end
	for _, r in ipairs(rows) do
		setBase(r.edge, "Transparency", r.restT + (ROW_HOVER_T - r.restT) * r.h)
	end

	dim.BackgroundTransparency = 1 - DIM_MAX * winA
	if blur then
		blur.Size = BLUR_MAX * winA
		blur.Enabled = winA > 0.01
	end

	-- close button: the same spring pop, and the cross turns a quarter on hover
	local cTarget = closePressed and 0.88 or (closeHover and 1.1 or 1)
	cCur, cVel = springStep(cCur, cVel, cTarget, 300, 18, dt)
	closeScale.Scale = math.max(cCur, 0.01)
	crossRot = approach(crossRot, closeHover and 90 or 0, 12, dt)
	cross.Rotation = crossRot

	-- sliders: the handle glides to the value, swells on hover, more while held
	for _, sl in ipairs(sliders) do
		sl.shown = approach(sl.shown, sl.target, sl.dragging and 30 or 16, dt)
		sl.fill.Size = UDim2.new(sl.shown, 0, 1, 0)
		local pos = UDim2.fromScale(sl.shown, 0.5)
		sl.handle.Position = pos
		sl.halo.Position = pos
		local hsTarget = sl.dragging and 1.2 or (sl.hovering and 1.1 or 1)
		sl.hsCur, sl.hsVel = springStep(sl.hsCur, sl.hsVel, hsTarget, 300, 20, dt)
		sl.handleScale.Scale = sl.hsCur
		sl.haloA = approach(sl.haloA, sl.dragging and 1 or (sl.hovering and 0.45 or 0), 14, dt)
		local hs = 24 + math.round(18 * sl.haloA)
		sl.halo.Size = UDim2.fromOffset(hs, hs)
		setBase(sl.halo, "BackgroundTransparency", 1 - 0.32 * sl.haloA)
	end

	-- send button: the close button's spring pop
	bCur, bVel = springStep(bCur, bVel, bugPressed and 0.9 or (bugHover and 1.06 or 1), 300, 18, dt)
	bugScale.Scale = math.max(bCur, 0.01)

	-- shadows toggle: sprung knob, squashes while held, track colour eases over
	kCur, kVel = springStep(kCur, kVel, shadowsOn and 1 or 0, 320, 21, dt)
	squash = approach(squash, tPressed and 1 or 0, 18, dt)
	local k = math.clamp(kCur, -0.05, 1.05)
	knob.AnchorPoint = Vector2.new(math.clamp(k, 0, 1), 0.5)
	knob.Position = UDim2.fromScale((KNOB_INSET + k * (TOGGLE_W - 2 * KNOB_INSET)) / TOGGLE_W, 0.5)
	knob.Size = UDim2.fromOffset(KNOB_W + math.round(6 * squash), KNOB_W)
	colA = approach(colA, shadowsOn and 1 or 0, 12, dt)
	toggle.BackgroundColor3 = TRACK_OFF:Lerp(TRACK_ON, colA)

	-- faded right out: put it away
	if not isOpen and winA < 0.01 then
		winA, lastWinA = 0, 0
		for _, rec in ipairs(fades) do applyFade(rec) end
		window.Visible, dim.Visible = false, false
		if blur then blur.Size = 0; blur.Enabled = false end
	end
end)

--------------------------------------------------------------------- input: gear
btn.MouseEnter:Connect(function()
	if isTouch() then return end
	hovering = true
	sfxHover:Play()
	playSweep(btnSweep, 0.5)
end)

btn.MouseLeave:Connect(function()
	hovering = false
	pressed  = false
end)

btn.MouseButton1Down:Connect(function()
	pressed = true
	playPress()
	if isTouch() then hovering = true end

	local eff = btn.AbsoluteSize.X / LOCAL_SIZE
	if eff > 0 then
		local rel = (pointer() - btn.AbsolutePosition) / eff
		ripple(btn, rel.X, rel.Y, 110)
	else
		ripple(btn, LOCAL_SIZE / 2, LOCAL_SIZE / 2, 110)
	end
end)

btn.MouseButton1Up:Connect(function()
	pressed = false
end)

-- covers drag-off and touch release, which MouseButton1Up alone misses
btn.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		pressed = false
		if isTouch() then hovering = false end
	end
end)

btn.Selectable = true
btn.SelectionGained:Connect(function() hovering = true; playSweep(btnSweep, 0.5) end)
btn.SelectionLost:Connect(function() hovering = false end)

btn.Activated:Connect(function()
	if not ready then return end
	menu:toggle(open, close)          -- the gear toggles its menu (UITemplates.Menus)
end)
-- the ride's controls popup is modal: the gear takes no input while it is up
Menus.Lockable(btn, function() hovering, pressed = false, false end)

--------------------------------------------------------------------- input: window
closeBtn.MouseEnter:Connect(function()
	if isTouch() or not isOpen then return end
	closeHover = true
	sfxHover:Play()
end)
closeBtn.MouseLeave:Connect(function()
	closeHover, closePressed = false, false
end)
closeBtn.MouseButton1Down:Connect(function()
	if not isOpen then return end
	closePressed = true
	playPress()
end)
closeBtn.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		closePressed = false
	end
end)
closeBtn.SelectionGained:Connect(function() closeHover = true end)
closeBtn.SelectionLost:Connect(function() closeHover = false end)
closeBtn.Activated:Connect(close)

-- the Dim only darkens: clicks outside the window go through it (UITemplates.Menus)

for _, r in ipairs(rows) do
	r.frame.MouseEnter:Connect(function() if not isTouch() then r.hover = true end end)
	r.frame.MouseLeave:Connect(function() r.hover = false end)
end

for _, sl in ipairs(sliders) do
	-- d-pad left/right changes the value instead of moving the selection away
	sl.hit.NextSelectionLeft  = sl.hit
	sl.hit.NextSelectionRight = sl.hit
	sl.hit.MouseEnter:Connect(function() if not isTouch() then sl.hovering = true end end)
	sl.hit.MouseLeave:Connect(function() sl.hovering = false end)
	sl.hit.SelectionGained:Connect(function() sl.hovering = true end)
	sl.hit.SelectionLost:Connect(function() sl.hovering = false end)
	sl.hit.InputBegan:Connect(function(input)
		if not isOpen then return end
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then return end
		endDrag()
		activeDrag, dragInput = sl, input
		sl.dragging = true
		playPress(1.05)
		setValue(sl, valueAt(sl, input.Position.X))
	end)
end

UserInputService.InputChanged:Connect(function(input)
	if not activeDrag then return end
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseMovement
		or (kind == Enum.UserInputType.Touch and input == dragInput) then
		setValue(activeDrag, valueAt(activeDrag, input.Position.X))
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if not activeDrag then return end
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseButton1
		or (kind == Enum.UserInputType.Touch and input == dragInput) then
		endDrag()
	end
end)

UserInputService.InputBegan:Connect(function(input)
	if not isOpen then return end
	local key = input.KeyCode
	if key == Enum.KeyCode.ButtonB then
		playPress(0.9)
		close()
	elseif key == Enum.KeyCode.DPadLeft or key == Enum.KeyCode.DPadRight then
		local sel = GuiService.SelectedObject
		for _, sl in ipairs(sliders) do
			if sel == sl.hit then
				setValue(sl, sl.target + (key == Enum.KeyCode.DPadLeft and -0.05 or 0.05))
				Settings:Set(sl.key, sl.target, true)
			end
		end
	end
end)

toggle.MouseEnter:Connect(function()
	if not isTouch() and isOpen then sfxHover:Play() end
end)
toggle.MouseButton1Down:Connect(function()
	if isOpen then tPressed = true end
end)
toggle.MouseLeave:Connect(function() tPressed = false end)
toggle.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		tPressed = false
	end
end)
toggle.Activated:Connect(function()
	if not isOpen then return end
	shadowsOn = not shadowsOn
	Settings:Set("Shadows", shadowsOn, true)
	playPress(shadowsOn and 1.1 or 0.9)
	if shadowsOn then playSweep(toggleSweep, 0.5) end
end)

--------------------------------------------------------------------- input: report a bug
local bugNote = 0
local function noteBug(text, good)
	bugNote += 1
	local n = bugNote
	bugDesc.Text = text
	bugDesc.TextColor3 = good and Color3.fromRGB(120, 230, 130) or Color3.fromRGB(255, 205, 64)
	task.delay(4, function()
		if bugNote == n then
			bugDesc.Text = BUG_DESC
			bugDesc.TextColor3 = rows[1].frame.Desc.TextColor3
		end
	end)
end

local bugLastText = ""
bugBox:GetPropertyChangedSignal("Text"):Connect(function()
	local text = bugBox.Text
	if utf8.len(text) and utf8.len(text) > BUG_MAX then
		text = text:sub(1, utf8.offset(text, BUG_MAX + 1) - 1)
	end
	-- no more than BUG_LINES wrapped lines: anything that would start a sixth is undone
	if text == bugBox.Text and #text > #bugLastText then
		local lineH = bugBox.TextSize * 1.23 * bugBox.LineHeight   -- Montserrat's own line spacing
		if bugBox.TextBounds.Y > lineH * (BUG_LINES + 0.5) then text = bugLastText end
	end
	bugLastText = text
	if bugBox.Text ~= text then bugBox.Text = text end
end)

local function sendBug()
	if not isOpen or bugBusy then return end
	local text = bugBox.Text
	if #(text:match("^%s*(.-)%s*$")) < 5 then noteBug("Tell us a bit more first.") return end
	bugBusy = true
	bugLabel.Text = "..."
	local ok, sent, why = pcall(function() return bugRemote:InvokeServer(text) end)
	bugBusy = false
	bugLabel.Text = "Send"
	if ok and sent then
		bugBox.Text = ""
		noteBug("Sent! Thanks for the report.", true)
		playSweep(panelSweep, 0.6)
	else
		noteBug(ok and why or "Couldn't send right now, try again later.")
	end
end

bugSend.MouseEnter:Connect(function()
	if isTouch() or not isOpen then return end
	bugHover = true
	sfxHover:Play()
end)
bugSend.MouseLeave:Connect(function() bugHover, bugPressed = false, false end)
bugSend.MouseButton1Down:Connect(function()
	if not isOpen then return end
	bugPressed = true
	playPress()
end)
bugSend.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		bugPressed = false
	end
end)
bugSend.SelectionGained:Connect(function() bugHover = true end)
bugSend.SelectionLost:Connect(function() bugHover = false end)
bugSend.Activated:Connect(sendBug)
bugBox.FocusLost:Connect(function(enter) if enter then sendBug() end end)

--------------------------------------------------------------------- input: tutorial
-- The first-join booth tutorial's hints again (StarterPlayerScripts.BoothTutorial): the
-- window closes and the hints start over from where the player is (lobby or booth).
local tutorialRow = rowsFrame:FindFirstChild("TutorialRow")
if tutorialRow then
	local showBtn   = tutorialRow:WaitForChild("Show")
	local showScale = showBtn:WaitForChild("Scale")
	local popInfo   = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local function pop(size) TweenService:Create(showScale, popInfo, { Scale = size }):Play() end

	showBtn.MouseEnter:Connect(function()
		if isTouch() or not isOpen then return end
		sfxHover:Play()
		pop(1.06)
	end)
	showBtn.MouseLeave:Connect(function() pop(1) end)
	showBtn.MouseButton1Down:Connect(function() if isOpen then pop(0.9) end end)
	showBtn.SelectionGained:Connect(function() pop(1.06) end)
	showBtn.SelectionLost:Connect(function() pop(1) end)
	showBtn.Activated:Connect(function()
		pop(1)
		if not isOpen then return end
		local tutorial = player:WaitForChild("PlayerScripts"):FindFirstChild("BoothTutorial")
		local replay = tutorial and tutorial:FindFirstChild("Replay")
		if not replay then return end
		playPress()
		close()
		task.delay(0.3, function() replay:Fire() end)
	end)
end

--------------------------------------------------------------------- settings
Settings.Changed:Connect(function(key, value)
	for _, sl in ipairs(sliders) do
		if sl.key == key and not sl.dragging and sl.target ~= value then
			sl.target = value
			sl.step = math.floor(value * 20 + 1e-6)
			sl.label.Text = math.round(value * 100) .. "%"
			if not isOpen then sl.shown = value end
		end
	end
	if key == "Shadows" and shadowsOn ~= value then
		shadowsOn = value
		if not isOpen then kCur, kVel = value and 1 or 0, 0; colA = kCur end
	end
end)

local function showSaveState(state)
	footer.Text = SAVE_TEXT[state] or SAVE_TEXT.saved
end
Settings.SaveStateChanged:Connect(showSaveState)
showSaveState(Settings:GetSaveState())

--------------------------------------------------------------------- ambient loops
-- idle specular sweep, as on the Invite button
task.spawn(function()
	while btn.Parent do
		task.wait(7 + math.random() * 2.5)
		if ready and not hovering and not isOpen then playSweep(btnSweep, 0.6) end
	end
end)

--------------------------------------------------------------------- start
-- The loading screen's fly-down owns the screen until it hands over; the gear
-- pops in in that same frame, together with the Invite and Scooters tiles.
container.Visible = false
HudSync.WhenIntroDone(playEntrance)
