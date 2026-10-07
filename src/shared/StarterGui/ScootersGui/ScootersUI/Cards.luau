--=====================================================================
-- Cards   (ScootersUI)
--
-- The 4 x 3 grid: one card per scooter in Shared.Scooters, then empty slots up to
-- Scooters.Slots (more scooters than that: whole extra rows, the grid scrolls). Built
-- ONCE from the registry, so a new scooter only needs its entry and model.
-- Order (arrange): once the server has answered, the skins the player has come first -
-- the default, then the rest in SortOrder (the equipped one stays in its place among
-- them) - and the ones they don't have follow, in SortOrder. An archived skin (Scooters.Archived) gets a card
-- too, shown only to a player who has it, so they can always pick it again. Each card shows, top to bottom: the
-- skin's name (coloured for it), its real model turning in a dark well framed by
-- corner brackets (Preview), a white padlock over it while it isn't theirs, and
-- its pill: a small button clipped over the card's bottom edge, right under the
-- scooter, one flat colour with a black rim and a thin black outline on its text:
--   LOCKED      red; picking it does nothing
--   JOIN GROUP  blue, a group's scooter (or group reward) and they're not in the group:
--               picking it opens Roblox's join prompt (Menu)
--   UNLOCK      blue, a group reward they're in the group for but haven't been asked about:
--               picking it shows "like the game, then rejoin" (Menu -> RewardAction)
--   REJOIN      blue, a group reward they've been asked about: like, then rejoin (the
--               server grants it by itself when their next session starts)
--   25 (icon)   light green, green price and a green Robux icon, a scooter sold for
--               Robux; picking it opens the purchase prompt (Menu)
--   LIMITED     purple, a Daily Rewards skin they haven't claimed: never sold; picking
--               it says which calendar day gives it (Menu -> RewardAction)
--   SELECT      green; asks the server to equip it
--   EQUIPPED    orange; the scooter this player rides (and drives for their team).
--               Its card also gets a fuller glow and a slight lift.
-- A Robux skin that can be gifted (Gift.canGift) also gets a small pink gift button to
-- the right of its pill: it opens the Gift page (Menu -> Gift), whoever owns it.
-- Each card's foot glows faintly in its skin's colour (TINT), dimmer while locked.
-- The whole card is the button, so it is an easy tap and a gamepad stop.
--=====================================================================

local RS = game:GetService("ReplicatedStorage")

local Motion   = require(RS:WaitForChild("CheckpointSelector"):WaitForChild("Motion"))
local Scooters = require(RS:WaitForChild("ScooterSystem"):WaitForChild("Shared"):WaitForChild("Scooters"))
local Preview  = require(script.Parent:WaitForChild("Preview"))
local Gift     = require(script.Parent:WaitForChild("Gift"))

local RGB, WHITE = Color3.fromRGB, Color3.new(1, 1, 1)

-- the pill's flat fill (its rim and text outline are black, in the template)
local LOOK = {
	Locked   = { text = "LOCKED",     fill = RGB(226, 54, 64),   ink = WHITE,              outline = 0 },
	Join     = { text = "JOIN GROUP", fill = RGB(54, 154, 242),  ink = WHITE,              outline = 0 },
	Buy      = { text = "BUY",        fill = RGB(170, 244, 150), ink = WHITE,              outline = 0 },   -- light green, white price text (matches the white Robux icon)
	Rejoin   = { text = "REJOIN",     fill = RGB(54, 154, 242),  ink = WHITE,              outline = 0 },
	Unlock   = { text = "UNLOCK",     fill = RGB(54, 154, 242),  ink = WHITE,              outline = 0 },
	Limited  = { text = "LIMITED",    fill = RGB(150, 84, 255),  ink = WHITE,              outline = 0 },
	Select   = { text = "SELECT",     fill = RGB(76, 202, 88),   ink = WHITE,              outline = 0 },
	Selected = { text = "EQUIPPED",   fill = RGB(255, 142, 28),  ink = WHITE,              outline = 0 },
	Waiting  = { text = "...",        fill = RGB(86, 95, 138),   ink = RGB(228, 234, 250), outline = 0.3 },
}
local CARD_BG_T, CARD_BG_T_ON = 0.06, 0              -- the card's navy fill (its Fill gradient); the equipped one solid
local EDGE_T, EDGE_T_HOVER = 0.5, 0.2               -- every card's cool rim (the template's) firms up on hover
local GLOW_T, GLOW_T_LOCKED, GLOW_T_ON = 0.5, 0.8, 0.15   -- the skin's glow: faint, fainter while locked, fuller when equipped
local LIFT_ON = 0.025                                -- the equipped card sits a touch larger

-- each skin's name, coloured for its scooter (any other skin: white)
local NAME_STYLE = {
	Red = { top = WHITE,             bottom = RGB(226, 230, 240), edge = RGB(0, 0, 0) },
	Ice = { top = RGB(236, 250, 255), bottom = RGB(112, 198, 255), edge = RGB(12, 44, 88) },   -- icy
	Bee = { top = RGB(255, 238, 120), bottom = RGB(255, 170, 30),  edge = RGB(66, 34, 0) },
	-- the scooter's own rainbow, left to right
	Rainbow = { edge = RGB(34, 16, 56), seq = ColorSequence.new({
		ColorSequenceKeypoint.new(0, RGB(255, 72, 72)), ColorSequenceKeypoint.new(0.2, RGB(255, 150, 50)),
		ColorSequenceKeypoint.new(0.4, RGB(255, 222, 64)), ColorSequenceKeypoint.new(0.6, RGB(86, 214, 96)),
		ColorSequenceKeypoint.new(0.8, RGB(64, 170, 255)), ColorSequenceKeypoint.new(1, RGB(190, 96, 255)),
	}) },
	Gold = { top = RGB(255, 246, 184), bottom = RGB(226, 150, 12), edge = RGB(84, 48, 0) },   -- polished gold
	Magma = { top = RGB(255, 214, 90), bottom = RGB(255, 84, 20), edge = RGB(44, 10, 0) },    -- glowing cracks
	Grass = { top = RGB(196, 250, 120), bottom = RGB(62, 170, 48), edge = RGB(14, 50, 10) },   -- fresh grass
	Glass = { top = RGB(255, 255, 255), bottom = RGB(176, 222, 255), edge = RGB(30, 56, 86) },  -- clear glass
	-- the scooter's nebula, left to right
	Galaxy = { edge = RGB(20, 8, 44), seq = ColorSequence.new({
		ColorSequenceKeypoint.new(0, RGB(255, 110, 210)), ColorSequenceKeypoint.new(0.5, RGB(176, 96, 255)),
		ColorSequenceKeypoint.new(1, RGB(90, 140, 255)),
	}) },
	Candy = { top = RGB(255, 226, 240), bottom = RGB(255, 84, 164), edge = RGB(96, 10, 52) },  -- candy pink
	ToxicSlime = { top = RGB(222, 255, 120), bottom = RGB(76, 206, 30), edge = RGB(12, 50, 0) },  -- toxic green
	Chrome = { top = RGB(255, 255, 255), bottom = RGB(148, 158, 176), edge = RGB(28, 32, 42) },   -- polished chrome
	Camo = { top = RGB(178, 196, 112), bottom = RGB(96, 112, 54), edge = RGB(24, 28, 12) },     -- army green
	-- sand to sea, left to right
	Beach = { edge = RGB(60, 40, 14), seq = ColorSequence.new({
		ColorSequenceKeypoint.new(0, RGB(255, 222, 140)), ColorSequenceKeypoint.new(0.42, RGB(255, 206, 120)),
		ColorSequenceKeypoint.new(0.58, RGB(70, 206, 228)), ColorSequenceKeypoint.new(1, RGB(70, 206, 228)),
	}) },
	Troll = { top = RGB(200, 255, 250), bottom = RGB(40, 196, 190), edge = RGB(6, 44, 44) },    -- teal troll
	Dragon = { top = RGB(255, 214, 90), bottom = RGB(255, 60, 10), edge = RGB(54, 6, 4) },     -- molten fire
	Oni = { top = RGB(255, 120, 120), bottom = RGB(200, 10, 24), edge = RGB(20, 0, 4) },        -- cursed red
	Reaper = { top = RGB(226, 200, 255), bottom = RGB(140, 60, 240), edge = RGB(14, 4, 28) },   -- spectral violet
	InkDemon = { top = RGB(250, 246, 236), bottom = RGB(170, 164, 150), edge = RGB(8, 8, 10) },  -- paper and ink
	Watcher = { top = RGB(255, 236, 190), bottom = RGB(196, 140, 60), edge = RGB(30, 20, 8) },    -- ivory and antique gold
	-- arcade colours in hard steps across the word, like pixels
	Pixel = { edge = RGB(20, 14, 50), seq = ColorSequence.new({
		ColorSequenceKeypoint.new(0, RGB(0, 210, 255)), ColorSequenceKeypoint.new(0.41, RGB(0, 210, 255)),
		ColorSequenceKeypoint.new(0.42, RGB(255, 70, 190)), ColorSequenceKeypoint.new(0.58, RGB(255, 70, 190)),
		ColorSequenceKeypoint.new(0.59, RGB(255, 218, 40)), ColorSequenceKeypoint.new(1, RGB(255, 218, 40)),
	}) },
}
-- each skin's glow at the foot of its card (any other skin: a cool blue)
local TINT = {
	Red = RGB(255, 84, 84),
	Ice = RGB(92, 182, 255),
	Bee = RGB(255, 194, 46),
	Rainbow = RGB(190, 110, 255),
	Gold = RGB(255, 184, 40),
	Magma = RGB(255, 96, 28),
	Grass = RGB(92, 210, 70),
	Glass = RGB(200, 236, 255),
	Galaxy = RGB(160, 96, 255),
	Candy = RGB(255, 110, 190),
	ToxicSlime = RGB(110, 232, 60),
	Chrome = RGB(206, 216, 236),
	Camo = RGB(130, 152, 78),
	Beach = RGB(90, 206, 222),
	Troll = RGB(60, 210, 200),
	Pixel = RGB(255, 70, 190),
	Dragon = RGB(255, 80, 10),
	Oni = RGB(230, 20, 36),
	Reaper = RGB(160, 80, 255),
	InkDemon = RGB(228, 222, 206),
	Watcher = RGB(232, 176, 90),
}
local TINT_OTHER = RGB(128, 148, 255)
-- every scooter starts from the same three-quarter view and turns in step with
-- the others (the preview models all face the same way)
local TURN_START = math.rad(60)
local LOCK_TINT = RGB(112, 120, 158)                -- a locked scooter dims behind its padlock
local ICON_GAP  = 4                                 -- between a price and its Robux icon
local GIFT_FILL = RGB(255, 196, 40)                 -- the gift button: gold (as the Gift page's GIFT)
local GIFT_SIZE, GIFT_GAP = 34, 6                  -- the gift button, and its gap from the pill

local Cards = {}
Cards.__index = Cards

-- gamepad: a white ring round the card it is on
local function ring()
	local f = Instance.new("Frame")
	f.Name = "SelectionRing"
	f.BackgroundTransparency = 1
	f.Position = UDim2.fromOffset(-5, -5)
	f.Size = UDim2.new(1, 10, 1, 10)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = f
	local s = Instance.new("UIStroke"); s.Color = WHITE; s.Thickness = 3; s.Parent = f
	return f
end

function Cards.new(grid, templates, fader, sfx)
	local self = setmetatable({ fader = fader, sfx = sfx, list = {}, byId = {}, price = {}, onPick = nil,
		empties = {}, slotOf = {} }, Cards)
	local cardT, emptyT = templates:WaitForChild("CardTemplate"), templates:WaitForChild("EmptyTemplate")
	-- every scooter gets a card (archived ones last, hidden until arrange shows them to an
	-- owner): past Scooters.Slots the grid grows by whole rows
	local all = table.clone(Scooters.List)
	for _, def in ipairs(Scooters.Archived or {}) do table.insert(all, def) end
	local layout = grid:FindFirstChildOfClass("UIGridLayout")
	local columns = (layout and layout.FillDirectionMaxCells > 0) and layout.FillDirectionMaxCells or 4
	self.columns = columns
	self.minSlots = math.max(Scooters.Slots, math.ceil(#Scooters.List / columns) * columns)
	local slots = math.max(Scooters.Slots, math.ceil(#all / columns) * columns)
	for slot = 1, slots do
		local def = all[slot]
		if def then
			local frame = cardT:Clone()
			frame.Name = "Card_" .. def.Id
			frame.LayoutOrder = slot
			local archived = slot > #Scooters.List
			frame.Visible = not archived
			frame.SelectionImageObject = ring()
			local name = frame:WaitForChild("Title")
			name.Text = def.DisplayName
			local style = NAME_STYLE[def.Id] or NAME_STYLE.Red
			local grad = Instance.new("UIGradient")
			grad.Rotation = style.seq and 0 or 90
			grad.Color = style.seq or ColorSequence.new(style.top, style.bottom)
			grad.Parent = name
			name:WaitForChild("UIStroke").Color = style.edge
			local glow = frame:WaitForChild("Glow")
			glow:WaitForChild("Falloff").Color = ColorSequence.new(TINT[def.Id] or TINT_OTHER)
			local lock = frame:WaitForChild("Lock")
			local action = frame:WaitForChild("Action")
			local label = action:WaitForChild("Label")
			local c = {
				def = def, frame = frame, edge = frame:WaitForChild("Edge"), scale = frame:WaitForChild("Scale"), glow = glow,
				label = label, labelStroke = label:WaitForChild("UIStroke"), sweep = action:WaitForChild("Sweep"),
				action = action, robux = action:WaitForChild("Robux"),
				view = frame:WaitForChild("View"),
				preview = Preview.new(frame:WaitForChild("View"), def.Id, TURN_START),
				lock = lock, lockPop = lock:WaitForChild("Pop"),
				archived = archived,
				look = nil, hover = false, h = 0, on = 0, s = 1, sv = 0,
				locked = false, lockA = 0, ls = 0, lsv = 0,
			}
			frame.Parent = grid
			-- a Robux skin: the gift button beside its pill (opens the Gift page)
			if Gift.canGift(def) then
				-- the pill and the gift button sit side by side, centred together under the scooter
				local shift = (GIFT_GAP + GIFT_SIZE) / 2
				local half = action.Size.X.Offset / 2
				action.Position += UDim2.fromOffset(-shift, 0)
				local shadow = frame:FindFirstChild("ActionShadow")
				if shadow then shadow.Position += UDim2.fromOffset(-shift, 0) end
				local holder, face = Gift.pressable(frame, { Name = "GiftButton",
					Position = UDim2.new(0.5, -shift + half + GIFT_GAP + GIFT_SIZE / 2, 1, -4),
					Size = UDim2.fromOffset(GIFT_SIZE, GIFT_SIZE), Color = GIFT_FILL, ZIndex = 9, Corner = 7 })
				local inset = Instance.new("Frame")
				inset.Name = "Inset"
				inset.BackgroundTransparency = 1
				inset.AnchorPoint = Vector2.new(0.5, 0.5)
				inset.Position = UDim2.fromScale(0.5, 0.5)
				inset.Size = UDim2.fromScale(0.78, 0.78)
				inset.ZIndex = 10
				inset.Parent = face
				Gift.icon(inset, 10)
				c.gift = Motion.button(holder, { fader = fader, sfx = sfx, hover = 1.12, press = 0.88,
					onActivate = function() if self.onGift then self.onGift(def.Id) end end })
			end

			local function hoverOn()
				c.hover = true
				if c.look ~= "Locked" then sfx:play("Hover") end
			end
			frame.MouseEnter:Connect(function() if not Motion.isTouch() then hoverOn() end end)
			frame.MouseLeave:Connect(function() c.hover = false end)
			frame.SelectionGained:Connect(hoverOn)
			frame.SelectionLost:Connect(function() c.hover = false end)
			frame.MouseButton1Down:Connect(function()
				if c.look == "Select" or c.look == "Join" or c.look == "Buy" or c.look == "Rejoin" or c.look == "Limited" then sfx:play("Click"); c.sv -= 1.2 end
			end)
			frame.Activated:Connect(function()
				self.spinId = def.Id     -- the one that turns on phones
				if self.onPick then self.onPick(def.Id) end
			end)
			self.list[slot] = c
			self.byId[def.Id] = c
		else
			local empty = emptyT:Clone()
			empty.Name = "Empty_" .. slot
			empty.LayoutOrder = slot
			empty.Visible = slot <= self.minSlots
			empty.Parent = grid
			table.insert(self.empties, empty)
		end
	end
	self:arrange(nil)
	return self
end

-- The cards' order (see the header), from the server's state (nil: not answered yet, the
-- usual order). Just the new order, no animation: it shows as it is drawn.
function Cards:arrange(state)
	local shown = {}
	for _, c in ipairs(self.list) do
		local id = c.def.Id
		local has = state ~= nil and (state.Selected == id or (state.Unlocked and state.Unlocked[id]) == true)
		c.frame.Visible = not c.archived or has
		if c.frame.Visible then
			local rank = 3                                   -- not theirs
			if has and id == Scooters.DefaultId then rank = 1
			elseif has then rank = 2 end
			table.insert(shown, { c = c, rank = rank })
		end
	end
	table.sort(shown, function(a, b)
		if a.rank ~= b.rank then return a.rank < b.rank end
		if a.c.def.SortOrder ~= b.c.def.SortOrder then return a.c.def.SortOrder < b.c.def.SortOrder end
		return a.c.def.Id < b.c.def.Id
	end)
	table.clear(self.slotOf)
	for i, e in ipairs(shown) do
		e.c.frame.LayoutOrder = i
		self.slotOf[e.c.def.Id] = i
	end
	-- empty slots after the cards, filling the grid out to whole rows (at least Scooters.Slots)
	local total = math.max(self.minSlots, math.ceil(#shown / self.columns) * self.columns)
	for i, e in ipairs(self.empties) do
		e.LayoutOrder = #shown + i
		e.Visible = #shown + i <= total
	end
end

-- where a scooter's card sits in the grid now (1 = top left), or nil if it isn't shown
function Cards:slot(id)
	return self.slotOf[id]
end

-- state: the server's { Selected, Unlocked }, or nil before it has answered
function Cards:render(state, pendingId)
	self:arrange(state)
	for _, c in ipairs(self.list) do
		local id, look = c.def.Id, nil
		-- padlocked while the server says it isn't theirs (unknown yet: no lock)
		c.locked = state ~= nil and state.Selected ~= id and not (state.Unlocked and state.Unlocked[id])
		if not state or pendingId == id then
			look = "Waiting"
		elseif state.Selected == id then
			look = "Selected"
		elseif state.Unlocked and state.Unlocked[id] then
			look = "Select"
		else
			local u = c.def.Unlock
			if u and u.Type == "Group" then
				look = "Join"
			elseif u and u.Type == "GroupReward" then
				-- what the server says this player can do about it right now
				local claim = state.Claim and state.Claim[id]
				look = (claim == "rejoin" and "Rejoin") or (claim == "ask" and "Unlock") or "Join"
			elseif u and u.Type == "Product" and (u.ProductId or u.Price) then
				look = "Buy"
			elseif u and (u.Type == "DailyReward" or u.Type == "Limited") then
				look = "Limited"
			else
				look = "Locked"
			end
		end
		if look ~= c.look then
			c.look = look
			local L = LOOK[look]
			c.label.Text = L.text
			c.label.TextColor3 = L.ink
			c.action.BackgroundColor3 = L.fill
			self.fader:setBase(c.labelStroke, "Transparency", L.outline)
			c.label.Position = UDim2.fromScale(0.5, 0.5)
		end
		-- a price shows as the number and a green Robux icon beside it (placed in update)
		local p = look == "Buy" and (self.price[id] or c.def.Unlock.Price) or nil
		if look == "Buy" then c.label.Text = p and tostring(p) or "BUY" end
		c.robux.Visible = p ~= nil
		if not p then c.label.Position = UDim2.fromScale(0.5, 0.5) end
	end
end

-- a Robux scooter's real price, once its Developer Product has answered (Menu)
function Cards:setPrice(id, robux)
	self.price[id] = robux
end

-- the card that gamepad selection starts on
function Cards:focus(state)
	local c = (state and self.byId[state.Selected]) or self.list[1]
	return c and c.frame
end

-- a small pop and a glare on the newly equipped card
function Cards:celebrate(id)
	local c = self.byId[id]
	if not c then return end
	c.sv += 3
	Motion.sweep(c.sweep, 0.45)
end

-- every frame while the window is showing
function Cards:update(dt, active)
	-- phones and tablets: twelve turning scooters is too much to draw every frame, so
	-- only one turns (the last one tapped, else the equipped one). The rest ease back
	-- to the starting view and stand still, so their viewports aren't redrawn.
	local still = Motion.isTouch()
	local spinId = self.byId[self.spinId] and self.spinId or nil
	if still and not spinId then
		for _, c in ipairs(self.list) do
			if c.look == "Selected" then spinId = c.def.Id end
		end
	end
	for _, c in ipairs(self.list) do
		if not c.frame.Visible then continue end   -- an archived skin they don't have
		c.on = Motion.approach(c.on, c.look == "Selected" and 1 or 0, 12, dt)
		c.h  = Motion.approach(c.h, (active and c.hover and c.look ~= "Locked") and 1 or 0, 14, dt)
		c.s, c.sv = Motion.spring(c.s, c.sv, 1 + 0.04 * c.h + LIFT_ON * c.on, 300, 20, dt)
		c.scale.Scale = math.max(c.s, 0.01)
		self.fader:setBase(c.edge, "Transparency", EDGE_T + (EDGE_T_HOVER - EDGE_T) * c.h)
		self.fader:setBase(c.frame, "BackgroundTransparency", CARD_BG_T + (CARD_BG_T_ON - CARD_BG_T) * c.on)
		-- the padlock pops on while it isn't theirs and off the moment it is
		c.ls, c.lsv = Motion.spring(c.ls, c.lsv, c.locked and 1 or 0, 260, 16, dt)
		c.lockPop.Scale = math.max(c.ls, 0.01)
		c.lock.Visible = c.ls > 0.02
		c.lockA = Motion.approach(c.lockA, c.locked and 1 or 0, 10, dt)
		c.view.ImageColor3 = WHITE:Lerp(LOCK_TINT, c.lockA)
		local glowT = GLOW_T + (GLOW_T_LOCKED - GLOW_T) * c.lockA
		self.fader:setBase(c.glow, "BackgroundTransparency", glowT + (GLOW_T_ON - glowT) * c.on)
		-- price + icon centred together on the pill, the icon a little taller than the digits
		if c.robux.Visible then
			local ratio = c.action.AbsoluteSize.X / math.max(c.action.Size.X.Offset, 1)   -- screen px per template px
			if ratio > 0 then
				local tw, th = c.label.TextBounds.X / ratio, c.label.TextBounds.Y / ratio
				local icon = th * 1.2
				local shift = (ICON_GAP + icon) / 2
				c.label.Position = UDim2.new(0.5, -shift, 0.5, 0)
				c.robux.Size = UDim2.fromOffset(icon, icon)
				c.robux.Position = UDim2.new(0.5, tw / 2 - shift + ICON_GAP + icon / 2, 0.5, 0)
			end
		end
		local stand = still and c.def.Id ~= spinId
		if not stand then
			c.preview:step(dt)
		elseif c.preview.angle ~= TURN_START then
			local d = (TURN_START - c.preview.angle + math.pi) % (math.pi * 2) - math.pi
			c.preview.angle = math.abs(d) < 0.002 and TURN_START or c.preview.angle + d * math.min(1, 8 * dt)
			c.preview:place()
		end
		if c.stand ~= stand then
			c.stand = stand
			c.view:SetAttribute("Still", stand or nil)   -- SkinFx leaves a still card's skin alone
		end
		if c.gift then c.gift:update(dt) end
	end
end

-- a skin's name colours (the Gift page shows its name the same way)
function Cards.NameStyle(id)
	return NAME_STYLE[id] or NAME_STYLE.Red
end

return Cards
