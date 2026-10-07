--=====================================================================
-- RespawnUI   (StarterGui.RespawnGui)
--
-- The Respawn button while riding. It only asks (Remotes.Respawn): the server (ScooterSystem
-- Main) ends the ride for BOTH riders and respawns them both at the lobby spawn.
--   Shown    while this player is on a ride (Remotes.StateChanged "Riding"), never while
--            the ride is down (the death popup has it) or during the finish cutscene.
--   Where    a keyboard: just above the horn, at the left edge. A touch screen: top left,
--            above the Driver's left arrow / the Motor's brake pedal, sized down so it never
--            reaches them.
-- The Skip Stage button's make (the ride's Exit button's red): FredokaOne, a glossy two-tone
-- face, a dark 3 px edge, 12 px corners, the same hover pop and click.
--=====================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS     = game:GetService("UserInputService")
local TS      = game:GetService("TweenService")
local RS      = game:GetService("ReplicatedStorage")

local Root      = RS:WaitForChild("ScooterSystem")
local Remotes   = Root:WaitForChild("Remotes")
local Cinematic = require(Root:WaitForChild("Cinematic"))
local Menus     = require(RS:WaitForChild("UITemplates"):WaitForChild("Menus"))
local remote    = Remotes:WaitForChild("Respawn")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui       = script.Parent
local holder    = gui:WaitForChild("Holder")
local fit       = holder:WaitForChild("Fit")
local button    = holder:WaitForChild("Button")
local press     = button:WaitForChild("Press")
local confirm   = gui:WaitForChild("Confirm")
local confirmFit = confirm:WaitForChild("Fit")
local confirmPop = confirm:WaitForChild("Pop")
local yesBtn    = confirm:WaitForChild("Card"):WaitForChild("Yes")
local noBtn     = confirm.Card:WaitForChild("No")

local DESIGN_H    = holder.Size.Y.Offset
local TOUCH_SIZE  = holder.Size                                -- "Respawn"
local PC_SIZE     = UDim2.fromOffset(186, DESIGN_H)            -- "Respawn (R)"
local KEY         = Enum.KeyCode.R                             -- opens the Yes / No popup on a keyboard
local label       = holder:WaitForChild("Button"):WaitForChild("Label")
local TOUCH_SCALE = 0.72    -- on a touch screen: at most this size...
local TOUCH_MIN   = 0.5     -- ...and never smaller than this
local GAP         = 10      -- px above the horn (keyboard)
local TOUCH_GAP   = 34      -- px above the arrow / pedal (touch)
local EDGE        = 14      -- px from the left edge on a touch screen
local TOP         = 8       -- px kept clear under the top of the screen

---------------------------------------------------------------- the ride's HUD (placement)
local function rideGui() return playerGui:FindFirstChild("RideGui") end
local function find(root, ...)
	local o = root
	for _, name in ipairs({ ... }) do o = o and o:FindFirstChild(name) end
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
	local origin = gui.AbsolutePosition
	if keyboard() then
		-- above the horn, lined up with its left edge
		local face = find(r, "HornControls", "Horn", "Face")
		fit.Scale = 1
		holder.Size = PC_SIZE
		label.Text = "Respawn (R)"
		holder.AnchorPoint = Vector2.new(0, 1)
		if face and face.AbsoluteSize.X > 0 then
			holder.Position = UDim2.fromOffset(math.round(face.AbsolutePosition.X - origin.X),
				math.round(face.AbsolutePosition.Y - GAP - origin.Y))
		else
			holder.Position = UDim2.new(0, 16, 0.6, -46)
		end
		return
	end
	-- touch: top left, above whichever control this rider has on the left
	holder.Size = TOUCH_SIZE
	label.Text = "Respawn"
	local below
	for _, path in ipairs({ { "DriverControls", "SteerLeft" }, { "MotorControls", "Pedals", "Brake", "Art" } }) do
		local panel = find(r, path[1])
		local o = find(r, table.unpack(path))
		if panel and panel.Visible and o and o.AbsoluteSize.Y > 0 then
			below = math.min(below or math.huge, o.AbsolutePosition.Y)
		end
	end
	local bottom = (below or (origin.Y + gui.AbsoluteSize.Y * 0.55)) - TOUCH_GAP
	local room = bottom - (origin.Y + TOP)
	fit.Scale = math.clamp(room / DESIGN_H, TOUCH_MIN, TOUCH_SCALE)
	holder.AnchorPoint = Vector2.new(0, 1)
	holder.Position = UDim2.fromOffset(EDGE, math.round(bottom - origin.Y))
end

---------------------------------------------------------------- when it shows
local riding, down, sent = false, false, false

-- "Are you sure you want to respawn?" Yes / No, in the middle of the screen
local openedAt = 0
local function showConfirm(on)
	if on == confirm.Visible then return end
	confirm.Visible = on
	if on then
		openedAt = os.clock()
		Menus.CloseCurrent()   -- an open menu (Settings, Scooters) makes way, as menus do for each other
		local cam = workspace.CurrentCamera
		local short = cam and math.min(cam.ViewportSize.X, cam.ViewportSize.Y) or 720
		confirmFit.Scale = math.clamp(short / 720, 0.6, 1.2)   -- the same size on every screen
		confirmPop.Scale = 0.7
		TS:Create(confirmPop, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

local function refresh()
	local want = riding and not down and not sent and not Cinematic.IsActive()
	if want ~= holder.Visible then
		holder.Visible = want
		if want then
			press.Scale = 0.6
			TS:Create(press, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end
	if not want then showConfirm(false) end
end

Remotes:WaitForChild("StateChanged").OnClientEvent:Connect(function(state)
	local now = type(state) == "table" and state.Phase == "Riding"
	if now and not riding then sent = false end   -- a new ride
	riding = now
	if not now then down = false end
	refresh()
end)
Remotes:WaitForChild("DeathState").OnClientEvent:Connect(function(s)
	down = type(s) == "table" and s.Active == true
	refresh()
end)
Cinematic.Changed:Connect(refresh)
UIS.LastInputTypeChanged:Connect(refresh)

---------------------------------------------------------------- press
local function sound(name)
	local s = find(rideGui(), "Sfx", name)
	if s then s:Play() end
end

local hover, held = false, false
local function look()
	TS:Create(press, TweenInfo.new(held and 0.07 or 0.2, held and Enum.EasingStyle.Quad or Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = held and 0.93 or (hover and 1.05 or 1) }):Play()
end
button.MouseEnter:Connect(function()
	if UIS.TouchEnabled and not UIS.MouseEnabled then return end
	hover = true
	sound("Hover")
	look()
end)
button.MouseLeave:Connect(function() hover, held = false, false; look() end)
button.MouseButton1Down:Connect(function() held = true; look() end)
button.InputEnded:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
		held = false
		look()
	end
end)
button.Activated:Connect(function()
	if not holder.Visible or sent then return end
	-- it only asks: the popup's Yes respawns. Pressed again while the popup is up, it closes
	-- it (as No does) - but not in the same instant it opened, since one tap can arrive as
	-- two presses on some touch screens.
	if confirm.Visible then
		if os.clock() - openedAt < 0.3 then return end
		sound("Click")
		showConfirm(false)
		return
	end
	sound("Click")
	showConfirm(true)
end)

-- the popup's buttons: the same pop as the others
for _, b in ipairs({ yesBtn, noBtn }) do
	local s = b:FindFirstChildOfClass("UIScale")
	local function to(v) if s then TS:Create(s, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = v }):Play() end end
	b.MouseEnter:Connect(function() if not (UIS.TouchEnabled and not UIS.MouseEnabled) then sound("Hover"); to(1.06) end end)
	b.MouseLeave:Connect(function() to(1) end)
	b.MouseButton1Down:Connect(function() to(0.92) end)
	b.MouseButton1Up:Connect(function() to(1) end)
end
-- A click or tap anywhere outside the popup closes it - and still does whatever it was
-- clicking (Settings opens, Skip Stage presses...): it's only listened to, never used up,
-- so nothing needs clicking twice. Its own card, and the Respawn button, don't count.
local function inside(gui2, x, y)
	local p, s = gui2.AbsolutePosition, gui2.AbsoluteSize
	return x >= p.X and x <= p.X + s.X and y >= p.Y and y <= p.Y + s.Y
end
UIS.InputBegan:Connect(function(input)
	if not confirm.Visible then return end
	local t = input.UserInputType
	if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then return end
	local x, y = input.Position.X, input.Position.Y
	if inside(confirm.Card, x, y) or inside(button, x, y) then return end
	showConfirm(false)
end)

-- R on a keyboard: the same as pressing the button (the popup, never a respawn by itself)
UIS.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or input.KeyCode ~= KEY then return end
	if not holder.Visible or sent or confirm.Visible or not button.Interactable then return end
	sound("Click")
	showConfirm(true)
end)

noBtn.Activated:Connect(function()
	sound("Click")
	showConfirm(false)
end)
yesBtn.Activated:Connect(function()
	if not confirm.Visible or sent or not holder.Visible then return end
	showConfirm(false)
	sent = true   -- once per ride: the server ends it for both riders
	sound("Click")
	remote:FireServer()
	refresh()
	-- still riding a few seconds on (the server didn't take it): the button comes back
	task.delay(3, function() sent = false; refresh() end)
end)
-- a modal popup (the ride's controls card) takes the screen: no presses meanwhile
Menus.Lockable(button, function() hover, held = false, false; look() end)

-- Placed again only when the layout really changes (screen size, touch / keyboard, which
-- controls this rider has) - never because an arrow or pedal shrinks while it's pressed,
-- which would drag the button along with it. Measured again once any show animation has
-- settled.
local function layoutKey()
	local r = rideGui()
	local cam = workspace.CurrentCamera
	local function vis(name) local o = find(r, name); return o and o.Visible and "1" or "0" end
	return table.concat({ tostring(cam and cam.ViewportSize), tostring(gui.AbsoluteSize), tostring(keyboard()),
		vis("DriverControls"), vis("MotorControls"), vis("HornControls"), tostring(holder.Visible) }, "|")
end
local lastKey, since = nil, 0
RunService.RenderStepped:Connect(function(dt)
	since += dt
	if since < 0.1 then return end
	since = 0
	if not holder.Visible then lastKey = nil return end
	local k = layoutKey()
	if k == lastKey then return end
	lastKey = k
	layout()
	task.delay(0.6, function() if holder.Visible and lastKey == k then layout() end end)
end)
refresh()
