--=====================================================================
-- Menu   (DailyUI)
--
-- The Daily Rewards window (StarterGui.DailyWindow): the house panel as the Skins
-- window has it - the same size, title and red X - in green, with studs a shade
-- lighter all over it (Panel.Studs). It moves like every menu (UITemplates.Menus):
-- it drops in from above, fades as one and dims the world behind; only the red X,
-- B, the DAILY tile again, or another menu opening close it. On a touch screen it
-- fits under Roblox's top bar exactly as the Skins window does.
-- Inside (Panel.Content): the status line, the seven days (Days.Day1..7) and CLAIM
-- (the house button, as REVIVE). All drawn from what the server says (DailyRewards:
-- the player's DailyDay and DailyNextAt attributes); CLAIM only asks
-- (Remotes.DailyClaim) - the server decides, gives the reward and moves the clock.
-- Every day is the Skins window's card (its CardTemplate): "DAY n" as its white headline,
-- the reward in the dark well with what it is under the headline in one soft colour (a
-- skin's well is lighter, so the scooter shows), and the day's state at a glance:
--   Claimed  a green tick stamped over the reward, the card sat back a little
--   Ready    today: lifted and floating gently, with a gold rim and glow (the one CLAIM takes)
--   Waiting  the next day while its 24 h runs: a grey pill counts down
--   Locked   days further on: darker, with a small padlock; the reward stays in view
--   Soon     a day with no reward set yet: "?" and SOON
-- One call to action: CLAIM. The line above the cards only speaks up to say what a claim
-- gave (or why it didn't).
-- The cards are the Troll window's name pill in green: a deeper green than the studded
-- panel, with a dark green rim, the studs showing round them. Anything not unlocked
-- yet is grey: the LOCKED / SOON / countdown pills, and CLAIM (with the countdown)
-- until a day is ready, when it turns bright green.
--=====================================================================

local RunService       = game:GetService("RunService")
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService       = game:GetService("GuiService")
local RS               = game:GetService("ReplicatedStorage")

local selector    = RS:WaitForChild("CheckpointSelector")
local Motion      = require(selector:WaitForChild("Motion"))
local Sfx         = require(selector:WaitForChild("Sfx"))
local Menus       = require(RS:WaitForChild("UITemplates"):WaitForChild("Menus"))

local playerGui   = Players.LocalPlayer:WaitForChild("PlayerGui")
local winGui      = playerGui:WaitForChild("DailyWindow")
local dim         = winGui:WaitForChild("Dim")
local window      = winGui:WaitForChild("Window")
local winScale    = window:WaitForChild("Scale")
local panel       = window:WaitForChild("Panel")
local panelSweep  = panel:WaitForChild("Sweep")
local closeBtn    = panel:WaitForChild("CloseButton")
local closeScale  = closeBtn:WaitForChild("Scale")
local cross       = closeBtn:WaitForChild("Cross")
local title       = panel:WaitForChild("Title")
local titleEdge   = title:WaitForChild("UIStroke")
local settingsWin = playerGui:WaitForChild("SettingsWindow"):WaitForChild("Window")
local content     = panel:WaitForChild("Content")
local statusLbl   = content:WaitForChild("Status")
local daysHolder  = content:WaitForChild("Days")
local claimHolder = content:WaitForChild("ClaimButton")
local claimFace   = claimHolder:WaitForChild("Face")
local claimLabel  = claimFace:WaitForChild("Label")
local claimSweep  = claimFace:WaitForChild("Sweep")
local Root        = RS:WaitForChild("ScooterSystem")
local Days        = require(Root:WaitForChild("Shared"):WaitForChild("DailyRewards"))
local DailyClaim  = Root:WaitForChild("Remotes"):WaitForChild("DailyClaim")
-- the Skins window's scooter preview, for a skin's day
local Preview     = require(playerGui:WaitForChild("ScootersGui"):WaitForChild("ScootersUI"):WaitForChild("Preview"))
local player      = Players.LocalPlayer

local DIM_MAX = 0.25        -- how far the world darkens, as Settings

local sfx   = Sfx.new(winGui:WaitForChild("Sfx"))
local fader = Motion.fader(nil)
fader:trackTree(window)

local Menu = {}
local slide = Menus.new(window, { dim = dim, onReplace = function() Menu.Close() end })

local isOpen = false
local winA = 0

-- On a touch screen the red X gets a bigger, invisible tap area, as on the Skins
-- window: it grows up and out, past the window's corner. It looks exactly the
-- same; PC never has it.
local closeHit = Instance.new("TextButton")
closeHit.Name = "TouchHit"
closeHit.Position = UDim2.fromOffset(-4, -34)
closeHit.Size = UDim2.new(1, 38, 1, 38)
closeHit.BackgroundTransparency = 1
closeHit.Text = ""
closeHit.AutoButtonColor = false
closeHit.Selectable = false
closeHit.ZIndex = closeBtn.ZIndex + 1
closeHit.Visible = false
closeHit.Parent = closeBtn

local cCur, cVel, crossRot = 1, 0, 0
local closeHover, closePressed = false, false

--------------------------------------------------------------------- the calendar
local RGB   = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local SLACK = 0.5   -- s: a day reads as ready this long after the server's time, so a
                    -- claim never beats the server's own clock
local PILL = {      -- the day's pill: a flat fill with a black rim, as the Skins pills
	Claimed = { text = "CLAIMED", fill = RGB(76, 202, 88) },
	Ready   = { text = "READY",   fill = RGB(255, 170, 28) },
	-- not unlocked yet: grey (the owners' rule for every button that isn't open yet)
	Waiting = { text = "",        fill = RGB(122, 128, 144) },   -- the countdown
	Locked  = { text = "LOCKED",  fill = RGB(122, 128, 144) },
	Soon    = { text = "SOON",    fill = RGB(122, 128, 144) },
}
-- each reward's name, coloured for it as the Skins names are (top, bottom, outline), and
-- the glow at the foot of its card
local NAME = {
	Revive = { RGB(255, 198, 212), RGB(255, 86, 122),  RGB(70, 8, 28),  RGB(255, 90, 130) },
	Skip   = { RGB(172, 250, 240), RGB(38, 200, 190),  RGB(0, 50, 54),  RGB(60, 220, 210) },
	Skin   = { RGB(255, 238, 120), RGB(255, 170, 30),  RGB(66, 34, 0),  RGB(255, 194, 46) },   -- the Bee's
	-- a skin's own colours (as its Skins card name), by "Skin" .. its Id
	SkinGrass = { RGB(196, 250, 120), RGB(62, 170, 48),  RGB(14, 50, 10), RGB(92, 210, 70) },
	SkinBeach = { RGB(255, 232, 160), RGB(240, 180, 90), RGB(60, 40, 14), RGB(90, 206, 222) },
	Soon   = { RGB(214, 240, 206), RGB(146, 190, 140), RGB(12, 40, 18), RGB(120, 210, 120) },
}
local RIM, RIM_READY = RGB(10, 50, 20), RGB(255, 196, 60)   -- the card's rim: dark green, gold when ready
local DIMMED    = RGB(186, 212, 180)   -- a locked reward, a touch dimmed (still in view)
local LOCK_SIZE = 0.42                 -- the Skins padlock, small in the well's corner
local REWARD_INK    = RGB(214, 240, 206)   -- what a day gives, under its DAY headline: one soft colour
local LOCKED_SHADE  = RGB(150, 160, 150)   -- days further on sit darker
local CLAIMED_SHADE = RGB(205, 215, 205)   -- claimed days sit back a little
local TALLER        = 22                 -- px each card grows now there's no line above them (the second
                                         -- row's pill must clear CLAIM: 28 made them touch)
local TOP_PAD       = 6                  -- px from the top of the content to the first row

-- a claimed day's stamp: a chunky cartoon tick over the reward
local CHECK_ICON = "rbxassetid://101901789819557"
local function checkStamp(frame)
	local tick = Instance.new("ImageLabel")
	tick.Name = "Check"
	tick.BackgroundTransparency = 1
	tick.Image = CHECK_ICON
	tick.ScaleType = Enum.ScaleType.Fit
	tick.AnchorPoint = Vector2.new(0.5, 0.5)
	tick.Position = UDim2.new(0.5, 0, 0, 102)
	tick.Size = UDim2.fromOffset(84, 84)
	tick.Rotation = -6
	tick.ZIndex = 9
	tick.Visible = false
	tick.Parent = frame
	fader:trackTree(tick)
	return tick
end
-- CLAIM's face (top, bottom), lip and outlines: green while a day is ready, grey while not
local CLAIM_ON  = { RGB(130, 234, 110), RGB(48, 176, 74),   RGB(30, 112, 48), RGB(14, 60, 26) }
local CLAIM_OFF = { RGB(178, 184, 198), RGB(122, 128, 144), RGB(82, 86, 100), RGB(40, 44, 54) }   -- grey: nothing to claim yet
local claimGrad  = claimFace:WaitForChild("UIGradient")
local claimLip   = claimHolder:WaitForChild("Lip")
local claimEdges = { claimFace:WaitForChild("Edge"), claimLip:WaitForChild("Edge"), claimLabel:WaitForChild("UIStroke") }
local SIDE_ON   = math.rad(90)        -- a skin's preview: side on, standing still
local SIDE_FIT  = 1.45                -- ...framed to fit the WHOLE scooter (wheels to handlebars) in
                                      -- the part of its box between the DAY label and the pill

-- The calendar as the server has it, or nil until it has loaded: the last day claimed,
-- the next day and its reward (nil: not set yet), the seconds until it is ready, and
-- whether it is ready now. The DAILY tile's notification reads it too.
function Menu.Status()
	local day, nextAt = player:GetAttribute("DailyDay"), player:GetAttribute("DailyNextAt")
	if type(day) ~= "number" or type(nextAt) ~= "number" then return nil end
	local reward = Days.Get(day + 1)
	local left = math.max(nextAt + SLACK - workspace:GetServerTimeNow(), 0)
	return { day = day, nextDay = day + 1, reward = reward, left = left, ready = reward ~= nil and left <= 0 }
end

local function clock(s)
	s = math.ceil(s)
	return string.format("%02d:%02d:%02d", s // 3600, s % 3600 // 60, s % 60)
end

local function gives(reward)
	if reward.Kind == "Skin" then return "the " .. reward.Name end
	local n = reward.Amount or 1
	return n .. " " .. reward.Name .. (n == 1 and "" or "s")
end

-- the seven cards; what each day gives never changes, so it is set once
local cards = {}
for i = 1, Days.Count do
	local frame = daysHolder:WaitForChild("Day" .. i)
	local r = Days.Get(i)
	local action = frame:WaitForChild("Action")
	local glow = frame:WaitForChild("Glow")
	local c = {
		i = i, reward = r, scale = frame:WaitForChild("Scale"), edge = frame:WaitForChild("Edge"),
		glow = glow, falloff = glow:WaitForChild("Falloff"), icon = frame:WaitForChild("Icon"), view = frame:WaitForChild("View"),
		action = action, label = action:WaitForChild("Label"), sweep = action:WaitForChild("Sweep"),
		lock = frame:WaitForChild("Lock"),
		look = nil, s = 1, sv = 0, ls = 0, lsv = 0, glowA = 0,
	}
	c.lockPop = c.lock:WaitForChild("Pop")
	local style = (r and r.Kind == "Skin" and NAME["Skin" .. r.Skin]) or NAME[r and r.Kind or "Soon"] or NAME.Soon
	c.tint = style[4]
	-- the day is the headline (white, as every title in the game); what it gives sits
	-- under it in the well, in one soft colour - no colour per reward
	local title = frame:WaitForChild("Title")
	title.Text = "DAY " .. i
	title.TextColor3 = WHITE
	title:WaitForChild("UIStroke").Color = Color3.new(0, 0, 0)
	local rewardLbl = frame:WaitForChild("DayLabel")
	rewardLbl.Text = r and string.upper(r.Name) or "???"
	rewardLbl.TextColor3 = REWARD_INK
	rewardLbl.Size = UDim2.new(1, -40, 0, 19)
	rewardLbl.TextScaled = true
	c.frame, c.home = frame, frame.Position
	c.shadow = frame:WaitForChild("ActionShadow")
	c.well = frame:WaitForChild("Well")
	c.check = checkStamp(frame)
	-- a skin's scooter is lit brighter so it stands out on the dark well (the same well as
	-- every other day: the owners found a lighter one for skins odd)
	if r and r.Kind == "Skin" then
		c.view.LightColor, c.view.Ambient = WHITE, RGB(215, 215, 215)
	end
	frame:WaitForChild("Mystery").Visible = r == nil
	c.icon.Visible = r ~= nil and r.Kind ~= "Skin"
	if r and r.Icon then c.icon.Image = r.Icon end
	local amount = frame:WaitForChild("Amount")
	amount.Visible = r ~= nil and r.Amount ~= nil
	amount.Text = (r and r.Amount) and ("x" .. r.Amount) or ""
	c.view.Visible = r ~= nil and r.Kind == "Skin"
	if c.view.Visible then c.preview = Preview.new(c.view, r.Skin, SIDE_ON) end
	-- taller cards: the strip above them is gone, so each card grows by TALLER and what's in
	-- its well grows / moves down with it (bigger pictures)
	frame.Size += UDim2.fromOffset(0, TALLER)
	if frame.Position.Y.Offset > 0 then frame.Position += UDim2.fromOffset(0, TALLER) end   -- the second row
	c.home = frame.Position
	c.well.Size += UDim2.fromOffset(0, TALLER)
	c.view.Size += UDim2.fromOffset(0, TALLER)
	for _, name in ipairs({ "Icon", "Mystery", "Check" }) do
		local o = frame:FindFirstChild(name)
		if o then
			o.Position += UDim2.fromOffset(0, TALLER / 2)
			o.Size += UDim2.fromOffset(TALLER / 2, TALLER / 2)
		end
	end
	amount.Position += UDim2.fromOffset(0, TALLER)
	cards[i] = c
end

-- the cards start right under the window's top edge (no status line above them any more)
daysHolder.Position = UDim2.fromOffset(0, TOP_PAD)
daysHolder.Size += UDim2.fromOffset(0, 2 * TALLER)

local function lookOf(c, st)
	if not st then return "Locked" end
	if c.i <= st.day then return "Claimed" end
	if not c.reward then return "Soon" end
	if c.i == st.nextDay then return st.ready and "Ready" or "Waiting" end
	return "Locked"
end

-- CLAIM: asks once; the server's answer (and its new attributes) is what gets drawn
local asking = false
local flashText, flashUntil = nil, 0
local function flash(text) flashText, flashUntil = text, os.clock() + 2.6 end

local claimBtn
claimBtn = Motion.button(claimHolder, {
	fader = fader, sfx = sfx, hover = 1.04, press = 0.95, lift = 2, sink = 4,
	onActivate = function()
		local st = Menu.Status()
		if asking or not isOpen or not (st and st.ready) then claimBtn:shake() return end
		asking = true
		local day, reward = st.nextDay, st.reward
		task.spawn(function()
			local ok, given, why = pcall(DailyClaim.InvokeServer, DailyClaim)
			asking = false
			if ok and given then
				sfx:play("Success")
				local c = cards[day]
				if c then c.sv += 3; Motion.sweep(c.sweep, 0.55) end
				flash("You got " .. gives(reward) .. "!")
			else
				claimBtn:shake()
				if not ok or why then flash(ok and why or "Couldn't claim - try again.") end
			end
		end)
	end,
})

local nextGlare = 0
local claimLit          -- CLAIM's colours as last set (green / grey)
local function drawCalendar(dt)
	local st = Menu.Status()
	local pulse = 0.5 + 0.5 * math.sin(os.clock() * 3.2)
	local glare = os.clock() > nextGlare
	if glare then nextGlare = os.clock() + 2.6 end
	for _, c in ipairs(cards) do
		local look = lookOf(c, st)
		if look ~= c.look then
			c.look = look
			local P = PILL[look]
			c.label.Text = P.text
			c.action.BackgroundColor3 = P.fill
			-- only the countdown (and SOON) keep a pill: a claimed day has its tick, today its gold
			local pill = look == "Waiting" or look == "Soon"
			c.action.Visible, c.shadow.Visible = pill, pill
			c.check.Visible = look == "Claimed"
			c.frame.BackgroundColor3 = (look == "Locked" and LOCKED_SHADE) or (look == "Claimed" and CLAIMED_SHADE) or WHITE
			local tint = (look == "Locked" or look == "Soon") and DIMMED or WHITE
			c.icon.ImageColor3, c.view.ImageColor3 = tint, tint
			-- a claimed reward fades back: it's theirs, the eye moves on
			fader:setBase(c.icon, "ImageTransparency", look == "Claimed" and 0.7 or 0)
			fader:setBase(c.view, "ImageTransparency", look == "Claimed" and 0.7 or 0)
		end
		-- the next day's pill counts down to it
		if look == "Waiting" then
			local left = clock(st.left)
			if c.label.Text ~= left then c.label.Text = left end
		end
		-- a small padlock in the well's corner on days further on
		c.ls, c.lsv = Motion.spring(c.ls, c.lsv, (look == "Locked" and c.reward) and LOCK_SIZE or 0, 260, 16, dt)
		c.lockPop.Scale = math.max(c.ls, 0.01)
		c.lock.Visible = c.ls > 0.02
		-- the ready day: a gold rim, a fuller gold glow, a gentle breath and a glare on its pill
		local ready = look == "Ready"
		c.glowA = Motion.approach(c.glowA, ready and 1 or 0, 8, dt)
		c.edge.Color = RIM:Lerp(RIM_READY, c.glowA)
		c.edge.Thickness = 2.5 + 0.5 * c.glowA
		fader:setBase(c.edge, "Transparency", 0.1 - 0.1 * c.glowA)
		c.falloff.Color = ColorSequence.new(c.tint:Lerp(RIM_READY, c.glowA))
		local glowT = (look == "Claimed" and 0.8) or ((look == "Locked" or look == "Soon") and 0.85) or 0.55
		fader:setBase(c.glow, "BackgroundTransparency", glowT + ((0.12 + 0.2 * pulse) - glowT) * c.glowA)
		c.s, c.sv = Motion.spring(c.s, c.sv, 1 + (ready and 0.02 * pulse or 0), 300, 20, dt)
		c.scale.Scale = math.max(c.s, 0.01)
		-- today's card is lifted and floats gently
		c.frame.Position = c.home + UDim2.fromOffset(0, -c.glowA * (4 + 2 * math.sin(os.clock() * 2.4)))
		if ready and glare then Motion.sweep(c.sweep, 0.6) end
		if c.preview and c.preview.model then
			c.preview:place()
			-- side on, backed off just enough that the whole model fits the box's width and height
			local cam = c.preview.cam
			local box, size = c.preview.model:GetBoundingBox()
			local focus = box.Position
			local dir = (cam.CFrame.Position - focus).Unit
			local view = c.view.AbsoluteSize
			local aspect = view.Y > 0 and view.X / view.Y or 1
			local tanV = math.tan(math.rad(cam.FieldOfView) / 2)
			local side = cam.CFrame.RightVector
			-- the model's extent across the screen and up it, from its box's corners
			local w, h = 0, 0
			for _, sx in ipairs({ -1, 1 }) do for _, sy in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do
				local p = box:PointToWorldSpace(size * Vector3.new(sx, sy, sz) / 2) - focus
				w = math.max(w, math.abs(p:Dot(side)))
				h = math.max(h, math.abs(p.Y))
			end end end
			local dist = math.max(h / tanV, w / (tanV * aspect)) * SIDE_FIT
			cam.CFrame = CFrame.lookAt(focus + dir * dist, focus)
		end
	end

	local text
	if not st then
		text = "Loading..."
	elseif st.ready then
		text = ("Day %d is ready to claim!"):format(st.nextDay)
	elseif not st.reward then
		text = "More rewards coming soon!"
	else
		text = ("Come back later for Day %d!"):format(st.nextDay)   -- the countdown is on its pill and CLAIM
	end
	-- no line above the cards any more: what a claim gave (or why it didn't) shows on CLAIM
	-- itself for a moment, and the cards and CLAIM already show what's ready
	local flashing = os.clock() < flashUntil
	statusLbl.Visible = false

	-- CLAIM: green while a day is ready; grey with the countdown while not (a press only shakes)
	local lit = st ~= nil and st.ready
	local label = (flashing and flashText) or (asking and "...") or (lit and "CLAIM") or (st and st.reward and clock(st.left))
		or (st and "COMING SOON") or "..."
	if claimLabel.Text ~= label then claimLabel.Text = label end
	if lit ~= claimLit then
		claimLit = lit
		local C = lit and CLAIM_ON or CLAIM_OFF
		claimGrad.Color = ColorSequence.new(C[1], C[2])
		claimLip.BackgroundColor3 = C[3]
		for _, e in ipairs(claimEdges) do e.Color = C[4] end
	end
	if lit and not asking and glare then Motion.sweep(claimSweep, 0.6) end
	claimBtn:update(dt)
end

--------------------------------------------------------------------- responsive (as the Skins window)
local BASE_W = window.Size.X.Offset
local BASE_H = window.Size.Y.Offset + 30       -- the title rides above the panel
local TITLE_SIZE, TITLE_EDGE = title.TextSize, titleEdge.Thickness
local WINDOW_SIZE     = 0.565  -- about 830 x 490 on a 1080p screen, as the Skins window
local TOUCH_MARGIN_X  = 0.08   -- touch: of the screen's width, each side (clears a notch)
local TOUCH_MARGIN_Y  = 0.10   -- touch: of the height under the top bar, above and below
local TOUCH_TITLE_MAX = 1.6    -- touch: the title grows at most this much over the window
local BASE_HOME = slide.home   -- where the window sits on PC: the middle of the screen
local rootScale = 1
local function updateScale()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local vp = cam.ViewportSize
	if vp.X < 1 or vp.Y < 1 then return end
	local minAxis = math.min(vp.X, vp.Y)
	local s = minAxis / 720
	if Motion.isTouch() and minAxis < 500 then s *= 1.15 end
	local raw = s
	s = math.clamp(s * WINDOW_SIZE, 0.75, 1.15)   -- a compact window, even on big screens
	rootScale = math.min(s, vp.X * 0.94 / BASE_W, vp.Y * 0.9 / BASE_H)
	local home = BASE_HOME
	local touch = Motion.isTouch()
	if touch then
		local top = GuiService:GetGuiInset().Y
		rootScale = math.min(rootScale,
			vp.X * (1 - 2 * TOUCH_MARGIN_X) / BASE_W,
			(vp.Y - top) * (1 - 2 * TOUCH_MARGIN_Y) / BASE_H)
		-- the middle of the space under the top bar; the title rides above the
		-- panel, so the panel sits that much lower for the two to be centred together
		home = UDim2.new(0.5, 0, 0.5, top / 2 + (BASE_H - window.Size.Y.Offset) / 2 * rootScale)
	end
	slide:setHome(home)
	-- the title text matches the Settings title on screen, as the Skins window's
	local sw = settingsWin.Size
	local settingsScale = math.min(math.clamp(raw, 0.75, 1.3), vp.X * 0.94 / sw.X.Offset, vp.Y * 0.9 / sw.Y.Offset)
	local k = settingsScale / rootScale
	if touch then k = math.min(k, TOUCH_TITLE_MAX) end
	title.TextSize = math.round(TITLE_SIZE * k)
	titleEdge.Thickness = TITLE_EDGE * k
	closeHit.Visible = touch
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

--------------------------------------------------------------------- open / close
function Menu.IsOpen()
	return isOpen
end

function Menu.Open()
	if isOpen then return end
	if not slide:open() then return false end  -- a blocking screen is up: the tile shakes and says why
	isOpen = true
	updateScale()
	if winA < 0.05 then
		task.delay(0.24, function() if isOpen then Motion.sweep(panelSweep, 0.75) end end)
	end
	-- no open / close whoosh, as the Skins window (the tile's own click stays)
	window.Visible, dim.Visible = true, true
	return true
end

function Menu.Close()
	if not isOpen then return end
	isOpen = false
	slide:close()
	closeHover, closePressed = false, false
	claimBtn:reset()
	local sel = GuiService.SelectedObject
	if sel and sel:IsDescendantOf(winGui) then GuiService.SelectedObject = nil end
	-- the frame loop hides the window once it has faded out
end

-- what the DAILY tile does (UITemplates.Menus): false = the open was refused
function Menu.Toggle()
	return slide:toggle(Menu.Open, Menu.Close)
end

--------------------------------------------------------------------- input (connected once)
closeBtn.MouseEnter:Connect(function()
	if Motion.isTouch() or not isOpen then return end
	closeHover = true
	sfx:play("Hover")
end)
closeBtn.MouseLeave:Connect(function() closeHover, closePressed = false, false end)
closeBtn.MouseButton1Down:Connect(function()
	if not isOpen then return end
	closePressed = true
	sfx:play("Click")
end)
closeBtn.InputEnded:Connect(function(input)
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then closePressed = false end
end)
closeBtn.SelectionGained:Connect(function() closeHover = true end)
closeBtn.SelectionLost:Connect(function() closeHover = false end)
closeBtn.Activated:Connect(Menu.Close)
-- its touch tap area does what the X does
closeHit.MouseButton1Down:Connect(function()
	if not isOpen then return end
	closePressed = true
	sfx:play("Click")
end)
closeHit.InputEnded:Connect(function(input)
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then closePressed = false end
end)
closeHit.Activated:Connect(Menu.Close)

-- the Dim only darkens: clicks outside the window go through it (UITemplates.Menus)

UserInputService.InputBegan:Connect(function(input)
	if isOpen and input.KeyCode == Enum.KeyCode.ButtonB then Menu.Close() end
end)

--------------------------------------------------------------------- frame loop
RunService.RenderStepped:Connect(function(dt)
	if not window.Visible then return end
	dt = math.min(dt, 1 / 30)

	-- slides in from above and back up (UITemplates.Menus); the fade and the dim follow it
	winScale.Scale = rootScale
	winA = slide:alpha()
	fader:set(winA, {})
	dim.BackgroundTransparency = 1 - DIM_MAX * winA

	-- close button: a spring pop, and the cross turns a quarter on hover (as Settings)
	cCur, cVel = Motion.spring(cCur, cVel, closePressed and 0.88 or (closeHover and 1.1 or 1), 300, 18, dt)
	closeScale.Scale = math.max(cCur, 0.01)
	crossRot = Motion.approach(crossRot, closeHover and 90 or 0, 12, dt)
	cross.Rotation = crossRot

	drawCalendar(dt)

	if not isOpen and winA < 0.01 then
		winA = 0
		fader:set(0, {})
		window.Visible, dim.Visible = false, false
	end
end)

return Menu
