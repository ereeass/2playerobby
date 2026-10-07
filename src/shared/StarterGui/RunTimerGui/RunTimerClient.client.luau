--=====================================================================
-- RunTimerClient   (StarterGui.RunTimerGui)
--
-- Draws the duo's course stopwatch - and nothing else: every state and time comes from
-- the server (ServerScriptService.ScooterSystem.RunTimer, over Remotes.RunTimer), and
-- this never sends anything back.
--   Ready     on a ride from Checkpoint 1: 0:00.00, not counting
--   Running   counting from the server's start time on the server's clock
--             (GetServerTimeNow), so both riders see the same time
--   Finished  frozen on the server's own final time, in gold, with a small pop
--   None      hidden (the ride is over)
-- Shown only while the player has it switched on (the stopwatch button,
-- StarterGui.StopwatchGui, attribute "On"; off by default). The state is always
-- followed, so switching it on mid-ride shows the time the run is already on.
-- Look (the reference): white rounded bold digits with a dark outline and no panel,
-- top centre just under Roblox's top bar. Every character has its own fixed-width
-- slot, so the digits never shuffle sideways as they change. Its size follows the
-- screen (Fit: from the screen's short side, a little bigger on small touch screens),
-- the same on every resolution and UI scale. It only updates every frame while it counts.
--=====================================================================

local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local TS         = game:GetService("TweenService")
local RS         = game:GetService("ReplicatedStorage")

local Root    = RS:WaitForChild("ScooterSystem")
local remote  = Root:WaitForChild("Remotes"):WaitForChild("RunTimer")
local RunTime = require(Root:WaitForChild("Shared"):WaitForChild("RunTime"))

local gui    = script.Parent
local holder = gui:WaitForChild("Timer")
local fit    = holder:WaitForChild("Fit")
local digits = holder:WaitForChild("Digits")
local pop    = digits:WaitForChild("Pop")
local toggle = gui.Parent:WaitForChild("StopwatchGui")   -- its "On" attribute: the player wants it shown

-- the look, at a 1080-pixel-high screen (Fit scales it from there)
local FONT        = Enum.Font.FredokaOne
local TEXT_SIZE   = 28
local HEIGHT      = 34
local DIGIT_W     = 16      -- a digit's slot
local SEP_W       = 8       -- a ":" or "." slot
local WHITE       = Color3.new(1, 1, 1)
local GOLD        = Color3.fromRGB(255, 214, 72)
local OUTLINE     = Color3.fromRGB(20, 22, 34)
local OUTLINE_W   = 2.2
local FIT_MIN, FIT_MAX = 0.75, 1.6

---------------------------------------------------------------- the digits
local slots = {}
local shown, colour = nil, WHITE

local function slot(i)
	local s = slots[i]
	if s then return s end
	s = Instance.new("TextLabel")
	s.Name = "Char" .. i
	s.LayoutOrder = i
	s.BackgroundTransparency = 1
	s.Font = FONT
	s.TextSize = TEXT_SIZE
	s.TextColor3 = colour
	s.TextXAlignment = Enum.TextXAlignment.Center
	s.TextYAlignment = Enum.TextYAlignment.Center
	local stroke = Instance.new("UIStroke")
	stroke.Color = OUTLINE
	stroke.Thickness = OUTLINE_W
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = s
	s.Parent = digits
	slots[i] = s
	return s
end

local function show(text)
	if text == shown then return end
	shown = text
	local width = 0
	for i = 1, #text do
		local c = text:sub(i, i)
		local s = slot(i)
		local w = (c == ":" or c == ".") and SEP_W or DIGIT_W
		if s.Text ~= c then s.Text = c end
		s.Size = UDim2.fromOffset(w, HEIGHT)
		s.Visible = true
		width += w
	end
	for i = #text + 1, #slots do slots[i].Visible = false end
	holder.Size = UDim2.fromOffset(width + 8, HEIGHT)
end

local function tint(c)
	colour = c
	for _, s in ipairs(slots) do s.TextColor3 = c end
end

---------------------------------------------------------------- size
local function refit()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize
	if not vp or vp.X < 1 or vp.Y < 1 then return end
	local short = math.min(vp.X, vp.Y)
	local s = short / 1080
	if UIS.TouchEnabled and not UIS.MouseEnabled and short < 600 then s *= 1.25 end   -- phones: easier to read
	fit.Scale = math.clamp(s, FIT_MIN, FIT_MAX)
end
local function watchCamera()
	local cam = workspace.CurrentCamera
	if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(refit) end
	refit()
end
watchCamera()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)

---------------------------------------------------------------- states
local ticking   -- the per-frame update, only while counting
local startedAt
local active = false   -- on a ride (any state but None), whether or not it is shown

local function stopTicking()
	if ticking then ticking:Disconnect() ticking = nil end
end

local function wanted() return toggle:GetAttribute("On") == true end
local function refresh() holder.Visible = active and wanted() end

toggle:GetAttributeChangedSignal("On"):Connect(function()
	if startedAt and ticking then show(RunTime.Format(workspace:GetServerTimeNow() - startedAt)) end
	refresh()
end)

remote.OnClientEvent:Connect(function(msg)
	if type(msg) ~= "table" then return end
	local state = msg.State
	if state == "Ready" then
		stopTicking()
		tint(WHITE)
		show(RunTime.Format(0))
		active = true
	elseif state == "Running" and type(msg.StartedAt) == "number" then
		startedAt = msg.StartedAt
		tint(WHITE)
		active = true
		stopTicking()
		ticking = RunService.RenderStepped:Connect(function()
			if holder.Visible then show(RunTime.Format(workspace:GetServerTimeNow() - startedAt)) end
		end)
	elseif state == "Finished" and type(msg.Time) == "number" then
		stopTicking()
		show(RunTime.Format(msg.Time))   -- the server's time, not this clock's
		tint(GOLD)
		active = true
		pop.Scale = 1.3
		TS:Create(pop, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	else   -- "None": the ride is over
		stopTicking()
		active = false
	end
	refresh()
end)
