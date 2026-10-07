--=====================================================================
-- CheckpointSelector   (client)
--
-- The "Select a Checkpoint" window: ONE checkpoint card at a time with arrows
-- (and A / D, swipe) to slide to the previous / next, a START and a LEAVE button. GUI ONLY:
-- nothing here moves the player or knows what a checkpoint does. Whoever
-- opens it hands it a list and listens for the choice:
--
--     local CheckpointSelector = require(ReplicatedStorage.CheckpointSelector)
--
--     CheckpointSelector.Open(checkpoints [, startId])  -- show the window
--     CheckpointSelector.SetCheckpoints(checkpoints)    -- swap the list, open or not
--     CheckpointSelector.Close()                        -- animate it away
--     CheckpointSelector.GetSelectedCheckpoint()        -- the entry picked, and its index
--     CheckpointSelector.IsOpen()
--
--     CheckpointSelector.CheckpointSelected:Connect(function(checkpoint, index) end) -- START
--     CheckpointSelector.SelectionChanged:Connect(function(checkpoint, index) end)   -- picked another
--     CheckpointSelector.Closed:Connect(function(reason) end) -- "Start", "Leave" or "Code"
--
-- A checkpoint is any table with
--     Id     whatever identifies it (handed back untouched)
--     Name   the text on its card (DisplayName works too, as in Shared.Checkpoints)
--     Image  "rbxassetid://..." card picture; without one the card shows placeholder art
--     Unlocked  false: the card says COMING SOON and START won't take it
--     Locked    true: the card says LOCKED (not unlocked by both players) and START won't take it
-- The same table comes back out of the signals, extra fields and all.
--
-- The booth opens it for the Driver (StarterGui.RideGui.Controller, with the
-- list from Shared.Checkpoints).
--
-- Pieces:  View      the GUI from data (StarterGui.CheckpointSelectorGui holds the look)
--          Carousel  the one-card view: arrows, sliding cards, dots
--          Motion    springs, the window fade, the button feel
--          Sfx       sounds (the Sounds live in CheckpointSelectorGui.Sfx)
--=====================================================================

local Players              = game:GetService("Players")
local RunService           = game:GetService("RunService")
local GuiService           = game:GetService("GuiService")
local UserInputService     = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local Lighting             = game:GetService("Lighting")

local Motion   = require(script:WaitForChild("Motion"))
local View     = require(script:WaitForChild("View"))
local Carousel = require(script:WaitForChild("Carousel"))
local Sfx      = require(script:WaitForChild("Sfx"))
local Menus    = require(script.Parent:WaitForChild("UITemplates"):WaitForChild("Menus"))
local ControlHolds = require(script.Parent:WaitForChild("ScooterSystem"):WaitForChild("ControlHolds"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local refs      = View.find(playerGui:WaitForChild("CheckpointSelectorGui"))

-- "Checkpoints" across the empty bar above the cards (Content's top ~11%), in the
-- window's own font: white with a black stroke, scaled to the bar on every screen, at its left
do
	local content = refs.cards.Parent
	if not content:FindFirstChild("BarTitle") then
		local title = Instance.new("TextLabel")
		title.Name = "BarTitle"
		-- left edge lined up with the cards' left edge (Cards: 0.955 wide, centred)
		title.AnchorPoint = Vector2.new(0, 0.5)
		title.Position = UDim2.fromScale(0.0225, 0.06)
		title.Size = UDim2.fromScale(0.6, 0.1)
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.BackgroundTransparency = 1
		title.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json")
		title.Text = "Checkpoints"
		title.TextColor3 = Color3.new(1, 1, 1)
		title.TextScaled = true
		title.ZIndex = 16
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = 50
		limit.Parent = title
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(0, 0, 0)
		stroke.Thickness = 2.5
		stroke.Parent = title
		title.Parent = content
	end
end

--------------------------------------------------------------------- consts
local DIM_MAX     = 0.35   -- how far the world behind darkens (0..1)
local BLUR_MAX    = 0      -- blur behind the window; 0 = none, as in Settings
local RISE        = 16     -- px the card row and the buttons rise as they appear
local CLOSE_DELAY = 0.1    -- START / LEAVE: the press reads before the window goes

-- the window's share of the screen. Window.Aspect keeps its shape and
-- Window.Limit caps it on very big screens; phones get more of the screen.
local SIZE_DESKTOP = UDim2.fromScale(0.62, 0.52)
local SIZE_PHONE   = UDim2.fromScale(0.94, 0.74)

-- keys the window holds while open (movement comes back the moment it closes)
local ACTION = "CheckpointSelectorKeys"
local KEYS = {
	Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
	Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right,
	Enum.KeyCode.Space, Enum.KeyCode.Return, Enum.KeyCode.KeypadEnter,
}

--------------------------------------------------------------------- signals
local function newSignal()
	local handlers = {}
	local signal = {}
	function signal:Connect(fn)
		local key = {}
		handlers[key] = fn
		return { Disconnect = function() handlers[key] = nil end }
	end
	function signal:Fire(...)
		for _, fn in pairs(handlers) do task.spawn(fn, ...) end
	end
	return signal
end

local Selector = {
	CheckpointSelected = newSignal(),   -- (checkpoint, index)  START was pressed
	SelectionChanged   = newSignal(),   -- (checkpoint, index)  another card was picked
	Closed             = newSignal(),   -- (reason)             "Start", "Leave" or "Code"
}

--------------------------------------------------------------------- pieces
-- the window fades as one; the card row and the buttons also have their own
-- reveal, so on opening they arrive a beat apart
local function groupOf(o)
	while o and o ~= refs.window do
		if o == refs.cards then return "cards" end
		if o == refs.actions then return "actions" end
		o = o.Parent
	end
	return nil
end
local fader = Motion.fader(groupOf)
fader:trackTree(refs.window, function(o) return o == refs.cardTemplate end)

local sfx      = Sfx.new(refs.sfx)
local carousel = Carousel.new(refs, fader, sfx)

--------------------------------------------------------------------- state
local isOpen, leaving = false, false
local closeToken      = 0
local winA            = 0
-- drops in from above and lifts back out like every menu (UITemplates.Menus). It
-- is part of the booth, so it is never replaced; it is blocking: while it is up
-- the open menu closes and no other menu can open over it.
local slide           = Menus.new(refs.window, { exclusive = false, blocking = true })
local groupA          = { cards = 0, actions = 0 }
local groupWant       = { cards = 0, actions = 0 }
local cardsHome       = refs.cards.Position
local actionsHome     = refs.actions.Position
local blur

--------------------------------------------------------------------- responsive
local function updateSize()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local vp = cam.ViewportSize
	if vp.X < 1 or vp.Y < 1 then return end
	local inset = GuiService:GetGuiInset().Y     -- keep clear of the Roblox top bar
	local phone = math.min(vp.X, vp.Y - inset) < 500
	refs.window.Size = phone and SIZE_PHONE or SIZE_DESKTOP
	-- centred under the top bar, nudged down for the title riding on the top edge
	slide:setHome(UDim2.new(0.5, 0, 0.5, inset / 2 + (phone and 8 or 16)))
end

updateSize()
local function bindCamera()
	local c = workspace.CurrentCamera
	if c then c:GetPropertyChangedSignal("ViewportSize"):Connect(updateSize) end
end
bindCamera()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	bindCamera(); updateSize()
end)

local function ensureBlur()
	if BLUR_MAX <= 0 or (blur and blur.Parent) then return end
	blur = Instance.new("BlurEffect")
	blur.Name = "CheckpointSelectorBlur"
	blur.Size = 0
	blur.Enabled = false
	blur.Parent = Lighting
end

--------------------------------------------------------------------- actions
local buttons = {}
local startBtn, leaveBtn
local close

local function live()
	return isOpen and not leaving
end

-- a COMING SOON or LOCKED pick greys START out and says so
local startFace  = refs.start:WaitForChild("Face")
local startLabel = startFace:WaitForChild("Label")
local startGrad  = startFace:FindFirstChildOfClass("UIGradient")
local startLip   = refs.start:WaitForChild("Lip")
local startEdges = { startFace:WaitForChild("Edge"), startLip:WaitForChild("Edge"), startLabel:WaitForChild("UIStroke") }
local START_LOOK = { grad = startGrad.Color, lip = startLip.BackgroundColor3, edge = startEdges[1].Color, text = startLabel.Text }
local SOON_GRAD  = ColorSequence.new(Color3.fromRGB(150, 156, 172), Color3.fromRGB(96, 102, 120))
local SOON_LIP   = Color3.fromRGB(56, 60, 74)
local SOON_EDGE  = Color3.fromRGB(26, 28, 36)

local function refreshStart()
	local cp = carousel:current()
	local soon = cp ~= nil and View.isLocked(cp)
	startGrad.Color = soon and SOON_GRAD or START_LOOK.grad
	startLip.BackgroundColor3 = soon and SOON_LIP or START_LOOK.lip
	for _, e in ipairs(startEdges) do e.Color = soon and SOON_EDGE or START_LOOK.edge end
	startLabel.Text = soon and View.lockText(cp) or START_LOOK.text
end

local function changed()
	refreshStart()
	sfx:play("Navigate")
	Selector.SelectionChanged:Fire(carousel:current())
end

-- A / D, the arrow keys and the bumpers step through the cards
local function navigate(step)
	if live() and carousel:go(step) then changed() end
end

-- a card was clicked (or reached with the gamepad)
carousel.onSelect = function(i)
	if live() and carousel:select(i) then changed() end
end

local function start()
	if not live() then return end
	local checkpoint, index = carousel:current()
	if not checkpoint then return end
	if View.isLocked(checkpoint) then
		startBtn:shake()          -- COMING SOON: nothing to start yet
		return
	end
	leaving = true
	sfx:play("Start")
	Motion.sweep(startBtn.sweepFrame, 0.45)
	Selector.CheckpointSelected:Fire(checkpoint, index)
	local token = closeToken
	task.delay(CLOSE_DELAY, function()
		if closeToken == token then close("Start") end
	end)
end

local function leave()
	if not live() then return end
	leaving = true
	local token = closeToken
	task.delay(CLOSE_DELAY, function()
		if closeToken == token then close("Leave") end
	end)
end

local function addButton(holder, opts)
	opts.fader, opts.sfx = fader, sfx
	local b = Motion.button(holder, opts)
	table.insert(buttons, b)
	return b
end
startBtn = addButton(refs.start, { hover = 1.03, press = 0.96, lift = 2, sink = 4, onActivate = start })
leaveBtn = addButton(refs.leave, { hover = 1.04, press = 0.95, lift = 2, sink = 4, onActivate = leave })

-- gamepad: a white ring shaped like the button it sits on
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
startBtn.face.SelectionImageObject = ring(UDim.new(0, 19))
leaveBtn.face.SelectionImageObject = ring(UDim.new(0, 19))

--------------------------------------------------------------------- input
-- keyboard: A / D or the arrow keys step through the cards, Enter starts; the
-- movement keys are held so the character stays put behind the window
local function onKey(_, state, input)
	if state == Enum.UserInputState.Begin and live() then
		local k = input.KeyCode
		if k == Enum.KeyCode.A or k == Enum.KeyCode.Left then
			navigate(-1)
		elseif k == Enum.KeyCode.D or k == Enum.KeyCode.Right then
			navigate(1)
		elseif k == Enum.KeyCode.Return or k == Enum.KeyCode.KeypadEnter then
			startBtn:kick(); start()
		end
	end
	return Enum.ContextActionResult.Sink
end

-- gamepad: the bumpers step through the cards from anywhere, B leaves
UserInputService.InputBegan:Connect(function(input)
	if not live() then return end
	local k = input.KeyCode
	if k == Enum.KeyCode.ButtonL1 then
		navigate(-1)
	elseif k == Enum.KeyCode.ButtonR1 then
		navigate(1)
	elseif k == Enum.KeyCode.ButtonB then
		leave()
	end
end)

local HOLD = "CheckpointSelector"
local function setModal(on)
	if on then
		ContextActionService:BindActionAtPriority(ACTION, onKey, false,
			Enum.ContextActionPriority.High.Value, table.unpack(KEYS))
		-- touch: the thumbstick and jump button step aside while the window is up (shared
		-- with the cutscenes and the death popup: back once the last of them lets go)
		ControlHolds.Hold(HOLD, { "TouchControls" })
	else
		ContextActionService:UnbindAction(ACTION)
		ControlHolds.Release(HOLD)
	end
end

--------------------------------------------------------------------- open / close
local function open()
	if carousel:count() == 0 then
		warn("[CheckpointSelector] Open: there are no checkpoints to show")
		return false
	end
	closeToken += 1          -- cancels a START / LEAVE close still on its way
	leaving = false
	if isOpen then return true end
	isOpen = true
	updateSize()
	ensureBlur()
	if winA < 0.05 then
		-- a fresh open: pop in from small, then the cards and the buttons rise in
		carousel:snap()
		for k in pairs(groupA) do groupA[k], groupWant[k] = 0, 0 end
		task.delay(0.04, function() if isOpen then groupWant.cards = 1 end end)
		task.delay(0.11, function() if isOpen then groupWant.actions = 1 end end)
		task.delay(0.26, function() if isOpen then Motion.sweep(refs.panelSweep, 0.75) end end)
	else
		for k in pairs(groupWant) do groupWant[k] = 1 end   -- reopened mid-close: just turn around
	end
	refreshStart()
	sfx:play("Open")
	refs.window.Visible, refs.dim.Visible = true, true
	slide:open()
	setModal(true)
	if Motion.isGamepad() then GuiService.SelectedObject = startBtn.face end
	return true
end

close = function(reason)
	if not isOpen then return end
	isOpen, leaving = false, false
	slide:close()
	closeToken += 1
	setModal(false)
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(refs.gui) then GuiService.SelectedObject = nil end
	for _, b in ipairs(buttons) do b:reset() end
	if reason ~= "Start" then sfx:play("Close") end
	Selector.Closed:Fire(reason)
	-- the frame loop hides the window once it has faded out
end

--------------------------------------------------------------------- public API
function Selector.SetCheckpoints(checkpoints)
	assert(type(checkpoints) == "table", "CheckpointSelector.SetCheckpoints: expected a list of checkpoints")
	local list = {}
	for _, cp in ipairs(checkpoints) do
		if type(cp) == "table" then table.insert(list, cp) end
	end
	carousel:setList(list)
	refreshStart()
	if #list == 0 then close("Code") end
end

function Selector.Open(checkpoints, startId)
	if checkpoints ~= nil then Selector.SetCheckpoints(checkpoints) end
	if startId ~= nil then carousel:show(startId) end
	return open()
end

function Selector.Close()
	close("Code")
end

function Selector.GetSelectedCheckpoint()
	return carousel:current()
end

function Selector.IsOpen()
	return isOpen
end

--------------------------------------------------------------------- frame loop
local t = 0
RunService.RenderStepped:Connect(function(dt)
	if not refs.window.Visible then return end
	dt = math.min(dt, 1 / 30)
	t += dt

	-- drops in from above and lifts back out (UITemplates.Menus); the fade and the dim follow it
	refs.winScale.Scale = 1
	winA = slide:alpha()
	for k, want in pairs(groupWant) do
		groupA[k] = Motion.approach(groupA[k], want, 12, dt)
	end
	refs.cards.Position   = cardsHome   + UDim2.fromOffset(0, RISE * (1 - groupA.cards))
	refs.actions.Position = actionsHome + UDim2.fromOffset(0, RISE * (1 - groupA.actions))
	fader:set(winA, groupA)

	refs.dim.BackgroundTransparency = 1 - DIM_MAX * winA
	if blur then
		blur.Size = BLUR_MAX * winA
		blur.Enabled = winA > 0.01
	end

	local usable = live()
	for _, b in ipairs(buttons) do
		b.enabled = usable
		b:update(dt)
	end
	carousel:update(dt, usable)
	refs.cloth.Rotation = math.sin(t * 2.4) * 3     -- the flag flutters

	-- faded right out: put it away
	if not isOpen and winA < 0.01 then
		winA = 0
		fader:set(0, groupA)
		refs.window.Visible, refs.dim.Visible = false, false
		if blur then blur.Size = 0; blur.Enabled = false end
	end
end)

return Selector
