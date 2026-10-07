--=====================================================================
-- DonationBoardClient / BoardUI
--
-- Builds the three SurfaceGuis in code and fills them from the board
-- snapshot. Layout is written in layout px (50 per stud) and a UIScale
-- raises it to Config.PixelsPerStud, so text keeps one physical size on
-- every board and stays sharp. Resize a board part and its layout
-- follows; a taller list simply shows more rows.
--
-- Every hoverable widget is built the same way, which is what lets
-- HoverLift pop any of them out:
--   Holder     layout slot, invisible
--     Socket   dark recess, shown while the widget is lifted out
--     Face     the visible widget; HoverLift clones it onto a part
--
-- BoardUI.newTop builds just the ranked board (podium cards + list) on any
-- part, for other leaderboards (the Top Playtime board); its opts give the
-- title, how a value reads, and drop the tabs and the Robux icon.
--
-- BoardUI.newDuo builds the same ranked list for two-player records (the
-- Fastest Duos board): one row per duo, #rank | avatar name | time | avatar
-- name, and a "Refreshes in Ns" line under it.
--=====================================================================

local TextService       = game:GetService("TextService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("DonationSystem"):WaitForChild("Config"))

local BoardUI = {}
BoardUI.__index = BoardUI

--------------------------------------------------------------------- consts
local DESIGN_PPS = 50
local FONT       = Enum.Font.Arcade
local VERIFIED   = utf8.char(0xE000)     -- Roblox's verified-badge glyph
local INSET      = 3                     -- bezel inset; the dark part shows through as an outline
local ROW_H      = 36                    -- leaderboard row
local BUTTON_H   = 44                    -- donate button
local FILL_T     = 0.3                   -- widget see-through, so the board's studs show
local WHITE      = Color3.new(1, 1, 1)

-- soft light around each widget: rings just outside its rim, fading outward
local GLOW_RINGS = {
	{ Gap = 2, Thickness = 2, Transparency = 0.4 },
	{ Gap = 4, Thickness = 3, Transparency = 0.72 },
}

local FACES = {
	Front = Enum.NormalId.Front, Back  = Enum.NormalId.Back,
	Left  = Enum.NormalId.Left,  Right = Enum.NormalId.Right,
}

local C = {
	Frame      = Color3.fromRGB(30, 32, 74),
	Bezel      = Color3.fromRGB(200, 204, 238),
	Rivet      = Color3.fromRGB(118, 124, 186),
	Title      = Color3.fromRGB(36, 38, 92),
	Screen     = Color3.fromRGB(66, 70, 156),
	Rim        = Color3.fromRGB(150, 170, 255),
	Socket     = Color3.fromRGB(14, 15, 40),
	Text       = Color3.fromRGB(255, 255, 255),
	TextEdge   = Color3.fromRGB(22, 24, 60),
	AvatarBg   = Color3.fromRGB(28, 30, 70),
	TabOn      = Color3.fromRGB(38, 40, 98),
	TabOff     = Color3.fromRGB(214, 217, 245),
	TabOffText = Color3.fromRGB(104, 110, 168),
	Button     = Color3.fromRGB(92, 100, 232),
	Empty      = Color3.fromRGB(92, 96, 150),
	Verified   = Color3.fromRGB(70, 170, 255),
	Muted      = Color3.fromRGB(176, 180, 226),
}

-- Last Donators rows are coloured by the size of the gift
local TIERS = {
	{ min = 10000, color = Color3.fromRGB(255, 208, 72)  },   -- gold
	{ min = 5000,  color = Color3.fromRGB(242, 146, 52)  },   -- orange
	{ min = 2500,  color = Color3.fromRGB(236, 104, 70)  },   -- ember
	{ min = 1000,  color = Color3.fromRGB(150, 96, 232)  },   -- purple
	{ min = 500,   color = Color3.fromRGB(222, 72, 104)  },   -- red
	{ min = 200,   color = Color3.fromRGB(226, 100, 174) },   -- pink
	{ min = 50,    color = Color3.fromRGB(232, 196, 64)  },   -- yellow
	{ min = 20,    color = Color3.fromRGB(86, 198, 98)   },   -- green
	{ min = 0,     color = Color3.fromRGB(72, 188, 232)  },   -- cyan
}

-- leaderboard rows walk cyan -> pink by rank and back, so a long list never jumps colour
local RANK_COLORS = {
	Color3.fromRGB(72, 188, 232),
	Color3.fromRGB(78, 146, 234),
	Color3.fromRGB(100, 110, 230),
	Color3.fromRGB(136, 96, 226),
	Color3.fromRGB(174, 88, 212),
	Color3.fromRGB(210, 92, 182),
	Color3.fromRGB(228, 104, 152),
}

local MEDALS = {
	{ fill = Color3.fromRGB(238, 206, 80),  edge = Color3.fromRGB(146, 104, 18) },   -- 1st gold
	{ fill = Color3.fromRGB(192, 198, 218), edge = Color3.fromRGB(92, 98, 128)  },   -- 2nd silver
	{ fill = Color3.fromRGB(206, 140, 92),  edge = Color3.fromRGB(112, 64, 34)  },   -- 3rd bronze
}

--------------------------------------------------------------------- helpers
local function new(class, props, children)
	local obj = Instance.new(class)
	for k, v in pairs(props) do
		if k ~= "Parent" then obj[k] = v end
	end
	for _, child in ipairs(children or {}) do child.Parent = obj end
	obj.Parent = props.Parent
	return obj
end

local function frame(props, children)
	props.BorderSizePixel = 0
	return new("Frame", props, children)
end

local function corner(r)
	return new("UICorner", { CornerRadius = UDim.new(0, r) })
end

local function edge(color, thickness)
	return new("UIStroke", {
		Name = "Edge", Color = color, Thickness = thickness,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
end

-- vertical gloss: multiplies the fill, full colour at the top
local function shade(bottom)
	return new("UIGradient", {
		Name = "Shade", Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), bottom or Color3.fromRGB(200, 202, 222)),
	})
end

local function label(props)
	props.BackgroundTransparency = 1
	props.Font = props.Font or FONT
	props.TextColor3 = props.TextColor3 or C.Text
	return new("TextLabel", props)
end

-- dark outline on light text; scales with the board, unlike TextStroke
local function outlined(textLabel, thickness)
	new("UIStroke", {
		Color = C.TextEdge, Thickness = thickness or 1.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Miter,
		Parent = textLabel,
	})
	return textLabel
end

-- light halo behind dark text, keeps it crisp over the stud shading
local function halo(textLabel)
	new("UIStroke", {
		Color = WHITE, Thickness = 2, Transparency = 0.25,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = textLabel,
	})
	return textLabel
end

local function formatNumber(n)
	n = math.floor(n + 0.5)
	-- a million or more would outgrow the amount columns: 1 250 000 -> 1.25M
	-- (rounded down, so the board never shows more than was given)
	if n >= 1e6 then
		local v, unit = n / 1e6, "M"
		if n >= 1e9 then v, unit = n / 1e9, "B" end
		local digits = (v < 10) and 2 or (v < 100) and 1 or 0
		local f = 10 ^ digits
		local s = ("%." .. digits .. "f"):format(math.floor(v * f) / f)
		if digits > 0 then s = s:gsub("0+$", ""):gsub("%.$", "") end
		return s .. unit
	end
	local s = tostring(n)
	local sep = Config.ThousandsSeparator
	local out = s:reverse():gsub("(%d%d%d)", "%1" .. sep:reverse()):reverse()
	if out:sub(1, #sep) == sep then out = out:sub(#sep + 1) end
	return out
end

local function tierColor(amount)
	for _, t in ipairs(TIERS) do
		if amount >= t.min then return t.color end
	end
	return TIERS[#TIERS].color
end

local function rankColor(rank)
	local n = #RANK_COLORS
	local i = (rank - 4) % (2 * n - 2)
	if i >= n then i = 2 * n - 2 - i end
	return RANK_COLORS[i + 1]
end

-- Tints a widget: see-through fill, a bright rim and a matching halo.
-- lit = false drops the halo (empty slots should not glow).
local function paint(face, color, fillT, lit)
	face.BackgroundColor3 = color
	face.BackgroundTransparency = fillT or FILL_T
	face.Edge.Color = color:Lerp(WHITE, 0.5)
	for i = 1, #GLOW_RINGS do
		local ring = face:FindFirstChild("Glow" .. i)
		if ring then
			ring.Visible = lit ~= false
			ring.Ring.Color = color:Lerp(WHITE, 0.25)
		end
	end
end

local function headshot(userId)
	if not userId or userId <= 0 then return "" end
	return ("rbxthumb://type=AvatarHeadShot&id=%d&w=48&h=48"):format(userId)
end

local function bust(userId)
	if not userId or userId <= 0 then return "" end
	return ("rbxthumb://type=AvatarBust&id=%d&w=150&h=150"):format(userId)
end

--------------------------------------------------------------------- pieces
local function surface(part, name, playerGui, lift, design)
	design = design or DESIGN_PPS              -- layout px per stud
	local face = FACES[part:GetAttribute("Face") or "Back"] or Enum.NormalId.Back
	local gui = new("SurfaceGui", {
		Name = name,
		Adornee = part,
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = Config.PixelsPerStud,
		LightInfluence = 0,
		Brightness = 1.15,
		MaxDistance = Config.MaxViewDistance,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ClipsDescendants = true,
		ResetOnSpawn = false,
		Parent = playerGui,
	})
	local scale = Config.PixelsPerStud / design
	local board = lift.AddBoard(part, face, gui, scale)
	board.Root = frame({
		Name = "Root", BackgroundTransparency = 1,
		Size = UDim2.fromScale(1 / scale, 1 / scale),
		Parent = gui,
	}, { new("UIScale", { Scale = scale }) })
	return board, board.W * design, board.H * design
end

-- glowing rim with corner rivets and the title; returns it and its inner size.
-- No fill: the board's own white studs are the background.
local function bezel(board, dw, dh, title, titleSize)
	local bz = frame({
		Name = "Bezel", BackgroundTransparency = 1,
		Position = UDim2.fromOffset(INSET, INSET),
		Size = UDim2.new(1, -2 * INSET, 1, -2 * INSET),
		Parent = board.Root,
	}, { corner(12), edge(C.Rim, 3) })

	for _, a in ipairs({ Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) }) do
		frame({
			Name = "Rivet", BackgroundColor3 = C.Rivet, AnchorPoint = a,
			Position = UDim2.new(a.X, a.X == 0 and 7 or -7, a.Y, a.Y == 0 and 7 or -7),
			Size = UDim2.fromOffset(7, 7), Parent = bz,
		}, { corner(2) })
	end

	halo(label({
		Name = "Title", Text = title, TextSize = titleSize, TextColor3 = C.Title,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 5),
		Size = UDim2.new(1, -44, 0, 36), Parent = bz,
	}))
	return bz, dw - 2 * INSET, dh - 2 * INSET
end

-- tinted glass panel the rows sit in; the studs show through it
local function screen(parent, pos, size)
	return frame({
		Name = "Screen", BackgroundColor3 = C.Screen, BackgroundTransparency = 0.45,
		Position = pos, Size = size, Parent = parent,
	}, {
		corner(8), edge(C.Rim, 2),
		-- shadow along the top edge, so the panel reads as sunk into the bezel
		new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 152, 186)),
				ColorSequenceKeypoint.new(0.06, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(206, 206, 230)),
			}),
		}),
	})
end

local function scroller(parent)
	local sf = new("ScrollingFrame", {
		Name = "List", BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.Bezel, ScrollBarImageTransparency = 0.1,
		ElasticBehavior = Enum.ElasticBehavior.Never,
		Parent = parent,
	})
	new("UIPadding", {
		PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5),
		PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 13),
		Parent = sf,
	})
	new("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, Parent = sf })
	return sf
end

local function holdable(parent, name, size, pos, radius)
	local holder = frame({
		Name = name, BackgroundTransparency = 1,
		Size = size, Position = pos or UDim2.new(), Parent = parent,
	})
	local socket = frame({
		Name = "Socket", BackgroundColor3 = C.Socket, BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1), Visible = false, Parent = holder,
	}, { corner(radius) })
	local face = frame({
		Name = "Face", BackgroundTransparency = FILL_T, Size = UDim2.fromScale(1, 1), Parent = holder,
	}, { corner(radius), edge(C.Rim, 2) })
	-- halo rings sit outside the face, so they never cover its content
	for i, ring in ipairs(GLOW_RINGS) do
		frame({
			Name = "Glow" .. i, BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 2 * ring.Gap, 1, 2 * ring.Gap), Parent = face,
		}, {
			new("UICorner", { CornerRadius = UDim.new(0, radius + ring.Gap) }),
			new("UIStroke", {
				Name = "Ring", Color = C.Rim,
				Thickness = ring.Thickness, Transparency = ring.Transparency,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
		})
	end
	return holder, face, socket
end

local function amountGroup(parent, textSize, iconSize, align, props)
	props.Name = "AmountGroup"
	props.BackgroundTransparency = 1
	props.Parent = parent
	local group = frame(props, {
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = align,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),              -- clears the text outline
		}),
	})
	local text = outlined(label({
		Name = "Amount", Text = "0", TextSize = textSize,
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0),
		LayoutOrder = 1, Parent = group,
	}))
	new("ImageLabel", {
		Name = "Robux", Image = Config.RobuxIcon, BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit, Size = UDim2.fromOffset(iconSize, iconSize),
		LayoutOrder = 2, Parent = group,
	})
	return group, text
end

-- player name with a verified badge that follows the text; long names end in "..."
local function nameField(parent, x, maxW, textSize)
	return {
		X = x, Max = maxW,
		Label = outlined(label({
			Name = "PlayerName", Text = "", TextSize = textSize,
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(x, 0), Size = UDim2.new(0, maxW, 1, 0), Parent = parent,
		})),
		Badge = label({
			Name = "Verified", Text = VERIFIED, Font = Enum.Font.BuilderSans,
			TextSize = textSize, TextColor3 = C.Verified, Visible = false,
			Size = UDim2.new(0, textSize, 1, 0), Parent = parent,
		}),
	}
end

local function setName(field, text, verified)
	field.Label.Text = text
	if verified then
		local size = field.Label.TextSize
		local w = TextService:GetTextSize(text, size, FONT, Vector2.new(4096, 256)).X
		local nameW = math.min(math.ceil(w) + 2, field.Max - size - 3)
		field.Label.Size = UDim2.new(0, nameW, 1, 0)
		field.Badge.Position = UDim2.fromOffset(field.X + nameW + 3, 0)
		field.Badge.Visible = true
	else
		field.Label.Size = UDim2.new(0, field.Max, 1, 0)
		field.Badge.Visible = false
	end
end

-- 2D interface sound (not parented to a part, so it is not positional)
local function makeSound(name)
	local spec = Config.Sounds[name]
	local sound = new("Sound", {
		Name = "Sfx" .. name, SoundId = spec.Id, Volume = spec.Volume,
		PlaybackSpeed = spec.Speed or 1, Parent = script,
	})
	sound:SetAttribute("MinGap", spec.MinGap or 0)
	return sound
end

--------------------------------------------------------------------- build
function BoardUI.new(parts, playerGui, lift, actions)
	local self = setmetatable({}, BoardUI)
	self.Lift = lift
	self.Actions = actions
	self.Data = {}
	self.Tab = "allTime"
	self.LastRows, self.Cards, self.Rows, self.Tabs, self.Buttons = {}, {}, {}, {}, {}
	self.Sounds = {
		ButtonHover = makeSound("ButtonHover"),
		ButtonClick = makeSound("ButtonClick"),
		EntryHover  = makeSound("EntryHover"),
	}

	-- rows past the snapshot's top 100, loaded a page at a time as the list is scrolled
	self.Extra = { allTime = { list = {}, page = 1 }, recent = { list = {}, page = 1 } }

	self:BuildLast(parts.Last, playerGui)
	self:BuildTop(parts.Top, playerGui)
	self:BuildDonate(parts.Donate, playerGui)
	self:SelectTab("allTime")
	self.List:GetPropertyChangedSignal("CanvasPosition"):Connect(function() self:MaybeLoadMore() end)
	self.List:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(function() self:MaybeLoadMore() end)
	return self
end

-- Just the ranked board (podium cards + scrolling list) on one part. opts:
--   GuiName, Title ("" = none), DesignPPS (layout px per stud: higher fits more),
--   Format(value) -> text, NoIcon (no Robux icon), Empty / EmptyShort (notes),
--   Header + HeaderText: a title drawn on a separate part above the board,
--   Podium = "Stack": its own top 3 (a #1 banner over #2 and #3), not the Robux cards
--   Footer = true: a "Refreshes in Ns" line under the list (set with SetFooter)
function BoardUI.newTop(part, playerGui, lift, actions, opts)
	local self = setmetatable({}, BoardUI)
	self.Lift, self.Actions, self.Opts = lift, actions, opts
	self.Data, self.Tab = {}, "allTime"
	self.Cards, self.Rows, self.Tabs = {}, {}, {}
	self.Sounds = { EntryHover = makeSound("EntryHover") }
	self:BuildTop(part, playerGui, opts)
	if opts.Header then
		local gui = new("SurfaceGui", {
			Name = opts.GuiName .. "_Header", Adornee = opts.Header,
			Face = FACES[opts.Header:GetAttribute("Face") or "Back"] or Enum.NormalId.Back,
			SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = Config.PixelsPerStud,
			LightInfluence = 0, Brightness = 1.15, MaxDistance = Config.MaxViewDistance,
			ResetOnSpawn = false, Parent = playerGui,
		})
		outlined(label({
			Name = "Title", Text = opts.HeaderText, TextScaled = true, LineHeight = 0.95,
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.94, 0.82), Parent = gui,
		}), 3)
	end
	self:RenderTop()
	return self
end

-- a new snapshot for a newTop board: { allTime = { {u, a, n, v}, ... } }
function BoardUI:ApplyTop(data)
	self.Data = data
	self:RenderTop()
end

function BoardUI:Format(value)
	return (self.Opts and self.Opts.Format or formatNumber)(value)
end

function BoardUI:InspectHandler()
	return function(item) self.Actions.Inspect(item.UserId) end
end

-------------------------------------------- left: Last Donators
function BoardUI:BuildLast(part, playerGui)
	local board, dw, dh = surface(part, "DonationBoard_LastDonators", playerGui, self.Lift)
	local bz, bw, bh = bezel(board, dw, dh, Config.Titles.Last, 26)

	local top, pad, gap = 44, 6, 5
	local sw, sh = bw - 16, bh - top - 8
	local scr = screen(bz, UDim2.fromOffset(8, top), UDim2.new(1, -16, 1, -top - 8))

	local n = Config.MaxLastDonators
	local rowH = math.floor((sh - 2 * pad - gap * (n - 1)) / n)
	local rowW = math.floor(sw - 2 * pad)
	local y0 = math.floor((sh - (rowH * n + gap * (n - 1))) / 2)
	local av = rowH - 10
	local amountW = 92                    -- fits "10 000" plus the icon
	local nameX = 5 + av + 7

	for i = 1, n do
		local holder, face, socket = holdable(scr, "Row" .. i,
			UDim2.fromOffset(rowW, rowH), UDim2.fromOffset(pad, y0 + (i - 1) * (rowH + gap)), 6)
		shade().Parent = face

		local avBg = frame({
			Name = "AvatarBg", BackgroundColor3 = C.AvatarBg, BackgroundTransparency = 0.1,
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 5, 0.5, 0),
			Size = UDim2.fromOffset(av, av), Parent = face,
		}, { corner(5) })
		local avatar = new("ImageLabel", {
			Name = "Avatar", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = avBg,
		}, { corner(5) })

		local name = nameField(face, nameX, rowW - nameX - amountW - 8, 15)
		local group, amount = amountGroup(face, 17, 16, Enum.HorizontalAlignment.Right, {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -7, 0, 0),
			Size = UDim2.new(0, amountW, 1, 0),
		})
		local flash = frame({
			Name = "Flash", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = face,
		}, { corner(6) })

		local item = self.Lift.AddItem(board, {
			Holder = holder, Face = face, Socket = socket,
			Depth = 0.55, Enabled = false, OnClick = self:InspectHandler(),
			HoverSound = self.Sounds.EntryHover,
		})
		self.LastRows[i] = {
			Item = item, Face = face, AvatarBg = avBg, Avatar = avatar,
			Name = name, Group = group, Amount = amount, Flash = flash,
		}
	end
end

-------------------------------------------- middle: Top Donators + ranked list
function BoardUI:MakeCard(board, parent, rank, w, h, x, y)
	local medal = MEDALS[rank]
	local big = rank == 1
	local holder, face, socket = holdable(parent, "Card" .. rank,
		UDim2.fromOffset(w, h), UDim2.fromOffset(x, y), 10)
	paint(face, medal.fill, 0.25)
	face.Edge.Thickness = big and 3 or 2
	shade(Color3.fromRGB(190, 190, 208)).Parent = face

	local stripH = big and 24 or 22
	local amountH = big and 28 or 26
	local strip = frame({
		Name = "NameStrip", BackgroundColor3 = C.Frame, BackgroundTransparency = 0.4,
		Position = UDim2.fromOffset(5, 5), Size = UDim2.new(1, -10, 0, stripH), ZIndex = 2, Parent = face,
	}, { corner(6) })
	local name = outlined(label({
		Name = "PlayerName", Text = "", TextSize = big and 15 or 14,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(5, 0), Size = UDim2.new(1, -10, 1, 0), Parent = strip,
	}))

	-- avatar on a soft halo, between the name and amount strips
	local areaTop = 5 + stripH + 2
	local areaH = h - areaTop - (amountH + 7)
	local haloSize = math.min(areaH, w - 10)
	frame({
		Name = "Halo", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.55,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, areaTop + areaH / 2),
		Size = UDim2.fromOffset(haloSize, haloSize), ZIndex = 1, Parent = face,
	}, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local avatar = new("ImageLabel", {
		Name = "Avatar", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit,
		Position = UDim2.fromOffset(5, areaTop), Size = UDim2.new(1, -10, 0, areaH),
		ZIndex = 2, Parent = face,
	})
	local placeholder = outlined(label({
		Name = "Placeholder", Text = "?", TextSize = big and 44 or 38, TextTransparency = 0.15,
		Position = UDim2.fromOffset(5, areaTop), Size = UDim2.new(1, -10, 0, areaH),
		ZIndex = 2, Parent = face,
	}), 2)

	local amountStrip = frame({
		Name = "AmountStrip", BackgroundColor3 = C.Frame, BackgroundTransparency = 0.4,
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 5, 1, -5),
		Size = UDim2.new(1, -10, 0, amountH), ZIndex = 2, Parent = face,
	}, { corner(6) })
	local amountBox, amount = amountGroup(amountStrip, big and 20 or 17, big and 18 or 15,
		Enum.HorizontalAlignment.Center, { Size = UDim2.fromScale(1, 1) })
	if self.Opts and self.Opts.NoIcon then amountBox.Robux.Visible = false end

	local badgeSize = big and 26 or 22
	local badge = frame({
		Name = "Rank", BackgroundColor3 = medal.edge,
		Position = UDim2.fromOffset(9, areaTop + 3), Size = UDim2.fromOffset(badgeSize, badgeSize),
		ZIndex = 3, Parent = face,
	}, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }), edge(medal.fill, 2) })
	outlined(label({
		Name = "Number", Text = tostring(rank), TextSize = big and 18 or 15,
		Size = UDim2.fromScale(1, 1), Parent = badge,
	}))

	local item = self.Lift.AddItem(board, {
		Holder = holder, Face = face, Socket = socket,
		Depth = 0.8, Enabled = false, OnClick = self:InspectHandler(),
		HoverSound = self.Sounds.EntryHover,
	})
	return { Item = item, Name = name, Avatar = avatar, Placeholder = placeholder, Amount = amount }
end

-- The Stack podium's card: a horizontal medal card, round avatar on the left with
-- its rank on a tag, name, and the value in a pill beside it. #1 is the big banner.
function BoardUI:MakeRankCard(board, parent, rank, w, h, x, y)
	local medal = MEDALS[rank]
	local big = rank == 1
	local holder, face, socket = holdable(parent, "Card" .. rank,
		UDim2.fromOffset(w, h), UDim2.fromOffset(x, y), big and 16 or 12)
	paint(face, medal.fill, 0.4)
	face.Edge.Thickness = big and 3 or 2
	-- sideways sheen (the Robux cards shade top to bottom)
	new("UIGradient", {
		Name = "Shade", Rotation = 0,
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(168, 168, 192)),
		Parent = face,
	})

	local pad = big and 12 or 8
	local av = h - (big and 22 or 18)
	local ring = frame({
		Name = "Ring", BackgroundColor3 = C.Frame, BackgroundTransparency = 0.15,
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, pad, 0.5, -3),
		Size = UDim2.fromOffset(av, av), ZIndex = 2, Parent = face,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		new("UIStroke", { Color = medal.edge, Thickness = big and 4 or 3 }),
	})
	local avatar = new("ImageLabel", {
		Name = "Avatar", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Crop,
		Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = ring,
	}, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local placeholder = outlined(label({
		Name = "Placeholder", Text = "?", TextSize = big and 40 or 28,
		Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = ring,
	}), 2)
	local tag = frame({
		Name = "Rank", BackgroundColor3 = medal.edge,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.fromOffset(big and 46 or 34, big and 22 or 17), ZIndex = 4, Parent = ring,
	}, { corner(9), edge(medal.fill, 2) })
	outlined(label({
		Name = "Number", Text = "#" .. rank, TextSize = big and 16 or 12,
		Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = tag,
	}))

	local tx = pad + av + (big and 16 or 9)
	local name = outlined(label({
		Name = "PlayerName", Text = "", TextSize = big and 20 or 14,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(tx, big and 12 or 7), Size = UDim2.new(1, -tx - 8, 0, big and 24 or 18),
		ZIndex = 2, Parent = face,
	}))
	halo(label({
		Name = "Caption", Text = big and "MOST TIME PLAYED" or "PLAYTIME", TextSize = big and 12 or 10,
		TextColor3 = C.Frame, TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(tx, big and 40 or 27), Size = UDim2.new(1, -tx - 8, 0, 14),
		ZIndex = 2, Parent = face,
	}))
	local pill = frame({
		Name = "TimePill", BackgroundColor3 = C.Frame, BackgroundTransparency = 0.25,
		Position = UDim2.fromOffset(tx - 2, big and 58 or 43), Size = UDim2.new(1, -tx - 6, 0, big and 38 or 26),
		ZIndex = 2, Parent = face,
	}, { corner(big and 12 or 9), edge(medal.fill, 2) })
	local amount = outlined(label({
		Name = "Amount", Text = "", TextSize = big and 26 or 16,
		Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = pill,
	}))

	local item = self.Lift.AddItem(board, {
		Holder = holder, Face = face, Socket = socket,
		Depth = 0.8, Enabled = false, OnClick = self:InspectHandler(),
		HoverSound = self.Sounds.EntryHover,
	})
	return { Item = item, Name = name, Avatar = avatar, Placeholder = placeholder, Amount = amount }
end

function BoardUI:MakeTab(board, parent, text, key, w, h, x, y)
	local holder, face, socket = holdable(parent, "Tab_" .. key,
		UDim2.fromOffset(w, h), UDim2.fromOffset(x, y), 7)
	local textLabel = label({
		Name = "Label", Text = text, TextSize = 18, Size = UDim2.fromScale(1, 1), Parent = face,
	})
	local item = self.Lift.AddItem(board, {
		Holder = holder, Face = face, Socket = socket, Depth = 0.6,
		OnClick = function() self:SelectTab(key) end,
		HoverSound = self.Sounds.EntryHover,
	})
	return { Item = item, Face = face, Label = textLabel }
end

function BoardUI:BuildTop(part, playerGui, opts)
	opts = opts or {}
	local board, dw, dh = surface(part, opts.GuiName or "DonationBoard_Leaderboard", playerGui, self.Lift, opts.DesignPPS)
	local bz, bw = bezel(board, dw, dh, opts.Title or Config.Titles.Top, 30)

	-- podium order: silver, gold, bronze; gold is bigger and stands taller
	local cardsTop = opts.Title == "" and 12 or 46
	local bigW, bigH = math.floor(bw * 0.31), 150
	local smallW, smallH = math.floor(bw * 0.265), 132
	local gap = 12
	local listY = cardsTop + bigH + 9
	if opts.Podium == "Stack" then
		-- #1 across the top, #2 and #3 side by side under it
		local heroH, chipH, chipGap, side = 112, 80, 8, 18
		cardsTop = 22                          -- clear of the frame on top
		self.Cards[1] = self:MakeRankCard(board, bz, 1, bw - 2 * side, heroH, side, cardsTop)
		local chipW = math.floor((bw - 2 * side - chipGap) / 2)
		local y2 = cardsTop + heroH + chipGap
		self.Cards[2] = self:MakeRankCard(board, bz, 2, chipW, chipH, side, y2)
		self.Cards[3] = self:MakeRankCard(board, bz, 3, chipW, chipH, math.floor(bw - side - chipW), y2)
		listY = y2 + chipH + 10
	else
		local x = math.floor((bw - bigW - 2 * smallW - 2 * gap) / 2)
		for _, rank in ipairs({ 2, 1, 3 }) do
			local w, h = smallW, smallH
			if rank == 1 then w, h = bigW, bigH end
			self.Cards[rank] = self:MakeCard(board, bz, rank, w, h, x, cardsTop + bigH - h)
			x += w + gap
		end
	end
	if not self.Opts then                      -- the donation board's ALL-TIME / LAST 30 DAYS tabs
		local tabsY, tabH = cardsTop + bigH + 9, 30
		local tabW = math.floor((bw - 16 - 8) / 2)
		self.Tabs.allTime = self:MakeTab(board, bz, "ALL-TIME", "allTime", tabW, tabH, 8, tabsY)
		self.Tabs.recent = self:MakeTab(board, bz, ("LAST %d DAYS"):format(Config.RecentDays), "recent",
			tabW, tabH, math.floor(bw - 8 - tabW), tabsY)
		listY = tabsY + tabH + 7
	end
	-- opts.Footer: a "Refreshes in Ns" line under the list (SetFooter), as on the duo board
	local footH = opts.Footer and 24 or 0
	local scr = screen(bz, UDim2.fromOffset(8, listY), UDim2.new(1, -16, 1, -listY - 8 - (footH > 0 and footH + 2 or 0)))
	if opts.Footer then
		self.Footer = halo(label({
			Name = "Refresh", Text = "", TextSize = 14, TextColor3 = C.Title,
			AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4),
			Size = UDim2.new(1, -40, 0, footH), Parent = bz,
		}))
	end
	self.List = scroller(scr)
	self.ListBoard = board
	if not self.Opts then                      -- the donation board: shown while the next page loads
		self.Loader = label({
			Name = "Loader", Text = "LOADING...", TextSize = 14, TextColor3 = C.Muted,
			Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 1e9, Visible = false, Parent = self.List,
		})
	end
	self.RowW = math.floor(bw - 16 - 5 - 13)
	self.EmptyNote = label({
		Name = "EmptyNote", Text = "", TextSize = 16, TextColor3 = C.Muted, TextWrapped = true,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -30, 0, 60), Visible = false, Parent = scr,
	})
end

-- rows are made on demand, so an empty board costs nothing
function BoardUI:Row(i)
	local row = self.Rows[i]
	if row then return row end

	local holder, face, socket = holdable(self.List, "Row" .. i, UDim2.new(1, 0, 0, ROW_H), nil, 6)
	holder.LayoutOrder = i
	shade().Parent = face

	local rank = outlined(label({
		Name = "Rank", Text = "", TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(8, 0), Size = UDim2.new(0, 44, 1, 0), Parent = face,
	}))

	local avBg = frame({
		Name = "AvatarBg", BackgroundColor3 = C.AvatarBg, BackgroundTransparency = 0.1,
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 54, 0.5, 0),
		Size = UDim2.fromOffset(28, 28), Parent = face,
	}, { corner(5) })
	local avatar = new("ImageLabel", {
		Name = "Avatar", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = avBg,
	}, { corner(5) })

	local amountW = 104
	local name = nameField(face, 90, self.RowW - 90 - amountW - 12, 16)
	local amountBox, amount = amountGroup(face, 18, 17, Enum.HorizontalAlignment.Right, {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 0),
		Size = UDim2.new(0, amountW, 1, 0),
	})
	if self.Opts and self.Opts.NoIcon then amountBox.Robux.Visible = false end

	local item = self.Lift.AddItem(self.ListBoard, {
		Holder = holder, Face = face, Socket = socket, Viewport = self.List,
		Depth = 0.55, Enabled = false, OnClick = self:InspectHandler(),
		HoverSound = self.Sounds.EntryHover,
	})
	row = { Holder = holder, Item = item, Face = face, Rank = rank, Avatar = avatar, Name = name, Amount = amount }
	self.Rows[i] = row
	return row
end

-------------------------------------------- right: Donate
function BoardUI:BuildDonate(part, playerGui)
	local board, dw, dh = surface(part, "DonationBoard_Donate", playerGui, self.Lift)
	local bz = bezel(board, dw, dh, Config.Titles.Donate, 28)

	local top, footH = 44, 30
	local scr = screen(bz, UDim2.fromOffset(8, top), UDim2.new(1, -16, 1, -top - footH - 12))
	local list = scroller(scr)

	local amounts = {}
	for amount in pairs(Config.DonationProducts) do table.insert(amounts, amount) end
	table.sort(amounts)

	for i, amount in ipairs(amounts) do
		local holder, face, socket = holdable(list, "Donate" .. amount, UDim2.new(1, 0, 0, BUTTON_H), nil, 8)
		holder.LayoutOrder = i
		paint(face, C.Button)
		shade(Color3.fromRGB(180, 186, 232)).Parent = face
		frame({
			Name = "Shine", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.72,
			Position = UDim2.fromOffset(8, 4), Size = UDim2.new(1, -16, 0, 3), Parent = face,
		}, { corner(2) })
		local _, text = amountGroup(face, 24, 22, Enum.HorizontalAlignment.Center, { Size = UDim2.fromScale(1, 1) })
		text.Text = formatNumber(amount)

		local item = self.Lift.AddItem(board, {
			Holder = holder, Face = face, Socket = socket, Viewport = list, Depth = 1,
			OnClick = function() self.Actions.Donate(amount) end,
			HoverSound = self.Sounds.ButtonHover,
			ClickSound = self.Sounds.ButtonClick,
		})
		self.Buttons[amount] = { Item = item, Text = text, Label = text.Text }
	end

	-- footer: the viewer's own all-time total
	local foot = frame({
		Name = "Footer", BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.new(1, -24, 0, footH), Parent = bz,
	}, {
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 5),
		}),
	})
	self.FootCaption = halo(label({
		Name = "Caption", Text = "Donated:", TextSize = 16, TextColor3 = C.Title,
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), LayoutOrder = 1, Parent = foot,
	}))
	self.FootAmount = halo(label({
		Name = "Amount", Text = "0", TextSize = 16, TextColor3 = C.Title,
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), LayoutOrder = 2, Parent = foot,
	}))
	self.FootIcon = new("ImageLabel", {
		Name = "Robux", Image = Config.RobuxIcon, ImageColor3 = C.Title, BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit, Size = UDim2.fromOffset(15, 15), LayoutOrder = 3, Parent = foot,
	})
end

--------------------------------------------------------------------- render
function BoardUI:Apply(data)
	self.Data = data
	self:RenderLast(data.last or {})
	self:RenderTop()
end

function BoardUI:RenderLast(list)
	for i, row in ipairs(self.LastRows) do
		local e = list[i]
		local item = row.Item
		if e then
			paint(row.Face, tierColor(e.a))
			row.AvatarBg.Visible = true
			row.Avatar.Image = headshot(e.u)
			setName(row.Name, e.n or "Player", e.v)
			row.Amount.Text = formatNumber(e.a)
			row.Group.Visible = true
			item.UserId, item.Enabled = e.u, true
		else
			paint(row.Face, C.Empty, 0.65, false)
			row.AvatarBg.Visible = false
			setName(row.Name, "---", false)
			row.Group.Visible = false
			item.UserId, item.Enabled = nil, false
		end
		self.Lift.ContentChanged(item)
	end

	-- a donation just landed: flash the newest row
	local first = list[1]
	local sig = first and ("%s:%s:%s"):format(tostring(first.u), tostring(first.t), tostring(first.a)) or nil
	if self.LastSig and sig and sig ~= self.LastSig then
		local flash = self.LastRows[1].Flash
		flash.BackgroundTransparency = 0.2
		TweenService:Create(flash, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 }):Play()
	end
	self.LastSig = sig
end

-- the tab's rows: the snapshot's top 100, then any deeper pages loaded (each donor once)
function BoardUI:TopList()
	local list = self.Data[self.Tab] or {}
	local extra = self.Extra and self.Extra[self.Tab]
	if not extra or #extra.list == 0 then return list end
	local out, seen = {}, {}
	for _, src in ipairs({ list, extra.list }) do
		for _, e in ipairs(src) do
			if not seen[e.u] then
				seen[e.u] = true
				table.insert(out, e)
			end
		end
	end
	return out
end

-- near the bottom of a tab that goes on: fetch its next page (donation board only)
function BoardUI:MaybeLoadMore()
	if not self.Extra or self.Loading or not self.Actions.FetchPage then return end
	local tab = self.Tab
	local extra = self.Extra[tab]
	local more = extra.page == 1 and (self.Data.more and self.Data.more[tab]) or (extra.page > 1 and extra.more)
	if not more or os.clock() < (extra.retryAt or 0) then return end
	local sf = self.List
	local left = sf.AbsoluteCanvasSize.Y - (sf.CanvasPosition.Y + sf.AbsoluteWindowSize.Y)
	if left > sf.AbsoluteWindowSize.Y then return end   -- more than a screen still to go

	self.Loading = true
	if self.Loader then self.Loader.Visible = true end
	task.spawn(function()
		local page = extra.page + 1
		local result = self.Actions.FetchPage(tab, page)
		if result and self.Extra[tab] == extra then
			for _, e in ipairs(result.list) do table.insert(extra.list, e) end
			extra.page, extra.more, extra.at = page, result.more == true, os.clock()
		elseif not result then
			extra.retryAt = os.clock() + 5          -- busy or offline: try again shortly
		end
		self.Loading = false
		if self.Loader then self.Loader.Visible = false end
		if self.Tab == tab then self:RenderTop() end
		task.defer(function() self:MaybeLoadMore() end)
	end)
end

function BoardUI:RenderTop()
	local list = self:TopList()

	for rank = 1, 3 do
		local card, e = self.Cards[rank], list[rank]
		local item = card.Item
		if e then
			card.Name.Text = e.n or "Player"
			card.Avatar.Image = bust(e.u)
			card.Avatar.Visible = true
			card.Placeholder.Visible = false
			card.Amount.Text = self:Format(e.a)
			item.UserId, item.Enabled = e.u, true
		else
			card.Name.Text = "---"
			card.Avatar.Image = ""
			card.Avatar.Visible = false
			card.Placeholder.Visible = true
			card.Amount.Text = self:Format(0)
			item.UserId, item.Enabled = nil, false
		end
		self.Lift.ContentChanged(item)
	end

	local count = math.max(#list - 3, 0)
	for i = 1, count do
		local rank, e = i + 3, list[i + 3]
		local row = self:Row(i)
		row.Holder.Visible = true
		paint(row.Face, rankColor(rank))
		row.Rank.Text = "#" .. rank
		row.Rank.TextSize = (rank >= 10000) and 9 or (rank >= 1000) and 11 or (rank >= 100) and 13 or 17
		row.Avatar.Image = headshot(e.u)
		setName(row.Name, e.n or "Player", e.v)
		row.Amount.Text = self:Format(e.a)
		row.Item.UserId, row.Item.Enabled = e.u, true
		self.Lift.ContentChanged(row.Item)
	end
	for i = count + 1, #self.Rows do
		local row = self.Rows[i]
		row.Holder.Visible = false
		row.Item.Enabled = false
		self.Lift.ContentChanged(row.Item)
	end

	local opts = self.Opts
	if #list == 0 then
		self.EmptyNote.Text = (opts and opts.Empty) or ((self.Tab == "recent")
			and ("No donations in the last %d days yet"):format(Config.RecentDays)
			or "No donations yet. Be the first!")
		self.EmptyNote.Visible = true
	elseif count == 0 then
		self.EmptyNote.Text = (opts and opts.EmptyShort) or "Donate to join the leaderboard!"
		self.EmptyNote.Visible = true
	else
		self.EmptyNote.Visible = false
	end
end

function BoardUI:SelectTab(key)
	self.Tab = key
	-- deeper pages go stale: coming back to a tab after a while starts from its top 100 again
	local extra = self.Extra and self.Extra[key]
	if extra and extra.page > 1 and os.clock() - (extra.at or 0) > 300 then
		self.Extra[key] = { list = {}, page = 1 }
	end
	for k, tab in pairs(self.Tabs) do
		local on = k == key
		paint(tab.Face, on and C.TabOn or C.TabOff, on and 0.2 or 0.35, on)
		tab.Label.TextColor3 = on and C.Text or C.TabOffText
		self.Lift.ContentChanged(tab.Item)
	end
	self.List.CanvasPosition = Vector2.zero
	self:RenderTop()
end

--------------------------------------------------------------------- duo board
-- One row per duo (the Fastest Duos board). Same pieces as the Top Playtime list:
-- the bezel, the glass screen, the scrolling list, rows that lift out on hover,
-- rank colours (medal colours for the top 3), headshots and name fields. opts:
--   GuiName, DesignPPS, Header + HeaderText (the title part above the board),
--   HeaderSub (optional small line under the title, on the same part),
--   Format(seconds) -> text, Empty (note when there are no records),
--   Margin = { Left, Right, Top, Bottom } layout px kept clear around the whole board
--     (so it sits inside the model's frame with a gap, not under it)
function BoardUI.newDuo(part, playerGui, lift, opts)
	local self = setmetatable({}, BoardUI)
	self.Lift, self.Opts = lift, opts
	self.Duos, self.Rows = {}, {}
	self.Sounds = { EntryHover = makeSound("EntryHover") }

	local board, dw, dh = surface(part, opts.GuiName, playerGui, lift, opts.DesignPPS)
	local m = opts.Margin or {}
	local ml, mr, mt, mb = m.Left or 0, m.Right or 0, m.Top or 0, m.Bottom or 0
	local inner = frame({
		Name = "Inner", BackgroundTransparency = 1,
		Position = UDim2.fromOffset(ml, mt), Size = UDim2.new(1, -ml - mr, 1, -mt - mb),
		Parent = board.Root,
	})
	local bz, bw, bh = bezel({ Root = inner }, dw - ml - mr, dh - mt - mb, "", 30)
	local top, footH = 12, 24
	local scr = screen(bz, UDim2.fromOffset(8, top), UDim2.new(1, -16, 1, -top - footH - 10))
	self.List = scroller(scr)
	self.ListBoard = board
	self.RowW = math.floor(bw - 16 - 5 - 13)
	self.EmptyNote = label({
		Name = "EmptyNote", Text = opts.Empty or "", TextSize = 16, TextColor3 = C.Muted, TextWrapped = true,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -30, 0, 60), Visible = true, Parent = scr,
	})
	-- the countdown to the next reload, under the list
	self.Footer = halo(label({
		Name = "Refresh", Text = "", TextSize = 14, TextColor3 = C.Title,
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(1, -40, 0, footH), Parent = bz,
	}))

	if opts.Header then
		local gui = new("SurfaceGui", {
			Name = opts.GuiName .. "_Header", Adornee = opts.Header,
			Face = FACES[opts.Header:GetAttribute("Face") or "Back"] or Enum.NormalId.Back,
			SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = Config.PixelsPerStud,
			LightInfluence = 0, Brightness = 1.15, MaxDistance = Config.MaxViewDistance,
			ResetOnSpawn = false, Parent = playerGui,
		})
		local sub = opts.HeaderSub
		outlined(label({
			Name = "Title", Text = opts.HeaderText, TextScaled = true, LineHeight = 0.95,
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, sub and 0.36 or 0.5),
			Size = UDim2.fromScale(0.94, sub and 0.6 or 0.82), Parent = gui,
		}), 3)
		if sub then
			outlined(label({
				Name = "Subtitle", Text = sub, TextScaled = true,
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.8),
				Size = UDim2.fromScale(0.9, 0.2), Parent = gui,
			}), 2)
		end
	end
	self:RenderDuos()
	return self
end

-- The booths' own role icons (the Driver's wheel, the Motor's pedal), copied from their
-- smart screens into ReplicatedStorage.RoleIcons. Drawn at 100 px; shown at ICON_W.
local ICON_W, ICON_GAP = 20, 5
local function roleIcon(parent, role)
	local holder = frame({
		Name = "RoleIcon", BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(ICON_W, ICON_W), Parent = parent,
	})
	local folder = ReplicatedStorage:WaitForChild("RoleIcons", 10)
	local template = folder and folder:FindFirstChild(role)
	if template then
		local icon = template:Clone()
		local s = icon:FindFirstChildOfClass("UIScale") or new("UIScale", { Parent = icon })
		s.Scale = s.Scale * ICON_W / 100
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Parent = holder
	end
	return holder
end

-- one player's half of a duo row: headshot (a "?" shows if it cannot load), name and
-- role icon. Unmirrored (the Driver): [avatar] name [icon]. Mirrored (the Motor): the
-- headshot at the far right (x is where the half starts), [icon] name [avatar], the name
-- right-aligned against the headshot.
local function duoSide(face, x, nameW, mirrored, role)
	local avBg = frame({
		Name = "AvatarBg", BackgroundColor3 = C.AvatarBg, BackgroundTransparency = 0.1,
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, mirrored and x + nameW + 6 or x, 0.5, 0),
		Size = UDim2.fromOffset(28, 28), Parent = face,
	}, { corner(5) })
	outlined(label({
		Name = "Placeholder", Text = "?", TextSize = 16, TextTransparency = 0.3,
		Size = UDim2.fromScale(1, 1), Parent = avBg,
	}))
	local avatar = new("ImageLabel", {
		Name = "Avatar", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = avBg,
	}, { corner(5) })
	local name = nameField(face, mirrored and x or x + 34, nameW, 16)
	name.Mirrored = mirrored
	if mirrored then name.Label.TextXAlignment = Enum.TextXAlignment.Right end
	name.Icon = roleIcon(face, role)
	return { Avatar = avatar, Name = name }
end

-- A duo name: the name, its verified badge, and the role icon beside it - after the
-- name for the Driver, before it for the Motor. A name that doesn't fit shrinks its text
-- (down to NAME_MIN) so the badge and the icon always fit. It is never cut short with
-- "...": the label scales its text to whatever width it really draws at (at most the size
-- worked out here), so a name that draws a hair wider than measured just shrinks a hair.
local NAME_SIZE, NAME_MIN = 16, 11
local DRAWN_WIDER = 1.15   -- measured 1.11 on the board (Arcade, outlined), plus a little room
local function setDuoName(field, text, verified)
	field.Label.Text = text
	local iconW = ICON_W + ICON_GAP
	-- TextService, widened by DRAWN_WIDER: these boards draw text ~11% wider than it measures
	-- (measured without it, every name was cut short with "..."). Never the label's own
	-- TextBounds: while the board isn't being drawn (far away, still loading) that's the old,
	-- already-cut width, and the name would stay cut.
	local size, w, badgeW
	for s = NAME_SIZE, NAME_MIN, -1 do
		size = s
		badgeW = verified and NAME_SIZE + 3 or 0     -- the badge keeps its size
		w = math.ceil(TextService:GetTextSize(text, s, FONT, Vector2.new(4096, 256)).X * DRAWN_WIDER) + 4
		if w <= field.Max - badgeW - iconW then break end
	end
	field.Label.TextSize = size
	-- never "...": fit the text to the label's real drawn width instead (no bigger than `size`)
	field.Label.TextTruncate = Enum.TextTruncate.None
	field.Label.TextScaled = true
	local fit = field.Label:FindFirstChild("NameFit") or new("UITextSizeConstraint", { Name = "NameFit", Parent = field.Label })
	fit.MaxTextSize = size
	fit.MinTextSize = 6
	local nameW = math.max(math.min(w, field.Max - badgeW - iconW), 0)
	field.Label.Size = UDim2.new(0, nameW, 1, 0)
	field.Badge.Visible = verified and true or false
	if field.Mirrored then
		-- [icon] name [badge] | avatar
		local right = field.X + field.Max
		field.Badge.Position = UDim2.fromOffset(right - NAME_SIZE, 0)
		local nameX = right - badgeW - nameW
		field.Label.Position = UDim2.fromOffset(nameX, 0)
		field.Icon.Position = UDim2.new(0, nameX - iconW, 0.5, 0)
	else
		-- avatar | name [badge] [icon]
		field.Label.Position = UDim2.fromOffset(field.X, 0)
		field.Badge.Position = UDim2.fromOffset(field.X + nameW + 3, 0)
		field.Icon.Position = UDim2.new(0, field.X + nameW + badgeW + ICON_GAP, 0.5, 0)
	end
end

-- rows are made on demand, so an empty board costs nothing
function BoardUI:DuoRow(i)
	local row = self.Rows[i]
	if row then return row end

	local holder, face, socket = holdable(self.List, "Row" .. i, UDim2.new(1, 0, 0, ROW_H), nil, 6)
	holder.LayoutOrder = i
	shade().Parent = face

	local rank = outlined(label({
		Name = "Rank", Text = "", TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(8, 0), Size = UDim2.new(0, 44, 1, 0), Parent = face,
	}))

	-- rank | [avatar] name | time | [avatar] name, the time centred between the two halves
	local left, right = 54, self.RowW - 8
	local pillW = 112
	local pillX = math.floor((left + right) / 2 - pillW / 2)
	local sideW = pillX - 8 - left                      -- avatar + gap + name, each side
	local first = duoSide(face, left, sideW - 34, false, "Driver")                -- the Driver
	local second = duoSide(face, pillX + pillW + 8, sideW - 34, true, "Motor")    -- the Motor, headshot at the far right

	local pill = frame({
		Name = "TimePill", BackgroundColor3 = C.Frame, BackgroundTransparency = 0.25,
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, pillX, 0.5, 0),
		Size = UDim2.fromOffset(pillW, ROW_H - 8), Parent = face,
	}, { corner(9), edge(C.Rim, 2) })
	local time = outlined(label({
		Name = "Time", Text = "", TextSize = 18, Size = UDim2.fromScale(1, 1), Parent = pill,
	}))

	local item = self.Lift.AddItem(self.ListBoard, {
		Holder = holder, Face = face, Socket = socket, Viewport = self.List,
		Depth = 0.55, Enabled = false, HoverSound = self.Sounds.EntryHover,
	})
	row = { Holder = holder, Item = item, Face = face, Rank = rank, First = first, Second = second,
		Pill = pill, Time = time }
	self.Rows[i] = row
	return row
end

-- a new snapshot for a newDuo board: { duos = { {a, an, av, b, bn, bv, t}, ... } }, fastest
-- first; a is the Driver and b the Motor at the finish (FastestDuosLeaderboard)
function BoardUI:ApplyDuos(data)
	self.Duos = (type(data) == "table" and type(data.duos) == "table") and data.duos or {}
	self:RenderDuos()
end

function BoardUI:RenderDuos()
	local list, shown = self.Duos, 0
	for _, e in ipairs(list) do
		if shown >= 100 then break end
		if type(e) == "table" and tonumber(e.t) and tonumber(e.a) and tonumber(e.b) then
			shown += 1
			local rank = shown
			local row = self:DuoRow(rank)
			row.Holder.Visible = true
			local medal = MEDALS[rank]
			if medal then
				paint(row.Face, medal.fill, 0.25)
				row.Pill.Edge.Color = medal.fill
			else
				local color = rankColor(rank)
				paint(row.Face, color)
				row.Pill.Edge.Color = color:Lerp(WHITE, 0.5)
			end
			row.Rank.Text = "#" .. rank
			row.Rank.TextSize = (rank >= 100) and 13 or 17
			row.First.Avatar.Image = headshot(tonumber(e.a))
			setDuoName(row.First.Name, tostring(e.an or "Player"), e.av)
			row.Second.Avatar.Image = headshot(tonumber(e.b))
			setDuoName(row.Second.Name, tostring(e.bn or "Player"), e.bv)
			row.Time.Text = self.Opts.Format(tonumber(e.t))
			row.Item.Enabled = true
			self.Lift.ContentChanged(row.Item)
		end
	end
	for i = shown + 1, #self.Rows do
		local row = self.Rows[i]
		row.Holder.Visible = false
		row.Item.Enabled = false
		self.Lift.ContentChanged(row.Item)
	end
	self.EmptyNote.Visible = shown == 0
end

function BoardUI:SetFooter(text)
	if self.Footer and self.Footer.Text ~= text then self.Footer.Text = text end
end

--------------------------------------------------------------------- donate panel
function BoardUI:SetMyTotal(total, thanked)
	self.MyTotal = total
	self.ThanksToken = (self.ThanksToken or 0) + 1
	if thanked then
		local token = self.ThanksToken
		self.FootCaption.Text = "THANK YOU!"
		self.FootAmount.Visible, self.FootIcon.Visible = false, false
		task.delay(4, function()
			if self.ThanksToken == token then self:SetMyTotal(self.MyTotal) end
		end)
		return
	end
	self.FootCaption.Text = "Donated:"
	self.FootAmount.Text = formatNumber(total)
	self.FootAmount.Visible, self.FootIcon.Visible = true, true
end

-- brief message on a donate button, e.g. "SOON" when its product id is not set
function BoardUI:FlashButton(amount, text)
	local button = self.Buttons[amount]
	if not button then return end
	button.Text.Text = text
	self.Lift.ContentChanged(button.Item)
	button.Token = (button.Token or 0) + 1
	local token = button.Token
	task.delay(1.2, function()
		if button.Token == token then
			button.Text.Text = button.Label
			self.Lift.ContentChanged(button.Item)
		end
	end)
end

return BoardUI
