--=====================================================================
-- BoothTutorial   (each player's own machine)
--
-- First-join hints at the bottom of the screen, alongside the lobby's guide arrows
-- (BoothGuide, which always shows):
--   in the lobby                 "Scooter takes two. Follow the arrow to the booth."
--     ...while someone waits     "Someone is waiting at a booth. Join them!" (a station with
--        alone in a booth        one of its two booths taken - the booth the arrows lead to;
--                                back to the line above as soon as nobody is waiting)
--   alone in a booth             "Stay inside the booth. Someone will take the other side."
--   still alone after ALONE_HINT "No one yet? Invite a friend!"
-- It ends (and is saved as seen: ServerScriptService.BoothTutorial) once a partner joins,
-- or when the player holds "Hold to skip tutorial". Shown once per player, ever.
-- Hidden during a cutscene. Booth state comes from Remotes.StateChanged, as RideGui uses.
--
-- To show it again later (a Tutorial button): BoothTutorial.Replay:Fire() from the client.
--=====================================================================

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ScooterSystem = ReplicatedStorage:WaitForChild("ScooterSystem")
local Remotes       = ScooterSystem:WaitForChild("Remotes")
local Cinematic     = require(ScooterSystem:WaitForChild("Cinematic"))
local HudSync       = require(ReplicatedStorage:WaitForChild("HudSync"))

local TEXT_LOBBY   = "Scooter takes two. Follow the arrow to the booth."
local TEXT_JOIN    = "Someone is waiting at a booth. Join them!"
local TEXT_BOOTH   = "Stay inside the booth. Someone will take the other side."
local TEXT_INVITE  = "No one yet? Invite a friend!"
local ALONE_HINT   = 7          -- seconds alone in a booth before the invite hint
local HOLD_TIME    = 1          -- seconds to hold "Hold to skip tutorial"
local FADE         = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local ICON_IMAGE   = "rbxassetid://135170211247390"   -- before each hint: the guide arrows' cyan chevron
-- Where the hint sits is worked out from what is really on this screen (place, below), so it
-- sits right on phones, tablets and PC alike:
--   lobby   LOBBY_LIFT of the screen's height up from the bottom (close to the bottom on a
--           phone) - and above a touch screen's jump button and thumbstick ring where
--           they'd meet it (only what is drawn: the thumbstick's frame is a big invisible box)
--   booth   the bottom is the booth's status card (RideGui.BoothStatus) and the middle is the
--           player, so it goes under the top bar's progress bar (CourseProgressGui)
-- Lines longer than MAX_WIDTH of the screen wrap, so they never run under the side tiles.
local LOBBY_LIFT = 0.16       -- of the screen's height (about 120 on a PC)
local LIFT_MIN, LIFT_MAX = 44, 120
local LOBBY_LIFT_TOUCH = 0.10  -- a touch screen (phone, tablet): a little closer to the bottom
local LIFT_MIN_TOUCH   = 32
local GAP        = 12
local MAX_WIDTH  = 0.62
local MAX_WIDTH_TOUCH = 0.52   -- narrower on a touch screen: fits between the thumbstick and jump button

local player = Players.LocalPlayer

local replay = Instance.new("BindableEvent")
replay.Name = "Replay"
replay.Parent = script

---------------------------------------------------------------- the hint
local gui = Instance.new("ScreenGui")
gui.Name = "BoothTutorialGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 11
gui.Enabled = false

local holder = Instance.new("Frame")
holder.AnchorPoint = Vector2.new(0.5, 1)
holder.Position = UDim2.new(0.5, 0, 1, -LIFT_MAX)
holder.Size = UDim2.fromOffset(0, 0)
holder.AutomaticSize = Enum.AutomaticSize.XY
holder.BackgroundTransparency = 1
holder.Parent = gui
local list = Instance.new("UIListLayout")
list.HorizontalAlignment = Enum.HorizontalAlignment.Center
list.Padding = UDim.new(0, 3)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = holder

-- the hint line: the icon, then the text
local line = Instance.new("Frame")
line.Name = "Line"
line.LayoutOrder = 1
line.BackgroundTransparency = 1
line.AutomaticSize = Enum.AutomaticSize.XY
line.Size = UDim2.fromOffset(0, 0)
line.Parent = holder
local row = Instance.new("UIListLayout")
row.FillDirection = Enum.FillDirection.Horizontal
row.VerticalAlignment = Enum.VerticalAlignment.Center
row.Padding = UDim.new(0, 6)
row.SortOrder = Enum.SortOrder.LayoutOrder
row.Parent = line

local icon = Instance.new("ImageLabel")
icon.Name = "Icon"
icon.LayoutOrder = 1
icon.BackgroundTransparency = 1
icon.Image = ICON_IMAGE
icon.ScaleType = Enum.ScaleType.Fit
icon.ImageTransparency = 1
icon.Parent = line

local label = Instance.new("TextLabel")
label.LayoutOrder = 2
label.BackgroundTransparency = 1
label.AutomaticSize = Enum.AutomaticSize.XY
label.Size = UDim2.fromOffset(0, 0)
label.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold)
label.RichText = true
label.TextColor3 = Color3.new(1, 1, 1)
label.TextSize = 20
label.Text = ""
label.TextWrapped = true
label.Parent = line
local maxWidth = Instance.new("UISizeConstraint")   -- set from the screen in place()
maxWidth.Parent = label
local stroke = Instance.new("UIStroke")
stroke.Thickness = 1.5
stroke.Transparency = 0.45
stroke.Color = Color3.fromRGB(20, 20, 20)
stroke.Parent = label

local skip = Instance.new("TextButton")
skip.LayoutOrder = 2
skip.AutoButtonColor = false
skip.BackgroundTransparency = 1
skip.AutomaticSize = Enum.AutomaticSize.XY
skip.Size = UDim2.fromOffset(0, 0)
skip.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Medium)
skip.Text = "Hold to skip tutorial"
local skipPad = Instance.new("UIPadding")   -- a bigger area to press and hold on a phone
skipPad.PaddingTop, skipPad.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6)
skipPad.PaddingLeft, skipPad.PaddingRight = UDim.new(0, 14), UDim.new(0, 14)
skipPad.Parent = skip
skip.TextColor3 = Color3.new(1, 1, 1)
skip.TextTransparency = 0.45
skip.TextSize = 15
skip.Parent = holder
local skipStroke = stroke:Clone()
skipStroke.Thickness = 1
skipStroke.Transparency = 0.82
skipStroke.Parent = skip
local underline = Instance.new("Frame")   -- fills up while held
underline.AnchorPoint = Vector2.new(0, 1)
underline.Position = UDim2.new(0, 14, 1, 6)       -- (inside the padding: under the words)
underline.Size = UDim2.new(1, -28, 0, 2)
underline.BackgroundColor3 = Color3.new(1, 1, 1)
underline.BackgroundTransparency = 0.72
underline.BorderSizePixel = 0
underline.Parent = skip
local lineEdge = Instance.new("UIStroke")   -- a faint dark edge, so the line shows on light ground too
lineEdge.Color = Color3.fromRGB(20, 20, 20)
lineEdge.Transparency = 0.88
lineEdge.Thickness = 1
lineEdge.Parent = underline
local fill = underline:Clone()
fill:FindFirstChildOfClass("UIStroke"):Destroy()   -- the fill is bright only
fill.Size = UDim2.new(0, 0, 0, 2)
fill.BackgroundTransparency = 0
local FILL_FULL = UDim2.new(1, -28, 0, 2)
fill.Parent = skip

gui.Parent = player:WaitForChild("PlayerGui")

-- text a little bigger on wide screens, never tiny on phones
local function fit()
	local cam = workspace.CurrentCamera
	local w = cam and cam.ViewportSize.X or 1280
	label.TextSize = math.clamp(math.floor(w / 64), 15, 22)
	icon.Size = UDim2.fromOffset(math.floor(label.TextSize * 0.95), math.floor(label.TextSize * 0.56))
	skip.TextSize = math.clamp(math.floor(w / 105), 12, 14)
end
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
fit()

---------------------------------------------------------------- someone waiting?
-- A station with exactly one of its two booths taken (each booth model's Occupied, set by
-- the server) - the same test the guide arrows use to lead there first.
local stations = workspace:WaitForChild("RideSystem"):WaitForChild("CapsuleStations")
local function taken(station, role)
	local trigger = station:FindFirstChild(role)
	local ref = trigger and trigger:FindFirstChild("CapsuleModel")
	local booth = ref and ref.Value
	return booth ~= nil and booth:GetAttribute("Occupied") == true
end
local function someoneWaiting()
	for _, station in ipairs(stations:GetChildren()) do
		if taken(station, "DriverCapsule") ~= taken(station, "MotorCapsule") then return true end
	end
	return false
end

---------------------------------------------------------------- placement
local playerGui = player:WaitForChild("PlayerGui")
local spot = "lobby"

-- shown on screen: visible all the way up, in an enabled ScreenGui
local function onScreen(obj)
	local o = obj
	while o and o:IsA("GuiObject") do
		if not o.Visible then return false end
		o = o.Parent
	end
	return o ~= nil and o:IsA("LayerCollector") and o.Enabled
end

-- All AbsolutePositions share one screen space (the top bar is above this gui's origin), so
-- the other HUD pieces can be compared with this gui directly.
local function place()
	local root, size = gui.AbsolutePosition, gui.AbsoluteSize
	if size.X < 2 or size.Y < 2 then return end
	local touch = playerGui:FindFirstChild("TouchGui")
	local frame = touch and touch.Enabled and touch:FindFirstChild("TouchControlFrame")
	local share = frame and MAX_WIDTH_TOUCH or MAX_WIDTH
	maxWidth.MaxSize = Vector2.new(math.max(220, math.floor(size.X * share)), math.huge)
	local w = holder.AbsoluteSize.X
	local left = root.X + (size.X - w) / 2
	local right = left + w
	if spot == "booth" then
		local top = root.Y + GAP
		local bar = playerGui:FindFirstChild("CourseProgressGui")
		local c = bar and bar:FindFirstChild("Container")
		if c and onScreen(c) then top = math.max(top, c.AbsolutePosition.Y + c.AbsoluteSize.Y + GAP) end
		holder.AnchorPoint = Vector2.new(0.5, 0)
		holder.Position = UDim2.new(0.5, 0, 0, math.floor(top - root.Y))
	else
		local lift = frame and math.clamp(math.floor(size.Y * LOBBY_LIFT_TOUCH), LIFT_MIN_TOUCH, LIFT_MAX)
			or math.clamp(math.floor(size.Y * LOBBY_LIFT), LIFT_MIN, LIFT_MAX)
		local bottom = root.Y + size.Y - lift
		if frame then
			local stick = frame:FindFirstChild("ThumbstickFrame")
			for _, o in pairs({ jump = frame:FindFirstChild("JumpButton"), ring = stick and stick:FindFirstChild("OuterImage") }) do
				if o and o:IsA("GuiObject") and onScreen(o) then
					local p0, p1 = o.AbsolutePosition, o.AbsolutePosition + o.AbsoluteSize
					if p1.X > left and p0.X < right then bottom = math.min(bottom, p0.Y - GAP) end
				end
			end
		end
		holder.AnchorPoint = Vector2.new(0.5, 1)
		holder.Position = UDim2.new(0.5, 0, 0, math.floor(bottom - root.Y))
	end
end

---------------------------------------------------------------- state
local active = false
local phase = "None"
local aloneSince
local shownText

local function show(text, where)
	spot = where
	if text == shownText then return end
	shownText = text
	TweenService:Create(label, FADE, { TextTransparency = 1 }):Play()
	TweenService:Create(icon, FADE, { ImageTransparency = 1 }):Play()
	task.delay(0.2, function()
		if shownText ~= text then return end
		label.Text = text
		TweenService:Create(label, FADE, { TextTransparency = 0 }):Play()
		TweenService:Create(icon, FADE, { ImageTransparency = 0 }):Play()
	end)
end

local function finish()
	if not active then return end
	active = false
	shownText = nil
	gui.Enabled = false
	label.Text = ""
	icon.ImageTransparency = 1
	Remotes:WaitForChild("BoothTutorialSeen"):FireServer()
end

local function start()
	active = true
	shownText = nil
	aloneSince = nil
	fill.Size = UDim2.new(0, 0, 0, 2)
end

Remotes:WaitForChild("StateChanged").OnClientEvent:Connect(function(state)
	phase = type(state) == "table" and state.Phase or "None"
	if phase == "Waiting" then aloneSince = aloneSince or os.clock() else aloneSince = nil end
	if active and (phase == "Selecting" or phase == "Ready" or phase == "Countdown"
		or phase == "Launched" or phase == "Riding") then
		finish()   -- a partner joined: done
	end
end)

RunService.Heartbeat:Connect(function()
	if not active then return end
	local cam = workspace.CurrentCamera
	local hidden = Cinematic.IsActive() or not cam or cam.CameraType ~= Enum.CameraType.Custom
	if gui.Enabled == hidden then gui.Enabled = not hidden end
	if phase == "Waiting" then
		if aloneSince and os.clock() - aloneSince >= ALONE_HINT then show(TEXT_INVITE, "booth")
		else show(TEXT_BOOTH, "booth") end
	elseif phase == "None" or phase == "Empty" then
		show(someoneWaiting() and TEXT_JOIN or TEXT_LOBBY, "lobby")
	end
	if gui.Enabled then place() end
end)

---------------------------------------------------------------- hold to skip
local holding = 0
local function release()
	holding += 1
	TweenService:Create(fill, TweenInfo.new(0.15), { Size = UDim2.new(0, 0, 0, 2) }):Play()
end
skip.InputBegan:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
	holding += 1
	local mine = holding
	TweenService:Create(fill, TweenInfo.new(HOLD_TIME, Enum.EasingStyle.Linear), { Size = FILL_FULL }):Play()
	task.delay(HOLD_TIME, function()
		if holding == mine and active then finish() end
	end)
end)
skip.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then release() end
end)
skip.MouseLeave:Connect(release)

---------------------------------------------------------------- go
replay.Event:Connect(start)
HudSync.WhenIntroDone(function()
	local ok, want = pcall(function() return Remotes:WaitForChild("BoothTutorialState", 10):InvokeServer() end)
	if ok and want and not active then start() end
end)
