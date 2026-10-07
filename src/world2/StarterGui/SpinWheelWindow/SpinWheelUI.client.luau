--=====================================================================
-- SpinWheelUI   (StarterGui.SpinWheelWindow)
--
-- The Daily Wheel: its window, and the wheel in the lobby (Workspace["Spin the Wheel"]).
--   Lobby    the wheel turns slowly on this player's screen while it waits; WHEEL SPINNER
--            and this player's own countdown float above it; its E prompt (DAILY WHEEL,
--            Roblox's own prompt) opens the window.
--   Window   a menu like every other (UITemplates.Menus): it drops in from above, dims and
--            lightly blurs the world behind (Lighting blur: the 3D world only, never a GUI); its X, B, another menu opening, or a booth close it. WHEEL SPINNER
--            and the countdown on top, the wheel, SPIN (n) under it, Robux spins on the right.
--            The wheel turns slowly while it waits, as the lobby one does; after a spin it
--            rests on the slot it landed on for a moment, then turns again.
--   Spins    SPIN (n) is the server's balance plus the free daily spin while it is ready
--            (the SpinBalance / SpinFreeAt attributes, ScooterSystem.SpinWheel). SPIN only
--            asks (Remotes.SpinWheel); the wheel then speeds up, slows and lands on the slot
--            the server picked. Lit (green) while there is a spin, grey at 0.
--   Robux    (only where Roblox's paid random items policy allows: the server checks it, see
--            ScooterSystem.SpinWheel "Policy") Shared.SpinWheel.Products. A button whose ProductId is still 0 says "Coming
--            soon!" and opens nothing; with an ID it opens Roblox's purchase prompt and the
--            server adds the spins (DonationHandler -> SpinWheel.ProcessReceipt).
--   Slots    names, icons and prizes come from Shared.SpinWheel.Slots. A slot with a prize
--            shows its real chance; a skin prize shows the scooter side on (the Skins
--            window's Preview). The lobby wheel is a SurfaceGui, where Roblox doesn't draw
--            ViewportFrames, so there a skin prize is its flat side-on picture (its
--            Picture in Shared.Scooters) in the slot, turning with the wheel. The wheel only ever lands where the server says; then the
--            REWARD banner under the spin packs names what the server gave (the text it
--            sent: "REWARD: RAINBOW SCOOTER"), and a prize the server says is 10% or rarer
--            (Shared.SpinWheel.ConfettiChance) rains confetti down the screen.
--=====================================================================

local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local GuiService         = game:GetService("GuiService")
local CollectionService  = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local RS                 = game:GetService("ReplicatedStorage")

local selector = RS:WaitForChild("CheckpointSelector")
local Motion   = require(selector:WaitForChild("Motion"))
local Sfx      = require(selector:WaitForChild("Sfx"))
local Menus    = require(RS:WaitForChild("UITemplates"):WaitForChild("Menus"))
local HudSync  = require(RS:WaitForChild("HudSync"))
local Root     = RS:WaitForChild("ScooterSystem")
local Wheel    = require(Root:WaitForChild("Shared"):WaitForChild("SpinWheel"))
local Scooters = require(Root:WaitForChild("Shared"):WaitForChild("Scooters"))
local Remote   = Root:WaitForChild("Remotes"):WaitForChild("SpinWheel")

local player     = Players.LocalPlayer
-- the big reveal (the gifting one) for a prize: Gift.fx.win
local GiftFx     = require(player:WaitForChild("PlayerGui"):WaitForChild("ScootersGui"):WaitForChild("ScootersUI"):WaitForChild("Gift")).fx
-- the Skins window's scooter preview, for a skin prize's picture
local Preview    = require(player:WaitForChild("PlayerGui"):WaitForChild("ScootersGui"):WaitForChild("ScootersUI"):WaitForChild("Preview"))
local gui        = script.Parent
local dim        = gui:WaitForChild("Dim")
local window     = gui:WaitForChild("Window")
local winScale   = window:WaitForChild("Scale")
local timerLbl   = window:WaitForChild("Timer")
local wheel      = window:WaitForChild("Wheel")
local disc       = wheel:WaitForChild("Spin")
local spinHolder = window:WaitForChild("SpinButton")
local spinFace   = spinHolder:WaitForChild("Face")
local spinLabel  = spinFace:WaitForChild("Label")
local spinSweep  = spinFace:WaitForChild("Sweep")
local shop       = window:WaitForChild("Shop")
local closeBtn   = window:WaitForChild("CloseButton")
local closeScale = closeBtn:WaitForChild("Scale")
local cross      = closeBtn:WaitForChild("Cross")
local banner     = shop:WaitForChild("Reward")       -- the REWARD banner under the spin packs
local bannerPop  = banner:WaitForChild("Pop")
local bannerText = banner:WaitForChild("Label")
local bannerSweep = banner:WaitForChild("Sweep")

local DIM_MAX    = 0.25          -- how far the world darkens, as every menu
local BLUR_MAX   = 10            -- how much the world blurs behind the window (a little)
local IDLE_SPEED = 9             -- degrees a second: the lobby wheel's slow turn
local SPIN_TIME  = 4.6           -- seconds from SPIN to landing
local SPIN_TURNS = 5             -- whole turns on the way
local REST_TIME  = 3             -- seconds the wheel rests on the slot it landed on
local SLOT_ANGLE = 360 / #Wheel.Slots
local RGB = Color3.fromRGB
-- a button's face (top, bottom), lip and outlines: green while it can be used, grey while not
local ON  = { RGB(130, 234, 110), RGB(48, 176, 74),   RGB(30, 112, 48), RGB(14, 60, 26) }
local OFF = { RGB(178, 184, 198), RGB(122, 128, 144), RGB(82, 86, 100), RGB(40, 44, 54) }

local sfx   = Sfx.new(gui:WaitForChild("Sfx"))
local fader = Motion.fader(nil)
fader:trackTree(window)

local isOpen, winA = false, 0

-- the blur behind the window: this player's view of the world only, made when first needed
local blur
local function setBlur(a)
	if not (blur and blur.Parent) then
		if a <= 0 then return end
		blur = Instance.new("BlurEffect")
		blur.Name = "SpinWheelBlur"
		blur.Parent = game:GetService("Lighting")
	end
	blur.Size = BLUR_MAX * a
	blur.Enabled = a > 0
end
local open, close
local slide = Menus.new(window, { dim = dim, onReplace = function() close() end })

--------------------------------------------------------------------- the player's spins
-- nil until the server has loaded them
local function status()
	local balance, freeAt = player:GetAttribute("SpinBalance"), player:GetAttribute("SpinFreeAt")
	if type(balance) ~= "number" or type(freeAt) ~= "number" then return nil end
	local left = math.max(freeAt + 0.5 - workspace:GetServerTimeNow(), 0)   -- (never ahead of the server's clock)
	local free = left <= 0
	return { count = balance + (free and 1 or 0), free = free, left = left }
end

local function clock(s)
	s = math.ceil(s)
	return string.format("%02d:%02d:%02d", s // 3600, s % 3600 // 60, s % 60)
end

local function timerText(st)
	if not st then return "..." end
	if st.free then return "FREE SPIN READY!" end
	return "NEXT SPIN IN " .. clock(st.left)
end

local flashText, flashUntil = nil, 0
local function flash(text) flashText, flashUntil = text, os.clock() + 3 end

-- a scooter straight side on, whole, standing still (the front to the right), framed tight
-- to its side profile so it fills its picture: its length and height just fit, with a hair
-- of room
local FRAME_MARGIN = 1.06
local function sideView(viewport, skinId)
	local p = Preview.new(viewport, skinId, 0)
	local function place()
		if not (p.model and p.points and viewport.Parent) or viewport.AbsoluteSize.X < 2 then return false end
		local abs = viewport.AbsoluteSize
		local aspect = abs.X / math.max(abs.Y, 1)
		local y0, y1, z0, z1, x1 = math.huge, -math.huge, math.huge, -math.huge, 0
		for _, q in ipairs(p.points) do           -- the model's corners, about its centre
			y0, y1 = math.min(y0, q.Y), math.max(y1, q.Y)
			z0, z1 = math.min(z0, q.Z), math.max(z1, q.Z)
			x1 = math.max(x1, math.abs(q.X))
		end
		local tanV = math.tan(math.rad(p.cam.FieldOfView) / 2)
		local d = x1 + math.max((y1 - y0) / 2, (z1 - z0) / 2 / aspect) * FRAME_MARGIN / tanV
		local focus = p.center + Vector3.new(0, (y0 + y1) / 2, (z0 + z1) / 2)
		p.cam.CFrame = CFrame.lookAt(focus + Vector3.new(d, 0, 0), focus)
		return true
	end
	task.spawn(function()
		while viewport.Parent and not place() do task.wait(0.2) end
	end)
	viewport:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
end

-- a chance as the wheel shows it: 1%, 24.75%, 0.5%
local function percent(c)
	return (string.format("%.2f", c):gsub("%.?0+$", "")) .. "%"
end

local function label(name, parent, pos, size)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json")
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextScaled = true
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position, l.Size = pos, size
	l.ZIndex = 8
	local s = Instance.new("UIStroke")
	s.Color, s.Thickness = Color3.new(0, 0, 0), 2
	s.Parent = l
	l.Parent = parent
	return l
end

-- A prize slot's picture: where it sits in the slot (the label's own scale) - its middle
-- PIC_Y down from the slot's outer edge, PIC_W x PIC_H of the wheel's turning disc
local PIC_Y, PIC_W, PIC_H = 0.13, 0.32, 0.2

-- the lobby wheel's skin prize: its flat side-on picture, in the slot's label (part of the
-- turning disc, so it turns with the wheel); where the window's side view would be
local function lobbyPicture(lab, skinId)
	local skin = Scooters.Get(skinId)
	local pic = Instance.new("ImageLabel")
	pic.Name = "Picture"
	pic.BackgroundTransparency = 1
	pic.Image = skin and skin.Picture or ""
	pic.ScaleType = Enum.ScaleType.Fit
	pic.AnchorPoint = Vector2.new(0.5, 0.5)
	pic.Position, pic.Size = UDim2.fromScale(0.5, PIC_Y), UDim2.fromScale(PIC_W, PIC_H)
	pic.ZIndex = 8
	pic.Parent = lab
	return pic
end

-- the slots' names, icons and prizes, from Shared.SpinWheel (both wheels). A prize slot:
-- its picture out toward the rim, its name, and its real chance under it. (lobbyFace: the
-- lobby wheel's face part - its skin prizes are flat pictures instead of 3D views.)
local function dress(w, fade, lobbyFace)
	local d = w:WaitForChild("Spin")
	for i, s in ipairs(Wheel.Slots) do
		local lab = d:WaitForChild("Label" .. i)
		local nameLbl = lab:WaitForChild("RewardName")
		nameLbl.Text = string.upper(s.Name or "")
		local icon = lab:WaitForChild("Icon")
		local img = icon:WaitForChild("Image")
		img.Visible = s.Icon ~= nil
		if s.Icon then img.Image = s.Icon end
		icon:WaitForChild("Glyph").Visible = s.Icon == nil
		local r = s.Reward
		if r and not lab:FindFirstChild("Chance") then
			-- the name on two lines if it needs them, so it can be big enough to read
			nameLbl.Position, nameLbl.Size = UDim2.fromScale(0.5, 0.272), UDim2.fromScale(0.22, 0.085)
			nameLbl.TextWrapped = true
			local made = { label("Chance", lab, UDim2.fromScale(0.5, 0.338), UDim2.fromScale(0.12, 0.05)) }
			made[1].Text = percent(s.Chance or 0)
			-- a prize with a picture (a revive, a skip): the picture where a scooter would be,
			-- clear of its name and chance
			if r.Kind ~= "Skin" then
				icon.Position = UDim2.fromScale(0.5, PIC_Y)
				icon.Size = UDim2.fromScale(0.16, 0.16)
			end
			if r.Kind == "Skin" and lobbyFace then
				icon.Visible = false
				lobbyPicture(lab, r.Skin)
			elseif r.Kind == "Skin" then
				icon.Visible = false
				local vp = Instance.new("ViewportFrame")
				vp.Name = "Picture"
				vp.BackgroundTransparency = 1
				vp.AnchorPoint = Vector2.new(0.5, 0.5)
				vp.Position, vp.Size = UDim2.fromScale(0.5, PIC_Y), UDim2.fromScale(PIC_W, PIC_H)
				vp.Ambient, vp.LightColor = Color3.fromRGB(150, 158, 178), Color3.fromRGB(255, 250, 242)
				vp.LightDirection = Vector3.new(-0.55, -1, -0.65)
				vp.ZIndex = 8
				vp.Parent = lab
				sideView(vp, r.Skin)
				table.insert(made, vp)
			end
			-- the window's own: fading with it (tracked as made, before any fade)
			if fade then for _, o in ipairs(made) do fade:trackTree(o) end end
		end
	end
end
dress(wheel, fader)

local function paint(holder, C)
	local face, lip = holder:WaitForChild("Face"), holder:WaitForChild("Lip")
	face:WaitForChild("UIGradient").Color = ColorSequence.new(C[1], C[2])
	lip.BackgroundColor3 = C[3]
	face:WaitForChild("Edge").Color = C[4]
	lip:WaitForChild("Edge").Color = C[4]
	for _, name in ipairs({ "Label", "Price", "Caption" }) do
		local l = face:FindFirstChild(name)
		local s = l and l:FindFirstChildOfClass("UIStroke")
		if s then s.Color = C[4] end
	end
end

--------------------------------------------------------------------- the lobby wheel
local lobbyDisc, lobbyTimer, lobbyTitle
local prompts = {}
local function findLobby()
	local m = workspace:FindFirstChild("Spin the Wheel")
	local face = m and m:FindFirstChild("Face")
	local sg = face and face:FindFirstChild("WheelGui")
	local w = sg and sg:FindFirstChild("Wheel")
	if w and w:FindFirstChild("Spin") and w ~= (lobbyDisc and lobbyDisc.Parent) then
		lobbyDisc = w.Spin
		dress(w, nil, face)
		lobbyTitle = face:FindFirstChild("Title")
		lobbyTimer = lobbyTitle and lobbyTitle:FindFirstChild("Timer")
		if lobbyTitle then lobbyTitle.Enabled = not isOpen end
	end
end
-- the wheel's E prompt (tagged, so one streaming back in is wired again)
local function wirePrompt(p)
	if prompts[p] then return end
	prompts[p] = true
	p.Triggered:Connect(function(who)
		if who == nil or who == player then open() end
	end)
	p.Destroying:Connect(function() prompts[p] = nil end)
end
CollectionService:GetInstanceAddedSignal("SpinWheelPrompt"):Connect(wirePrompt)
for _, p in ipairs(CollectionService:GetTagged("SpinWheelPrompt")) do wirePrompt(p) end

--------------------------------------------------------------------- spinning
-- speed over the spin: a quick run-up, then a long slow-down (the table maps time to turn)
local EASE = {}
do
	local N, total, acc = 200, 0, {}
	for i = 0, N do
		local t = i / N
		local v = math.min(t / 0.12, 1) * (1 - t) ^ 3
		total += v
		acc[i] = total
	end
	for i = 0, N do EASE[i] = acc[i] / total end
end
local function ease(t)
	local x = math.clamp(t, 0, 1) * 200
	local i = math.floor(x)
	if i >= 200 then return 1 end
	return EASE[i] + (EASE[i + 1] - EASE[i]) * (x - i)
end

local rot = 0                     -- the window wheel's turn (degrees)
local spinning = false
local spinFrom, spinTo, spinT, spinSlot, spinDup, spinInfo = 0, 0, nil, nil, false, nil
-- the wheel's ticking while it spins (Roblox's own short click, always there)
local tickSound = Instance.new("Sound")
tickSound.Name = "WheelTick"
tickSound.SoundId = "rbxasset://sounds/clickfast.wav"
tickSound.Volume = 0.2
tickSound.Parent = script
local tickSeg, lastTick = nil, 0
local restUntil = 0

-- the REWARD banner: pops in with the server's text and stays until the next spin
local popS, popV = 1, 0
local bannerEdge, bannerFill = banner:WaitForChild("Edge"), banner:WaitForChild("Fill")
local BANNER_LOOK = { edge = bannerEdge.Color, fill = bannerFill.Color }
local OWNED_LOOK  = { edge = RGB(92, 10, 18), fill = ColorSequence.new(RGB(255, 96, 96), RGB(214, 30, 44)) }
local function showReward(text, owned)
	local look = owned and OWNED_LOOK or BANNER_LOOK
	bannerEdge.Color, bannerFill.Color = look.edge, look.fill
	bannerText.Text = owned and text or ("REWARD: " .. text)
	banner.Visible = true
	popS, popV = 0.4, 0
	task.delay(0.15, function() if banner.Visible then Motion.sweep(bannerSweep, 0.7) end end)
end
local function hideReward() banner.Visible = false end

-- confetti from the top of the screen: one burst of pieces that tumble, sway and fade out,
-- each removed as it goes (never more than CONFETTI_CAP on screen)
local CONFETTI_COUNT, CONFETTI_CAP = 80, 160
local CONFETTI_COLORS = { RGB(255, 72, 72), RGB(255, 160, 40), RGB(255, 226, 64), RGB(86, 214, 96),
	RGB(64, 170, 255), RGB(170, 96, 255), RGB(255, 110, 200), RGB(255, 255, 255) }
local confettiLayer = Instance.new("Frame")
confettiLayer.Name = "Confetti"
confettiLayer.BackgroundTransparency = 1
confettiLayer.Size = UDim2.fromScale(1, 1)
confettiLayer.ZIndex = 60
confettiLayer.Parent = gui
local pieces = {}
local function confetti()
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	local unit = math.clamp(math.min(vp.X, vp.Y) / 720, 0.6, 1.6)   -- the same size on a phone as on PC
	for _ = 1, math.min(CONFETTI_COUNT, CONFETTI_CAP - #pieces) do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BackgroundColor3 = CONFETTI_COLORS[math.random(#CONFETTI_COLORS)]
		f.ZIndex = 60
		local w, h = math.random(7, 11) * unit, math.random(12, 19) * unit
		f.Size = UDim2.fromOffset(w, h)
		f.Parent = confettiLayer
		table.insert(pieces, {
			f = f, w = w, h = h,
			x = math.random(), y = -0.05 - math.random() * 0.45,     -- spread above the top: they arrive over ~1.5 s
			vy = 0.28 + math.random() * 0.22,                         -- screen heights a second
			phase = math.random() * math.pi * 2, sway = 0.015 + math.random() * 0.025,
			rot = math.random(0, 359), vr = math.random(-280, 280),
			flip = math.random() * math.pi * 2, age = 0, life = 3.2 + math.random() * 1.2,
		})
	end
end
local function stepConfetti(dt)
	for i = #pieces, 1, -1 do
		local p = pieces[i]
		p.age += dt
		p.y += p.vy * dt
		local x = p.x + math.sin(p.age * 2.4 + p.phase) * p.sway
		p.rot += p.vr * dt
		if p.y > 1.08 or p.age > p.life then
			p.f:Destroy()
			table.remove(pieces, i)
		else
			p.f.Position = UDim2.fromScale(x, p.y)
			p.f.Rotation = p.rot
			p.f.Size = UDim2.fromOffset(p.w * math.abs(math.cos(p.age * 5 + p.flip)) + 1, p.h)   -- flutter
			p.f.BackgroundTransparency = math.clamp((p.age - (p.life - 0.6)) / 0.6, 0, 1)
		end
	end
end

-- the wheel has landed on the server's slot: say what the server gave
local function finishSpin()
	rot = spinTo % 360
	spinT, spinning = nil, false
	restUntil = os.clock() + REST_TIME
	sfx:play("Success")
	local info = spinInfo or {}
	local s = Wheel.Slots[spinSlot]
	local r = s and s.Reward
	if spinDup then
		-- a skin they already own: nothing new, so no reveal - the banner says so, in red
		showReward("YOU ALREADY OWN THIS ITEM", true)
		return
	end
	-- the prize, big in the middle of the screen (with its own confetti): the gifting reveal
	local prize = r and r.Kind == "Skin" and { Skin = r.Skin, Name = s.Name }
		or { Icon = s and s.Icon, Name = info.Text or (s and s.Name) or "?" }
	-- the window was closed mid-spin (a booth, another menu): it waits until they're free,
	-- like a gift's reveal
	local ok, err
	if isOpen then
		ok, err = pcall(GiftFx.win, prize)
	else
		ok, err = pcall(GiftFx.queue, prize.Skin, nil, prize)
	end
	if not ok then
		-- the reveal failed for some reason: say it on the banner as before, so a prize never goes unsaid
		warn("[SpinWheel] prize reveal failed:", err)
		showReward(info.Text or "?")
		if type(info.Chance) == "number" and info.Chance <= Wheel.ConfettiChance then confetti() end
	end
end

local spinBtn
spinBtn = Motion.button(spinHolder, {
	fader = fader, sfx = sfx, hover = 1.04, press = 0.95, lift = 2, sink = 4,
	onActivate = function()
		local st = status()
		if spinning or not isOpen or not (st and st.count > 0) then spinBtn:shake() return end
		spinning = true
		hideReward()
		task.spawn(function()
			local ok, done, slot, _, dup, info = pcall(Remote.InvokeServer, Remote, "spin")
			if not (ok and done and type(slot) == "number") then
				spinning = false
				spinBtn:shake()
				if ok and type(slot) == "string" then flash(slot) end
				return
			end
			-- land the slot under the pointer, a little off its middle, as a real wheel would
			local target = -((slot - 0.5) * SLOT_ANGLE) + (math.random() - 0.5) * SLOT_ANGLE * 0.6
			spinFrom = rot
			spinTo = rot + SPIN_TURNS * 360 + ((target - rot) % 360)
			spinT, spinSlot, spinDup = 0, slot, dup == true
			spinInfo = type(info) == "table" and info or nil
		end)
	end,
})

-- Robux spins: a button whose product isn't set up yet says so and opens nothing
local buyBtns = {}
for i, p in ipairs(Wheel.Products) do
	local holder = shop:WaitForChild("Buy" .. i)
	-- its price: Shared.SpinWheel's, then the Developer Product's real one once it has loaded
	local priceLbl = holder:WaitForChild("Face"):WaitForChild("Price")
	priceLbl.Text = tostring(p.Price)
	local PRICE_POS, PRICE_SIZE = priceLbl.Position, priceLbl.Size
	local PRICE_ANCHOR, PRICE_ALIGN = priceLbl.AnchorPoint, priceLbl.TextXAlignment
	if p.ProductId and p.ProductId ~= 0 then
		task.spawn(function()
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, p.ProductId, Enum.InfoType.Product)
			if ok and info and info.PriceInRobux then
				holder:SetAttribute("PriceText", tostring(info.PriceInRobux))
				if priceLbl.Text ~= "NOT AVAILABLE" then priceLbl.Text = tostring(info.PriceInRobux) end
			end
		end)
	end
	local b
	b = Motion.button(holder, {
		fader = fader, sfx = sfx, hover = 1.04, press = 0.95, lift = 2, sink = 4,
		onActivate = function()
			if not isOpen then return end
			if not p.ProductId or p.ProductId == 0 then
				b:shake()
				flash("Coming soon!")
				return
			end
			-- the server checks Roblox's paid random items policy and opens the purchase itself
			task.spawn(function()
				local ok, done, why = pcall(Remote.InvokeServer, Remote, "buy", i)
				if not (ok and done) then
					b:shake()
					if ok and why == "Extra spins aren't available in your region." then
						-- the red notice says why (the server); the button says so for a moment
						local robux = holder.Face:FindFirstChild("Robux")
						priceLbl.Text = "NOT AVAILABLE"
						priceLbl.Position, priceLbl.Size = UDim2.fromScale(0.5, 0.36), UDim2.fromScale(0.92, 0.42)
						priceLbl.AnchorPoint, priceLbl.TextXAlignment = Vector2.new(0.5, 0.5), Enum.TextXAlignment.Center
						if robux then robux.Visible = false end
						task.delay(1.6, function()
							priceLbl.Text = holder:GetAttribute("PriceText") or tostring(p.Price)
							priceLbl.Position, priceLbl.Size = PRICE_POS, PRICE_SIZE
							priceLbl.AnchorPoint, priceLbl.TextXAlignment = PRICE_ANCHOR, PRICE_ALIGN
							if robux then robux.Visible = true end
						end)
					elseif ok and type(why) == "string" then
						flash(why)
					end
				end
			end)
		end,
	})
	buyBtns[i] = b
end

-- Where paid random items aren't allowed (the server's PolicyService check: the player's
-- PaidSpinsBlocked attribute) the buy buttons go and a note says why. Until the answer is in
-- they stay hidden too. Free spins are unaffected.
-- the note sits on a card in the REWARD banner's style (its corners, edge, fill and gloss),
-- filling the space the three buy buttons take
local blockedCard = Instance.new("Frame")
blockedCard.Name = "BlockedCard"
blockedCard.AnchorPoint = Vector2.new(0.5, 0)
blockedCard.Position = UDim2.new(0.5, 0, 0, 46)
blockedCard.Size = UDim2.fromOffset(220, 280)
blockedCard.BackgroundColor3 = banner.BackgroundColor3
blockedCard.BackgroundTransparency = 0
blockedCard.ZIndex = 6
blockedCard.Visible = false
for _, name in ipairs({ "UICorner", "Edge", "Fill", "Gloss" }) do
	local part = banner:FindFirstChild(name)
	if part then
		local c = part:Clone()
		if c:IsA("GuiObject") then c.Size = UDim2.new(1, -8, 0, 60); c.ZIndex = 7 end
		c.Parent = blockedCard
	end
end
blockedCard.Parent = shop
local blockedNote = Instance.new("TextLabel")
blockedNote.Name = "BlockedNote"
blockedNote.AnchorPoint = Vector2.new(0.5, 0.5)
blockedNote.Position = UDim2.fromScale(0.5, 0.5)
blockedNote.Size = UDim2.new(1, -24, 1, -40)
blockedNote.ZIndex = 8
blockedNote.BackgroundTransparency = 1
blockedNote.FontFace = shop:WaitForChild("Header").FontFace
blockedNote.TextColor3 = Color3.new(1, 1, 1)
blockedNote.TextStrokeTransparency = 0.4
blockedNote.TextScaled = true
blockedNote.TextWrapped = true
blockedNote.Text = "Extra spins aren't available in your region.\n\nYou still get a free spin for every 15 minutes you play!"
blockedNote.Parent = blockedCard
local function applyPolicy()
	local blocked = player:GetAttribute("PaidSpinsBlocked")
	for i in ipairs(Wheel.Products) do
		local holder = shop:FindFirstChild("Buy" .. i)
		if holder then holder.Visible = true end   -- always (a refused press says why)
	end
	blockedCard.Visible = false
end
player:GetAttributeChangedSignal("PaidSpinsBlocked"):Connect(applyPolicy)
applyPolicy()

--------------------------------------------------------------------- open / close
local closeHover, closePressed = false, false
local cCur, cVel, crossRot = 1, 0, 0

-- On a touch screen the red X gets a bigger, invisible tap area (as on the other menus)
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

--------------------------------------------------------------------- responsive (as the other menus)
local BASE_W, BASE_H = window.Size.X.Offset, window.Size.Y.Offset
local WINDOW_SIZE    = 0.85    -- a large wheel: most of the screen's height
local TOUCH_MARGIN_X = 0.08    -- touch: of the screen's width, each side (clears a notch)
local TOUCH_MARGIN_Y = 0.06    -- touch: of the height under the top bar, above and below
local BASE_HOME = slide.home
local rootScale = 1
local function updateScale()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local vp = cam.ViewportSize
	if vp.X < 1 or vp.Y < 1 then return end
	local s = math.min(vp.X, vp.Y) / 720
	if Motion.isTouch() and math.min(vp.X, vp.Y) < 500 then s *= 1.15 end
	s = math.clamp(s * WINDOW_SIZE, 0.6, 1.15)
	rootScale = math.min(s, vp.X * 0.94 / BASE_W, vp.Y * 0.92 / BASE_H)
	local home = BASE_HOME
	local touch = Motion.isTouch()
	if touch then
		local top = GuiService:GetGuiInset().Y
		rootScale = math.min(rootScale, vp.X * (1 - 2 * TOUCH_MARGIN_X) / BASE_W, (vp.Y - top) * (1 - 2 * TOUCH_MARGIN_Y) / BASE_H)
		home = UDim2.new(0.5, 0, 0.5, top / 2)
	end
	slide:setHome(home)
	closeHit.Visible = touch
end
updateScale()
local function bindCamera()
	local c = workspace.CurrentCamera
	if c then c:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale) end
end
bindCamera()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function() bindCamera(); updateScale() end)

open = function()
	if isOpen then return end
	if HudSync.InGame() then return end            -- queued or riding: not now
	if not slide:open() then return end            -- a blocking screen is up
	isOpen = true
	updateScale()
	window.Visible, dim.Visible = true, true
	-- the lobby wheel's prompt and floating title step aside while the window shows its own
	for p in pairs(prompts) do p.Enabled = false end
	if lobbyTitle then lobbyTitle.Enabled = false end
end

close = function()
	if not isOpen then return end
	isOpen = false
	slide:close()
	closeHover, closePressed = false, false
	-- closed mid-spin: the prize is already theirs (the server gave it); the wheel lands at
	-- once and the banner waits for the next open. Otherwise the banner goes with the window.
	if spinT then finishSpin(); disc.Rotation = rot else hideReward() end
	spinBtn:reset()
	for _, b in ipairs(buyBtns) do b:reset() end
	for p in pairs(prompts) do p.Enabled = true end
	if lobbyTitle then lobbyTitle.Enabled = true end
	local sel = GuiService.SelectedObject
	if sel and sel:IsDescendantOf(gui) then GuiService.SelectedObject = nil end
end

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
closeBtn.Activated:Connect(function() close() end)
closeHit.MouseButton1Down:Connect(function()
	if not isOpen then return end
	closePressed = true
	sfx:play("Click")
end)
closeHit.InputEnded:Connect(function(input)
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then closePressed = false end
end)
closeHit.Activated:Connect(function() close() end)
UserInputService.InputBegan:Connect(function(input)
	if isOpen and input.KeyCode == Enum.KeyCode.ButtonB then close() end
end)
-- a booth: every lobby window closes
HudSync.OnInGame(function(on) if on then close() end end)

--------------------------------------------------------------------- frame loop
local lit, nextGlare, since = nil, 0, 1
RunService.RenderStepped:Connect(function(dt)
	dt = math.min(dt, 1 / 30)
	local st = status()

	-- the lobby wheel: its slow turn, and this player's countdown over it
	since += dt
	if since >= 1 then since = 0; findLobby() end
	if lobbyDisc and lobbyDisc.Parent then
		lobbyDisc.Rotation = (lobbyDisc.Rotation + IDLE_SPEED * dt) % 360
	end
	local text = timerText(st)
	if lobbyTimer and lobbyTimer.Text ~= text then lobbyTimer.Text = text end

	if #pieces > 0 then stepConfetti(dt) end       -- (it finishes even if the window closes)

	if not window.Visible then return end
	winScale.Scale = rootScale
	winA = slide:alpha()
	fader:set(winA, {})
	dim.BackgroundTransparency = 1 - DIM_MAX * winA
	setBlur(winA)                                  -- fades in and out with the window

	-- the spin: runs up, slows, lands on the server's slot
	if spinT then
		spinT += dt / SPIN_TIME
		rot = spinFrom + (spinTo - spinFrom) * ease(spinT)
		-- a tick each time a slot's edge passes the pointer: a fast rattle that slows with the wheel
		local seg = math.floor(rot / (360 / math.max(#Wheel.Slots, 1)))
		if tickSeg and seg ~= tickSeg and os.clock() - lastTick > 0.045 then
			lastTick = os.clock()
			tickSound.PlaybackSpeed = 0.95 + math.random() * 0.1
			game:GetService("SoundService"):PlayLocalSound(tickSound)
		end
		tickSeg = seg
		if spinT >= 1 then finishSpin(); tickSeg = nil end
	elseif os.clock() > restUntil then
		rot = (rot + IDLE_SPEED * dt) % 360        -- the slow idle turn
	end
	disc.Rotation = rot

	-- the REWARD banner springs in
	if banner.Visible then
		popS, popV = Motion.spring(popS, popV, 1, 260, 16, dt)
		bannerPop.Scale = math.max(popS, 0.01)
	end

	-- the countdown (or what just happened)
	local line = os.clock() < flashUntil and flashText or text
	if timerLbl.Text ~= line then timerLbl.Text = line end

	-- SPIN (n): lit while there is a spin to use
	local label = ("SPIN (%d)"):format(st and st.count or 0)
	if spinLabel.Text ~= label then spinLabel.Text = label end
	local can = st ~= nil and st.count > 0 and not spinning
	if can ~= lit then lit = can; paint(spinHolder, can and ON or OFF) end
	if can and os.clock() > nextGlare then nextGlare = os.clock() + 2.6; Motion.sweep(spinSweep, 0.6) end
	spinBtn:update(dt)
	for _, b in ipairs(buyBtns) do b:update(dt) end

	-- close button: a spring pop, and the cross turns a quarter on hover (as the other menus)
	cCur, cVel = Motion.spring(cCur, cVel, closePressed and 0.88 or (closeHover and 1.1 or 1), 300, 18, dt)
	closeScale.Scale = math.max(cCur, 0.01)
	crossRot = Motion.approach(crossRot, closeHover and 90 or 0, 12, dt)
	cross.Rotation = crossRot

	if not isOpen and winA < 0.01 then
		winA = 0
		fader:set(0, {})
		setBlur(0)
		window.Visible, dim.Visible = false, false
	end
end)
