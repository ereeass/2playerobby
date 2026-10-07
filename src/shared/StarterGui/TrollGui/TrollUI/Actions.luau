--=====================================================================
-- Actions   (TrollUI)
--
-- The Troll window's troll buttons, down the LEFT side of the screen while the window is open
-- (an effect with Side = "Right" in the list goes down the RIGHT side instead, mirrored)
-- (watching a duo or not - bought with no duo on screen, one is saved as a free one for later): one per effect in ReplicatedStorage.TrollFx.Effects - its image with no background,
-- held still, tilted as the list says (Rocket Launch: 45 degrees clockwise), its name under it in
-- white and what it does in tilted yellow at its top right, both heavy caps in a black stroke.
-- The button swells on hover and squashes when pressed, with the house tiles' sounds; a saved
-- free one shows as the red count (UITemplates.CountBadge).
--
-- A button only ASKS the server to troll the duo on screen (Remotes.TrollRequest) - it never
-- does anything itself. The server checks everything, then plays a saved free one or opens
-- Roblox's purchase window; only Roblox's receipt starts a bought one. While a request or a
-- purchase window is open, or the duo on screen is already being trolled, the buttons dim and
-- only shake; a refusal shakes and says why under the button.
-- The server's notes to the buyer (a purchase saved as a free one, a duo that left before the
-- end) pop up at the top of the screen, whether the window is open or not.
--=====================================================================

local Players            = game:GetService("Players")
local TweenService       = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local RS                 = game:GetService("ReplicatedStorage")

local selector   = RS:WaitForChild("CheckpointSelector")
local Motion     = require(selector:WaitForChild("Motion"))
local Sfx        = require(selector:WaitForChild("Sfx"))
local CountBadge = require(RS:WaitForChild("UITemplates"):WaitForChild("CountBadge"))
local Effects    = require(RS:WaitForChild("TrollFx"):WaitForChild("Effects"))
local Root       = RS:WaitForChild("ScooterSystem")
local Config     = require(Root:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes    = Root:WaitForChild("Remotes")
local request    = Remotes:WaitForChild("TrollRequest")
local alert      = Remotes:WaitForChild("TrollAlert")

local player  = Players.LocalPlayer
local winGui  = player:WaitForChild("PlayerGui"):WaitForChild("TrollWindow")
-- the TROLL tile's own gui keeps clear of a phone's notch (CoreUISafeInsets); this window's
-- doesn't, so the buttons take their place from that one
local safeGui = player.PlayerGui:WaitForChild("TrollGui")
local sfx     = Sfx.new(winGui:WaitForChild("Sfx"))

local FONT      = Font.new("rbxasset://fonts/families/FredokaOne.json")
local NAME_FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local TAG_FONT  = Font.new("rbxasset://fonts/families/LuckiestGuy.json")
local TAG_COLOR = Color3.fromRGB(255, 232, 0)
local DEAL_COLOR = Color3.fromRGB(240, 36, 36)
local HINT_FONT = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold)
local ICON      = 128     -- px: the image's box
local WIDTH     = 176     -- px: a button, words included
local HOLDER_H  = ICON + 40   -- px: a button's slot in the column (the words end at ICON + 26)
local HINT_TIME = 2.4     -- seconds a refusal's reason stays up
local TOUCH_UP  = 0.08    -- phones and tablets: both columns sit this much of the screen's height higher (PC: centred)
local RIGHT_IN  = 36      -- px the right-hand column keeps further in (its yellow words stick out to the right)
local PROMPT_MAX = 60     -- seconds a purchase window may keep a button busy, at most
local TOAST_TIME = 4.5
local PRODUCTS  = Config.TrollProducts or {}
local HudSync   = require(RS:WaitForChild("HudSync"))

local Actions = {}

--------------------------------------------------------------------- the buttons
-- a column of buttons: Left (level with the lobby tiles) or Right (mirrored on the other side)
local function makeColumn(side)
	local root = Instance.new("Frame")
	root.Name = side == "Right" and "ActionsRight" or "Actions"
	root.BackgroundTransparency = 1
	root.AnchorPoint = side == "Right" and Vector2.new(1, 0) or Vector2.new(0, 0)
	root.Position = UDim2.new(0, 30, 0.5, 0)
	root.Size = UDim2.fromOffset(WIDTH, 10)
	root.AutomaticSize = Enum.AutomaticSize.Y
	root.Visible = false
	root.ZIndex = 6
	root.Parent = winGui
	local fitScale = Instance.new("UIScale")
	fitScale.Name = "Fit"
	fitScale.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 16)
	layout.Parent = root
	return { side = side, root = root, fitScale = fitScale, layout = layout, count = 0 }
end
local columns = { Left = makeColumn("Left"), Right = makeColumn("Right") }

local buttons = {}

local function makeButton(def, order)
	local col = columns[def.Side == "Right" and "Right" or "Left"]
	col.count += 1
	-- its slot in the column: a fixed size, so one button swelling never moves the others
	local slot = Instance.new("Frame")
	slot.Name = def.Id
	slot.BackgroundTransparency = 1
	slot.Size = UDim2.fromOffset(WIDTH, HOLDER_H)
	slot.LayoutOrder = order
	slot.Parent = col.root
	-- the button itself, in the slot: it swells and squashes from its middle (its UIScale)
	local holder = Instance.new("Frame")
	holder.Name = "Body"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = slot
	local scale = Instance.new("UIScale")
	scale.Name = "Scale"
	scale.Parent = holder

	-- the image, unboxed: an upright holder (for the count) with the tilted picture in it
	local iconBox = Instance.new("Frame")
	iconBox.Name = "IconBox"
	iconBox.BackgroundTransparency = 1
	iconBox.AnchorPoint = Vector2.new(0.5, 0)
	iconBox.Position = UDim2.new(0.5, 0, 0, 0)
	iconBox.Size = UDim2.fromOffset(ICON, ICON)
	iconBox.Parent = holder
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Image = def.Image
	icon.ScaleType = Enum.ScaleType.Fit
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(1.2, 1.2)
	icon.Rotation = def.Rotation or 0
	icon.ZIndex = 2
	icon.Parent = iconBox
	-- a soft dark copy just behind and below it, so it stands off the screen a little
	local shadow = icon:Clone()
	shadow.Name = "Shadow"
	shadow.ImageColor3 = Color3.new(0, 0, 0)
	shadow.ImageTransparency = 0.65
	shadow.Position = UDim2.new(0.5, 4, 0.5, 6)
	shadow.ZIndex = 1
	shadow.Parent = iconBox

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, ICON - 30)
	label.ZIndex = 3   -- over the flame a little
	label.Size = UDim2.fromOffset(WIDTH, 56)
	label.FontFace = NAME_FONT
	label.Text = string.upper(def.Label)
	label.TextSize = 24
	label.LineHeight = 0.9
	label.TextWrapped = true
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = holder
	local edge = Instance.new("UIStroke")
	edge.Color = Color3.new(0, 0, 0)
	edge.Thickness = 2
	edge.Parent = label

	-- what it does: yellow, tilted, over the image's top right
	if def.Tag then
		local tag = Instance.new("TextLabel")
		tag.Name = "Tag"
		tag.BackgroundTransparency = 1
		tag.AnchorPoint = Vector2.new(0.5, 0.5)
		tag.Position = def.TagAt or UDim2.new(1, -4, 0, 20)   -- the list can move it onto its own picture
		tag.Size = UDim2.fromOffset(200, 44)
		tag.Rotation = 14
		tag.FontFace = TAG_FONT
		tag.Text = string.upper(def.Tag)
		tag.TextSize = 17
		tag.LineHeight = 0.85
		tag.TextColor3 = TAG_COLOR
		tag.ZIndex = 3
		tag.Parent = iconBox
		local tagEdge = Instance.new("UIStroke")
		tagEdge.Color = Color3.new(0, 0, 0)
		tagEdge.Thickness = 1.4
		tagEdge.Parent = tag
	end

	-- the deal, red, over the image's top left
	if def.Deal then
		local deal = Instance.new("TextLabel")
		deal.Name = "Deal"
		deal.BackgroundTransparency = 1
		deal.AnchorPoint = Vector2.new(0.5, 0.5)
		deal.Position = UDim2.new(0, 26, 0, 38)
		deal.Size = UDim2.fromOffset(70, 48)
		deal.Rotation = -6
		deal.LineHeight = 0.85
		deal.FontFace = TAG_FONT
		deal.Text = string.upper(def.Deal)
		deal.TextSize = 22
		deal.TextColor3 = DEAL_COLOR
		deal.ZIndex = 3
		deal.Parent = iconBox
		local dealEdge = Instance.new("UIStroke")
		dealEdge.Color = Color3.new(0, 0, 0)
		dealEdge.Thickness = 1.6
		dealEdge.Parent = deal
	end

	-- the reason a press was refused (the tiles' hint pill)
	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.Position = UDim2.new(0.5, 0, 1, 2)
	hint.Size = UDim2.fromOffset(0, 30)
	hint.AutomaticSize = Enum.AutomaticSize.X
	hint.BackgroundColor3 = Color3.fromRGB(14, 17, 25)
	hint.BackgroundTransparency = 1
	hint.FontFace = HINT_FONT
	hint.TextSize = 13
	hint.TextColor3 = Color3.new(1, 1, 1)
	hint.TextTransparency = 1
	hint.Text = ""
	hint.ZIndex = 8
	hint.Parent = holder
	local hintCorner = Instance.new("UICorner")
	hintCorner.CornerRadius = UDim.new(0, 10)
	hintCorner.Parent = hint
	local hintStroke = Instance.new("UIStroke")
	hintStroke.Color = Color3.fromRGB(78, 90, 115)
	hintStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	hintStroke.Transparency = 1
	hintStroke.Parent = hint
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
	pad.Parent = hint

	-- the whole button takes the press
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 10
	hit.Parent = holder

	-- saved free ones: the red count, moved off the top-right corner (the yellow words are there)
	-- to the empty bottom right, beside the rocket's body
	local badge = CountBadge.Attach(iconBox, def.Credits)
	badge.Position = UDim2.fromScale(0.86, 0.64)

	return {
		def = def, holder = holder, scale = scale, icon = icon, shadow = shadow, hint = hint, hintStroke = hintStroke, hit = hit,
		sCur = 1, sVel = 0, lean = 0, shakeT = 0, dim = 1, hintA = 0, hintUntil = 0,
		hover = false, pressed = false, busy = false, waiting = nil,
	}
end

for i, def in ipairs(Effects) do
	if (PRODUCTS[def.Id] or 0) ~= 0 then table.insert(buttons, makeButton(def, i)) end
end

local fader = Motion.fader(function(o)
	for _, b in ipairs(buttons) do
		if o == b.holder or o:IsDescendantOf(b.holder) then return b.def.Id end
	end
	return nil
end)
for _, col in pairs(columns) do
	fader:trackTree(col.root, function(o) return o.Name == "Hint" end)   -- the hints fade on their own
end

--------------------------------------------------------------------- pressing
local watched         -- the duo on screen (Spectate.Current), from the last Update

local function say(b, text)
	if not text or text == "" then return end
	b.hint.Text = text
	b.hintUntil = os.clock() + HINT_TIME
end

local function refuse(b, text)
	b.shakeT = 1
	say(b, text)
end

local function press(b)
	if b.busy then refuse(b, "Hang on...") return end
	local duo = watched   -- nil: nobody on screen, so it's bought for later
	if duo and duo.Scooter:GetAttribute("Troll") then refuse(b, "They're already being trolled!") return end
	b.busy = true
	task.spawn(function()
		local ok, status, why = pcall(request.InvokeServer, request, b.def.Id, duo and duo.Scooter or nil)
		if not ok then status, why = "refused", "Couldn't do that right now - try again!" end
		if status == "prompted" then
			b.waiting = os.clock()   -- until Roblox's purchase window closes
			return
		end
		b.busy = false
		if status ~= "started" then refuse(b, why or "They can't be trolled right now!") end
	end)
end

for _, b in ipairs(buttons) do
	b.hit.MouseEnter:Connect(function()
		if Motion.isTouch() then return end
		b.hover = true
		sfx:play("Hover")
	end)
	b.hit.MouseLeave:Connect(function() b.hover, b.pressed = false, false end)
	b.hit.MouseButton1Down:Connect(function()
		b.pressed = true
		sfx:play("Click")
	end)
	b.hit.InputEnded:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then b.pressed = false end
	end)
	b.hit.Activated:Connect(function() press(b) end)
end

-- the purchase window closed (bought or not): the button is free again; a bought one
-- starts on Roblox's receipt, a moment later
MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId)
	if userId ~= player.UserId then return end
	for _, b in ipairs(buttons) do
		if b.waiting and PRODUCTS[b.def.Id] == productId then
			b.waiting = nil
			b.busy = false
		end
	end
end)

--------------------------------------------------------------------- every frame
local shownA = 0

-- where the lobby tiles sit (all four step away while the window is open): level with the
-- tile grid's left edge, from the top of its first row
local function home()
	local s = HudSync.TileScale()
	local tile = HudSync.TILE * s
	local at = HudSync.TileAt(safeGui, 1, 1, s)
	local shift = safeGui.AbsolutePosition - winGui.AbsolutePosition   -- into this window's space
	return at.X.Offset + shift.X - tile / 2, at.Y.Offset + shift.Y - tile / 2
end

-- windowAlpha: the Troll window's own (0 .. 1); duo: the one on screen, or nil (the buttons still
-- show: bought then, it's saved for later); scale: the window's
function Actions.Update(dt, windowAlpha, duo, scale)
	watched = duo
	shownA = Motion.approach(shownA, 1, 12, dt)
	local a = windowAlpha * shownA
	local any = false
	for _, col in pairs(columns) do
		col.root.Visible = a > 0.01 and col.count > 0
		any = any or col.root.Visible
	end
	if not any then return end
	local x, y = home()
	for _, col in pairs(columns) do
		if col.root.Visible then
			-- the window's size, but never taller than the room left below the column's top (phones:
			-- the whole stack of buttons always fits on screen)
			local pad = col.layout.Padding.Offset
			local tall = col.count * HOLDER_H + math.max(col.count - 1, 0) * pad + 36   -- + the last hint pill
			-- centred up and down in the safe area (clear of the top bar and a phone's notch)
			local top = safeGui.AbsolutePosition.Y - winGui.AbsolutePosition.Y
			local room = safeGui.AbsoluteSize.Y - 16
			local fit = math.max(math.min((scale or 1) * 1.05, room / tall), 0.3)
			col.fitScale.Scale = fit
			local y = top + (safeGui.AbsoluteSize.Y - (tall - 36) * fit) / 2
			if HudSync.IsTouch() then y = math.max(y - safeGui.AbsoluteSize.Y * TOUCH_UP, top + 4) end
			if col.side == "Right" then
				-- mirrored: as far in from the safe area's right edge as the left one is from its left
				local margin = x - (safeGui.AbsolutePosition.X - winGui.AbsolutePosition.X)
				local right = safeGui.AbsolutePosition.X + safeGui.AbsoluteSize.X - winGui.AbsolutePosition.X
				col.root.Position = UDim2.fromOffset(right - margin - RIGHT_IN * fit + 40 * (1 - shownA), y)
			else
				col.root.Position = UDim2.fromOffset(x - 40 * (1 - shownA), y)
			end
		end
	end
	local trolled = duo and duo.Scooter:GetAttribute("Troll") ~= nil
	local groups = {}
	local t = os.clock()
	for _, b in ipairs(buttons) do
		if b.waiting and t - b.waiting > PROMPT_MAX then b.waiting, b.busy = nil, false end
		local usable = not trolled and not b.busy
		local target = (b.pressed and 0.92) or ((b.hover and usable) and 1.08) or 1
		b.sCur, b.sVel = Motion.spring(b.sCur, b.sVel, target, 250, 19, dt)
		b.scale.Scale = math.max(b.sCur, 0.01)
		-- the image holds still at its tilt; only a refusal shakes it
		b.shakeT = math.max(b.shakeT - dt * 3, 0)
		b.icon.Rotation = (b.def.Rotation or 0) + math.sin(t * 55) * 9 * b.shakeT
		b.shadow.Rotation = b.icon.Rotation
		-- dimmed while it can't be used
		b.dim = Motion.approach(b.dim, usable and 1 or 0.45, 10, dt)
		groups[b.def.Id] = b.dim
		-- its hint
		b.hintA = Motion.approach(b.hintA, t < b.hintUntil and 1 or 0, 14, dt)
		b.hint.TextTransparency = 1 - b.hintA * a
		b.hint.BackgroundTransparency = 1 - 0.86 * b.hintA * a
		b.hintStroke.Transparency = 1 - 0.75 * b.hintA * a
	end
	fader:set(a, groups)
end

function Actions.Hide()
	shownA = 0
	for _, col in pairs(columns) do col.root.Visible = false end
	for _, b in ipairs(buttons) do b.hover, b.pressed = false, false end
end

--------------------------------------------------------------------- the buyer's notes
local toast = Instance.new("Frame")
toast.Name = "Toast"
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, -120)
toast.Size = UDim2.fromOffset(560, 60)
toast.BackgroundColor3 = Color3.new(1, 1, 1)
toast.Visible = false
toast.ZIndex = 20
toast.Parent = winGui
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 16)
	c.Parent = toast
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(Color3.fromRGB(120, 196, 255), Color3.fromRGB(64, 146, 232))
	g.Parent = toast
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(16, 52, 110)
	s.Thickness = 3
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = toast
end
local toastScale = Instance.new("UIScale")
toastScale.Parent = toast
local toastText = Instance.new("TextLabel")
toastText.BackgroundTransparency = 1
toastText.Size = UDim2.new(1, -28, 1, -12)
toastText.AnchorPoint = Vector2.new(0.5, 0.5)
toastText.Position = UDim2.fromScale(0.5, 0.5)
toastText.FontFace = FONT
toastText.TextScaled = true
toastText.TextColor3 = Color3.new(1, 1, 1)
toastText.ZIndex = 21
toastText.Parent = toast
do
	local s = Instance.new("UIStroke")
	s.Color = Color3.new(0, 0, 0)
	s.Thickness = 2.5
	s.Parent = toastText
	local k = Instance.new("UITextSizeConstraint")
	k.MaxTextSize = 22
	k.MinTextSize = 12
	k.Parent = toastText
end

local toastToken = 0
local function showToast(text)
	toastToken += 1
	local mine = toastToken
	local cam = workspace.CurrentCamera
	local vw = cam and cam.ViewportSize.X or 1000
	toastScale.Scale = math.min(1, vw * 0.9 / 560)
	toastText.Text = text
	toast.Visible = true
	toast.Position = UDim2.new(0.5, 0, 0, -120)
	TweenService:Create(toast, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0, 78) }):Play()
	sfx:play("Start")
	task.delay(TOAST_TIME, function()
		if toastToken ~= mine then return end
		local tw = TweenService:Create(toast, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.new(0.5, 0, 0, -120) })
		tw:Play()
		tw.Completed:Once(function() if toastToken == mine then toast.Visible = false end end)
	end)
end

alert.OnClientEvent:Connect(function(info)
	if type(info) == "table" and info.Kind == "Notice" and type(info.Text) == "string" then
		showToast(info.Text)
	end
end)

return Actions
