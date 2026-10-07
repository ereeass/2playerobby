--=====================================================================
-- Carousel
--
-- The row of checkpoint cards. One card per checkpoint, made from the data
-- (View.newCard); clicking a card picks it and the green border moves to it.
-- EXACTLY 2.5 cards show at once (two full, the third cut in half at the right
-- edge): the card width comes from the row's own width, so the rule holds at
-- every screen size. The row scrolls sideways with the mouse wheel, by dragging
-- it, or by swiping, and when the pick moves (a click, A / D, the bumpers, the
-- gamepad) it glides so the picked card sits in the middle, the first and last
-- stopping at the ends. A locked card stays in the row but darkened with the
-- shop's padlock. Cards are only rebuilt when the list
-- really changes, so reopening keeps the pick and never doubles anything up.
--=====================================================================

local UserInputService = game:GetService("UserInputService")
local StarterGui       = game:GetService("StarterGui")

local Motion = require(script.Parent:WaitForChild("Motion"))
local View   = require(script.Parent:WaitForChild("View"))

local GREEN       = Color3.fromRGB(96, 232, 108)   -- the picked card's border
local NEUTRAL     = Color3.new(1, 1, 1)
local EDGE_T      = 0.72                            -- how faint the other cards' borders are
local EDGE_W      = 2
local EDGE_W_ON   = 5.5
local DRAG_SLOP   = 8      -- px the mouse moves before a press on the row becomes a drag
local SCROLL_RATE = 14     -- how quickly the row glides to a card
local VISIBLE     = 2.5    -- cards shown across the row at once (two and a half)
local LOCKED_DIM  = 0.5    -- the dark veil over a locked card (lower = darker)
local LOCK_SIZE   = 0.3    -- the padlock's height, as a share of the card's

local Carousel = {}
Carousel.__index = Carousel

-- gamepad: a white ring round the card (or arrow) it is on
local function ring(radius)
	local f = Instance.new("Frame")
	f.Name = "SelectionRing"
	f.BackgroundTransparency = 1
	f.Position = UDim2.fromOffset(-6, -6)
	f.Size = UDim2.new(1, 12, 1, 12)
	local c = Instance.new("UICorner"); c.CornerRadius = radius or UDim.new(0, 18); c.Parent = f
	local s = Instance.new("UIStroke"); s.Color = Color3.new(1, 1, 1); s.Thickness = 3; s.Parent = f
	return f
end

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

-- a round arrow button (Motion.button shape: Frame + Scale + Face, the face holds a
-- Chevron). Exposed as Carousel.arrowButton for other windows that want the same
-- arrow (the Troll window's spectate bar); they place and size the holder themselves.
local ARROW_H, ARROW_X, ARROW_Y = 0.2, 0.07, 0.42
local function arrowButton(parent, side)
	local holder = new("Frame", {
		Name = side < 0 and "PrevArrow" or "NextArrow", BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(side < 0 and ARROW_X or 1 - ARROW_X, ARROW_Y),
		Size = UDim2.fromScale(ARROW_H, ARROW_H), ZIndex = 30,
	}, parent)
	new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, holder)
	new("UIScale", { Name = "Scale" }, holder)
	local face = new("TextButton", {
		Name = "Face", Text = "", AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(18, 24, 44), BackgroundTransparency = 0.2,
		Size = UDim2.fromScale(1, 1), ZIndex = 5,
	}, holder)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, face)
	new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 3, Transparency = 0.15 }, face)
	local shine = new("Frame", { Name = "Shine", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1), ZIndex = 6 }, face)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, shine)
	local chev = new("Frame", { Name = "Chevron", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 7 }, face)
	local T, L = 0.095, 0.36
	local tipX = 0.5 + side * 0.1
	local d = (L - T) / 2 * math.sqrt(0.5)
	for _, arm in ipairs({ -1, 1 }) do
		local bar = new("Frame", {
			Name = "Bar", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(tipX - side * d, 0.5 + arm * d),
			Size = UDim2.fromScale(L, T),
			Rotation = -side * arm * 45, ZIndex = 7,
		}, chev)
		new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, bar)
	end
	face.SelectionImageObject = ring(UDim.new(0.5, 0))
	return holder, face
end
-- the same arrow for other windows (the Troll window's spectate bar); they place and size it
Carousel.arrowButton = arrowButton

local function signature(list)
	local parts = {}
	for i, cp in ipairs(list) do
		parts[i] = tostring(cp.Id) .. "\0" .. View.nameOf(cp, i) .. "\0" .. tostring(cp.Image) .. "\0" .. tostring(View.isLocked(cp))
	end
	return table.concat(parts, "\1")
end

function Carousel.new(refs, fader, sfx)
	local self = setmetatable({
		refs = refs, fader = fader, sfx = sfx,
		list = {}, index = 1, cards = {}, sig = nil,
		scrollTo = nil, pendingReveal = false,
		drag = nil, dragEnded = 0,
		onSelect = nil,   -- set by the owner: called with a card's index when it is picked
	}, Carousel)
	local row = refs.cards

	self.layout = row:FindFirstChildOfClass("UIListLayout")
	self.pad = row:FindFirstChildOfClass("UIPadding")
	-- re-fit the cards (2.5 across) and keep the pick in view whenever the row resizes
	row:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:layoutCards()
		self:reveal(self.index, true)
	end)

	-- mouse: press on the row and drag to scroll it (touch swipes it natively)
	UserInputService.InputChanged:Connect(function(input)
		local d = self.drag
		if not d or input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
		local dx = input.Position.X - d.x
		if not d.moved and math.abs(dx) > DRAG_SLOP then
			d.moved = true
			if d.card then d.card.button.pressed = false end
		end
		if d.moved then
			self.scrollTo = nil
			row.CanvasPosition = Vector2.new(self:clampX(d.canvas - dx / self:scale()), 0)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if self.drag and input.UserInputType == Enum.UserInputType.MouseButton1 then
			if self.drag.moved then self.dragEnded = os.clock(); self.pendingReveal = false end
			self.drag = nil
		end
	end)
	row.InputBegan:Connect(function(input) self:beginDrag(input, nil) end)
	-- scrolling by hand (wheel or swipe) always wins over a glide in progress
	row.InputChanged:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseWheel or kind == Enum.UserInputType.Touch then
			self.scrollTo, self.pendingReveal = nil, false
		end
	end)
	return self
end

function Carousel:beginDrag(input, card)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	if self.drag and self.drag.card then return end     -- a card already started this press
	self.drag = { x = input.Position.X, canvas = self.refs.cards.CanvasPosition.X, moved = false, card = card }
end

-- true while (or just after) the mouse dragged the row: that release is not a click
function Carousel:wasDrag()
	return (self.drag ~= nil and self.drag.moved) or os.clock() - self.dragEnded < 0.15
end

-- the window's pop-in scale: on-screen sizes are divided by it to get canvas
-- units, so scrolling maths stays right while the window is still springing in
function Carousel:scale()
	return math.max(self.refs.winScale.Scale, 0.01)
end

function Carousel:clampX(x)
	local row = self.refs.cards
	return math.clamp(x, 0, math.max((row.AbsoluteCanvasSize.X - row.AbsoluteWindowSize.X) / self:scale(), 0))
end

function Carousel:count()
	return #self.list
end

function Carousel:current()
	return self.list[self.index], self.index
end

function Carousel:find(id)
	if id == nil then return nil end
	for i, cp in ipairs(self.list) do
		if cp.Id == id then return i end
	end
	return nil
end

-- a new list: stay on the same checkpoint if it is still there, and only
-- rebuild the cards when the list really changed
function Carousel:setList(list)
	local keep = self.list[self.index]
	self.list = list
	self.index = (keep and self:find(keep.Id)) or math.clamp(self.index, 1, math.max(#list, 1))
	local sig = signature(list)
	if sig ~= self.sig then
		self.sig = sig
		self:build()
	end
	self:snap()
end

function Carousel:show(id)
	local i = self:find(id)
	if i then
		self.index = i
		self:snap()
	end
end

function Carousel:build()
	for _, c in ipairs(self.cards) do
		self.fader:untrackTree(c.holder)
		c.holder:Destroy()                  -- its connections go with it
	end
	self.cards = {}
	self.drag = nil
	for i, cp in ipairs(self.list) do
		local holder, face, edge = View.newCard(self.refs.cardTemplate, cp, i)
		local aspect = holder:FindFirstChildOfClass("UIAspectRatioConstraint")
		if aspect then aspect:Destroy() end     -- width comes from the 2.5-across rule, not a fixed shape
		-- not unlocked by the pair yet: darken the card and show the shop's padlock
		-- (ScootersWindow CardTemplate.Lock) in the middle; START already refuses it
		if cp.Unlocked ~= false and cp.Locked == true then
			local nameLabel = face:FindFirstChild("CheckpointName")
			if nameLabel then nameLabel.Visible = false end
			local art = face:FindFirstChild("Art")
			local number = art and art:FindFirstChild("Number")
			if number then number.Visible = false end
			local soon = face:FindFirstChild("Soon")
			if soon then
				soon.BackgroundTransparency = LOCKED_DIM
				if soon:FindFirstChild("Pill") then soon.Pill.Visible = false end
			end
			local shop = StarterGui:FindFirstChild("ScootersWindow")
			local src = shop and shop:FindFirstChild("CardTemplate", true)
			src = src and src:FindFirstChild("Lock")
			if src then
				local lock = src:Clone()
				lock.AnchorPoint = Vector2.new(0.5, 0.5)
				lock.Position = UDim2.fromScale(0.5, 0.5)
				lock.Visible = true
				for _, o in ipairs(lock:GetDescendants()) do
					if o:IsA("GuiObject") then o.ZIndex += 12 end
				end
				lock.ZIndex += 12
				local pop = lock:FindFirstChild("Pop")
				local function fit()
					if pop then pop.Scale = math.max(face.AbsoluteSize.Y * LOCK_SIZE / 60, 0.01) end
				end
				face:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
				fit()
				lock.Parent = face
			end
		end
		holder.Parent = self.refs.cards
		self.fader:trackTree(holder)
		local card = { holder = holder, face = face, edge = edge, on = -1 }
		card.button = Motion.button(holder, {
			fader = self.fader, sfx = self.sfx, hover = 1.04, press = 0.96, lift = 3, sink = 2,
			onActivate = function()
				if not self:wasDrag() and self.onSelect then self.onSelect(i) end
			end,
		})
		face.SelectionImageObject = ring()
		face.InputBegan:Connect(function(input) self:beginDrag(input, card) end)
		-- gamepad: moving onto a card picks it
		face.SelectionGained:Connect(function()
			if self.onSelect then self.onSelect(i) end
		end)
		self.cards[i] = card
	end
	self:layoutCards()
end

-- straight to the picked card with no motion (opening, or a new list)
function Carousel:snap()
	self:layoutCards()
	for i, c in ipairs(self.cards) do
		c.on = (i == self.index) and 1 or 0
		self:drawCard(c)
	end
	self.scrollTo = nil
	self.pendingReveal = true          -- scroll it into view once the row is laid out
end

function Carousel:select(i)
	if not self.list[i] then return false end
	local changed = i ~= self.index
	self.index = i
	local c = self.cards[i]
	if c and changed then c.button.sv += 2 end     -- a small pop as it is picked
	self:reveal(i, false)
	return changed
end

function Carousel:go(step)
	if #self.list < 2 then return false end
	return self:select(math.clamp(self.index + step, 1, #self.list))
end

-- the card width that shows exactly VISIBLE (2.5) cards across the row, worked
-- out from the row's own width so the rule holds at every screen size, and a
-- height that fills the row between its top / bottom padding
function Carousel:cardSize()
	local row = self.refs.cards
	local winW = row.AbsoluteWindowSize.X / self:scale()
	local winH = row.AbsoluteWindowSize.Y / self:scale()
	local gap = self.layout.Padding.Offset
	local w = (winW - self.pad.PaddingLeft.Offset - 2 * gap) / VISIBLE
	local h = winH - self.pad.PaddingTop.Offset - self.pad.PaddingBottom.Offset
	return math.max(w, 1), math.max(h, 1)
end

-- size every card to the 2.5-across width and set the scroll width to match
function Carousel:layoutCards()
	local row = self.refs.cards
	if row.AbsoluteWindowSize.X <= 0 then return end
	local w, h = self:cardSize()
	for _, c in ipairs(self.cards) do
		c.holder.Size = UDim2.fromOffset(w, h)
	end
	local gap = self.layout.Padding.Offset
	local n = #self.cards
	local canvas = self.pad.PaddingLeft.Offset + self.pad.PaddingRight.Offset
		+ n * w + math.max(n - 1, 0) * gap
	row.CanvasSize = UDim2.fromOffset(canvas / self:scale(), 0)
end

-- where card i sits along the row, in canvas units (so a card's own hover /
-- press swell never nudges it)
function Carousel:cardSpan(i)
	local w = self:cardSize()
	return self.pad.PaddingLeft.Offset + (i - 1) * (w + self.layout.Padding.Offset), w
end

-- scroll so card i sits in the middle of the row (the first and last cards
-- stop at the ends, as the row can't scroll past them)
function Carousel:reveal(i, instant)
	local row = self.refs.cards
	if not self.cards[i] or row.AbsoluteWindowSize.X <= 0 then return end
	local left, w = self:cardSpan(i)
	local target = self:clampX(left + w / 2 - row.AbsoluteWindowSize.X / self:scale() / 2)
	if instant then
		self.scrollTo = nil
		row.CanvasPosition = Vector2.new(target, 0)
	else
		self.scrollTo = target
	end
end

function Carousel:drawCard(c)
	c.edge.Color = NEUTRAL:Lerp(GREEN, c.on)
	c.edge.Thickness = EDGE_W + (EDGE_W_ON - EDGE_W) * c.on
	self.fader:setBase(c.edge, "Transparency", EDGE_T * (1 - c.on))
end

function Carousel:update(dt, usable)
	local row = self.refs.cards
	if self.pendingReveal and row.AbsoluteWindowSize.X > 0 then
		-- on-screen sizes trail the window's pop-in by a frame, so keep sizing and
		-- aiming at the picked card until the window has settled at full size
		self:layoutCards()
		self:reveal(self.index, true)
		if math.abs(self:scale() - 1) < 0.004 then self.pendingReveal = false end
	end
	if self.scrollTo then
		local x = Motion.approach(row.CanvasPosition.X, self.scrollTo, SCROLL_RATE, dt)
		if math.abs(x - self.scrollTo) < 0.5 then x, self.scrollTo = self.scrollTo, nil end
		row.CanvasPosition = Vector2.new(x, 0)
	end
	for i, c in ipairs(self.cards) do
		local want = (i == self.index) and 1 or 0
		if c.on ~= want then
			c.on = Motion.approach(c.on, want, 16, dt)
			if math.abs(c.on - want) < 0.002 then c.on = want end
			self:drawCard(c)
		end
		c.button.enabled = usable
		c.button:update(dt)
	end
end

return Carousel
