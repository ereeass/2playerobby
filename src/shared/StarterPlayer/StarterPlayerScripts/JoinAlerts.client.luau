--=====================================================================
-- JoinAlerts   (each player's own machine)
--
-- JOIN cards down the right of the screen: one per player waiting ALONE in a booth
-- (the server's list, ReplicatedStorage.ScooterSystem.WaitingPlayers - see
-- ServerScriptService.ScooterSystem.JoinAlerts). Each card: their headshot, a "?" for the
-- free seat, their name, how long they've been waiting, and a green JOIN that puts this
-- player straight into the free booth beside them.
--
-- A card slides in when someone starts waiting and slides away the moment they stop
-- (a partner, leaving, a launch) - and back in if they're alone again. At most MAX_CARDS
-- (the longest waiting first).
--
-- Shown ONLY while walking around the lobby (the booth guide arrows' rules). Hidden while:
--   in a booth / queued / counting down / riding     HudSync.Aside
--   spectating a duo in the Troll window             HudSync.Aside
--   the loading screen or intro hasn't handed over   HudSync.WhenIntroDone
--   a cutscene                                       Cinematic.IsActive / camera not Custom
--   on a scooter, seated, dead, or no character
--   a menu open, or a blocking screen up             UITemplates.Menus
--   the first-join booth tutorial is showing         PlayerGui.BoothTutorialGui
--   teleporting to another place
--
-- The ARROW beside them tucks the cards away and brings them back (on by default, every
-- visit). Pointing away from the screen's edge: the cards are out. Pointing at the edge:
-- they're tucked away and the arrow waits at the edge. It shows whenever there is at least
-- one card to show, under the same rules as the cards.
--=====================================================================

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local ScooterSystem = ReplicatedStorage:WaitForChild("ScooterSystem")
local Remotes       = ScooterSystem:WaitForChild("Remotes")
local Cinematic     = require(ScooterSystem:WaitForChild("Cinematic"))
local HudSync       = require(ReplicatedStorage:WaitForChild("HudSync"))
local Menus         = require(ReplicatedStorage:WaitForChild("UITemplates"):WaitForChild("Menus"))
local list          = ScooterSystem:WaitForChild("WaitingPlayers")
local joinRemote    = Remotes:WaitForChild("JoinWaiting")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

---------------------------------------------------------------- settings (tune these)
local MAX_CARDS       = 3        -- 2 on short screens (phones held sideways)
local CARD_W, CARD_H  = 330, 78  -- unscaled; the whole stack has one UIScale
local GAP             = 10       -- between cards
local EDGE            = 14       -- from the right edge of the screen
local TOP_Y           = 0.40     -- the top card's top, of the screen height (PC)
local TOP_Y_TOUCH     = 0.20     -- phones and tablets (clear of the jump button)
local OFF             = CARD_W + 60   -- how far right a card slides to be out of sight
local JOINED_HIDE     = 4        -- after a JOIN that worked: cards away while walking into the booth
local RESULT_TIME     = 1.4      -- a refused JOIN's word stays on the button this long
local ARROW_IMAGE     = "rbxassetid://100295982938578"   -- white, dark outline, pointing right
local ARROW_SIZE      = 50       -- unscaled
local ARROW_GAP       = 6        -- between the arrow and the cards

local GREEN       = Color3.fromRGB(70, 214, 96)
local GREEN_EDGE  = Color3.fromRGB(85, 230, 120)   -- the booth glow's green
local FONT_BODY   = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.SemiBold)
local REFUSED = { gone = "TAKEN", cooldown = "WAIT", rejoin = "WAIT", busy = "BUSY" }

---------------------------------------------------------------- lobby state
local introDone, teleporting = false, false
local joining = false            -- a JOIN is on its way to the server (one at a time)
local joinedAt = -math.huge      -- when a JOIN of ours last worked
HudSync.WhenIntroDone(function() introDone = true end)
player.OnTeleport:Connect(function(state)
	teleporting = state == Enum.TeleportState.Started or state == Enum.TeleportState.InProgress
		or state == Enum.TeleportState.WaitingForServer
end)

local function walking()
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local root = hum and hum.RootPart
	if not (root and root.Parent) or hum.Health <= 0 then return false end
	if hum.Sit or hum.PlatformStand or root:FindFirstChild("ScooterRiderWeld") then return false end
	return true
end

local function tutorialShowing()
	local g = playerGui:FindFirstChild("BoothTutorialGui")
	return g ~= nil and g:IsA("ScreenGui") and g.Enabled
end

local function shouldShow()
	if not introDone or teleporting then return false end
	if os.clock() - joinedAt < JOINED_HIDE then return false end   -- on our way into a booth
	if HudSync.Aside() then return false end
	if Cinematic.IsActive() then return false end
	local cam = workspace.CurrentCamera
	if not cam or cam.CameraType ~= Enum.CameraType.Custom then return false end
	if Menus.IsOpen() or Menus.IsBlocked() then return false end
	if tutorialShowing() then return false end
	return walking()
end

---------------------------------------------------------------- the screen
local gui = Instance.new("ScreenGui")
gui.Name = "JoinAlertsGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 4
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local stack = Instance.new("Frame")
stack.Name = "Stack"
stack.AnchorPoint = Vector2.new(1, 0)
stack.Size = UDim2.fromOffset(CARD_W, (CARD_H + GAP) * MAX_CARDS)
stack.BackgroundTransparency = 1
stack.Parent = gui
local stackScale = Instance.new("UIScale")
stackScale.Parent = stack

-- the cards are out (true) or tucked away; every visit starts with them out
local expanded = true
local arrow = Instance.new("ImageButton")
arrow.Name = "Arrow"
arrow.AnchorPoint = Vector2.new(0.5, 0.5)
arrow.Size = UDim2.fromOffset(ARROW_SIZE, ARROW_SIZE)
arrow.BackgroundTransparency = 1
arrow.Image = ARROW_IMAGE
arrow.Visible = false
arrow.ZIndex = 2
arrow.Parent = stack
local arrowScale = Instance.new("UIScale")
arrowScale.Parent = arrow
local arrowState = { x = nil, vx = 0, y = nil, vy = 0, rot = 180, vrot = 0, s = 1, vs = 0, hover = false, press = false }
arrow.MouseEnter:Connect(function() arrowState.hover = not HudSync.IsTouch() end)   -- no hover on touch (it would stick)
arrow.MouseLeave:Connect(function() arrowState.hover, arrowState.press = false, false end)
arrow.MouseButton1Down:Connect(function() arrowState.press = true end)
arrow.MouseButton1Up:Connect(function() arrowState.press = false end)
arrow.Activated:Connect(function() expanded = not expanded end)

local function viewport()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	if vp.X < 1 or vp.Y < 1 then vp = Vector2.new(1280, 720) end
	return vp
end

local function maxCards()
	return viewport().Y < 500 and 2 or MAX_CARDS
end

local function layout()
	local vp = viewport()
	local touch = HudSync.IsTouch()
	local s = math.clamp(math.min(vp.X, vp.Y) / 1080 * 1.15, 0.62, 1.25)
	if touch then s = math.clamp(s * 1.25, 0.62, 1.1) end
	stackScale.Scale = s
	local top = vp.Y * (touch and TOP_Y_TOUCH or TOP_Y) - gui.AbsolutePosition.Y
	stack.Position = UDim2.new(1, -EDGE, 0, math.max(8, top))   -- never under the top bar
end

---------------------------------------------------------------- one card
local function corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = r
	c.Parent = parent
	return c
end

local function stroke(parent, thickness, transparency, color, border)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Transparency = transparency
	s.Color = color or Color3.new(0, 0, 0)
	s.LineJoinMode = Enum.LineJoinMode.Round
	if border then s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border end
	s.Parent = parent
	return s
end

local function label(parent, props)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.TextColor3 = Color3.new(1, 1, 1)
	for k, v in pairs(props) do t[k] = v end
	t.Parent = parent
	return t
end

local cards = {}   -- [entry] = card record

local function fmtTime(sec)
	sec = math.max(0, math.floor(sec))
	return string.format("Waiting %d:%02d", sec // 60, sec % 60)
end

local function makeCard(entry)
	local holder = Instance.new("Frame")
	holder.Name = "Card_" .. entry.Name
	holder.AnchorPoint = Vector2.new(1, 0)
	holder.Size = UDim2.fromOffset(CARD_W, CARD_H)
	holder.BackgroundTransparency = 1
	holder.Parent = stack
	local pop = Instance.new("UIScale")
	pop.Parent = holder

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = Color3.new(0, 0, 0)
	panel.BackgroundTransparency = 0.45
	panel.Parent = holder
	corner(panel, UDim.new(0, 16))
	stroke(panel, 3, 0.2, nil, true)

	-- the waiting player
	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.Position = UDim2.fromOffset(12, 13)
	avatar.Size = UDim2.fromOffset(52, 52)
	avatar.BackgroundColor3 = Color3.fromRGB(38, 42, 50)
	avatar.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(entry:GetAttribute("UserId")) .. "&w=150&h=150"
	avatar.Parent = panel
	corner(avatar, UDim.new(1, 0))
	stroke(avatar, 2.5, 0, GREEN_EDGE, true)

	-- the free seat
	local seat = Instance.new("Frame")
	seat.Name = "Seat"
	seat.Position = UDim2.fromOffset(72, 13)
	seat.Size = UDim2.fromOffset(52, 52)
	seat.BackgroundColor3 = Color3.new(1, 1, 1)
	seat.BackgroundTransparency = 0.85
	seat.Parent = panel
	corner(seat, UDim.new(1, 0))
	stroke(seat, 2, 0.35, Color3.new(1, 1, 1), true)
	local q = label(seat, {
		Name = "Mark", Size = UDim2.fromScale(1, 1), Text = "?",
		Font = Enum.Font.FredokaOne, TextSize = 30,
	})
	stroke(q, 2, 0)

	local name = label(panel, {
		Name = "PlayerName", Position = UDim2.fromOffset(134, 13), Size = UDim2.fromOffset(110, 26),
		Text = entry:GetAttribute("DisplayName") or "Player", Font = Enum.Font.FredokaOne, TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	})
	stroke(name, 2, 0)
	local timer = label(panel, {
		Name = "Timer", Position = UDim2.fromOffset(134, 41), Size = UDim2.fromOffset(110, 20),
		Text = "", FontFace = FONT_BODY, TextSize = 15, TextColor3 = Color3.fromRGB(210, 220, 230),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	stroke(timer, 1, 0.4)

	-- JOIN (the house button: solid body, light-to-dark gradient, thick black outline)
	local join = Instance.new("TextButton")
	join.Name = "Join"
	join.AnchorPoint = Vector2.new(1, 0.5)
	join.Position = UDim2.fromOffset(CARD_W - 12, CARD_H / 2)
	join.Size = UDim2.fromOffset(74, 46)
	join.BackgroundColor3 = GREEN
	join.Text = ""
	join.AutoButtonColor = false
	join.Parent = panel
	corner(join, UDim.new(0, 12))
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(165, 190, 170))
	grad.Parent = join
	local joinEdge = stroke(join, 3, 0.1, nil, true)
	local joinScale = Instance.new("UIScale")
	joinScale.Parent = join
	local joinText = label(join, {
		Name = "Label", Size = UDim2.fromScale(1, 1), Text = "JOIN",
		Font = Enum.Font.FredokaOne, TextSize = 21,
	})
	stroke(joinText, 2, 0)

	local card = {
		entry = entry, holder = holder, pop = pop, timer = timer,
		joinText = joinText, joinScale = joinScale, joinEdge = joinEdge,
		x = 1, vx = 0, y = nil, vy = 0,      -- x: 0 in place .. 1 out of sight (right)
		leaving = false, pending = false, hover = false, press = false,
		btnCur = 1, btnVel = 0, lastSec = -1, resultUntil = 0,
	}

	join.MouseEnter:Connect(function() card.hover = not HudSync.IsTouch() end)   -- no hover on touch (it would stick)
	join.MouseLeave:Connect(function() card.hover, card.press = false, false end)
	join.MouseButton1Down:Connect(function() card.press = true end)
	join.MouseButton1Up:Connect(function() card.press = false end)
	join.Activated:Connect(function()
		if joining or card.leaving or card.x > 0.3 or not shouldShow() then return end
		joining, card.pending = true, true
		joinText.Text = "..."
		local ok, result = pcall(joinRemote.InvokeServer, joinRemote, entry:GetAttribute("UserId"))
		joining, card.pending = false, false
		if ok and result == "ok" then
			joinedAt = os.clock()
			joinText.Text = "JOIN"          -- they're going in; the card slides away by itself
			return
		end
		joinText.Text = REFUSED[ok and result or "gone"] or "TAKEN"
		card.resultUntil = os.clock() + RESULT_TIME
	end)

	cards[entry] = card
	return card
end

---------------------------------------------------------------- the list
local function track(entry)
	if not entry:IsA("Configuration") or cards[entry] then return end
	if entry:GetAttribute("UserId") == player.UserId then return end   -- never my own card
	makeCard(entry)
end
for _, e in ipairs(list:GetChildren()) do track(e) end
list.ChildAdded:Connect(track)
list.ChildRemoved:Connect(function(entry)
	local card = cards[entry]
	if card then card.leaving = true end
end)

---------------------------------------------------------------- motion
local K, D = HudSync.STIFFNESS, HudSync.DAMPING
local function spring(cur, vel, target, dt)
	vel += ((target - cur) * K - vel * D) * dt
	return cur + vel * dt, vel
end

RunService.Heartbeat:Connect(function(dt)
	dt = math.min(dt, 1 / 20)
	layout()
	local show = shouldShow()

	-- the longest waiting first
	local order = {}
	for _, card in pairs(cards) do
		if not card.leaving then table.insert(order, card) end
	end
	table.sort(order, function(a, b)
		return (a.entry:GetAttribute("Since") or 0) < (b.entry:GetAttribute("Since") or 0)
	end)
	local room = maxCards()
	local slotOf = {}
	for i, card in ipairs(order) do slotOf[card] = i end

	local now = workspace:GetServerTimeNow()
	for entry, card in pairs(cards) do
		local slot = slotOf[card]
		local visible = show and expanded and slot ~= nil and slot <= room
		local targetY = ((math.min(slot or room, room)) - 1) * (CARD_H + GAP)
		if card.y == nil then card.y = targetY end
		card.x, card.vx = spring(card.x, card.vx, visible and 0 or 1, dt)
		card.y, card.vy = spring(card.y, card.vy, targetY, dt)

		if card.leaving and card.x > 0.97 then
			card.holder:Destroy()
			cards[entry] = nil
		else
			local xc = math.max(card.x, -0.2)
			card.holder.Position = UDim2.fromOffset(CARD_W + xc * OFF, card.y)
			card.pop.Scale = 1 - 0.12 * math.clamp(card.x, 0, 1)
			card.holder.Visible = card.x < 0.99

			-- the timer, once a second
			local sec = math.floor(now - (entry:GetAttribute("Since") or now))
			if sec ~= card.lastSec then
				card.lastSec = sec
				card.timer.Text = fmtTime(sec)
			end
			-- a refused JOIN's word goes back to JOIN
			if card.resultUntil > 0 and os.clock() > card.resultUntil and not card.pending then
				card.resultUntil = 0
				card.joinText.Text = "JOIN"
			end
			-- the button's hover / press
			local bt = card.press and 0.94 or (card.hover and 1.06 or 1)
			card.btnCur, card.btnVel = spring(card.btnCur, card.btnVel, bt, dt)
			card.joinScale.Scale = card.btnCur
			card.joinEdge.Thickness = card.hover and 3.5 or 3
			card.joinEdge.Transparency = card.hover and 0 or 0.1
		end
	end

	-- the arrow: beside the cards while they're out (pointing away from the edge), at the edge
	-- while they're tucked away (pointing at it), off screen when there is nothing to show
	local shown = math.min(#order, room)
	local a = arrowState
	local ax
	if not show or shown == 0 then
		ax = CARD_W + OFF                                   -- out of sight
	elseif expanded then
		ax = -ARROW_GAP - ARROW_SIZE / 2                     -- left of the cards
	else
		ax = CARD_W - ARROW_SIZE / 2                         -- at the screen's edge
	end
	local ay = (math.max(shown, 1) * (CARD_H + GAP) - GAP) / 2   -- level with the middle of the cards
	if a.x == nil then a.x, a.y = CARD_W + OFF, ay end
	a.x, a.vx = spring(a.x, a.vx, ax, dt)
	a.y, a.vy = spring(a.y, a.vy, ay, dt)
	a.rot, a.vrot = spring(a.rot, a.vrot, expanded and 180 or 0, dt)
	a.s, a.vs = spring(a.s, a.vs, a.press and 0.88 or (a.hover and 1.1 or 1), dt)
	arrow.Position = UDim2.fromOffset(a.x, a.y)
	arrow.Rotation = a.rot
	arrowScale.Scale = a.s
	arrow.Visible = a.x < CARD_W + OFF - 2
	arrow.Interactable = show and shown > 0   -- no clicks while it is away
end)
