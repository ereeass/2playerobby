--=====================================================================
-- Menu   (ShopUI)
--
-- The Shop window (StarterGui.ShopWindow): the house panel as the Skins window has it -
-- the same size, dark studded panel, title and red X - with the shop's picture (TitleIcon)
-- beside its title. It moves like every menu (UITemplates.Menus): it drops in from above,
-- fades as one and dims the world behind; only the red X, B, the SHOP tile again, or
-- another menu opening close it. On a touch screen it fits under Roblox's top bar exactly
-- as the Skins window does.
-- Inside (Panel.Content, a scrolling list, top to bottom):
--   Crate          the big offer card: its name (Title), its picture (Picture), what it
--                  can give (Items.Item1..4: a picture and its chance) and its price (Buy)
--   FeaturedHeader ★ FEATURED ★
--   Featured       a featured item: its name, a line under it, a tag, its picture and Buy
-- The crate's BUY asks the server (Remotes.CrateBuy: ScooterSystem.Crates checks Roblox's
-- paid random items rule and opens the purchase); once bought the window closes and the
-- crate drops and opens in front of the player (StarterPlayerScripts.CrateOpenFx). Its
-- prizes and odds are Shared.Crates' - the server's own. Until its ProductId is set it says
-- SOON!; where paid random items aren't allowed it says N/A. Any other Buy (the featured
-- item) only says SOON! for now.
-- The crate's gold gift button opens the gift page (ScootersUI.Gift, crate mode) in place of the
-- list: everyone else here with GIFT (ScooterSystem.Crates' gift rules). Its "<" (or B) comes
-- back; once a gift has gone the window closes. Hidden where paid random items aren't allowed.
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

local player      = Players.LocalPlayer
local playerGui   = player:WaitForChild("PlayerGui")
local winGui      = playerGui:WaitForChild("ShopWindow")
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

local DIM_MAX = 0.25        -- how far the world darkens, as Settings
local SOON_FOR = 1.2        -- seconds a Buy says SOON!

local sfx   = Sfx.new(winGui:WaitForChild("Sfx"))
local fader = Motion.fader(nil)
fader:trackTree(window)

local Menu = {}
local slide = Menus.new(window, { dim = dim, onReplace = function() Menu.Close() end })

local isOpen = false
local winA = 0

-- On a touch screen the red X gets a bigger, invisible tap area, as on the Skins window
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

--------------------------------------------------------------------- buy buttons
-- every "Buy" holder in the list is the house button; nothing is for sale yet
local buys = {}
local crateBuy                -- the crate's BUY (below); true = it handled the press
local function onBuy(holder, b)
	if crateBuy and crateBuy(holder, b) then return end
	-- not for sale yet: a "no" shake and SOON! for a moment
	b:shake()
	local label = holder.Face:FindFirstChild("Label")
	if not label then return end
	local was = holder:GetAttribute("PriceText") or label.Text
	holder:SetAttribute("PriceText", was)
	label.Text = "SOON!"
	local icon = holder.Face:FindFirstChild("Robux")
	if icon then icon.Visible = false end
	task.delay(SOON_FOR, function()
		label.Text = was
		if icon then icon.Visible = true end
	end)
end
for _, d in ipairs(content:GetDescendants()) do
	if d.Name == "Buy" and d:FindFirstChild("Face") and d:FindFirstChild("Scale") then
		local b
		b = Motion.button(d, {
			fader = fader, sfx = sfx, hover = 1.04, press = 0.95, lift = 2, sink = 4,
			onActivate = function() if isOpen then onBuy(d, b) end end,
		})
		table.insert(buys, b)
	end
end

--------------------------------------------------------------------- the Premium Crate
-- It feels alive: the chest floats gently and a light sweeps the card now and then. Under
-- the pointer (PC) it comes forward: the card swells a touch on a spring and its rim lights
-- up, the chest lifts, grows and leans toward the pointer, gold rays fan out and turn
-- behind it, sparkles twinkle round it, and a light sweeps across the card. A touch screen
-- has no hover: it keeps the idle float and sweeps.
local crate       = content:WaitForChild("Crate")
local crateScale  = crate:WaitForChild("HoverScale")
local crateSweep  = crate:WaitForChild("Sweep")
local crateRim    = crate:WaitForChild("Rim"):FindFirstChildOfClass("UIStroke")
local crateEdge   = crate:WaitForChild("Edge")
local chest       = crate:WaitForChild("Picture"):WaitForChild("Image")
local chestScale  = chest:WaitForChild("ChestScale")
local rays        = crate:WaitForChild("RayClip"):WaitForChild("Rays")
local raysScale   = rays:WaitForChild("Scale")
local sparkles    = crate:WaitForChild("Sparkles"):GetChildren()
local rayList     = {}
for _, r in ipairs(rays:GetChildren()) do if r:IsA("Frame") then table.insert(rayList, r) end end
local RIM_T, RIM_W, EDGE_W = crateRim.Transparency, crateRim.Thickness, crateEdge.Thickness
local CRATE_SWEEP_EVERY = 5          -- seconds between idle sweeps while the window is open
local crateH, crateS, crateV = 0, 1, 0
local crateT, crateHover, nextCrateSweep = 0, false, 0
local tiltX, tiltY, raysRot, lastRayA = 0, 0, 0, -1

-- under the pointer: inside the card AND inside the list's visible part (it scrolls)
local function overCrate()
	if Motion.isTouch() or not isOpen or not content.Visible then return false, 0, 0 end
	local m = UserInputService:GetMouseLocation()      -- this window ignores the top bar inset
	local p, s = crate.AbsolutePosition, crate.AbsoluteSize
	local cp, cs = content.AbsolutePosition, content.AbsoluteSize
	local inside = m.X >= p.X and m.X <= p.X + s.X and m.Y >= p.Y and m.Y <= p.Y + s.Y
		and m.Y >= cp.Y and m.Y <= cp.Y + cs.Y
	if not inside then return false, 0, 0 end
	-- where over the chest, -1..1, for its lean
	local c = chest.AbsolutePosition + chest.AbsoluteSize * 0.5
	local half = math.max(chest.AbsoluteSize.X * 0.5, 1)
	return true, math.clamp((m.X - c.X) / half, -1, 1), math.clamp((m.Y - c.Y) / half, -1, 1)
end

local function stepCrate(dt)
	crateT += dt
	local over, mx, my = overCrate()
	if over and not crateHover then
		sfx:play("Hover")
		Motion.sweep(crateSweep, 0.7)
		nextCrateSweep = os.clock() + CRATE_SWEEP_EVERY
	end
	crateHover = over
	crateH = Motion.approach(crateH, over and 1 or 0, 9, dt)
	-- the card: a springy swell, a brighter, thicker rim
	crateS, crateV = Motion.spring(crateS, crateV, over and 1.025 or 1, 260, 15, dt)
	crateScale.Scale = math.max(crateS, 0.01)
	fader:setBase(crateRim, "Transparency", RIM_T * (1 - crateH))
	crateRim.Thickness = RIM_W + 1.5 * crateH
	crateEdge.Thickness = EDGE_W + 0.5 * crateH
	-- the chest: an idle float; on hover it lifts, grows and leans toward the pointer
	tiltX = Motion.approach(tiltX, over and mx or 0, 8, dt)
	tiltY = Motion.approach(tiltY, over and my or 0, 8, dt)
	chest.Position = UDim2.new(0.5, tiltX * 6, 0.5, math.sin(crateT * 1.6) * 4 - 10 * crateH + tiltY * 4)
	chest.Rotation = math.sin(crateT * 1.1) * 1.5 + tiltX * 6 * crateH
	chestScale.Scale = 1 + 0.08 * crateH + math.sin(crateT * 1.6 + 1) * 0.01
	-- rays: fan out and turn (their fade only written when it changes)
	raysRot = (raysRot + dt * (6 + 24 * crateH)) % 360
	rays.Rotation = raysRot
	raysScale.Scale = 0.55 + 0.45 * crateH
	local rayA = math.floor(crateH * 40 + 0.5) / 40
	if rayA ~= lastRayA then
		lastRayA = rayA
		for _, r in ipairs(rayList) do fader:setBase(r, "BackgroundTransparency", 1 - 0.9 * rayA) end
	end
	-- sparkles: each twinkles on its own beat, only while hovered
	for i, sp in ipairs(sparkles) do
		local tw = math.max(0, math.sin(crateT * 3.2 + i * 1.9))
		fader:setBase(sp, "ImageTransparency", 1 - crateH * tw)
		sp.Rotation = (crateT * 40 + i * 50) % 360
	end
	-- an idle sweep now and then
	if os.clock() > nextCrateSweep then
		nextCrateSweep = os.clock() + CRATE_SWEEP_EVERY
		Motion.sweep(crateSweep, 0.8)
	end
end

-- the crate's prizes: each skin is its scooter straight side on and STILL (a still view is
-- only drawn again when something in it changes, so it costs a phone next to nothing), framed
-- tight to its side profile as the Daily Wheel frames its prizes. The legendary one gets a
-- slow shine every LEGEND_SHINE seconds while the window is open.
local Preview = require(playerGui:WaitForChild("ScootersGui"):WaitForChild("ScootersUI"):WaitForChild("Preview"))
local FRAME_MARGIN = 1.0
local function sideView(viewport, skinId)
	local p = Preview.new(viewport, skinId, 0)
	local function place()
		if not (p.model and p.points and viewport.Parent) or viewport.AbsoluteSize.X < 2 then return false end
		local abs = viewport.AbsoluteSize
		local aspect = abs.X / math.max(abs.Y, 1)
		local y0, y1, z0, z1, x1 = math.huge, -math.huge, math.huge, -math.huge, 0
		for _, q in ipairs(p.points) do
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
		while viewport.Parent and not place() do task.wait(0.25) end
	end)
end
local MarketplaceService = game:GetService("MarketplaceService")
local CrateShared = require(RS:WaitForChild("ScooterSystem"):WaitForChild("Shared"):WaitForChild("Crates"))
local CrateBuy    = RS:WaitForChild("ScooterSystem"):WaitForChild("Remotes"):WaitForChild("CrateBuy")
local CRATE_ID    = "Premium"
local crateDef    = CrateShared.Get(CRATE_ID)
local crateBuyHolder = crate:FindFirstChild("Buy")
local crateLabel  = crateBuyHolder and crateBuyHolder.Face:FindFirstChild("Label")
local crateRobux  = crateBuyHolder and crateBuyHolder.Face:FindFirstChild("Robux")
if crateDef then
	-- each slot shows the server's prize and its real chance
	for i, p in ipairs(crateDef.Prizes) do
		local slot = crate.Items:FindFirstChild("Item" .. i)
		if slot then
			slot:SetAttribute("Skin", p.Skin)
			local ch = slot:FindFirstChild("Chance")
			if ch then ch.Text = p.Chance .. "%" end
		end
	end
	-- the price: Shared.Crates' until the product's own has loaded
	if crateLabel then crateLabel.Text = tostring(crateDef.Price or "") end
	if crateDef.ProductId and crateDef.ProductId ~= 0 then
		task.spawn(function()
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, crateDef.ProductId, Enum.InfoType.Product)
			if ok and info and info.PriceInRobux and crateLabel then
				crateBuyHolder:SetAttribute("PriceText", tostring(info.PriceInRobux))   -- (the price is kept for when N/A goes)
				if crateLabel.Text ~= "NOT AVAILABLE" then crateLabel.Text = tostring(info.PriceInRobux) end
			end
		end)
	end
end
-- where paid random items aren't allowed (the server's check: PaidSpinsBlocked) it says N/A
local function crateBlocked()
	if CrateShared.Allowed(player) then return false end
	return player:GetAttribute("PaidSpinsBlocked") == true
end
-- the price always shows (no N/A, the owners' call); a press where crates aren't allowed is
-- refused instead (refuseCrate)
local function showCrateBlocked()
	if not (crateLabel and crateDef) then return end
	crateLabel.Text = crateBuyHolder:GetAttribute("PriceText") or tostring(crateDef.Price or "")
	if crateRobux then crateRobux.Visible = true end
end
local refusingUntil = 0
local function refuseCrate(b)
	b:shake()
	-- the server's red notice ("not available in your region") - it opens nothing
	task.spawn(function() pcall(CrateBuy.InvokeServer, CrateBuy, CRATE_ID, "check") end)
	if not (crateLabel and crateRobux) then return end
	refusingUntil = os.clock() + 1.6
	crateLabel.Text = "NOT AVAILABLE"
	crateRobux.Visible = false
	task.delay(1.6, function() if os.clock() >= refusingUntil then showCrateBlocked() end end)
end
player:GetAttributeChangedSignal("PaidSpinsBlocked"):Connect(showCrateBlocked)
showCrateBlocked()
local crateAsking = false
crateBuy = function(holder, b)
	if holder ~= crateBuyHolder or not crateDef then return false end
	if not crateDef.ProductId or crateDef.ProductId == 0 then return false end   -- not set up: SOON!
	if crateBlocked() then refuseCrate(b) return true end
	if crateAsking then return true end
	crateAsking = true
	task.spawn(function()
		local ok, opened = pcall(CrateBuy.InvokeServer, CrateBuy, CRATE_ID)
		crateAsking = false
		if not (ok and opened) then b:shake() end
	end)
	return true
end
-- the gift page and the gift button
local Gift = require(playerGui:WaitForChild("ScootersGui"):WaitForChild("ScootersUI"):WaitForChild("Gift"))
local TITLE_TEXT = title.Text
local giftPage
local function showList()
	if giftPage then giftPage:hide() end
	content.Visible = true
	title.Text = TITLE_TEXT
end
local function showGiftPage()
	if not (giftPage and crateDef) then return end
	if giftPage:showCrate(crate.Picture.Image.Image) then
		content.Visible = false
		title.Text = "Gift"
	end
end
if crateDef and crateDef.GiftProductId and crateDef.GiftProductId ~= 0 then
	giftPage = Gift.new({
		panel = panel, fader = fader, sfx = sfx, crate = crateDef, crateId = CRATE_ID,
		priceOf = function() return crateBuyHolder:GetAttribute("PriceText") or crateDef.Price end,
		onBack = showList,
		onSent = function() Menu.Close() end,
	})
	fader:trackTree(giftPage.page)
end
local giftHolder = crate:FindFirstChild("Gift")
local giftBtn
if giftHolder then
	giftBtn = Motion.button(giftHolder, {
		fader = fader, sfx = sfx, hover = 1.08, press = 0.92, lift = 2, sink = 4,
		onActivate = function()
			if not isOpen then return end
			if crateBlocked() then refuseCrate(giftBtn) return end
			showGiftPage()
		end,
	})
	local function giftShown() giftHolder.Visible = giftPage ~= nil end   -- always shown (a blocked press is refused)
	player:GetAttributeChangedSignal("PaidSpinsBlocked"):Connect(giftShown)
	giftShown()
end

-- bought: the window closes, and the crate drops in front of them (CrateOpenFx)
MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
	if purchased and userId == player.UserId and crateDef and productId == crateDef.ProductId then
		Menu.Close()
	end
end)
local LEGEND_SHINE = 3.2
local legendShine
for _, slot in ipairs(crate:WaitForChild("Items"):GetChildren()) do
	local skin = slot:GetAttribute("Skin")
	local view = slot:FindFirstChild("View")
	if type(skin) == "string" and view then sideView(view, skin) end
	if slot:GetAttribute("Rarity") == "LEGENDARY" then legendShine = slot:FindFirstChild("Shine") end
end
if legendShine then legendShine.Visible = false end
local nextLegendShine = 0
local function stepPrizes()
	if legendShine and isOpen and os.clock() > nextLegendShine then
		nextLegendShine = os.clock() + LEGEND_SHINE
		Motion.sweep(legendShine, 0.9)
	end
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
		-- the middle of the space under the top bar; the title rides above the panel
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
	content.CanvasPosition = Vector2.zero       -- always opens at the top
	if giftPage and giftPage.open then showList() end
	if winA < 0.05 then
		task.delay(0.24, function() if isOpen then Motion.sweep(panelSweep, 0.75) end end)
	end
	window.Visible, dim.Visible = true, true
	return true
end

function Menu.Close()
	if not isOpen then return end
	isOpen = false
	slide:close()
	closeHover, closePressed = false, false
	for _, b in ipairs(buys) do b:reset() end
	crateHover = false
	local sel = GuiService.SelectedObject
	if sel and sel:IsDescendantOf(winGui) then GuiService.SelectedObject = nil end
	-- the frame loop hides the window once it has faded out
end

-- what the SHOP tile does (UITemplates.Menus): false = the open was refused
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

--------------------------------------------------------------------- the wheel + revives
-- Under the crate: the Daily Wheel (its spins / the next free one's countdown; SPIN opens the
-- wheel's own window - SpinWheelWindow.OpenWheel), "You have N revives" (ReviveCredits /
-- InfiniteRevives, the server's), and the three revive offers. Revives aren't random items: their
-- purchase opens straight away, and the server saves them (DeathManager) - for the next fall.
local Config      = require(RS:WaitForChild("ScooterSystem"):WaitForChild("Shared"):WaitForChild("Config"))
local wheelCard   = content:WaitForChild("Wheel")
local wheelTimer  = wheelCard:WaitForChild("Timer")
local wheelSpot   = wheelCard:WaitForChild("WheelSpot")
local countLbl    = content:WaitForChild("ReviveCount"):WaitForChild("Label")
local reviveRow   = content:WaitForChild("Revives")
local wheelGui    = playerGui:WaitForChild("SpinWheelWindow")
local wheelDisc
task.spawn(function()
	-- a small copy of the real wheel (its slots already dressed), turning slowly
	local src = wheelGui:WaitForChild("Window"):WaitForChild("Wheel")
	task.wait(1)
	local copy = src:Clone()
	copy.AnchorPoint, copy.Position, copy.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1)
	copy.Parent = wheelSpot
	wheelDisc = copy:FindFirstChild("Spin")
	fader:trackTree(copy)
end)
local spinBtn = Motion.button(wheelCard:WaitForChild("Spin"), {
	fader = fader, sfx = sfx, hover = 1.04, press = 0.95, lift = 2, sink = 4,
	onActivate = function()
		if not isOpen then return end
		local ev = wheelGui:FindFirstChild("OpenWheel")
		if ev then ev:Fire() end              -- the wheel's window replaces this one (UITemplates.Menus)
	end,
})
table.insert(buys, spinBtn)
local OFFER_PRODUCT = { One = Config.ReviveProductId, Five = Config.ReviveFiveProductId, Infinite = Config.ReviveInfiniteProductId }
local infiniteFace
for name, pid in pairs(OFFER_PRODUCT) do
	local holder = reviveRow:WaitForChild(name):WaitForChild("BuyRevive")
	if name == "Infinite" then infiniteFace = holder end
	local b
	b = Motion.button(holder, {
		fader = fader, sfx = sfx, hover = 1.04, press = 0.95, lift = 2, sink = 4,
		onActivate = function()
			if not isOpen then return end
			if name == "Infinite" and player:GetAttribute("InfiniteRevives") == true then b:shake() return end
			if not pid or pid == 0 then b:shake() return end
			pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, player, pid)
		end,
	})
	table.insert(buys, b)
	-- the real price once loaded
	task.spawn(function()
		local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, pid, Enum.InfoType.Product)
		if ok and info and info.PriceInRobux then holder:SetAttribute("PriceText", tostring(info.PriceInRobux)) end
	end)
end
local function clockText(s)
	s = math.max(math.ceil(s), 0)
	if s >= 3600 then return string.format("%d:%02d:%02d", s // 3600, s % 3600 // 60, s % 60) end
	return string.format("%d:%02d", s // 60, s % 60)
end
local function stepRevives(dt)
	-- the wheel: spins to use, or when the next free one comes
	local balance, freeAt = player:GetAttribute("SpinBalance"), player:GetAttribute("SpinFreeAt")
	local t
	if type(balance) == "number" and balance > 0 then
		t = balance == 1 and "You have 1 spin!" or ("You have " .. balance .. " spins!")
	elseif type(freeAt) == "number" then
		t = "Free spin in " .. clockText(freeAt - workspace:GetServerTimeNow())
	else
		t = "..."
	end
	if wheelTimer.Text ~= t then wheelTimer.Text = t end
	if wheelDisc then wheelDisc.Rotation = (wheelDisc.Rotation + 12 * dt) % 360 end
	-- revives
	local inf = player:GetAttribute("InfiniteRevives") == true
	local n = tonumber(player:GetAttribute("ReviveCredits")) or 0
	local c = inf and "You have infinite revives!" or (n == 1 and "You have 1 revive" or ("You have " .. n .. " revives"))
	if countLbl.Text ~= c then countLbl.Text = c end
	if infiniteFace then
		local label = infiniteFace.Face.Label
		local want = inf and "OWNED" or (infiniteFace:GetAttribute("PriceText") or "139")
		if label.Text ~= want then
			label.Text = want
			local robux = infiniteFace.Face:FindFirstChild("Robux")
			if robux then robux.Visible = not inf end
		end
	end
	for _, name in ipairs({ "One", "Five" }) do
		local h = reviveRow[name].BuyRevive
		local p = h:GetAttribute("PriceText")
		if p and h.Face.Label.Text ~= p then h.Face.Label.Text = p end
	end
end

-- the Dim only darkens: clicks outside the window go through it (UITemplates.Menus)

UserInputService.InputBegan:Connect(function(input)
	if isOpen and input.KeyCode == Enum.KeyCode.ButtonB then
		if giftPage and giftPage.open then showList() else Menu.Close() end
	end
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

	for _, b in ipairs(buys) do b:update(dt) end
	stepCrate(dt)
	stepPrizes()
	stepRevives(dt)
	if giftBtn then giftBtn:update(dt) end
	if giftPage then giftPage:update(dt) end

	if not isOpen and winA < 0.01 then
		winA = 0
		fader:set(0, {})
		window.Visible, dim.Visible = false, false
	end
end)

return Menu
