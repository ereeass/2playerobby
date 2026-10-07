--=====================================================================
-- Menu   (TrollUI)
--
-- The Troll window (StarterGui.TrollWindow): the house panel as the Daily window has it -
-- title riding on top, highlight, outline - in red, with studs a shade lighter all over
-- it, docked at the bottom of the screen so the duo being watched stays in view:
--
--        Troll
--      [  <   [face]  Driver & Motor  [face]   >  ]
--                        EXIT
--
-- The arrows are the checkpoint picker's own (Carousel.arrowButton), EXIT is the booth's
-- LEAVE button, and all of them press like every house button (Motion.button). The faces
-- carry the Fastest Duos board's role icons (ReplicatedStorage.RoleIcons).
-- It moves like every menu (UITemplates.Menus): it drops in from above and fades as one;
-- only EXIT, B, the TROLL tile again, or another menu opening close it. There is no dim:
-- the world behind is the point. While it is open the player's own character stays put
-- (the movement keys are held, the touch controls step aside, camera input is off) and
-- Spectate has the camera; closing gives all of it back at once.
-- A / D, the arrow keys, the bumpers or the d-pad step through the duos.
-- The trolls themselves are the buttons down the left of the screen (Actions), shown while a
-- duo is on screen.
--=====================================================================

local Players              = game:GetService("Players")
local RunService           = game:GetService("RunService")
local UserInputService     = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService           = game:GetService("GuiService")
local TextService          = game:GetService("TextService")
local RS                   = game:GetService("ReplicatedStorage")

local selector  = RS:WaitForChild("CheckpointSelector")
local Motion    = require(selector:WaitForChild("Motion"))
local Sfx       = require(selector:WaitForChild("Sfx"))
local Carousel  = require(selector:WaitForChild("Carousel"))
local Menus     = require(RS:WaitForChild("UITemplates"):WaitForChild("Menus"))
local Spectate  = require(script.Parent:WaitForChild("Spectate"))
local Actions   = require(script.Parent:WaitForChild("Actions"))
local HudSync   = require(RS:WaitForChild("HudSync"))
local ControlHolds = require(RS:WaitForChild("ScooterSystem"):WaitForChild("ControlHolds"))

local player     = Players.LocalPlayer
local playerGui  = player:WaitForChild("PlayerGui")
local winGui     = playerGui:WaitForChild("TrollWindow")
local fade       = winGui:WaitForChild("Fade")
local window     = winGui:WaitForChild("Window")
local winScale   = window:WaitForChild("Scale")
local panel      = window:WaitForChild("Panel")
local panelSweep = panel:WaitForChild("Sweep")
local row        = panel:WaitForChild("Spectate")
local pill       = row:WaitForChild("NamePill")
local caption    = pill:WaitForChild("Caption")
local names      = pill:WaitForChild("Names")
local faces      = { Driver = pill:WaitForChild("DriverFace"), Motor = pill:WaitForChild("MotorFace") }
local exitHolder = panel:WaitForChild("ExitButton")
local roleIcons  = RS:WaitForChild("RoleIcons")

--------------------------------------------------------------------- consts
local BOTTOM       = 40      -- px (at scale 1) from the screen's bottom to the panel's; EXIT hangs in it
local WINDOW_SIZE  = 0.8     -- of the Invite tiles' scale: about 720 px wide on a 1080p screen
local NAME_MAX, NAME_MIN = 28, 15
local EMPTY_SIZE   = 22
local DRAWN_WIDER  = 1.15    -- the outline draws text this much wider than TextService measures
local ARROWS_OFF   = 0.4     -- the arrows' strength with nobody else to step to
local CLOSE_DELAY  = 0.1     -- EXIT: the press reads before the window goes (as the booth's LEAVE)
local EMPTY_TEXT   = "No duos are riding right now"
local NAMES_COLOR, EMPTY_COLOR = Color3.new(1, 1, 1), Color3.fromRGB(214, 234, 255)

--------------------------------------------------------------------- pieces made here
-- the role icons on the faces' badges, drawn at 100 px (as on the Fastest Duos board)
for role, holder in pairs(faces) do
	local badge = holder:WaitForChild("Role")
	if not badge:FindFirstChild(role) then
		local glyph = roleIcons:WaitForChild(role):Clone()
		glyph.AnchorPoint = Vector2.new(0.5, 0.5)
		glyph.Position = UDim2.fromScale(0.5, 0.5)
		local s = glyph:FindFirstChildOfClass("UIScale")
		if not s then
			s = Instance.new("UIScale")
			s.Parent = glyph
		end
		s.Scale = 0.17
		glyph.Parent = badge
	end
end

-- the arrows either side of the names: the checkpoint carousel's, in the name pill's blue
local function arrow(side)
	local holder, face = Carousel.arrowButton(row, side)
	holder.Position = UDim2.new(side < 0 and 0 or 1, -side * 48, 0.5, -2)
	holder.Size = UDim2.fromOffset(62, 62)
	holder.ZIndex = 8
	face.BackgroundColor3 = Color3.fromRGB(28, 92, 196)
	return holder
end
local prevHolder = arrow(-1)
local nextHolder = arrow(1)

-- gamepad: a white ring shaped like the button it sits on (as the booth's buttons)
local function ring(radius)
	local f = Instance.new("Frame")
	f.Name = "SelectionRing"
	f.BackgroundTransparency = 1
	f.Position = UDim2.fromOffset(-5, -5)
	f.Size = UDim2.new(1, 10, 1, 10)
	local c = Instance.new("UICorner"); c.CornerRadius = radius; c.Parent = f
	local s = Instance.new("UIStroke"); s.Color = Color3.new(1, 1, 1); s.Thickness = 3; s.Parent = f
	return f
end
exitHolder:WaitForChild("Face").SelectionImageObject = ring(UDim.new(0, 19))

--------------------------------------------------------------------- fading and motion
local fader = Motion.fader(function(o)
	if o == prevHolder or o:IsDescendantOf(prevHolder) then return "prev" end
	if o == nextHolder or o:IsDescendantOf(nextHolder) then return "next" end
	return nil
end)
fader:trackTree(window)

local Menu  = {}
local sfx   = Sfx.new(winGui:WaitForChild("Sfx"))
local slide = Menus.new(window, { onReplace = function() Menu.Close() end })

local isOpen = false
local winA, arrowA = 0, ARROWS_OFF
local arrowsOn = false
local closeToken = 0

local function step(d, fromKey)
	if not isOpen then return end
	local b = d < 0 and Menu.prev or Menu.next
	if Spectate.Step(d) then
		if fromKey then sfx:play("Click"); b:kick() end
	else
		b:shake()   -- nobody else to watch: a little "no"
	end
end

local function exit()
	if not isOpen then return end
	local token = closeToken
	task.delay(CLOSE_DELAY, function()
		if closeToken == token then Menu.Close() end
	end)
end

Menu.prev = Motion.button(prevHolder, { fader = fader, sfx = sfx, hover = 1.1, press = 0.9, nudge = -5, onActivate = function() step(-1) end })
Menu.next = Motion.button(nextHolder, { fader = fader, sfx = sfx, hover = 1.1, press = 0.9, nudge = 5, onActivate = function() step(1) end })
Menu.exit = Motion.button(exitHolder, { fader = fader, sfx = sfx, hover = 1.04, press = 0.95, lift = 2, sink = 4, onActivate = exit })
local buttons = { Menu.prev, Menu.next, Menu.exit }

--------------------------------------------------------------------- responsive
local BASE_W, BASE_H = window.Size.X.Offset, window.Size.Y.Offset
local rootScale = 1
local function updateScale()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local vp = cam.ViewportSize
	if vp.X < 1 or vp.Y < 1 then return end
	-- the Invite tiles' own maths, a little smaller: a bar, not a big window
	local minAxis = math.min(vp.X, vp.Y)
	local s = minAxis / 720
	if Motion.isTouch() and minAxis < 500 then s *= 1.15 end
	s = math.clamp(s * WINDOW_SIZE, 0.7, 1.25)
	rootScale = math.min(s, vp.X * 0.94 / BASE_W, vp.Y * 0.4 / (BASE_H + BOTTOM + 30))
	slide:setHome(UDim2.new(0.5, 0, 1, -math.floor(BOTTOM * rootScale)))
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

--------------------------------------------------------------------- the bar
local thumbs = {}          -- [userId] = headshot
local showToken = 0

local function face(holder, userId, token)
	local img = holder:WaitForChild("Avatar")
	if thumbs[userId] then img.Image = thumbs[userId] return end
	img.Image = ""
	task.spawn(function()
		local ok, url = pcall(Players.GetUserThumbnailAsync, Players, userId,
			Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		if ok and url then
			thumbs[userId] = url
			if showToken == token then img.Image = url end
		end
	end)
end

local function nameOf(userId)
	local p = Players:GetPlayerByUserId(userId)
	return p and p.DisplayName or "?"
end

-- the biggest size (NAME_MAX down to `min`) at which the text fits; below that it is cut with ...
local function fit(text, max, min)
	local pillW = BASE_W * pill.Size.X.Scale + pill.Size.X.Offset
	local w = pillW * names.Size.X.Scale + names.Size.X.Offset
	for size = max, min, -1 do
		local x = TextService:GetTextSize(text, size, Enum.Font.FredokaOne, Vector2.new(4096, 256)).X
		if x * DRAWN_WIDER <= w then return size end
	end
	return min
end

-- what Spectate is showing: the duo (Driver & Motor, their faces) or nobody
local function show(duo, index, count)
	showToken += 1
	local token = showToken
	local any = duo ~= nil
	arrowsOn = count > 1
	caption.Visible = any
	faces.Driver.Visible, faces.Motor.Visible = any, any
	if any then
		caption.Text = count > 1 and ("SPECTATING  %d / %d"):format(index, count) or "SPECTATING"
		names.Size = UDim2.new(1, -140, 0, 36)
		names.Position = UDim2.new(0.5, 0, 1, -8)
		names.Text = nameOf(duo.DriverId) .. " & " .. nameOf(duo.MotorId)
		names.TextSize = fit(names.Text, NAME_MAX, NAME_MIN)
		names.TextColor3 = NAMES_COLOR
		face(faces.Driver, duo.DriverId, token)
		face(faces.Motor, duo.MotorId, token)
	else
		names.Size = UDim2.new(1, -40, 0, 36)
		names.Position = UDim2.new(0.5, 0, 0.5, 18)
		names.Text = EMPTY_TEXT
		names.TextSize = fit(EMPTY_TEXT, EMPTY_SIZE, NAME_MIN)
		names.TextColor3 = EMPTY_COLOR
	end
end

--------------------------------------------------------------------- the player stays put
-- keys the window holds while open (movement comes back the moment it closes), as the
-- booth's checkpoint picker holds them
local ACTION = "TrollWindowKeys"
local KEYS = {
	Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
	Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right,
	Enum.KeyCode.Space,
}
local function onKey(_, state, input)
	if state == Enum.UserInputState.Begin and isOpen then
		local k = input.KeyCode
		if k == Enum.KeyCode.A or k == Enum.KeyCode.Left then
			step(-1, true)
		elseif k == Enum.KeyCode.D or k == Enum.KeyCode.Right then
			step(1, true)
		end
	end
	return Enum.ContextActionResult.Sink
end

-- Roblox's camera input (its CameraContext) is off and, on touch screens, the thumbstick and
-- jump button step aside while the window is up - shared with the cutscenes and the death
-- popup (ScooterSystem.ControlHolds): they come back once the last of them lets go
local HOLD = "TrollWindow"
local function holdPlayer(on)
	if on then
		ContextActionService:BindActionAtPriority(ACTION, onKey, false,
			Enum.ContextActionPriority.High.Value, table.unpack(KEYS))
		ControlHolds.Hold(HOLD, { "TouchControls", "CameraInput" })
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default   -- out of Shift-lock
	else
		ContextActionService:UnbindAction(ACTION)
		ControlHolds.Release(HOLD)
	end
end

--------------------------------------------------------------------- open / close
function Menu.IsOpen()
	return isOpen
end

function Menu.Open()
	if isOpen then return end
	if not slide:open() then return false end  -- a blocking screen is up: the tile shakes and says why
	isOpen = true
	closeToken += 1
	updateScale()
	if winA < 0.05 then
		task.delay(0.24, function() if isOpen then Motion.sweep(panelSweep, 0.75) end end)
	end
	-- no open / close whoosh, as the Skins and Daily windows (the tile's own click stays)
	window.Visible = true
	holdPlayer(true)
	HudSync.SetSpectating(true)   -- Skins and Daily step aside, Invite goes to the top bar
	Spectate.Start({ fade = fade, onChanged = show })
	return true
end

function Menu.Close()
	if not isOpen then return end
	isOpen = false
	closeToken += 1
	slide:close()
	Spectate.Stop()             -- the camera is the player's again, this frame
	holdPlayer(false)
	HudSync.SetSpectating(false)
	for _, b in ipairs(buttons) do b:reset() end
	local sel = GuiService.SelectedObject
	if sel and sel:IsDescendantOf(winGui) then GuiService.SelectedObject = nil end
	-- the frame loop hides the window once it has faded out
end

-- what the TROLL tile does (UITemplates.Menus): false = the open was refused
function Menu.Toggle()
	return slide:toggle(Menu.Open, Menu.Close)
end

--------------------------------------------------------------------- input (connected once)
-- gamepad: the bumpers and the d-pad step through the duos, B closes (as every menu)
UserInputService.InputBegan:Connect(function(input)
	if not isOpen then return end
	local k = input.KeyCode
	if k == Enum.KeyCode.ButtonL1 or k == Enum.KeyCode.DPadLeft then
		step(-1, true)
	elseif k == Enum.KeyCode.ButtonR1 or k == Enum.KeyCode.DPadRight then
		step(1, true)
	elseif k == Enum.KeyCode.ButtonB then
		Menu.Close()
	end
end)

-- the player's own character dies or a new one arrives: the window closes and the
-- camera goes back to them
local function watchCharacter(char)
	local hum = char:WaitForChild("Humanoid", 10)
	if hum then hum.Died:Connect(function() Menu.Close() end) end
end
player.CharacterAdded:Connect(function(char)
	Menu.Close()
	task.spawn(watchCharacter, char)
end)
if player.Character then task.spawn(watchCharacter, player.Character) end

--------------------------------------------------------------------- frame loop
RunService.RenderStepped:Connect(function(dt)
	if not window.Visible then return end
	dt = math.min(dt, 1 / 30)

	-- slides in from above and back up (UITemplates.Menus); the fade follows it
	winScale.Scale = rootScale
	winA = slide:alpha()
	arrowA = Motion.approach(arrowA, arrowsOn and 1 or ARROWS_OFF, 12, dt)
	fader:set(winA, { prev = arrowA, next = arrowA })
	for _, b in ipairs(buttons) do b:update(dt) end
	-- the troll buttons down the left: with the window, and only while a duo is on screen
	Actions.Update(dt, winA, isOpen and Spectate.Current() or nil, rootScale)

	if not isOpen and winA < 0.01 then
		winA = 0
		fader:set(0, { prev = arrowA, next = arrowA })
		window.Visible = false
		Actions.Hide()
	end
end)

return Menu
