--=====================================================================
-- TrollUI
--
-- The TROLL button, top right of the lobby tile grid (HudSync: Skins | Troll over
-- Daily | Invite), and (through Menu) the Troll window it opens. The button is made and
-- moves exactly like the Invite, Skins and Daily buttons - sprung scale for the hover
-- swell and the press pop, a glare sweep, the hint pill and the same sounds. Like them
-- it steps aside while the player is queued or riding.
--
-- Pieces:  Menu      the window: opening and closing, the spectate bar
--          Spectate  watching a duo from behind their scooter (camera, list of duos)
-- The troll actions themselves are not here yet: the window's Content is empty.
--=====================================================================

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local GuiService        = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
local btn        = container:WaitForChild("TrollButton")
local stroke     = btn:WaitForChild("Edge")
local icon       = btn:WaitForChild("Icon")
local iconScale  = icon:WaitForChild("IconScale")
local sweep      = btn:WaitForChild("Sweep")
local sfxHover   = gui:WaitForChild("SfxHover")
local sfxPress   = gui:WaitForChild("SfxPress")

--------------------------------------------------------------------- consts
local TILE             = 84           -- the Invite tile's size
local REST_T,  REST_W  = 0.1, 3       -- outline, as on the Invite button
local HOVER_T, HOVER_W = 0,   3.5
local BASE_ICON_POS    = icon.Position

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

RunService.RenderStepped:Connect(function(dt)
	dt = math.min(dt, 1 / 30)
	t += dt
	container.Position = HudSync.TileAt(gui, 2, 1, scale)   -- the grid's top right

	-- one spring: the entrance pop, hover swell, press pop, and stepping aside (in game, or
	-- while its own window is open - it leaves with Skins, Daily and Invite; EXIT brings it back)
	local open = Menu.IsOpen()
	if open then hovering, pressed = false, false end
	local shown = ready and not inGame and not open
	local target = 0
	if shown then target = pressed and 0.93 or (hovering and 1.06 or 1) end
	sCur, sVel = Motion.spring(sCur, sVel, target, 250, 19, dt)
	scaleObj.Scale = math.max(sCur, 0.01)
	-- Coming and going rides on RootScale (only one UIScale per object takes
	-- effect, so Container.Scale never shows) with HudSync's spring, in step
	-- with the Invite, Skins and Daily tiles.
	pCur, pVel = Motion.spring(pCur, pVel, shown and 1 or 0, HudSync.STIFFNESS, HudSync.DAMPING, dt)
	rootScale.Scale = scale * math.max(pCur, 0.01)
	container.Visible = shown or pCur > 0.03
	if not container.Visible then return end

	local wig, refusing = refusal:update(dt, hintA)
	rotCur, rotVel = Motion.spring(rotCur, rotVel, (pressed and -1.8 or 0) + wig, 320, 17, dt)
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
	hint.Position = UDim2.new(HudSync.HintX(2, hintA), 0, 0.5, 0)
	hint.BackgroundTransparency = 1 - 0.86 * hintA
	hint.TextTransparency       = 1 - hintA
	hintStroke.Transparency     = 1 - 0.75 * hintA
end)

--------------------------------------------------------------------- input
btn.MouseEnter:Connect(function()
	if Motion.isTouch() then return end
	hovering = true
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

-- queued or riding: the button steps aside with the other tiles (same HudSync
-- frame) and the window closes
HudSync.OnInGame(function(on)
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

-- the loading screen owns the screen until it hands over; the button pops in in
-- that same frame, with the other tiles and the Settings gear
HudSync.WhenIntroDone(function()
	pCur, pVel = HudSync.POP_FROM, HudSync.POP_VEL
	sCur, sVel = 0.32, 2.2
	ready = true
end)
