--=====================================================================
-- DailyUI
--
-- The DAILY button under the Skins button, and (through Menu) the Daily Rewards
-- window it opens. The button is made and moves exactly like the Skins and Invite
-- buttons: sprung scale for the hover swell and the press pop, a glare sweep, the
-- hint pill and the same sounds. It sits one tile under Skins at Invite's own
-- scale, and like them it steps aside while the player is queued or riding.
-- Notification: the Invite tile's own red badge and pulsing ring, up for as long as
-- a day is ready to claim (Menu.Status, from the server). Opening or closing the
-- window never takes it away - only claiming does, with the Invite badge's pop.
--
-- Pieces:  Menu     the window: opening and closing (the window only, for now)
--=====================================================================

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local GuiService        = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local Motion  = require(ReplicatedStorage:WaitForChild("CheckpointSelector"):WaitForChild("Motion"))
local Menu    = require(script:WaitForChild("Menu"))
local HudSync = require(ReplicatedStorage:WaitForChild("HudSync"))
local Menus   = require(ReplicatedStorage:WaitForChild("UITemplates"):WaitForChild("Menus"))

local playerGui  = Players.LocalPlayer:WaitForChild("PlayerGui")
local gui        = script.Parent
local container  = gui:WaitForChild("Container")
local rootScale  = container:WaitForChild("RootScale")
local scaleObj   = container:WaitForChild("Scale")
local hint       = container:WaitForChild("Hint")
local hintStroke = hint:WaitForChild("UIStroke")
local refusal    = Menus.refusal(hint)      -- a refused open shakes the tile and says why
local btn        = container:WaitForChild("DailyButton")
local stroke     = btn:WaitForChild("Edge")
local icon       = btn:WaitForChild("Icon")
local iconScale  = icon:WaitForChild("IconScale")
local sweep      = btn:WaitForChild("Sweep")
local sfxHover   = gui:WaitForChild("SfxHover")
local sfxPress   = gui:WaitForChild("SfxPress")
local invite     = playerGui:WaitForChild("InviteGui"):WaitForChild("Container")
local badge      = container:WaitForChild("Badge")
local badgeScale = badge:WaitForChild("BadgeScale")
local badgeRing  = container:WaitForChild("BadgeRing")
local ringStroke = badgeRing:WaitForChild("UIStroke")

--------------------------------------------------------------------- consts
local TILE, GAP        = 84, 14       -- the Invite tile's size, and the gap under each tile
local SLOT             = 2            -- tiles under Invite: Skins is the 1st, this the 2nd
local REST_T,  REST_W  = 0.1, 3       -- outline, as on the Invite button
local HOVER_T, HOVER_W = 0,   3.5
local BASE_ICON_POS    = icon.Position
local BADGE_PULSES     = 4            -- ring pulses when a day turns ready, as the Invite badge

--------------------------------------------------------------------- responsive
-- the lobby tile grid's size (HudSync), so the tiles always match
local scale = 1
local function updateScale()
	scale = HudSync.TileScale()
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

--------------------------------------------------------------------- state
local hovering, pressed = false, false
local ready, inGame     = false, false
local sCur, sVel        = 0, 0
local pCur, pVel        = 0, 0      -- presence: HudSync's shared spring
local rotCur, rotVel    = 0, 0
local strT, strW        = REST_T, REST_W
local icoHover, hintA   = 1, 0
local liftCur, parX, parY = 0, 0, 0
local t = 0
local bCur, bVel        = 0, 0      -- the notification badge's spring
local wasReady          = false
local pulsesLeft        = 0
local ackPopUntil       = 0

-- the Invite badge's ring: out from the badge and gone
local function pulseRing()
	badgeRing.Visible = true
	badgeRing.Size = UDim2.fromOffset(24, 24)
	ringStroke.Transparency = 0.15
	local info = TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(badgeRing, info, { Size = UDim2.fromOffset(46, 46) }):Play()
	local tw = TweenService:Create(ringStroke, info, { Transparency = 1 })
	tw:Play()
	tw.Completed:Once(function() badgeRing.Visible = false end)
end

RunService.RenderStepped:Connect(function(dt)
	dt = math.min(dt, 1 / 30)
	t += dt
	container.Position = HudSync.TileAt(gui, 1, 2, scale)   -- the grid's left column, under Skins

	-- one spring: the entrance pop, hover swell, press pop, and stepping aside
	local shown = ready and not inGame
	local target = 0
	if shown then target = pressed and 0.93 or (hovering and 1.06 or 1) end
	sCur, sVel = Motion.spring(sCur, sVel, target, 250, 19, dt)
	scaleObj.Scale = math.max(sCur, 0.01)
	-- Coming and going rides on RootScale (only one UIScale per object takes
	-- effect, so Container.Scale never shows) with HudSync's spring, in step
	-- with the Invite and Skins tiles.
	pCur, pVel = Motion.spring(pCur, pVel, shown and 1 or 0, HudSync.STIFFNESS, HudSync.DAMPING, dt)
	rootScale.Scale = scale * math.max(pCur, 0.01)
	container.Visible = shown or pCur > 0.03

	-- the notification: up while a day is ready; claimed, it pops and goes (as Invite's)
	local st = Menu.Status()
	local readyNow = st ~= nil and st.ready
	if readyNow and not wasReady then
		pulsesLeft = BADGE_PULSES
		if shown then pulseRing() end
	elseif wasReady and not readyNow then
		ackPopUntil = os.clock() + 0.09
		pulsesLeft = 0
	end
	wasReady = readyNow
	local badgeTarget = readyNow and 1 or 0
	if os.clock() < ackPopUntil then badgeTarget = 1.3 end
	bCur, bVel = Motion.spring(bCur, bVel, badgeTarget, 260, 18, dt)
	badgeScale.Scale = math.max(bCur, 0)

	if not container.Visible then return end

	local wig, refusing = refusal:update(dt, hintA)
	rotCur, rotVel = Motion.spring(rotCur, rotVel, (pressed and 1.8 or 0) + wig, 320, 17, dt)
	btn.Rotation = rotCur
	strT = Motion.approach(strT, hovering and HOVER_T or REST_T, 11, dt)
	strW = Motion.approach(strW, hovering and HOVER_W or REST_W, 11, dt)
	stroke.Transparency, stroke.Thickness = strT, strW
	icoHover = Motion.approach(icoHover, hovering and 1.08 or 1, 12, dt)
	iconScale.Scale = icoHover + math.sin(t * 1.3) * 0.012

	-- the Invite icon's cursor parallax (InviteClient): on hover the icon lifts and
	-- drifts toward the pointer, with a slight lean. Moved through Scale, not
	-- Offset, so the travel stays sub-pixel smooth.
	liftCur = Motion.approach(liftCur, hovering and -3.5 or 0, 12, dt)
	local pxT, pyT = 0, 0
	if hovering and not Motion.isTouch() then
		local m    = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
		local c    = btn.AbsolutePosition + btn.AbsoluteSize * 0.5
		local half = math.max(btn.AbsoluteSize.X * 0.5, 1)
		pxT = math.clamp((m.X - c.X) / half, -1, 1) * 3
		pyT = math.clamp((m.Y - c.Y) / half, -1, 1) * 3
	end
	parX = Motion.approach(parX, pxT, 14, dt)
	parY = Motion.approach(parY, pyT, 14, dt)
	icon.Position = UDim2.new(
		BASE_ICON_POS.X.Scale + parX / TILE, BASE_ICON_POS.X.Offset,
		BASE_ICON_POS.Y.Scale + (liftCur + parY) / TILE, BASE_ICON_POS.Y.Offset)
	icon.Rotation = parX * 0.6

	-- hover hint pill, never while the window is up (and the reason an open was refused)
	hintA = Motion.approach(hintA, (refusing or (hovering and shown and not Menu.IsOpen())) and 1 or 0, 14, dt)
	-- slides out to the right of the tile grid
	hint.Position = UDim2.new(HudSync.HintX(1, hintA), 0, 0.5, 0)
	hint.BackgroundTransparency = 1 - 0.86 * hintA
	hint.TextTransparency       = 1 - hintA
	hintStroke.Transparency     = 1 - 0.75 * hintA
end)

--------------------------------------------------------------------- input
btn.MouseEnter:Connect(function()
	if Motion.isTouch() then return end
	hovering = true
	pulsesLeft = 0            -- they have seen it; the ring stops waving (the badge stays)
	sfxHover:Play()
	Motion.sweep(sweep, 0.5)
end)
btn.MouseLeave:Connect(function()
	hovering, pressed = false, false
end)
btn.MouseButton1Down:Connect(function()
	pressed = true
	sfxPress:Play()
	if Motion.isTouch() then hovering = true end
end)
-- covers drag-off and touch release, which MouseButton1Up alone misses
btn.InputEnded:Connect(function(input)
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
		pressed = false
		if Motion.isTouch() then hovering = false end
	end
end)
btn.Selectable = true
btn.SelectionGained:Connect(function() hovering = true; Motion.sweep(sweep, 0.5) end)
btn.SelectionLost:Connect(function() hovering = false end)
btn.Activated:Connect(function(input)
	if not ready or inGame then return end
	local kind = input and input.UserInputType
	if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then sfxPress:Play() end
	-- the tile toggles its menu; refused (a blocking screen is up): the tile shakes
	-- and its hint says why
	if Menu.Toggle() == false then refusal:trigger() end
end)

-- queued or riding: the button steps aside with Invite and Skins (same HudSync
-- frame) and the window closes
HudSync.OnAside(function(on)   -- in game, or watching a duo in the Troll window
	inGame = on
	if inGame then
		hovering, pressed = false, false
		Menu.Close()
	end
end)

-- an idle glare now and then, as on the Invite button
task.spawn(function()
	while btn.Parent do
		task.wait(8 + math.random() * 3)
		if ready and not inGame and not hovering then Motion.sweep(sweep, 0.6) end
	end
end)

-- the badge's ring keeps pulsing a few times after a day turns ready, as on Invite
task.spawn(function()
	while btn.Parent do
		task.wait(4.5)
		if ready and not inGame and wasReady and pulsesLeft > 0 and bCur > 0.6 then
			pulsesLeft -= 1
			pulseRing()
		end
	end
end)

-- the loading screen owns the screen until it hands over; the button pops in in
-- that same frame, with the Invite and Skins tiles and the Settings gear
HudSync.WhenIntroDone(function()
	pCur, pVel = HudSync.POP_FROM, HudSync.POP_VEL
	sCur, sVel = 0.32, 2.2
	ready = true
end)
