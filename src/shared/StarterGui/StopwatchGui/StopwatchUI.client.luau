--=====================================================================
-- StopwatchUI   (StarterGui.StopwatchGui)
--
-- The stopwatch button in the top bar, left of Invite Friends: it shows and
-- hides the course stopwatch (StarterGui.RunTimerGui). OFF by default; the player's
-- choice is saved to their account with their other settings ("Stopwatch" in
-- ReplicatedStorage.SettingsSystem) and comes back next time they play. It only
-- switches the display - the run is timed by the server either way, so turning
-- it on mid-ride shows the time the duo is already on.
--   gui:GetAttribute("On")   read by RunTimerClient
-- Styled and animated like the Settings gear (SettingsUI); it comes and goes
-- with the Invite pill (HudSync.OnInGame), i.e. only while in a booth / riding.
--=====================================================================

local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HudSync = require(ReplicatedStorage:WaitForChild("HudSync"))
local Menus   = require(ReplicatedStorage:WaitForChild("UITemplates"):WaitForChild("Menus"))
local Settings = require(ReplicatedStorage:WaitForChild("SettingsSystem"):WaitForChild("SettingsController"))

local gui        = script.Parent
local container  = gui:WaitForChild("Container")
local scaleObj   = container:WaitForChild("Scale")
local hint       = container:WaitForChild("Hint")
local hintStroke = hint:WaitForChild("UIStroke")
local btn        = container:WaitForChild("StopwatchButton")
local stroke     = btn:WaitForChild("Edge")
local btnSweep   = btn:WaitForChild("Sweep")
local watch      = btn:WaitForChild("Watch")
local watchScale = watch:WaitForChild("WatchScale")
local face       = watch:WaitForChild("Face")
local ring       = face:WaitForChild("Ring")
local hand       = face:WaitForChild("Hand")
local sfxHover   = gui:WaitForChild("SfxHover")
local sfxPress   = gui:WaitForChild("SfxPress")

local LOCAL_SIZE = 44
local WHITE      = Color3.new(1, 1, 1)
local ACCENT     = Color3.fromRGB(255, 205, 64)   -- the stopwatch's gold / the menus' yellow
local STROKE_COLOR = stroke.Color
local REST_STROKE_T,  REST_STROKE_W  = stroke.Transparency, stroke.Thickness
local HOVER_STROKE_T, HOVER_STROKE_W = 0.45, 1.8
local ON_STROKE_T,    ON_STROKE_W    = 0.1, 2
local BG_REST = btn.BackgroundColor3
local BG_ON   = BG_REST:Lerp(Color3.fromRGB(70, 86, 128), 0.45)

-- every white part of the icon, tinted together
local iconParts = {}
for _, d in ipairs(watch:GetDescendants()) do
	if d:IsA("Frame") and d.BackgroundTransparency < 1 then table.insert(iconParts, d) end
end

gui:SetAttribute("On", Settings:Get("Stopwatch") == true)   -- off by default, until the saved choice loads

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

local sweepTween
local function playSweep(dur)
	local grad = btnSweep:FindFirstChild("SweepGradient")
	if not grad then return end
	if sweepTween then sweepTween:Cancel() end
	btnSweep.Visible = true
	grad.Offset = Vector2.new(-1.3, 0)
	sweepTween = TweenService:Create(grad, TweenInfo.new(dur or 0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Offset = Vector2.new(1.3, 0) })
	sweepTween:Play()
	sweepTween.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed then btnSweep.Visible = false end
	end)
end

--------------------------------------------------------------------- state
local introDone, inGame = false, HudSync.InGame()
local hovering, pressed = false, false
local on = false

local sCur, sVel     = 0, 0
local rotCur, rotVel = 0, 0
local onA            = 0
local handRot        = 0
local iconHover      = 1
local strT, strW     = REST_STROKE_T, REST_STROKE_W
local hintA          = 0
local t              = 0

local function shown() return introDone and inGame end

HudSync.WhenIntroDone(function()
	introDone = true
	if shown() then sCur, sVel = HudSync.POP_FROM, HudSync.POP_VEL end
end)
HudSync.OnInGame(function(now)
	inGame = now
	if not now then hovering, pressed = false, false end
	if shown() then
		sCur, sVel = HudSync.POP_FROM, HudSync.POP_VEL
		task.delay(0.34, function() if shown() then playSweep(0.6) end end)
	end
end)

--------------------------------------------------------------------- frame loop
RunService.RenderStepped:Connect(function(dt)
	dt = math.min(dt, 1 / 30)
	t += dt

	local sTarget = 0
	if shown() then
		sTarget = pressed and 0.93 or (hovering and 1.06 or 1)
	end
	sCur, sVel = springStep(sCur, sVel, sTarget, HudSync.STIFFNESS, HudSync.DAMPING, dt)
	scaleObj.Scale = math.max(sCur, 0.01)
	container.Visible = shown() or sCur > 0.05
	if not container.Visible then return end

	rotCur, rotVel = springStep(rotCur, rotVel, pressed and 1.8 or 0, 320, 17, dt)
	btn.Rotation = rotCur

	onA = approach(onA, on and 1 or 0, 10, dt)

	-- the hand sweeps round while on, and settles back to 12 o'clock when off
	if on then
		handRot = (handRot + dt * 180) % 360
	else
		handRot = approach(handRot, handRot > 180 and 360 or 0, 9, dt)
	end
	hand.Rotation = handRot
	iconHover = approach(iconHover, hovering and 1.08 or 1, 12, dt)
	watchScale.Scale = iconHover + math.sin(t * 0.9) * 0.014
	watch.Rotation = math.sin(t * 1.15) * 1.5

	local tint = WHITE:Lerp(ACCENT, onA)
	ring.Color = tint
	for _, p in ipairs(iconParts) do p.BackgroundColor3 = tint end

	local restT = REST_STROKE_T + math.sin(t * 1.9) * 0.05
	local baseT = hovering and HOVER_STROKE_T or restT
	local baseW = hovering and HOVER_STROKE_W or REST_STROKE_W
	strT = approach(strT, baseT + (ON_STROKE_T - baseT) * onA, 11, dt)
	strW = approach(strW, baseW + (ON_STROKE_W - baseW) * onA, 11, dt)
	stroke.Transparency = strT
	stroke.Thickness    = strW
	stroke.Color        = STROKE_COLOR:Lerp(ACCENT, onA)
	btn.BackgroundColor3 = BG_REST:Lerp(BG_ON, onA)

	hintA = approach(hintA, hovering and 1 or 0, 14, dt)
	hint.Position               = UDim2.new(1, 0, 1 + (2 + 6 * hintA) / LOCAL_SIZE, 0)
	hint.BackgroundTransparency = 1 - 0.86 * hintA
	hint.TextTransparency       = 1 - hintA
	hintStroke.Transparency     = 1 - 0.75 * hintA
end)

--------------------------------------------------------------------- input
local function setOn(v)
	on = v
	gui:SetAttribute("On", on)
	hint.Text = on and "Hide stopwatch" or "Show stopwatch"
end
-- the saved choice: whatever the player last left it on (off until their settings load)
setOn(Settings:Get("Stopwatch") == true)
onA = on and 1 or 0
Settings.Changed:Connect(function(key, value)
	if key == "Stopwatch" and value ~= on then setOn(value == true) end
end)

btn.MouseEnter:Connect(function()
	if isTouch() or not shown() then return end
	hovering = true
	sfxHover:Play()
	playSweep(0.5)
end)
btn.MouseLeave:Connect(function() hovering, pressed = false, false end)
btn.MouseButton1Down:Connect(function()
	if not shown() then return end
	pressed = true
	sfxPress.PlaybackSpeed = 1
	sfxPress:Play()
end)
btn.MouseButton1Up:Connect(function() pressed = false end)
btn.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		pressed = false
		if isTouch() then hovering = false end
	end
end)
btn.Selectable = true
btn.SelectionGained:Connect(function() hovering = true; playSweep(0.5) end)
btn.SelectionLost:Connect(function() hovering = false end)

btn.Activated:Connect(function()
	if not shown() then return end
	setOn(not on)
	Settings:Set("Stopwatch", on, true)   -- remembered on their account
	if on then playSweep(0.5) end
end)
-- the ride's controls popup is modal: no input while it is up
Menus.Lockable(btn, function() hovering, pressed = false, false end)

container.Visible = false
