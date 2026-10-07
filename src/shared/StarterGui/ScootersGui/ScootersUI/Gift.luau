--=====================================================================
-- Gift   (ScootersUI)
--
-- Gifting a Robux skin to another player in the server (the server side is
-- ServerScriptService.ScooterSystem.Gifting). A card's gift button opens the Gift
-- page in the Skins window, in place of the cards: the skin turning, its name and
-- price, and everyone else in the server with a GIFT button (OWNS IT when they
-- already have it). GIFT only asks (Remotes.GiftRequest): the server checks it can
-- go, notes who it's for and opens Roblox's purchase prompt. The server says when it
-- has been delivered (Remotes.GiftResult): the window closes and the buyer sees
-- "You have successfully given ...", the receiver "You have been gifted ...".
--   Gift.canGift(def)   whether a card gets the gift button (a Robux skin with a gift
--                       product; in Studio, before the product exists, too)
--   Gift.icon(parent)   the gift icon (Scooters.GiftIcon, or a drawn box until then)
--   Gift.new(opts)      the page, built once inside the window's Panel
--=====================================================================

local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local GuiService         = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local RS                 = game:GetService("ReplicatedStorage")

local Motion   = require(RS:WaitForChild("CheckpointSelector"):WaitForChild("Motion"))
local Scooters = require(RS:WaitForChild("ScooterSystem"):WaitForChild("Shared"):WaitForChild("Scooters"))
local Preview  = require(script.Parent:WaitForChild("Preview"))
local Remotes  = RS:WaitForChild("ScooterSystem"):WaitForChild("Remotes")
local HudSync  = require(RS:WaitForChild("HudSync"))
local Menus    = require(RS:WaitForChild("UITemplates"):WaitForChild("Menus"))
local Cinematic = require(RS:WaitForChild("ScooterSystem"):WaitForChild("Cinematic"))

local player = Players.LocalPlayer
local RGB, WHITE, BLACK = Color3.fromRGB, Color3.new(1, 1, 1), Color3.new(0, 0, 0)
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json")

local PINK      = RGB(255, 196, 40)     -- GIFT: gold (the cards' gift button)
local GREY      = RGB(86, 95, 138)      -- OWNS IT / waiting
local BLUE      = RGB(54, 154, 242)     -- back
local ROW_FILL  = ColorSequence.new({ ColorSequenceKeypoint.new(0, RGB(19, 23, 44)), ColorSequenceKeypoint.new(1, RGB(32, 38, 70)) })
local RIM       = RGB(118, 134, 206)
local ROBUX     = "rbxassetid://102636344783074"   -- the cards' white Robux icon
local RESULT_WAIT = 40                  -- seconds to wait for the server after a purchase
local ICON_FILL   = 1.35                -- the gift picture's size in its spot (it has a margin)

local Gift = {}
Gift.__index = Gift

--------------------------------------------------------------------- small builders
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end
local function corner(parent, r) return new("UICorner", { CornerRadius = UDim.new(0, r) }, parent) end
local function stroke(parent, th, color, t, mode)
	return new("UIStroke", { Thickness = th, Color = color or BLACK, Transparency = t or 0,
		ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Contextual, LineJoinMode = Enum.LineJoinMode.Round }, parent)
end
local function text(parent, props)
	local t = new("TextLabel", {
		BackgroundTransparency = 1, FontFace = FONT, TextColor3 = WHITE, TextScaled = true,
		TextWrapped = true, Text = "",
	}, parent)
	for k, v in pairs(props) do t[k] = v end
	return t
end
local function maxText(label, max, min)
	new("UITextSizeConstraint", { MaxTextSize = max, MinTextSize = min or 1 }, label)
end

-- "GALAXY" -> "Galaxy Scooter"
local function scooterName(def)
	local n = (def and (def.DisplayName or def.Id) or "Scooter"):lower():gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end)
	return n .. " Scooter"
end
Gift.scooterName = scooterName

function Gift.canGift(def)
	local u = def and def.Unlock
	if not (u and u.Type == "Product") then return false end
	return (type(u.GiftProductId) == "number" and u.GiftProductId > 0) or RunService:IsStudio()
end

-- the gift icon filling parent: the owners' picture (Scooters.GiftIcon), or a little box
-- drawn from frames until it's set
function Gift.icon(parent, z)
	z = z or parent.ZIndex + 1
	if type(Scooters.GiftIcon) == "string" and Scooters.GiftIcon ~= "" then
		-- the picture has empty space round the box: drawn a little bigger so the box fills its spot
		return new("ImageLabel", { Name = "GiftIcon", BackgroundTransparency = 1, Image = Scooters.GiftIcon,
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(ICON_FILL, ICON_FILL),
			ScaleType = Enum.ScaleType.Fit, ZIndex = z }, parent)
	end
	local box = new("Frame", { Name = "GiftIcon", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = z }, parent)
	new("UIAspectRatioConstraint", {}, box)
	local function part(name, pos, size, color, r, anchor, zz)
		local f = new("Frame", { Name = name, Position = pos, Size = size, BackgroundColor3 = color,
			AnchorPoint = anchor or Vector2.new(0.5, 0), ZIndex = z + (zz or 0), BorderSizePixel = 0 }, box)
		corner(f, r)
		return f
	end
	local blue, yellow = RGB(46, 150, 255), RGB(255, 214, 56)
	-- bow: two loops
	local l = part("BowL", UDim2.fromScale(0.36, 0.06), UDim2.fromScale(0.3, 0.24), yellow, 6, Vector2.new(0.5, 0))
	l.Rotation = -28 stroke(l, 1.6)
	local r = part("BowR", UDim2.fromScale(0.64, 0.06), UDim2.fromScale(0.3, 0.24), yellow, 6, Vector2.new(0.5, 0))
	r.Rotation = 28 stroke(r, 1.6)
	local body = part("Body", UDim2.fromScale(0.5, 0.42), UDim2.fromScale(0.78, 0.52), blue, 3)
	stroke(body, 1.8)
	local lid = part("Lid", UDim2.fromScale(0.5, 0.27), UDim2.fromScale(0.92, 0.2), RGB(76, 172, 255), 3, nil, 1)
	stroke(lid, 1.8)
	part("RibbonV", UDim2.fromScale(0.5, 0.27), UDim2.fromScale(0.16, 0.67), yellow, 1, nil, 2)
	part("Knot", UDim2.fromScale(0.5, 0.2), UDim2.fromScale(0.2, 0.14), yellow, 3, nil, 3)
	return box
end

-- a pressable holder (Motion.button): Frame "holder" > UIScale "Scale" + TextButton "Face"
local function pressable(parent, props)
	local holder = new("Frame", { Name = props.Name, BackgroundTransparency = 1, Position = props.Position,
		Size = props.Size, AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5), ZIndex = props.ZIndex }, parent)
	new("UIScale", { Name = "Scale" }, holder)
	local face = new("TextButton", { Name = "Face", Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = props.Color, ZIndex = props.ZIndex, Selectable = true }, holder)
	corner(face, props.Corner or 7)
	stroke(face, 2.5, BLACK, 0, Enum.ApplyStrokeMode.Border).Name = "Edge"
	return holder, face
end
Gift.pressable = pressable

--------------------------------------------------------------------- the reveal
-- Getting a scooter: it pops up big in the middle of the screen, turning, with a light
-- burst behind it, NEW SCOOTER!, its name in its colours, who it's from, and confetti.
-- The buyer gets one short line instead ("GIFT SENT TO ...!") that floats up and fades.
-- Both sit over everything for a few seconds and never block a click.
-- The Daily Wheel's prizes use the same reveal in its win mode (fx.win): YOU WON! over the
-- prize (a scooter turning, or a revive / skip picture), its name, and a green CLAIM!
-- button that closes it (it also goes by itself after WIN_HOLD seconds).
-- The reveal never interrupts anything: a scooter given while they ride, sit in a booth,
-- have a menu open, are dead, in a cutscene... is theirs at once, but its reveal WAITS
-- (queued, one after another) until they're free in the lobby: walking about on their
-- own feet, nothing open - the JOIN cards' rule (JoinAlerts) - for a moment.
local nameStyleOf                       -- Cards.NameStyle, handed over by Gift.new
local fx = {}
do
	local pg = player:WaitForChild("PlayerGui")
	for _, n in ipairs({ "GiftReveal", "GiftToast" }) do
		local old = pg:FindFirstChild(n)
		if old then old:Destroy() end
	end
	local gui = new("ScreenGui", { Name = "GiftReveal", ResetOnSpawn = false, DisplayOrder = 60, IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, pg)

	-- win mode: the screen darkens behind the prize (the busy wheel), never catching a click
	local WIN_BACKDROP = 0.6           -- how dark, at most
	local backdrop = new("Frame", { Name = "Backdrop", BackgroundColor3 = BLACK, BackgroundTransparency = 1,
		BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Active = false, Visible = false, ZIndex = 1 }, gui)
	-- the reveal: everything hangs off one centre point
	local reveal = new("CanvasGroup", { ZIndex = 2, Name = "Reveal", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.46), Size = UDim2.fromOffset(620, 560), Visible = false, GroupTransparency = 1 }, gui)
	local fit = new("UIScale", { Name = "Fit" }, reveal)
	-- the light burst: long soft rays turning slowly behind the scooter
	local burst = new("Frame", { Name = "Burst", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(310, 190), Size = UDim2.fromOffset(10, 10) }, reveal)
	local burstScale = new("UIScale", {}, burst)
	for k = 0, 11 do
		local ray = new("Frame", { Name = "Ray", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(k % 2 == 0 and 46 or 26, 560), Rotation = k * 15, BorderSizePixel = 0,
			BackgroundColor3 = RGB(255, 236, 160) }, burst)
		new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.75), NumberSequenceKeypoint.new(0.5, 0.45),
			NumberSequenceKeypoint.new(0.7, 0.75), NumberSequenceKeypoint.new(1, 1) }) }, ray)
	end
	local glow = new("Frame", { Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(310, 190),
		Size = UDim2.fromOffset(300, 300), BackgroundColor3 = RGB(255, 246, 210), BackgroundTransparency = 0.55, BorderSizePixel = 0 }, reveal)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, glow)
	new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 1) }) }, glow)
	local stage = new("Frame", { Name = "Stage", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(310, 190), Size = UDim2.fromOffset(400, 290) }, reveal)
	local stageScale = new("UIScale", {}, stage)

	local headline = text(reveal, { Name = "Headline", Text = "NEW SCOOTER!", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(310, 336), Size = UDim2.fromOffset(600, 72) })
	maxText(headline, 64)
	stroke(headline, 5)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(RGB(255, 248, 150), RGB(255, 176, 30)) }, headline)
	local hScale = new("UIScale", {}, headline)
	local nameLbl = text(reveal, { Name = "SkinName", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(310, 410),
		Size = UDim2.fromOffset(600, 56) })
	maxText(nameLbl, 48)
	local nameEdge = stroke(nameLbl, 4)
	local nameGrad = new("UIGradient", { Rotation = 90 }, nameLbl)
	local fromLbl = text(reveal, { Name = "From", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(310, 470),
		Size = UDim2.fromOffset(600, 40) })
	maxText(fromLbl, 32)
	stroke(fromLbl, 3)
	-- win mode (the Daily Wheel): a prize picture in place of a scooter, and CLAIM!
	local prizePic = new("ImageLabel", { Name = "Prize", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(230, 230), ScaleType = Enum.ScaleType.Fit,
		Visible = false }, stage)
	local claimHolder, claimFace = pressable(reveal, { Name = "Claim", Position = UDim2.fromOffset(310, 470),
		Size = UDim2.fromOffset(270, 66), Color = WHITE, Corner = 10, ZIndex = 3 })
	claimHolder.Visible = false
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(RGB(130, 234, 110), RGB(48, 176, 74)) }, claimFace)
	local claimLbl = text(claimFace, { Name = "Label", Text = "CLAIM!", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -24, 1, -14), ZIndex = 4 })
	maxText(claimLbl, 40)
	stroke(claimLbl, 3)
	local claimScale = claimHolder:WaitForChild("Scale")
	local claimHover, claimS, claimV = false, 0, 0
	-- where the pieces sit in each mode (the gift reveal keeps its own layout)
	local GIFT_LAYOUT = { at = reveal.Position, stage = stage.Position, headline = headline.Position, name = nameLbl.Position }
	local WIN_LAYOUT  = { at = UDim2.fromScale(0.5, 0.52), stage = UDim2.fromOffset(310, 222), headline = UDim2.fromOffset(310, 4),
		name = UDim2.fromOffset(310, 380) }
	local WIN_HOLD = 12                -- seconds a prize waits for CLAIM! before it goes by itself
	local winning = false

	-- confetti, over the whole screen
	local layer = new("Frame", { Name = "Confetti", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5 }, gui)
	local COLORS = { RGB(255, 72, 72), RGB(255, 160, 40), RGB(255, 226, 64), RGB(86, 214, 96), RGB(64, 170, 255), RGB(190, 96, 255) }
	local pieces = {}
	local function confetti()
		local w = gui.AbsoluteSize.X
		for _ = 1, math.min(70, 140 - #pieces) do
			local f = new("Frame", { BorderSizePixel = 0, BackgroundColor3 = COLORS[math.random(#COLORS)],
				Size = UDim2.fromOffset(math.random(8, 14), math.random(14, 22)), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 5 }, layer)
			table.insert(pieces, { f = f, x = math.random() * w, y = -20 - math.random() * 220, vy = 160 + math.random() * 170,
				sway = math.random() * 6.28, rot = math.random(0, 360), vr = math.random(-260, 260), life = 0 })
		end
	end

	-- the buyer's line
	local line = text(gui, { Name = "Line", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(900, 64), Visible = false })
	maxText(line, 52)
	local lineEdge = stroke(line, 4)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(RGB(160, 255, 140), RGB(60, 200, 70)) }, line)
	local lineSub = text(line, { Name = "Sub", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 2),
		Size = UDim2.fromOffset(700, 36), TextColor3 = WHITE })
	maxText(lineSub, 30)
	local subEdge = stroke(lineSub, 3)
	local lineFit = new("UIScale", {}, line)

	local revealToken, shownAt, showing = 0, 0, false
	local preview, view
	local s, sv = 0, 0
	local lineAt = 0

	-- win: nil for a gift; for a Daily Wheel prize { Skin = id } or { Icon = image, Name = text }
	function fx.reveal(skinId, from, win)
		local def = skinId and Scooters.Get(skinId)
		revealToken += 1
		local mine = revealToken
		winning = win ~= nil
		local L = winning and WIN_LAYOUT or GIFT_LAYOUT
		reveal.Position, stage.Position, headline.Position, nameLbl.Position = L.at, L.stage, L.headline, L.name
		backdrop.Visible = winning
		headline.Text = winning and "YOU WON!" or "NEW SCOOTER!"
		fromLbl.Visible = not winning
		claimHolder.Visible = winning
		claimHover, claimS, claimV = false, 0, 0
		nameLbl.Text = def and scooterName(def):upper() or string.upper(win and win.Name or "")
		local style = def and nameStyleOf and nameStyleOf(skinId)
		if style then
			nameGrad.Rotation = style.seq and 0 or 90
			nameGrad.Color = style.seq or ColorSequence.new(style.top, style.bottom)
			nameEdge.Color = style.edge
		else
			nameGrad.Rotation = 90
			nameGrad.Color = ColorSequence.new(WHITE, RGB(226, 230, 240))
			nameEdge.Color = BLACK
		end
		fromLbl.Text = from or ""
		if view then view:Destroy() end
		view, preview = nil, nil
		prizePic.Visible = def == nil
		prizePic.Image = (not def and win and win.Icon) or ""
		if def then
			view = new("ViewportFrame", { Name = "View", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
				Ambient = RGB(180, 180, 190), LightColor = WHITE }, stage)
			preview = Preview.new(view, skinId, math.rad(60))
		end
		reveal.Visible, showing, shownAt = true, true, os.clock()
		s, sv = 0, 0
		confetti()
		if winning and Motion.isGamepad() then GuiService.SelectedObject = claimFace end
		task.delay(winning and WIN_HOLD or 4.8, function() if revealToken == mine then showing = false end end)
	end
	-- CLAIM!: the prize is already theirs (the server gave it); this just closes the reveal
	local function claim()
		if not (winning and showing) then return end
		showing = false
		claimS = 0.9
		if GuiService.SelectedObject == claimFace then GuiService.SelectedObject = nil end
	end
	claimFace.Activated:Connect(claim)
	claimFace.MouseEnter:Connect(function() claimHover = true end)
	claimFace.MouseLeave:Connect(function() claimHover = false end)
	-- a Daily Wheel prize: shown now (the wheel's window is open, so nothing is interrupted)
	function fx.win(prize)
		if type(prize) ~= "table" then return end
		fx.reveal(prize.Skin, nil, prize)
	end

	-- free in the lobby (the JOIN cards' rule): nothing to interrupt
	local introDone, teleporting = false, false
	HudSync.WhenIntroDone(function() introDone = true end)
	player.OnTeleport:Connect(function(state)
		teleporting = state == Enum.TeleportState.Started or state == Enum.TeleportState.InProgress
			or state == Enum.TeleportState.WaitingForServer
	end)
	local function free()
		if not introDone or teleporting then return false end
		-- their own crate opening (CrateOpenFx) is playing: wait for it
		local cam0 = workspace.CurrentCamera
		local openings = cam0 and cam0:FindFirstChild("CrateOpenings")
		if openings and openings:FindFirstChild(player.Name) then return false end
		if HudSync.Aside() then return false end                       -- booth, queue, countdown, ride, spectating
		if Cinematic.IsActive() then return false end
		local cam = workspace.CurrentCamera
		if not cam or cam.CameraType ~= Enum.CameraType.Custom then return false end
		if Menus.IsOpen() or Menus.IsBlocked() then return false end  -- any menu, any blocking screen
		local tut = pg:FindFirstChild("BoothTutorialGui")
		if tut and tut:IsA("ScreenGui") and tut.Enabled then return false end
		local ch = player.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		local root = hum and hum.RootPart
		if not (root and root.Parent) or hum.Health <= 0 then return false end  -- dead / respawning
		if hum.Sit or hum.PlatformStand or root:FindFirstChild("ScooterRiderWeld") then return false end
		return true
	end
	local SETTLE = 1.2                 -- seconds free before a waiting reveal plays
	local waiting = {}                 -- { skinId, from } in the order they came
	local freeSince = nil
	function fx.queue(skinId, from, win)
		table.insert(waiting, { skinId, from, win })
	end
	fx.free = free
	fx.waiting = waiting
	RunService.Heartbeat:Connect(function()
		if #waiting == 0 then freeSince = nil return end
		if reveal.Visible or not free() then freeSince = nil return end
		freeSince = freeSince or os.clock()
		if os.clock() - freeSince < SETTLE then return end
		freeSince = nil
		local nextOne = table.remove(waiting, 1)
		fx.reveal(nextOne[1], nextOne[2], nextOne[3])
	end)

	function fx.line(msg, sub)
		line.Text, lineSub.Text = msg, sub or ""
		line.Visible, lineAt = true, os.clock()
	end

	RunService.RenderStepped:Connect(function(dt)
		dt = math.min(dt, 1 / 30)
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		if reveal.Visible then
			fit.Scale = math.clamp(math.min(vp.X / 700, vp.Y / 640), 0.45, 1.25)
			local t = os.clock() - shownAt
			s, sv = Motion.spring(s, sv, showing and 1 or 0.7, 220, 13, dt)
			stageScale.Scale = math.max(s, 0.01)
			hScale.Scale = math.max(0.01, 1 + 0.06 * math.sin(t * 5) * math.exp(-t * 0.6))
			burstScale.Scale = math.max(s, 0.01) * (1 + 0.05 * math.sin(t * 2))
			burst.Rotation += dt * 22
			reveal.GroupTransparency = Motion.approach(reveal.GroupTransparency, showing and 0 or 1, showing and 14 or 8, dt)
			if preview then preview:step(dt) end
			if backdrop.Visible then backdrop.BackgroundTransparency = 1 - WIN_BACKDROP * (1 - reveal.GroupTransparency) end
			if claimHolder.Visible then
				claimS, claimV = Motion.spring(claimS, claimV, showing and (claimHover and 1.06 or 1) or 0.9, 260, 15, dt)
				claimScale.Scale = math.max(claimS, 0.01)
				claimFace.Active = showing           -- a fading reveal never catches a click
			end
			if not showing and reveal.GroupTransparency > 0.98 then
				reveal.Visible = false
				claimHolder.Visible, winning = false, false
				backdrop.Visible = false
				if view then view:Destroy() end
				view, preview = nil, nil
			end
		end
		if line.Visible then
			lineFit.Scale = math.clamp(math.min(vp.X / 960, vp.Y / 640), 0.45, 1.15)
			local t = os.clock() - lineAt
			line.Position = UDim2.new(0.5, 0, 0.3, -math.min(t, 3) * 14)
			local a = (t < 2.4) and 0 or math.clamp((t - 2.4) / 0.6, 0, 1)
			line.TextTransparency, lineSub.TextTransparency = a, a
			lineEdge.Transparency, subEdge.Transparency = a, a
			if t > 3 then line.Visible = false end
		end
		if #pieces > 0 then
			local h = gui.AbsoluteSize.Y
			for i = #pieces, 1, -1 do
				local p = pieces[i]
				p.life += dt
				p.y += p.vy * dt
				p.rot += p.vr * dt
				p.f.Position = UDim2.fromOffset(p.x + math.sin(p.life * 3 + p.sway) * 24, p.y)
				p.f.Rotation = p.rot
				if p.y > h + 40 or p.life > 6 then
					p.f:Destroy()
					table.remove(pieces, i)
				end
			end
		end
	end)
end
Gift.fx = fx

-- what the server said about a gift (Remotes.GiftResult), for the buyer or the receiver
function Gift.message(kind, otherName, skinId)
	local def = Scooters.Get(skinId)
	local who = tostring(otherName or "someone")
	if kind == "received" then
		fx.queue(skinId, "Gift from " .. who)
	elseif kind == "sent" then
		fx.line("GIFT SENT TO " .. who:upper() .. "!", scooterName(def))
	elseif kind == "instead" then
		fx.queue(skinId, who .. " already had it, so it's yours!")
	elseif kind == "had" then
		fx.line(who:upper() .. " ALREADY HAD IT", scooterName(def))
	elseif kind == "self" then
		fx.queue(skinId, "Your gift couldn't be delivered, so it's yours!")
	end
end

-- what the server said about a crate gift (Remotes.CrateGiftResult), for the buyer
function Gift.crateMessage(kind, otherName)
	if kind == "sent" then
		fx.line("CRATE SENT TO " .. tostring(otherName or "someone"):upper() .. "!", "They'll open it when they're in the lobby")
	elseif kind == "self" then
		fx.line("YOUR GIFT COULDN'T BE DELIVERED", "So the crate is yours!")
	end
end

--------------------------------------------------------------------- the page
-- opts: panel, fader, sfx, title (the window's title label), onBack, onSent
function Gift.new(opts)
	nameStyleOf = opts.nameStyle
	local self = setmetatable({ opts = opts, fader = opts.fader, sfx = opts.sfx, rows = {}, open = false,
		skin = nil, busyFor = nil, buttons = {}, statusUntil = 0 }, Gift)
	local panel = opts.panel

	local page = new("Frame", { Name = "GiftPage", BackgroundTransparency = 1, Position = UDim2.fromOffset(18, 36),
		Size = UDim2.new(1, -36, 1, -54), ZIndex = 4, Visible = false }, panel)
	self.page = page

	-- the skin: back button, turning preview, name, price
	local hero = new("Frame", { Name = "Hero", Size = UDim2.new(1, 0, 0, 176), BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.04, ZIndex = 4 }, page)
	corner(hero, 7)
	new("UIGradient", { Rotation = 90, Color = ROW_FILL }, hero)
	stroke(hero, 1.5, RIM, 0.5, Enum.ApplyStrokeMode.Border)

	local back, backFace = pressable(hero, { Name = "Back", Position = UDim2.fromOffset(42, 42), Size = UDim2.fromOffset(56, 56),
		Color = BLUE, ZIndex = 6, Corner = 10 })
	local chevron = text(backFace, { Name = "Chevron", Text = "<", Size = UDim2.fromScale(1, 0.9),
		Position = UDim2.fromScale(0, 0.02), ZIndex = 7 })
	stroke(chevron, 2.5)
	self.back = Motion.button(back, { fader = self.fader, sfx = self.sfx, hover = 1.08, press = 0.9,
		onActivate = function() if opts.onBack then opts.onBack() end end })

	local well = new("Frame", { Name = "Well", Position = UDim2.fromOffset(86, 12), Size = UDim2.fromOffset(236, 152),
		BackgroundColor3 = RGB(8, 10, 24), BackgroundTransparency = 0.3, ZIndex = 5 }, hero)
	corner(well, 5)
	stroke(well, 1, RGB(190, 204, 255), 0.9)
	self.well = well

	local name = text(hero, { Name = "SkinName", Position = UDim2.fromOffset(344, 26), Size = UDim2.new(1, -520, 0, 58),
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6 })
	maxText(name, 50)
	self.nameEdge = stroke(name, 3)
	self.nameGrad = new("UIGradient", { Rotation = 90 }, name)
	self.name = name
	local sub = text(hero, { Name = "Subtitle", Position = UDim2.fromOffset(346, 88), Size = UDim2.new(1, -520, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = RGB(206, 214, 240), ZIndex = 6,
		Text = "Pick a player to gift it to!" })
	maxText(sub, 24)
	stroke(sub, 2)
	self.sub = sub
	local status = text(hero, { Name = "Status", Position = UDim2.fromOffset(346, 124), Size = UDim2.new(1, -520, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = RGB(255, 110, 120), ZIndex = 6, Visible = false })
	maxText(status, 22)
	stroke(status, 2)
	self.status = status

	local iconBox = new("Frame", { Name = "GiftIcon", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(1, -80, 0, 18), Size = UDim2.fromOffset(84, 84), ZIndex = 6 }, hero)
	Gift.icon(iconBox, 7)
	local price = new("Frame", { Name = "Price", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(1, -80, 0, 112), Size = UDim2.fromOffset(130, 40), ZIndex = 6 }, hero)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, price)
	new("ImageLabel", { Name = "Robux", BackgroundTransparency = 1, Image = ROBUX, Size = UDim2.fromOffset(30, 30),
		LayoutOrder = 1, ZIndex = 7 }, price)
	local amount = text(price, { Name = "Amount", Size = UDim2.fromOffset(70, 38), LayoutOrder = 2, ZIndex = 7,
		TextXAlignment = Enum.TextXAlignment.Left, TextScaled = false, TextSize = 34, AutomaticSize = Enum.AutomaticSize.X })
	amount.Size = UDim2.fromOffset(0, 38)
	stroke(amount, 2.5)
	self.amount = amount

	-- everyone else in the server
	local list = new("ScrollingFrame", { Name = "Players", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 188),
		Size = UDim2.new(1, 0, 1, -188), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6, ScrollBarImageColor3 = RGB(190, 200, 235), ScrollingDirection = Enum.ScrollingDirection.Y,
		BorderSizePixel = 0, ZIndex = 4, ScrollBarImageTransparency = 0.3 }, page)
	new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	new("UIPadding", { PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 2) }, list)
	self.list = list
	local empty = text(page, { Name = "Empty", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 300),
		Size = UDim2.new(0.8, 0, 0, 80), ZIndex = 5, Visible = false,
		Text = "Nobody else is in this server yet.\nInvite a friend to gift them this scooter!" })
	maxText(empty, 28)
	stroke(empty, 2.5)
	self.empty = empty

	-- the server's word on a gift: the buyer's window closes and both see the message
	local resultRemote = opts.crate and Remotes:WaitForChild("CrateGiftResult") or Remotes:WaitForChild("GiftResult")
	resultRemote.OnClientEvent:Connect(function(kind, otherName, skinId)
		if kind ~= "received" then
			self.busyFor = nil
			if opts.onSent then opts.onSent() end
		elseif opts.onReceived then
			opts.onReceived()
		end
		if opts.crate then Gift.crateMessage(kind, otherName) else Gift.message(kind, otherName, skinId) end
	end)
	local function relist()
		if self.open then task.defer(function() self:refresh() end) end
	end
	Players.PlayerAdded:Connect(relist)
	Players.PlayerRemoving:Connect(function(p)
		local row = self.rows[p.UserId]
		if row then self:removeRow(p.UserId) end
		self:layout()
	end)
	return self
end

function Gift:setStatus(msg)
	self.status.Text = msg
	self.status.Visible = true
	self.statusUntil = os.clock() + 3.5
end

-- one player's row: their headshot, names and the GIFT button
function Gift:makeRow(p)
	local row = new("Frame", { Name = "Row_" .. p.UserId, Size = UDim2.new(1, 0, 0, 86), BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.04, ZIndex = 4 }, self.list)
	corner(row, 7)
	new("UIGradient", { Rotation = 90, Color = ROW_FILL }, row)
	stroke(row, 1.5, RIM, 0.5, Enum.ApplyStrokeMode.Border)
	local av = new("ImageLabel", { Name = "Avatar", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.fromOffset(64, 64), BackgroundColor3 = RGB(36, 42, 74), ZIndex = 5, Image = "" }, row)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, av)
	stroke(av, 2.5, WHITE, 0, Enum.ApplyStrokeMode.Border)
	task.spawn(function()
		local ok, img = pcall(Players.GetUserThumbnailAsync, Players, p.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		if ok and av.Parent then av.Image = img end
	end)
	local dn = text(row, { Name = "DisplayName", Text = p.DisplayName, Position = UDim2.fromOffset(94, 12),
		Size = UDim2.new(1, -290, 0, 36), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5 })
	maxText(dn, 30)
	stroke(dn, 2.5)
	local un = text(row, { Name = "UserName", Text = "@" .. p.Name, Position = UDim2.fromOffset(95, 50),
		Size = UDim2.new(1, -290, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = RGB(178, 188, 222), ZIndex = 5 })
	maxText(un, 20)
	stroke(un, 1.5, BLACK, 0.2)

	local holder, face = pressable(row, { Name = "Gift", Position = UDim2.new(1, -92, 0.5, 0), Size = UDim2.fromOffset(150, 48),
		Color = PINK, ZIndex = 6, Corner = 7 })
	local label = text(face, { Name = "Label", Text = "GIFT", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -16, 0.62, 0), ZIndex = 7 })
	maxText(label, 26)
	stroke(label, 1.5)
	local rec = { player = p, row = row, face = face, label = label, look = nil }
	rec.button = Motion.button(holder, { fader = self.fader, sfx = self.sfx, hover = 1.05, press = 0.92,
		onActivate = function() self:send(rec) end })
	self.fader:trackTree(row)
	self.rows[p.UserId] = rec
	return rec
end

function Gift:removeRow(userId)
	local rec = self.rows[userId]
	if not rec then return end
	self.rows[userId] = nil
	self.fader:untrackTree(rec.row)
	rec.row:Destroy()
end

-- how a row's button looks: "gift", "owned", "wait" (this one is on its way), "off"
function Gift:setLook(rec, look)
	if rec.look == look then return end
	rec.look = look
	local fill = (look == "gift") and PINK or GREY
	rec.face.BackgroundColor3 = fill
	rec.label.Text = (look == "owned" and "OWNS IT") or (look == "wait" and "...") or "GIFT"
	rec.button.enabled = look == "gift"
	rec.face.Selectable = look == "gift"
end

function Gift:layout()
	local names = {}
	for _, rec in pairs(self.rows) do table.insert(names, rec) end
	table.sort(names, function(a, b) return a.player.DisplayName:lower() < b.player.DisplayName:lower() end)
	for i, rec in ipairs(names) do rec.row.LayoutOrder = i end
	self.empty.Visible = self.open and #names == 0
end

-- the players here and whether each owns this skin (the server's word)
function Gift:refresh()
	if not self.open or not self.skin then return end
	local skin = self.skin
	local targets = self.opts.crate and Remotes.CrateGiftTargets or Remotes.GiftTargets
	local ok, list = pcall(targets.InvokeServer, targets, skin)
	if not ok or type(list) ~= "table" or not self.open or self.skin ~= skin then
		if self.open and self.skin == skin and ok and list == nil then
			task.delay(0.5, function() self:refresh() end)   -- asked too soon: once more
		end
		return
	end
	local here = {}
	for _, e in ipairs(list) do
		local p = Players:GetPlayerByUserId(e.UserId)
		if p then
			here[e.UserId] = true
			local rec = self.rows[e.UserId] or self:makeRow(p)
			rec.owns = e.Owns
			if self.busyFor == e.UserId then self:setLook(rec, "wait")
			elseif e.Owns then self:setLook(rec, "owned")
			elseif self.busyFor then self:setLook(rec, "off")
			else self:setLook(rec, "gift") end
		end
	end
	for userId in pairs(self.rows) do
		if not here[userId] then self:removeRow(userId) end
	end
	self:layout()
end

-- every row back to what it should be (after a gift was cancelled or failed)
function Gift:settle()
	for _, rec in pairs(self.rows) do
		self:setLook(rec, rec.owns and "owned" or "gift")
	end
end

-- GIFT pressed: the server checks and opens Roblox's purchase prompt
function Gift:send(rec)
	if self.busyFor or not self.skin or rec.look ~= "gift" then return end
	local skin, target = self.skin, rec.player.UserId
	local def = Scooters.Get(skin)
	local productId = (self.opts.crate and self.opts.crate.GiftProductId) or (def and def.Unlock and def.Unlock.GiftProductId)
	self.busyFor = target
	for _, r in pairs(self.rows) do self:setLook(r, r == rec and "wait" or (r.owns and "owned" or "off")) end
	task.spawn(function()
		-- listen before asking: the prompt can close quickly
		local closed, bought = false, false
		local conn = MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, pid, purchased)
			if userId == player.UserId and pid == productId then closed, bought = true, purchased end
		end)
		local requestRemote = self.opts.crate and Remotes.CrateGiftRequest or Remotes.GiftRequest
		local ok, status = pcall(requestRemote.InvokeServer, requestRemote, skin, target)
		if not ok then status = "failed" end
		if status == "prompt" then
			local t0 = os.clock()
			while self.busyFor == target and not closed and os.clock() - t0 < 120 do task.wait(0.1) end
			if closed and bought then
				-- paid: the server delivers it and says so (GiftResult closes the window)
				local t1 = os.clock()
				while self.busyFor == target and os.clock() - t1 < RESULT_WAIT do task.wait(0.1) end
				if self.busyFor == target then
					self.busyFor = nil
					if self.opts.onSent then self.opts.onSent() end
					if self.opts.crate then
						fx.line("CRATE SENT TO " .. rec.player.DisplayName:upper() .. "!", "It's on its way!")
					else
						fx.line("GIFT SENT TO " .. rec.player.DisplayName:upper() .. "!", "It's on its way!")
					end
				end
			elseif self.busyFor == target then
				self.busyFor = nil                         -- closed without buying
			end
		elseif status == "studio" then
			-- a Studio test gift: GiftResult has already said so (or is on its way)
			local t1 = os.clock()
			while self.busyFor == target and os.clock() - t1 < 5 do task.wait(0.1) end
			self.busyFor = nil
		else
			self.busyFor = nil
			if status == "owned" then
				rec.owns = true
				self:setStatus(rec.player.DisplayName .. " already owns this scooter!")
			elseif status == "gone" then
				self:setStatus(rec.player.DisplayName .. " left the server.")
				self:removeRow(target)
				self:layout()
			elseif status == "busy" then
				self:setStatus("One moment, then try again!")
			elseif status == "blocked" then
				self:setStatus("Crates aren't available in your region.")
			else
				self:setStatus("The gift couldn't start. Please try again!")
			end
			if rec.button and status ~= "gone" then rec.button:shake() end
		end
		conn:Disconnect()
		if not self.busyFor then self:settle() end
	end)
end

-- show the page for this skin (the window is already open)
function Gift:show(id)
	local def = Scooters.Get(id)
	if not Gift.canGift(def) then return false end
	self.open, self.skin = true, id
	self.page.Visible = true
	self.status.Visible = false
	-- name, coloured like its card
	self.name.Text = scooterName(def)
	local style = self.opts.nameStyle and self.opts.nameStyle(id)
	if style then
		self.nameGrad.Rotation = style.seq and 0 or 90
		self.nameGrad.Color = style.seq or ColorSequence.new(style.top, style.bottom)
		self.nameEdge.Color = style.edge
	end
	self.amount.Text = tostring(self.opts.priceOf and self.opts.priceOf(id) or def.Unlock.Price or "")
	-- the skin turning in its well (a new viewport each time: the preview keeps its model)
	if self.view then
		self.fader:untrackTree(self.view)
		self.view:Destroy()
	end
	local view = new("ViewportFrame", { Name = "View", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
		ZIndex = 6, Ambient = RGB(170, 170, 180), LightColor = WHITE }, self.well)
	self.view = view
	self.preview = Preview.new(view, id, math.rad(60))
	self.fader:trackTree(view)
	-- the players, fresh
	for userId in pairs(self.rows) do self:removeRow(userId) end
	self.empty.Visible = false
	task.spawn(function() self:refresh() end)
	if Motion.isGamepad() then GuiService.SelectedObject = self.back.face end
	return true
end

-- show the page for a crate (the Shop): its picture, name and price; everyone else here
function Gift:showCrate(image)
	local c = self.opts.crate
	if not c then return false end
	self.open, self.skin = true, self.opts.crateId
	self.page.Visible = true
	self.status.Visible = false
	self.name.Text = c.Name or "CRATE"
	self.nameGrad.Rotation = 90
	self.nameGrad.Color = ColorSequence.new(RGB(255, 236, 120), RGB(255, 140, 30))
	self.nameEdge.Color = BLACK
	self.sub.Text = "Pick a player to gift it to!"
	self.amount.Text = tostring(self.opts.priceOf and self.opts.priceOf(self.opts.crateId) or c.Price or "")
	if self.view then
		self.fader:untrackTree(self.view)
		self.view:Destroy()
	end
	self.preview = nil
	local pic = new("ImageLabel", { Name = "View", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
		ScaleType = Enum.ScaleType.Fit, Image = image or "", ZIndex = 6 }, self.well)
	self.view = pic
	self.fader:trackTree(pic)
	for userId in pairs(self.rows) do self:removeRow(userId) end
	self.empty.Text = "Nobody else is in this server yet.\nInvite a friend to gift them a crate!"
	self.empty.Visible = false
	task.spawn(function() self:refresh() end)
	if Motion.isGamepad() then GuiService.SelectedObject = self.back.face end
	return true
end

function Gift:hide()
	self.open = false
	self.page.Visible = false
	self.skin = nil
	self.status.Visible = false
end

function Gift:update(dt)
	if not self.open then return end
	self.back:update(dt)
	for _, rec in pairs(self.rows) do rec.button:update(dt) end
	if self.preview then self.preview:step(dt) end
	if self.status.Visible and os.clock() > self.statusUntil then self.status.Visible = false end
end

return Gift
