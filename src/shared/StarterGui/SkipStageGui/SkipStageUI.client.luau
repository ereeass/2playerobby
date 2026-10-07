--=====================================================================
-- SkipStageUI   (StarterGui.SkipStageGui)
--
-- The Skip Stage button while riding. It only ASKS: pressing it calls Remotes.SkipStage and
-- the server (ServerScriptService.ScooterSystem.SkipStage) decides everything - whether this
-- ride can skip, opening Roblox's purchase prompt, and the skip itself once the purchase is
-- confirmed. Nothing here can move a scooter or touch the stopwatch.
--   Shown    while this player's ride can skip (their SkipStageTo attribute, set by the
--            server), never during the finish cutscene (Cinematic), and only once the product
--            is set up (Shared.Config.SkipStageProductId) or they have a free skip saved.
--   Says     "Skip Stage", "..." while a prompt is open on this scooter (SkipStageBusy), or
--            briefly why a press did nothing - always in the middle of the button.
--   Badge    saved free skips (SkipCredits): the red count on the top-right corner (the shared
--            UITemplates.CountBadge). A press spends one with no prompt (the server does),
--            and the count goes at 0.
--   Where    a keyboard: bottom centre (it steps aside while the ride's notice is up there).
--            A touch screen: just right of the horn, sized down so it never reaches the
--            Driver's right arrow or the Motor's gas pedal.
-- The ride's Start / Exit buttons' make: FredokaOne, a glossy two-tone face, a dark 3 px
-- edge, 12 px corners, the same hover pop and click.
--=====================================================================

local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local UIS                = game:GetService("UserInputService")
local TS                 = game:GetService("TweenService")
local RS                 = game:GetService("ReplicatedStorage")

local Root      = RS:WaitForChild("ScooterSystem")
local Config    = require(Root:WaitForChild("Shared"):WaitForChild("Config"))
local Cinematic = require(Root:WaitForChild("Cinematic"))
local Menus     = require(RS:WaitForChild("UITemplates"):WaitForChild("Menus"))
local CountBadge = require(RS:WaitForChild("UITemplates"):WaitForChild("CountBadge"))
local remote    = Root:WaitForChild("Remotes"):WaitForChild("SkipStage")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui       = script.Parent
local holder    = gui:WaitForChild("Holder")
local fit       = holder:WaitForChild("Fit")
local button    = holder:WaitForChild("Button")
local press     = button:WaitForChild("Press")
local label     = button:WaitForChild("Label")

local PRODUCT     = tonumber(Config.SkipStageProductId) or 0
local DESIGN_W    = holder.Size.X.Offset
local DESIGN_H    = holder.Size.Y.Offset
local TOUCH_H     = 48      -- px tall on a touch screen: the horn's face is the same (RideGui.Controller)
local TOUCH_SCALE = TOUCH_H / DESIGN_H
local TOUCH_MIN_W = 110     -- narrower than this (design px) and it doesn't fit at all
local TOUCH_GAP   = 10      -- px between the horn and the button
local CLEAR       = 8       -- px kept clear of the arrow / pedal
local PC_BOTTOM   = 18      -- px above the bottom edge on a keyboard
local TEXT        = "Skip Stage"

---------------------------------------------------------------- the ride's HUD (placement)
-- RideGui never resets, but is looked up each time so nothing here can go stale
local function rideGui() return playerGui:FindFirstChild("RideGui") end
local function find(root, ...)
	local o = root
	for _, name in ipairs({ ... }) do
		o = o and o:FindFirstChild(name)
	end
	return o
end

-- keyboard or touch, as the ride's own controls decide it (RideGui.Controller)
local PC_INPUT = {
	[Enum.UserInputType.Keyboard] = true, [Enum.UserInputType.MouseMovement] = true,
	[Enum.UserInputType.MouseButton1] = true, [Enum.UserInputType.MouseButton2] = true,
	[Enum.UserInputType.MouseButton3] = true, [Enum.UserInputType.MouseWheel] = true,
}
local function keyboard()
	if not UIS.KeyboardEnabled then return false end
	if not UIS.TouchEnabled then return true end
	return PC_INPUT[UIS:GetLastInputType()] == true
end

local function layout()
	local r = rideGui()
	local face = r and find(r, "HornControls", "Horn", "Face")
	local hornShown = face and find(r, "HornControls").Visible
	if keyboard() or not hornShown then
		holder.AnchorPoint = Vector2.new(0.5, 1)
		holder.Position = UDim2.new(0.5, 0, 1, -PC_BOTTOM)
		fit.Scale = keyboard() and 1 or TOUCH_SCALE
		holder.Size = UDim2.fromOffset(DESIGN_W, DESIGN_H)
		return
	end
	-- touch: right of the horn, level with it, as wide as the room up to the first control
	local origin = gui.AbsolutePosition
	local left = face.AbsolutePosition.X + face.AbsoluteSize.X + TOUCH_GAP
	local right = gui.AbsolutePosition.X + gui.AbsoluteSize.X - CLEAR
	for _, path in ipairs({
		{ "DriverControls", "SteerRight" },
		{ "MotorControls", "Pedals", "Accelerator" },
		{ "MotorControls", "Pedals", "Accelerator", "Art" },
	}) do
		local o = find(r, table.unpack(path))
		if o and o.AbsoluteSize.X > 0 then right = math.min(right, o.AbsolutePosition.X - CLEAR) end
	end
	-- always the horn's height; a tight screen makes it narrower, not shorter
	fit.Scale = TOUCH_SCALE
	holder.Size = UDim2.fromOffset(math.clamp(math.floor((right - left) / TOUCH_SCALE), TOUCH_MIN_W, DESIGN_W), DESIGN_H)
	holder.AnchorPoint = Vector2.new(0, 0.5)
	holder.Position = UDim2.fromOffset(
		math.round(left - origin.X),
		math.round(face.AbsolutePosition.Y + face.AbsoluteSize.Y / 2 - origin.Y))
end

---------------------------------------------------------------- what it shows
-- saved free skips: the red count on the corner, shown and hidden by itself
CountBadge.Attach(button, "SkipCredits")

local asking = false       -- waiting for the server's answer to a press
local flashText, flashToken = nil, 0
local shownBefore = false

local function refresh()
	local credits = tonumber(player:GetAttribute("SkipCredits")) or 0
	local to = player:GetAttribute("SkipStageTo")
	local want = to ~= nil and (PRODUCT ~= 0 or credits > 0) and not Cinematic.IsActive()
	if want and keyboard() then
		-- a keyboard's spot is the ride's notice's spot too: it steps aside meanwhile
		local notice = find(rideGui(), "Notice")
		if notice and notice.Visible then want = false end
	end
	if want ~= holder.Visible then
		holder.Visible = want
		if want and not shownBefore then
			press.Scale = 0.6
			TS:Create(press, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
		shownBefore = want
	end
	if not want then return end

	local busy = asking or player:GetAttribute("SkipStageBusy") == true
	local text = flashText or (busy and "..." or TEXT)
	if label.Text ~= text then label.Text = text end
end

local function flash(text)
	flashToken += 1
	local token = flashToken
	flashText = text
	refresh()
	task.delay(2.2, function()
		if flashToken == token then
			flashText = nil
			refresh()
		end
	end)
end

---------------------------------------------------------------- press
local function sound(name)
	local s = find(rideGui(), "Sfx", name)
	if s then s:Play() end
end

local hover, down = false, false
local function look()
	TS:Create(press, TweenInfo.new(down and 0.07 or 0.2, down and Enum.EasingStyle.Quad or Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = down and 0.93 or (hover and 1.05 or 1) }):Play()
end
button.MouseEnter:Connect(function()
	if UIS.TouchEnabled and not UIS.MouseEnabled then return end
	hover = true
	sound("Hover")
	look()
end)
button.MouseLeave:Connect(function() hover, down = false, false; look() end)
button.MouseButton1Down:Connect(function() down = true; look() end)
button.InputEnded:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
		down = false
		look()
	end
end)

button.Activated:Connect(function()
	if asking or not holder.Visible or player:GetAttribute("SkipStageBusy") == true then return end
	asking = true
	sound("Click")
	refresh()
	task.spawn(function()
		local ok, done, why = pcall(function() return remote:InvokeServer() end)
		asking = false
		if not ok then
			flash("Try again")
		elseif not done and type(why) == "string" then
			flash(why)
		else
			refresh()
		end
	end)
end)
-- a modal popup (the ride's controls card) takes the screen: no presses meanwhile
Menus.Lockable(button, function() hover, down = false, false; look() end)

---------------------------------------------------------------- follow
for _, attr in ipairs({ "SkipStageTo", "SkipStageBusy", "SkipCredits" }) do
	player:GetAttributeChangedSignal(attr):Connect(refresh)
end
Cinematic.Changed:Connect(refresh)
UIS.LastInputTypeChanged:Connect(refresh)
-- Placed again only when the layout really changes (screen size, touch / keyboard, which
-- controls this rider has) - never because the horn, an arrow or a pedal shrinks while it's
-- pressed, which would drag the button along with it. Measured again once any show
-- animation has settled.
local function layoutKey()
	local r = rideGui()
	local cam = workspace.CurrentCamera
	local function vis(name) local o = find(r, name); return o and o.Visible and "1" or "0" end
	return table.concat({ tostring(cam and cam.ViewportSize), tostring(gui.AbsoluteSize), tostring(keyboard()),
		vis("DriverControls"), vis("MotorControls"), vis("HornControls"), tostring(holder.Visible) }, "|")
end
local lastKey
local function place()
	if not holder.Visible then lastKey = nil return end
	local k = layoutKey()
	if k == lastKey then return end
	lastKey = k
	layout()
	task.delay(0.6, function() if holder.Visible and lastKey == k then layout() end end)
end
-- the notice comes and goes: keep up while it's shown
local since = 0
RunService.RenderStepped:Connect(function(dt)
	since += dt
	if since < 0.1 then return end
	since = 0
	if holder.Visible or player:GetAttribute("SkipStageTo") ~= nil then refresh() end
	place()
end)
refresh()
