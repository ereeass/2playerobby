-- Renders server state and forwards driver input. No client authority:
-- the server decides what any input is allowed to affect.

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local TS      = game:GetService("TweenService")
local UIS     = game:GetService("UserInputService")

local Remotes = RS:WaitForChild("ScooterSystem"):WaitForChild("Remotes")
local gui     = script.Parent

local dcP        = gui:WaitForChild("DriverControls")
local mcP        = gui:WaitForChild("MotorControls")
local noticeP    = gui:WaitForChild("Notice")
local noticeLbl  = noticeP:WaitForChild("Label")
local sfx        = gui:WaitForChild("Sfx")
local hornP      = gui:WaitForChild("HornControls")

-- The booth's one panel: "Waiting for partner.." while alone, then the 3, 2, 1, GO!,
-- with EXIT under it. And the controls popup shown on getting onto the scooter.
local boothP       = gui:WaitForChild("BoothStatus")
local boothCard    = boothP:WaitForChild("Card")
local statusLbl    = boothCard:WaitForChild("Status")
local statusPop    = statusLbl:WaitForChild("Pop")
local exitBtn      = boothCard:WaitForChild("ExitButton")
local controlsP    = gui:WaitForChild("ControlsPopup")
local controlsCard = controlsP:WaitForChild("Card")
local startBtn     = controlsCard:WaitForChild("StartButton")

-- the Driver's checkpoint window lives in its own module (the booth only opens it
-- when the server has Config.CheckpointPicker on)
local CheckpointSelector = require(RS:WaitForChild("CheckpointSelector"))
-- ...and the horn's sound, networking and who may use it live in theirs; this
-- script only feeds it the H key and the touch button
local Horn               = require(RS:WaitForChild("ScooterSystem"):WaitForChild("Horn"))
local Checkpoints        = require(RS:WaitForChild("ScooterSystem"):WaitForChild("Shared"):WaitForChild("Checkpoints"))
local Menus              = require(RS:WaitForChild("UITemplates"):WaitForChild("Menus"))
-- ...and while a cutscene has the player (the finish line's), the ride's controls stand down
local Cinematic          = require(RS:WaitForChild("ScooterSystem"):WaitForChild("Cinematic"))

---------------------------------------------------------------- panel lifecycle
local Panel = {}
Panel.__index = Panel
function Panel.new(frame, slide)
	local self = setmetatable({}, Panel)
	self.frame, self.slide = frame, slide or 0
	self.scale = frame:FindFirstChildOfClass("UIScale")
	self.basePos = frame.Position
	self.shadow = frame.Parent:FindFirstChild(frame.Name .. "Shadow")
	self.shadowBase = self.shadow and self.shadow.Position
	self.state, self.token = "Hidden", 0
	self.bases = {}
	self:Refresh()
	return self
end
-- Show and Hide tween the live properties, so those can never be re-read as the
-- "shown" look: after a Hide they sit at 1, and rebuilding the checkpoint list for
-- the next Driver session baked that in - the panel then faded in to invisible and
-- START could not be seen. Each object's shown value is read ONCE, the first time
-- the panel sees it; objects that are gone (old list buttons) are dropped.
function Panel:Refresh()
	local old, bases = self.bases, {}
	self.bases, self.items = bases, {}
	local function base(o, p)
		local b = bases[o]
		if not b then b = old[o] or {}; bases[o] = b end
		if b[p] == nil then b[p] = o[p] end
		return b[p]
	end
	local function add(o, p) table.insert(self.items, { o = o, prop = p, base = base(o, p) }) end
	-- a background only fades if it is actually drawn in the shown look
	local function addBg(o) if base(o, "BackgroundTransparency") < 1 then add(o, "BackgroundTransparency") end end
	addBg(self.frame)
	if self.shadow then add(self.shadow, "BackgroundTransparency") end
	for _, d in ipairs(self.frame:GetDescendants()) do
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			add(d, "TextTransparency")
			addBg(d)
		elseif d:IsA("Frame") then addBg(d)
		elseif d:IsA("ImageLabel") or d:IsA("ImageButton") then
			add(d, "ImageTransparency")
			addBg(d)
		elseif d:IsA("UIStroke") then add(d, "Transparency") end
	end
end
function Panel:Show()
	if self.state == "Showing" or self.state == "Active" then return end
	self.token += 1; local tok = self.token
	self.state = "Showing"
	self.frame.Visible = true
	if self.shadow then self.shadow.Visible = true end
	for _, it in ipairs(self.items) do it.o[it.prop] = 1 end
	if self.scale then self.scale.Scale = 0.92 end
	self.frame.Position = self.basePos + UDim2.fromOffset(0, self.slide)
	local info = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	if self.scale then TS:Create(self.scale, info, { Scale = 1 }):Play() end
	TS:Create(self.frame, info, { Position = self.basePos }):Play()
	if self.shadow then TS:Create(self.shadow, info, { Position = self.shadowBase }):Play() end
	for _, it in ipairs(self.items) do TS:Create(it.o, info, { [it.prop] = it.base }):Play() end
	task.delay(0.28, function() if self.token == tok then self.state = "Active" end end)
end
function Panel:Hide()
	if self.state == "Hidden" or self.state == "Hiding" then return end
	self.token += 1; local tok = self.token
	self.state = "Hiding"
	local info = TweenInfo.new(0.17, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	if self.scale then TS:Create(self.scale, info, { Scale = 0.95 }):Play() end
	TS:Create(self.frame, info, { Position = self.basePos + UDim2.fromOffset(0, self.slide * 0.6) }):Play()
	for _, it in ipairs(self.items) do TS:Create(it.o, info, { [it.prop] = 1 }):Play() end
	task.delay(0.17, function()
		if self.token == tok then
			self.frame.Visible = false
			if self.shadow then self.shadow.Visible = false; self.shadow.Position = self.shadowBase end
			self.state = "Hidden"
		end
	end)
end

local panels = {
	booth = Panel.new(boothP, 0),
	drive = Panel.new(dcP, 0), motor = Panel.new(mcP, 0),
}
local function apply(want)
	for k, p in pairs(panels) do if want[k] then p:Show() else p:Hide() end end
end

-- A one-off message from the server (e.g. the partner left). Kept out of `panels`
-- so the state changes that come with it never hide it early.
local NOTICE_TIME = 4
local noticePanel = Panel.new(noticeP, 16)
local noticeToken = 0
-- On a phone / tablet the Skip Stage button sits in the same bottom-centre spot, so while
-- it's showing the notice goes just above it instead (computers keep the usual spot)
local NOTICE_HOME = noticePanel.basePos
local function placeNotice()
	local home = NOTICE_HOME
	if UIS.TouchEnabled and not UIS.MouseEnabled then
		local skipGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
		skipGui = skipGui and skipGui:FindFirstChild("SkipStageGui")
		local holder = skipGui and skipGui.Enabled and skipGui:FindFirstChild("Holder")
		if holder and holder.Visible and holder.AbsoluteSize.Y > 0 then
			local top = holder.AbsolutePosition.Y - gui.AbsolutePosition.Y   -- the button's top, in this gui
			local bottom = gui.AbsoluteSize.Y + NOTICE_HOME.Y.Offset          -- where the notice's bottom sits normally
			if bottom > top - 8 then home = UDim2.new(NOTICE_HOME.X.Scale, NOTICE_HOME.X.Offset, 0, top - 8) end
		end
	end
	noticePanel.basePos = home
	if noticePanel.state == "Showing" or noticePanel.state == "Active" then noticeP.Position = home end
end
local function showNotice(text)
	noticeToken += 1; local tok = noticeToken
	noticeLbl.Text = text
	placeNotice()
	noticePanel:Show()
	task.delay(NOTICE_TIME, function() if noticeToken == tok then noticePanel:Hide() end end)
end
-- the same notice for one-off messages from other server systems (e.g. the Ice
-- Scooter podium's "You already own this item")
Remotes:WaitForChild("Notice").OnClientEvent:Connect(function(text)
	if type(text) == "string" then showNotice(text) end
end)

---------------------------------------------------------------- booth status
local WAITING_TEXT = "Waiting for\npartner.."

-- The line in the booth panel. Each step of the countdown settles in with a small
-- pop; anything else just changes. The same text twice (a repeated push) is a no-op.
local popTween
local function setStatus(text, pop)
	if statusLbl.Text == text then return end
	statusLbl.Text = text
	if popTween then popTween:Cancel(); popTween = nil end
	statusPop.Scale = pop and 1.14 or 1
	if pop then
		popTween = TS:Create(statusPop, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		popTween:Play()
	end
end

---------------------------------------------------------------- buttons + sound
local function play(name)
	local s = sfx:FindFirstChild(name)
	if s then s:Play() end       -- Sound:Play restarts, so rapid input cannot stack
end

local function wireButton(btn, hoverSound)
	local sc = btn:FindFirstChildOfClass("UIScale")
	local hovering, pressed, wasInside = false, false, false
	local function refresh()
		if not sc then return end
		local target = pressed and 0.94 or (hovering and 1.05 or 1)
		local info = pressed and TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			or TweenInfo.new(0.30, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		TS:Create(sc, info, { Scale = target }):Play()
	end
	btn.MouseEnter:Connect(function()
		if UIS.TouchEnabled and not UIS.MouseEnabled then return end
		hovering = true
		if hoverSound and not wasInside then wasInside = true; play("Hover") end
		refresh()
	end)
	btn.MouseLeave:Connect(function()
		hovering, pressed, wasInside = false, false, false
		refresh()
	end)
	btn.MouseButton1Down:Connect(function() pressed = true; refresh() end)
	btn.MouseButton1Up:Connect(function() pressed = false; refresh() end)
	btn.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1
			or i.UserInputType == Enum.UserInputType.Touch then pressed = false; refresh() end
	end)
end
wireButton(exitBtn, true)
wireButton(startBtn, true)

---------------------------------------------------------------- ride input
-- Two roles, two separate control sets. The client only ever SENDS; the server
-- decides whether the sender is allowed to affect that thing.
--
--   Driver     A = steer left, D = steer right. Nothing else.
--   Passenger  W = forward, S = backward (slows first if still rolling forward),
--              Space = brake. Nothing else. Space beats W and S, so W + Space
--              always slows down. W + S cancel out. Releasing lets it coast.
--   Either     H = horn, while held (or the horn button).
--
-- Nothing in here reads the camera, and steer is a scooter-local -1/0/+1 that the
-- server turns into a fork angle, so the scooter can never strafe.
local riding, myRole = false, nil
local localSteer = 0        -- the Driver's steer as this machine applies it (see "steering" below)

-- Roblox's own character controls (StarterPlayer.PlayerModule) listen to the same
-- W/A/S/D/Space through its CharacterContext input context. Left on, a rider's
-- Humanoid is told to walk with W/S and jump with Space for the whole ride - the
-- same keys doing two jobs. The context is off while riding and back on after.
local function characterInput(on)
	local pm = game:GetService("StarterPlayer"):FindFirstChild("PlayerModule")
	local contexts = pm and pm:FindFirstChild("InputContexts")
	local ctx = contexts and contexts:FindFirstChild("CharacterContext")
	-- ...and stays off while a cutscene has the player (Cinematic)
	if ctx and ctx:IsA("InputContext") then ctx.Enabled = on and not Cinematic.IsActive() end
end

local steerKeys = { left = false, right = false }
local motorKeys = { go = false, back = false, brake = false }
local touchSteer = 0        -- -1 / 0 / +1 from the mobile arrows
local touchMotor = nil      -- "go" / "reverse" / nil from the mobile buttons
-- a controller (console / gamepad): left stick steers, R2 go, L2 reverse, Square (X on Xbox)
-- brakes, Triangle (Y) honks. Its own state, so it never touches the keyboard's or touch's.
local padSteer = 0          -- -1 / 0 / +1 from the left stick
local padMotor = { go = false, back = false, brake = false }
local lastSteer, lastThrottle, lastBrake

local function pushInput()
	if not riding then return end
	-- A cutscene has the player (Cinematic): whatever is held, the fork goes straight and
	-- the motor brakes to a stop and holds there. Held keys count again once it's over.
	local held = Cinematic.IsActive()

	if myRole == "Driver" then
		local steer = touchSteer
		if steer == 0 then
			steer = (steerKeys.right and 1 or 0) - (steerKeys.left and 1 or 0)
		end
		if steer == 0 then steer = padSteer end
		if held then steer = 0 end
		localSteer = steer
		if steer ~= lastSteer then
			lastSteer = steer
			Remotes.DriveInput:FireServer({ Steer = steer })
		end

	elseif myRole == "Passenger" then
		-- the keyboard's keys and the controller's buttons, either one
		local motorKeys = { go = motorKeys.go or padMotor.go, back = motorKeys.back or padMotor.back,
			brake = motorKeys.brake or padMotor.brake }
		local mode
		if held or motorKeys.brake then
			-- the brake beats everything: holding it must slow down, never speed up
			mode = "brake"
		else
			mode = touchMotor
		end
		if not mode then
			-- W + S cancels out rather than picking a winner
			if motorKeys.go and not motorKeys.back then
				mode = "go"
			elseif motorKeys.back and not motorKeys.go then
				mode = "reverse"
			else
				mode = "coast"
			end
		end
		if mode ~= lastThrottle then
			lastThrottle = mode
			Remotes.DriveInput:FireServer({ Throttle = mode })
		end
		-- The brake itself, as its own signal: Space, or the touch Brake pedal while it
		-- is the pedal in charge (only that pedal ever sets touchMotor to "reverse"; the
		-- Accelerator pressed after it takes over). W and S never set it. Only the
		-- brake screech listens to it (RideManager); the scooter moves on the throttle.
		local brake = (motorKeys.brake or touchMotor == "reverse") and not held   -- a cutscene's stop is silent
		if brake ~= lastBrake then
			lastBrake = brake
			Remotes.DriveInput:FireServer({ Brake = brake })
		end
	end
end

local STEER_KEYS = {
	[Enum.KeyCode.A] = "left",
	[Enum.KeyCode.D] = "right",
}
local MOTOR_KEYS = {
	[Enum.KeyCode.W]     = "go",
	[Enum.KeyCode.S]     = "back",
	[Enum.KeyCode.Space] = "brake",
}
local HORN_KEY = Enum.KeyCode.H   -- Horn ignores it unless this player is on a scooter
local PAD_MOTOR = {
	[Enum.KeyCode.ButtonR2] = "go",      -- R2 / RT
	[Enum.KeyCode.ButtonL2] = "back",    -- L2 / LT
	[Enum.KeyCode.ButtonX]  = "brake",   -- Square / X
}
local PAD_HORN = Enum.KeyCode.ButtonY    -- Triangle / Y
local PAD_DEADZONE, PAD_RELEASE = 0.4, 0.3   -- stick past 0.4 steers, back under 0.3 lets go

-- a key only ever reaches the server for the role that owns it
local function mine(s, m)
	return (s and myRole == "Driver") or (m and myRole == "Passenger")
end
UIS.InputBegan:Connect(function(i, gp)
	if gp then return end
	if i.KeyCode == HORN_KEY then if not Cinematic.IsActive() then Horn.Press("key") end; return end
	local s = STEER_KEYS[i.KeyCode]; if s then steerKeys[s] = true end
	local m = MOTOR_KEYS[i.KeyCode]; if m then motorKeys[m] = true end
	if mine(s, m) then pushInput() end
end)
UIS.InputEnded:Connect(function(i)
	if i.KeyCode == HORN_KEY then Horn.Release("key"); return end
	local s = STEER_KEYS[i.KeyCode]; if s then steerKeys[s] = false end
	local m = MOTOR_KEYS[i.KeyCode]; if m then motorKeys[m] = false end
	if mine(s, m) then pushInput() end
end)

-- the controller (only gamepad inputs reach these; keyboard, mouse and touch never do)
local function isPad(i) return i.UserInputType.Name:sub(1, 7) == "Gamepad" end
UIS.InputBegan:Connect(function(i, gp)
	if gp or not isPad(i) then return end
	if i.KeyCode == PAD_HORN then if not Cinematic.IsActive() then Horn.Press("pad") end; return end
	local m = PAD_MOTOR[i.KeyCode]
	if m then padMotor[m] = true; if myRole == "Passenger" then pushInput() end end
end)
UIS.InputEnded:Connect(function(i)
	if not isPad(i) then return end
	if i.KeyCode == PAD_HORN then Horn.Release("pad"); return end
	local m = PAD_MOTOR[i.KeyCode]
	if m then padMotor[m] = false; if myRole == "Passenger" then pushInput() end end
end)
UIS.InputChanged:Connect(function(i)
	if i.KeyCode ~= Enum.KeyCode.Thumbstick1 or not isPad(i) then return end
	local x = i.Position.X
	-- while Roblox's menu cursor is driving the UI, the stick moves that, not the scooter
	if game:GetService("GuiService").SelectedObject then x = 0 end
	local want = padSteer
	if math.abs(x) >= PAD_DEADZONE then want = x > 0 and 1 or -1
	elseif math.abs(x) < PAD_RELEASE then want = 0 end
	if want ~= padSteer then
		padSteer = want
		if myRole == "Driver" then pushInput() end
	end
end)
UIS.GamepadDisconnected:Connect(function()
	padSteer = 0
	for k in pairs(padMotor) do padMotor[k] = false end
	Horn.Release("pad")
	pushInput()
end)

-- Hold-to-act for every touch button: pressing starts, releasing stops. Returns
-- its own release function so the panel can be force-released on dismount.
local PEDAL_HELD = Color3.fromRGB(200, 200, 200)   -- a pedal's artwork darkens a touch while held
local function wireHold(btn, onDown, onUp, baseT)
	local sc = btn:FindFirstChildOfClass("UIScale")
	local art = btn:FindFirstChild("Art")   -- pedals are artwork, not a background
	local held = false
	local function down()
		if held then return end
		held = true
		onDown(); pushInput()
		if sc then TS:Create(sc, TweenInfo.new(0.08), { Scale = 0.92 }):Play() end
		if art then TS:Create(art, TweenInfo.new(0.08), { ImageColor3 = PEDAL_HELD }):Play()
		else btn.BackgroundTransparency = math.max(0, baseT - 0.20) end
	end
	local function up()
		if not held then return end
		held = false
		onUp(); pushInput()
		if sc then TS:Create(sc, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play() end
		if art then TS:Create(art, TweenInfo.new(0.22), { ImageColor3 = Color3.new(1, 1, 1) }):Play()
		else btn.BackgroundTransparency = baseT end
	end
	btn.MouseButton1Down:Connect(down)
	btn.MouseButton1Up:Connect(up)
	btn.MouseLeave:Connect(up)
	btn.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.Touch
			or i.UserInputType == Enum.UserInputType.MouseButton1 then up() end
	end)
	return up
end

local releaseTouch = {}
local function wireArrow(btn, dir)
	table.insert(releaseTouch, wireHold(btn,
		function() touchSteer = dir end,
		function() if touchSteer == dir then touchSteer = 0 end end, 0.32))
end
local function wireMotor(btn, mode)
	table.insert(releaseTouch, wireHold(btn,
		function() touchMotor = mode end,
		function() if touchMotor == mode then touchMotor = nil end end, 0.32))
end
wireArrow(dcP:WaitForChild("SteerLeft"),  -1)
wireArrow(dcP:WaitForChild("SteerRight"),  1)
local pedals = mcP:WaitForChild("Pedals")
wireMotor(pedals:WaitForChild("Accelerator"), "go")
wireMotor(pedals:WaitForChild("Brake"),       "reverse")   -- the old BACK button's job, same as S on PC

---------------------------------------------------------------- horn
-- Hold to honk, for either rider: H (above) or the horn button, shown only while this
-- player is really on a scooter. On a keyboard the button shows the H key under the
-- horn; on a touch screen it is the horn alone. Both only ever call Horn.Press /
-- Horn.Release, so they are one horn. The button's touch area is bigger than the
-- button you see.
local hornBtn   = hornP:WaitForChild("Horn")
local hornFace  = hornBtn:WaitForChild("Face")
local hornIcon  = hornFace:WaitForChild("Icon")
local hornKey   = hornFace:WaitForChild("Key")
local hornPress = hornFace:WaitForChild("Press")
local hornPanel = Panel.new(hornP, 0)

-- yellow at rest; a deeper orange, pressed in, while it sounds (by the button or H)
local HORN_REST = hornFace.BackgroundColor3
local HORN_ON   = Color3.fromRGB(255, 146, 22)
local hornLit, hornHover = false, false
local function hornLook()
	local info = TweenInfo.new(hornLit and 0.06 or 0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TS:Create(hornFace, info, { BackgroundColor3 = hornLit and HORN_ON or HORN_REST }):Play()
	TS:Create(hornPress, hornLit and TweenInfo.new(0.07)
		or TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = hornLit and 0.92 or (hornHover and 1.05 or 1) }):Play()
end
hornBtn.MouseEnter:Connect(function()
	if UIS.TouchEnabled and not UIS.MouseEnabled then return end
	hornHover = true
	hornLook()
end)
hornBtn.MouseLeave:Connect(function()
	hornHover = false
	hornLook()
end)

-- Touch screens keep the button where it is placed (bottom, a little left of centre,
-- by the thumbs). A keyboard gets it at the left edge, a little below the middle,
-- where the lobby's Invite and Skins buttons sit (they step aside during a ride),
-- with the H under the horn: a phone has no H to press.
local HORN_TOUCH_ANCHOR = hornBtn.AnchorPoint   -- bottom centre of the button
local HORN_PC_ANCHOR,    HORN_PC_POS    = Vector2.new(0, 0.5), UDim2.new(0, 2, 0.6, 0)   -- the button 16 from the edge

-- Touch: a little smaller than on PC, low by the bottom edge (the face ends ~8 px
-- above it, clear of rounded corners and the home bar, which the RideGui's safe
-- insets already keep out) and a little left of centre - but never over the
-- Motor's brake pedal, whose touch area ends at PEDAL_EDGE of the width.
-- made here if it is missing: a lost size object must never stall this script
-- (everything below it, the booth panel included, would never run)
local hornFit           = hornBtn:FindFirstChild("TouchSize")
if not hornFit then
	hornFit = Instance.new("UIScale")
	hornFit.Name = "TouchSize"
	hornFit.Parent = hornBtn
end
local HORN_TOUCH_SCALE  = 48 / 72   -- the face 48 px tall: the Skip Stage button's touch height (SkipStageUI)
local HORN_TOUCH_X      = -110   -- px from the centre of the screen
local HORN_TOUCH_DROP   = 4      -- px the (empty) bottom of the touch area sits past the edge
local PEDAL_EDGE        = 0.31

-- Keyboard hints (the horn's H and PC spot, the PC keycaps) follow the controls the
-- player is using. Without a touch screen: on, whenever there is a keyboard. With
-- one: off, unless the player is actually on keys or a mouse (a laptop's touch
-- screen). A phone can report a keyboard and a mouse too until its first touch,
-- so those flags alone never switch a touch screen to the PC layout.
local PC_INPUT = {
	[Enum.UserInputType.Keyboard]      = true,
	[Enum.UserInputType.MouseMovement] = true,
	[Enum.UserInputType.MouseButton1]  = true,
	[Enum.UserInputType.MouseButton2]  = true,
	[Enum.UserInputType.MouseButton3]  = true,
	[Enum.UserInputType.MouseWheel]    = true,
}
local function keyboardHints()
	if not UIS.KeyboardEnabled then return false end
	if not UIS.TouchEnabled then return true end
	return PC_INPUT[UIS:GetLastInputType()] == true
end

local function layoutHorn()
	local key = keyboardHints()
	hornBtn.AnchorPoint = key and HORN_PC_ANCHOR or HORN_TOUCH_ANCHOR
	hornFit.Scale = key and 1 or HORN_TOUCH_SCALE
	if key then
		hornBtn.Position = HORN_PC_POS
	else
		local w = gui.AbsoluteSize.X
		local half = hornBtn.Size.X.Offset * HORN_TOUCH_SCALE / 2
		local x = math.max(w / 2 + HORN_TOUCH_X, w * PEDAL_EDGE + half + 6)
		hornBtn.Position = UDim2.new(0, math.round(x), 1, HORN_TOUCH_DROP)
	end
	hornKey.Visible = key
	hornIcon.Position = UDim2.fromScale(0.5, key and 0.4 or 0.5)
	hornIcon.Size = key and UDim2.fromScale(0.56, 0.56) or UDim2.fromScale(0.64, 0.64)
end

-- The touch (or click) holding the button. Only that same touch letting go releases
-- it, wherever it lets go, so a thumb coming off an arrow never cuts the horn.
local hornInput
local function hornDown(i)
	local t = i.UserInputType
	if hornInput or (t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseButton1) then return end
	hornInput = i
	Horn.Press("touch")
end
local function hornUp(i)
	if not hornInput then return end
	local same
	if hornInput.UserInputType == Enum.UserInputType.Touch then
		same = (i == hornInput)
	else
		same = (i.UserInputType == Enum.UserInputType.MouseButton1)
	end
	if not same then return end
	hornInput = nil
	Horn.Release("touch")
end
hornBtn.InputBegan:Connect(hornDown)
hornBtn.InputEnded:Connect(hornUp)
UIS.InputEnded:Connect(hornUp)
UIS.TouchEnded:Connect(hornUp)

-- a window that loses focus never hears its keys come back up
UIS.WindowFocusReleased:Connect(Horn.ReleaseAll)

Horn.Changed:Connect(function(held, available)
	if not held then hornInput = nil end
	if held ~= hornLit then
		hornLit = held
		hornLook()
	end
	-- touch screens press it and keyboards hold H; a gamepad alone has neither
	if available and (UIS.TouchEnabled or UIS.KeyboardEnabled) then
		layoutHorn()
		hornPanel:Show()
	else
		hornHover = false
		hornPanel:Hide()
	end
end)

---------------------------------------------------------------- control hints
-- A short list in the bottom-left corner while riding: a dark key badge and what it does,
-- one line per control, for this player's job only (the Driver steers, the Passenger makes
-- it go). A badge turns green while its key or button is held. Keyboard and controller
-- only (a touch screen has its own buttons to look at); it follows the controls in use and
-- switches the moment that changes. Shown only while this player is really on a scooter
-- (Horn's check: on it and alive). Look: KeyHints > Hints in RideGui.
local K = Enum.KeyCode
local HINTS = {
	Driver = {
		keys = { { "A", "Steer Left", { K.A } }, { "D", "Steer Right", { K.D } }, { "H", "Horn", { K.H } } },
		pad  = { { "L-STICK", "Steer", { "stick" } }, { "Y", "Horn", { K.ButtonY } } },
		ps   = { { "L-STICK", "Steer", { "stick" } }, { "TRIANGLE", "Horn", { K.ButtonY } } },
	},
	Passenger = {
		keys = { { "W", "Accelerate", { K.W } }, { "S", "Reverse", { K.S } }, { "SPACE", "Brake", { K.Space } },
		         { "H", "Horn", { K.H } } },
		pad  = { { "RT", "Accelerate", { K.ButtonR2 } }, { "LT", "Reverse", { K.ButtonL2 } },
		         { "X", "Brake", { K.ButtonX } }, { "Y", "Horn", { K.ButtonY } } },
		ps   = { { "R2", "Accelerate", { K.ButtonR2 } }, { "L2", "Reverse", { K.ButtonL2 } },
		         { "SQUARE", "Brake", { K.ButtonX } }, { "TRIANGLE", "Horn", { K.ButtonY } } },
	},
}
local LINE_H, LINE_GAP = 38, 7   -- px per line and between lines, as built at 1080p
local BADGE_OFF = Color3.fromRGB(28, 28, 30)
local BADGE_ON  = Color3.fromRGB(70, 175, 75)   -- held
local keysP     = gui:WaitForChild("KeyHints")
local hintsBox  = keysP:WaitForChild("Hints")
local keysFit   = hintsBox:WaitForChild("Fit")
local hintLines = {}
for i = 1, 4 do
	local line = hintsBox:WaitForChild("Line" .. i)
	local badge = line:WaitForChild("Badge")
	hintLines[i] = { line = line, badge = badge, key = badge:WaitForChild("Key"), label = line:WaitForChild("Label") }
end
local keysPanel = Panel.new(keysP, 8)
local shownKey            -- role .. mode on show, to spot a change
local badgeOf   = {}      -- [KeyCode or "stick"] = the badge showing it
local held      = {}      -- [KeyCode or "stick"] = true while held

local function light(code, down)
	held[code] = down or nil
	local badge = badgeOf[code]
	if badge then badge.BackgroundColor3 = down and BADGE_ON or BADGE_OFF end
end

-- the controls this player is using right now (the controls popup uses the same rule)
local function inputMode()
	local last = UIS:GetLastInputType()
	if last.Name:sub(1, 7) == "Gamepad"
		or (UIS.GamepadEnabled and not UIS.KeyboardEnabled and not UIS.TouchEnabled) then
		return "pad"
	end
	return keyboardHints() and "keys" or "touch"
end

-- a PlayStation controller names its buttons differently (Roblox reports ButtonA as "ButtonCross")
local function padNames()
	local ok, name = pcall(UIS.GetStringForKeyCode, UIS, K.ButtonA)
	return (ok and name == "ButtonCross") and "ps" or "pad"
end

local function refreshKeyHints()
	local mode = inputMode()
	local role = mode ~= "touch" and riding and Horn.IsAvailable() and HINTS[myRole] and myRole or nil
	if role then
		if mode == "pad" then mode = padNames() end
		local key = role .. mode
		if key ~= shownKey then
			shownKey = key
			table.clear(badgeOf)
			local lines = HINTS[role][mode]
			for i, l in ipairs(hintLines) do
				local e = lines[i]
				l.line.Visible = e ~= nil
				l.key.Text, l.label.Text = e and e[1] or "", e and e[2] or ""
				l.badge.BackgroundColor3 = BADGE_OFF
				if e then
					for _, code in ipairs(e[3]) do
						badgeOf[code] = l.badge
						if held[code] then l.badge.BackgroundColor3 = BADGE_ON end
					end
				end
			end
			hintsBox.Size = UDim2.fromOffset(hintsBox.Size.X.Offset, #lines * (LINE_H + LINE_GAP))
		end
		keysPanel:Show()
	else
		shownKey = nil
		keysPanel:Hide()
	end
end
Horn.Changed:Connect(refreshKeyHints)   -- off the scooter, dead, back on

-- the badges light with the real keys and buttons (looks only: the ride reads them above)
UIS.InputBegan:Connect(function(i, gp)
	if gp then return end
	light(i.KeyCode, true)
end)
UIS.InputEnded:Connect(function(i) light(i.KeyCode, false) end)
UIS.InputChanged:Connect(function(i)
	if i.KeyCode == K.Thumbstick1 then light("stick", math.abs(i.Position.X) >= PAD_DEADZONE) end
end)
UIS.WindowFocusReleased:Connect(function()
	for code in pairs(held) do light(code, false) end
end)

-- the horn's spot follows the keyboard; the hints follow any change of controls
local hintsOn = keyboardHints()
local function relayoutHints()
	local now = keyboardHints()
	if now ~= hintsOn then
		hintsOn = now
		if Horn.IsAvailable() then layoutHorn() end
	end
	refreshKeyHints()
end
UIS.LastInputTypeChanged:Connect(relayoutHints)
UIS:GetPropertyChangedSignal("TouchEnabled"):Connect(relayoutHints)
UIS:GetPropertyChangedSignal("KeyboardEnabled"):Connect(relayoutHints)
UIS.GamepadConnected:Connect(relayoutHints)
UIS.GamepadDisconnected:Connect(relayoutHints)

-- sized to the screen: as built at 1080p, bigger on a big screen, never too small
local function fitKeyHints()
	local cam = workspace.CurrentCamera
	local h = cam and cam.ViewportSize.Y or 0
	if h > 0 then keysFit.Scale = math.clamp(h / 1080, 0.6, 1.5) end
end

-- The booth panel and the controls popup are built in the pixels of their reference
-- art, taken at 1080p, where the Settings window is at its biggest (x1.3). From
-- there they follow the Settings window's own size rule (SettingsUI.updateScale):
-- the screen's short side / 720, a little bigger on a small touch screen, kept to
-- 0.75 .. 1.3 - and never wider or taller than the screen allows.
local ART_TO_UI     = 1 / 1.3
local CONTROLS_SIZE = 0.8    -- the controls popup a little under its art: it sits over the ride
local CONTROLS_Y    = 0.46   -- its usual height on the screen
local boothFit, controlsFit = boothCard:WaitForChild("Fit"), controlsCard:WaitForChild("Fit")
local controlsY = CONTROLS_Y
local function fitPanels()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize
	if not vp or vp.X < 1 or vp.Y < 1 then return end
	local short = math.min(vp.X, vp.Y)
	local s = short / 720
	if UIS.TouchEnabled and not UIS.MouseEnabled and short < 500 then s *= 1.15 end
	s = math.clamp(s, 0.75, 1.3) * ART_TO_UI
	local cw, ch = controlsCard.Size.X.Offset, controlsCard.Size.Y.Offset
	boothFit.Scale = math.min(s, vp.X * 0.9 / boothCard.Size.X.Offset, vp.Y * 0.6 / boothCard.Size.Y.Offset)

	-- A touch screen's ride controls sit in the bottom corners (the pedals take
	-- 4-31% and 69-96% of the width from 58% of the height down; the arrows are
	-- smaller). The popup stays clear of them: in landscape it keeps to the gap
	-- between them, in portrait it sits above them.
	local c = math.min(s * CONTROLS_SIZE, vp.X * 0.9 / cw, vp.Y * 0.55 / ch)
	controlsY = CONTROLS_Y
	if UIS.TouchEnabled then
		if vp.X >= vp.Y then
			c = math.min(c, vp.X * 0.36 / cw)
		else
			local area = gui.AbsoluteSize.Y > 0 and gui.AbsoluteSize.Y or vp.Y
			controlsY = math.min(CONTROLS_Y, (0.56 * area - ch * c / 2) / area)
		end
	end
	controlsFit.Scale = c
	controlsP.Position = UDim2.fromScale(0.5, controlsY)
end
local function fitHud()
	fitKeyHints(); fitPanels()
	if Horn.IsAvailable() then layoutHorn() end   -- the touch horn's spot depends on the width
end
local function watchCamera()
	local cam = workspace.CurrentCamera
	if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(fitHud) end
	fitHud()
end
watchCamera()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)

---------------------------------------------------------------- controls popup
-- Getting onto the scooter brings up this rider's own controls and nothing of the
-- other job: the Driver steers, the Passenger (the motor) makes it go. Keyboard keys
-- or the touch buttons, whichever this player is using (keyboardHints), switched
-- over if that changes while it is up. Start or CONTROLS_TIME puts it away, and it
-- never outlives the ride. It only informs: the ride's controls work all along.
-- While it is up it is MODAL (UITemplates.Menus.Modal): no menu opens, and the
-- top-bar Invite Friends and Settings buttons take no input until it goes.
local CONTROLS_TIME = 8
local CONTROLS = {
	Driver = {
		keys  = { { "\u{2022} Hold A", "Steer left" }, { "\u{2022} Hold D", "Steer right" } },
		touch = { { "\u{2022} Left arrow", "Steer left" }, { "\u{2022} Right arrow", "Steer right" } },
		pad   = { { "\u{2022} Left stick", "Steer" }, { "\u{2022} Triangle / Y", "Horn" } },
	},
	Passenger = {
		-- the brake is keyboard-only (Space); touch has no button for it
		keys  = { { "\u{2022} Hold W", "Accelerate" }, { "\u{2022} Hold S", "Reverse" },
		          { "\u{2022} Hold Space", "Brake" } },
		touch = { { "\u{2022} Right pedal", "Accelerate" }, { "\u{2022} Left pedal", "Reverse" } },
		pad   = { { "\u{2022} Hold R2 / RT", "Accelerate" }, { "\u{2022} Hold L2 / LT", "Reverse" },
		          { "\u{2022} Hold Square / X", "Brake" } },
	},
}
-- rows a set does not fill are hidden, so every other set keeps its two-row look
local controlRows = {}
for i = 1, 3 do
	local row = controlsCard:WaitForChild("Row" .. i)
	controlRows[i] = { row = row, key = row:WaitForChild("Key"), action = row:WaitForChild("Action") }
end
local controlsPanel = Panel.new(controlsP, 0)
local controlsRole, controlsToken = nil, 0

local function fillControls()
	local set = controlsRole and CONTROLS[controlsRole]
	if not set then return end
	-- a controller that was the last thing used (a console always is) gets its own lines
	local last = UIS:GetLastInputType()
	local pad = last.Name:sub(1, 7) == "Gamepad"
		or (UIS.GamepadEnabled and not UIS.KeyboardEnabled and not UIS.TouchEnabled)
	local lines = (pad and set.pad) or (keyboardHints() and set.keys) or set.touch
	for i, r in ipairs(controlRows) do
		local line = lines[i]
		r.row.Visible = line ~= nil
		r.key.Text, r.action.Text = line and line[1] or "", line and line[2] or ""
	end
end

local function hideControls()
	controlsToken += 1
	controlsRole = nil
	controlsPanel:Hide()
	Menus.Modal("RideControls", false)   -- everything else works again at once
end

local function showControls(role)
	if not CONTROLS[role] then return end
	controlsToken += 1; local tok = controlsToken
	controlsRole = role
	fillControls()
	fitPanels()
	controlsPanel.basePos = UDim2.fromScale(0.5, controlsY)   -- where fitPanels put it for this screen
	controlsPanel:Show()
	Menus.Modal("RideControls", true)    -- the open menu closes; nothing else can be used
	task.delay(CONTROLS_TIME, function() if controlsToken == tok then hideControls() end end)
end

startBtn.Activated:Connect(function()
	if not controlsRole then return end
	play("Click")
	hideControls()
end)
UIS.LastInputTypeChanged:Connect(function() if controlsRole then fillControls() end end)

---------------------------------------------------------------- checkpoint selector
-- The Driver picks the start in the CheckpointSelector window (ReplicatedStorage):
-- START sends the pick and readies up in one go; LEAVE leaves the queue, like EXIT.
-- It shows every checkpoint in Shared.Checkpoints, as the server sends it for this pair:
-- one not released says COMING SOON, one past the lower of the two players' progress
-- says LOCKED; neither can be started (the server refuses them too). The server sends
-- the list again when either player's progress changes, and an open window follows it.
local selectorOpen = false   -- the window is up for this booth session
local startPending = false   -- START was sent; the countdown comes next
local startToken   = 0
local lastState

local shownMenu = ""   -- what the open window is showing, to spot a changed list
local function menuKey(menu)
	local parts = {}
	for _, cp in ipairs(menu or {}) do
		table.insert(parts, tostring(cp.Id) .. (cp.Unlocked == false and "-" or "") .. (cp.Locked and "L" or ""))
	end
	return table.concat(parts, ",")
end

local function openSelector(state)
	selectorOpen = CheckpointSelector.Open(state.Menu or {}, state.CheckpointId)
	shownMenu = menuKey(state.Menu)
	return selectorOpen
end

-- the pair's list changed while the window is up (a save loaded, a partner's progress):
-- show the new one, staying on the card that was picked
local function refreshSelector(state)
	local key = menuKey(state.Menu)
	if key == shownMenu then return end
	shownMenu = key
	local current = CheckpointSelector.GetSelectedCheckpoint()
	CheckpointSelector.Open(state.Menu or {}, current and current.Id or state.CheckpointId)
end

local function closeSelector()
	if selectorOpen then
		selectorOpen = false
		CheckpointSelector.Close()
	end
end

---------------------------------------------------------------- render
-- While the death popup (StarterGui.DeathGui: SKIP / REVIVE) is up, the touch pedals
-- and steering arrows go: the scooter is down and they would sit under the popup.
-- They come back if the ride carries on (a revive), and never outlive the ride.
local down = false

-- the touch panel for this player's job, while riding and not down
local function applyRidePanels()
	local touch = UIS.TouchEnabled and riding and not down
	apply({
		drive = (touch and myRole == "Driver") or false,
		motor = (touch and myRole == "Passenger") or false,
	})
end

-- the checkpoint this booth session is starting from: the server sends it while choosing and
-- counting down, then clears it at launch, so it's remembered here for the boarding moment
local FIRST_CHECKPOINT = Checkpoints.ByOrder(1) and Checkpoints.ByOrder(1).Id
local startCheckpointId = nil

local function render(state)
	lastState = state
	local phase = state and state.Phase or "None"
	if phase == "None" or phase == "Empty" or phase == "Waiting" then
		startCheckpointId = nil
	elseif phase ~= "Riding" and state.CheckpointId then
		startCheckpointId = state.CheckpointId
	end
	if state and type(state.Notice) == "string" then showNotice(state.Notice) end

	if phase ~= "Riding" and riding then
		riding, down = false, false
		Horn.SetRider(nil)   -- the horn stops at once, and its button goes
		for _, release in ipairs(releaseTouch) do release() end
		touchSteer, touchMotor = 0, nil
		steerKeys.left, steerKeys.right = false, false
		motorKeys.go, motorKeys.back, motorKeys.brake = false, false, false
		lastSteer, lastThrottle, lastBrake = nil, nil, nil
		localSteer = 0
		characterInput(true)
		-- hand the vehicle back to neutral: getting off must never leave it driving
		Remotes.DriveInput:FireServer({ Steer = 0 })
		Remotes.DriveInput:FireServer({ Throttle = "coast", Brake = false })
		myRole = nil
		refreshKeyHints()
		hideControls()
	end

	-- the checkpoint window only belongs to the choosing phases
	if phase ~= "Selecting" and phase ~= "Ready" then
		closeSelector()
		startPending = false
	end
	-- EXIT works until GO!: from then on the server is putting the ride together
	exitBtn.Interactable = (phase ~= "Launched")

	if phase == "None" or phase == "Empty" then
		apply({}); return
	end

	if phase == "Waiting" then
		setStatus(WAITING_TEXT)
		apply({ booth = true })

	elseif phase == "Selecting" or phase == "Ready" then
		-- only with Config.CheckpointPicker on: the Driver picks the start first
		if state.CanPick then
			if selectorOpen and not startPending then refreshSelector(state) end
			if startPending or selectorOpen or openSelector(state) then
				apply({})   -- the window has its own LEAVE; after START the countdown is a moment away
			else
				setStatus("No checkpoint\nopen yet")
				apply({ booth = true })
			end
		else
			setStatus((phase == "Ready") and "Driver is\nstarting.." or "Driver is\nchoosing..")
			apply({ booth = true })
		end

	elseif phase == "Countdown" or phase == "Launched" then
		-- the server's count, pushed to both riders every second, so both panels step together
		local n = (phase == "Countdown" and tonumber(state.Countdown)) or 0
		setStatus(n > 0 and ("Starting in %d..."):format(n) or "GO!", true)
		apply({ booth = true })

	elseif phase == "Riding" then
		local boarding = not riding   -- once per ride, not on every push
		riding, myRole = true, state.Role
		Horn.SetRider(state.Role)
		refreshKeyHints()   -- A D or W S for this role, on a keyboard
		characterInput(false)
		-- touch panels only, and only the one for this player's job
		applyRidePanels()
		-- the controls popup is for a fresh start only (rides from checkpoint 1), and only
		-- once per player ever: the server remembers it in their save (ControlsPopupServer)
		if boarding and startCheckpointId == FIRST_CHECKPOINT then
			local role = state.Role
			task.spawn(function()
				local remote = Remotes:WaitForChild("ControlsPopup", 10)
				local ok, show = false, false
				if remote then ok, show = pcall(remote.InvokeServer, remote) end
				if ok and show == true and riding and myRole == role then showControls(role) end
			end)
		end
	end
end

---------------------------------------------------------------- steering (Driver's machine)
-- The Driver's machine simulates the scooter (RiderAttach gives it network ownership), so
-- it turns the fork itself the moment A/D (or an arrow) changes, instead of a network round
-- trip later when the server's answer arrives. Exactly the same maths as the server
-- (ReplicatedStorage.ScooterSystem.Shared.Steering), which still steers whenever the server
-- is the one simulating the scooter. The server stays in charge of who may steer: only the
-- Driver's inputs reach its copy, and only the Driver's machine runs this.
local RunService = game:GetService("RunService")
local Steering   = require(RS:WaitForChild("ScooterSystem"):WaitForChild("Shared"):WaitForChild("Steering"))
local steerNow = 0
local steerChassis, steerServos = nil, nil

local function drivenChassis()
	local ch   = Players.LocalPlayer.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local weld = root and root:FindFirstChild("ScooterRiderWeld")
	if not weld or weld:GetAttribute("Role") ~= "Driver" then return nil end
	return weld.Part0
end

RunService.PreSimulation:Connect(function(dt)
	local chassis = (riding and myRole == "Driver" and not down) and drivenChassis() or nil
	if chassis ~= steerChassis then
		steerChassis, steerServos, steerNow = chassis, nil, 0
	end
	if not (chassis and chassis.Parent) then return end
	if not steerServos or next(steerServos) == nil then
		steerServos = {}
		for _, d in ipairs(chassis.Parent:GetDescendants()) do
			if d:IsA("HingeConstraint") and d.ActuatorType == Enum.ActuatorType.Servo then
				steerServos[d] = Steering.Sign(d, chassis.CFrame)
			end
		end
	end
	steerNow = Steering.Ramp(steerNow, localSteer, dt)
	local angle = Steering.Angle(steerNow, chassis.AssemblyLinearVelocity:Dot(chassis.CFrame.LookVector))
	for servo, sign in pairs(steerServos) do
		local target = sign * angle
		if servo.TargetAngle ~= target then servo.TargetAngle = target end
	end
end)

Remotes.StateChanged.OnClientEvent:Connect(render)

-- DeathManager: { Active = true } when the scooter goes into the water, false when
-- the popup is done with. A pedal or arrow still held is let go as they hide. Back up
-- again (a revive: a new scooter): nothing held from before counts until it is pressed
-- afresh, and the new scooter hears every control anew.
Remotes:WaitForChild("DeathState").OnClientEvent:Connect(function(s)
	local now = type(s) == "table" and s.Active == true and riding
	if now == down then return end
	down = now
	if down then
		for _, release in ipairs(releaseTouch) do release() end
		touchSteer, touchMotor = 0, nil
		hideControls()   -- the controls popup too, if it is still up
	else
		steerKeys.left, steerKeys.right = false, false
		motorKeys.go, motorKeys.back, motorKeys.brake = false, false, false
		lastSteer, lastThrottle, lastBrake = nil, nil, nil
		localSteer = 0
	end
	if riding then applyRidePanels() end
end)

-- A cutscene took the player (Cinematic), or let them go. Taking: every held horn and
-- pedal lets go (its screen is hidden meanwhile, so they would never come up) and the
-- scooter is told to stop. Letting go: nothing held from before counts - a key still
-- down drives again only once it is pressed afresh, so nobody shoots off the moment the
-- game fades back in.
Cinematic.Changed:Connect(function(active)
	if active then
		Horn.ReleaseAll()
		for _, release in ipairs(releaseTouch) do release() end
		touchSteer, touchMotor = 0, nil
	else
		steerKeys.left, steerKeys.right = false, false
		motorKeys.go, motorKeys.back, motorKeys.brake = false, false, false
	end
	characterInput(not riding)
	pushInput()
end)

-- The server sending this player home after a run (RideManager.SendHome). This
-- machine simulates its own character, so it makes the move too: a move made only
-- by the server can be undone by the old position still in flight from here.
Remotes:WaitForChild("ReturnHome").OnClientEvent:Connect(function(cf)
	local ch   = Players.LocalPlayer.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if typeof(cf) ~= "CFrame" or not root then return end
	ch:PivotTo(cf)
	root.AssemblyLinearVelocity = Vector3.zero
end)
exitBtn.Activated:Connect(function() play("Click"); Remotes.ExitCapsule:FireServer() end)

CheckpointSelector.CheckpointSelected:Connect(function(checkpoint)
	if not selectorOpen then return end        -- not the booth's window (the Studio preview)
	selectorOpen, startPending = false, true
	startToken += 1
	local tok = startToken
	Remotes.SelectCheckpoint:FireServer(checkpoint.Id)
	Remotes.ReadyUp:FireServer()
	-- nothing came of it (the server turned it down): offer the window again
	task.delay(3, function()
		if startPending and startToken == tok then
			startPending = false
			render(lastState)
		end
	end)
end)
CheckpointSelector.Closed:Connect(function(reason)
	if reason == "Leave" and selectorOpen then Remotes.ExitCapsule:FireServer() end
	selectorOpen = false
end)

for _, p in pairs(panels) do
	p.frame.Visible = false
	if p.shadow then p.shadow.Visible = false end
end
hornP.Visible = false
keysP.Visible = false
controlsP.Visible = false
