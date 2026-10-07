--=====================================================================
-- Menu   (ScootersUI)
--
-- The Scooters window (StarterGui.ScootersWindow), made from the house panel
-- (UITemplates.PanelWindow) and moving like Settings (UITemplates.Menus): it drops
-- in from above, fades as one and dims the world behind; only the red X, B, the
-- Scooters tile again, or another menu opening close it.
-- Everything it shows comes from the server (Remotes.GetScooters). SELECT only
-- asks (Remotes.EquipScooter), and the server's answer is what gets drawn.
-- JOIN GROUP opens Roblox's join prompt; if it says they joined, the scooter is
-- asked for again and the server checks the group for itself.
-- R$ opens Roblox's purchase prompt for the scooter's Developer Product; the server
-- grants it from the receipt, and the card is asked for until that has landed.
-- A group reward (the Ice Scooter): its card and the lobby podium both use
-- Menu.RewardAction, which only asks (Remotes.RewardAction) and opens Roblox's join
-- prompt when the server says to. Neither can grant it: the server does that by
-- itself when a session starts (ScooterSelection.grantReward).
-- A Robux skin's gift button opens the Gift page in this window, in place of the cards
-- (ScootersUI.Gift): the players here, each with GIFT. Its "<" (or B) comes back to the
-- cards; once a gift has been delivered the window closes (the message says so).
-- Built once: opening and closing never adds cards, connections or loops.
--=====================================================================

local RunService       = game:GetService("RunService")
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService       = game:GetService("GuiService")
local GroupService     = game:GetService("GroupService")
local MarketplaceService = game:GetService("MarketplaceService")
local RS               = game:GetService("ReplicatedStorage")

local selector     = RS:WaitForChild("CheckpointSelector")
local Motion       = require(selector:WaitForChild("Motion"))
local Sfx          = require(selector:WaitForChild("Sfx"))
local Cards        = require(script.Parent:WaitForChild("Cards"))
local Gift         = require(script.Parent:WaitForChild("Gift"))
local Scooters     = require(RS:WaitForChild("ScooterSystem"):WaitForChild("Shared"):WaitForChild("Scooters"))
local Remotes      = RS:WaitForChild("ScooterSystem"):WaitForChild("Remotes")
local GetScooters  = Remotes:WaitForChild("GetScooters")
local EquipScooter = Remotes:WaitForChild("EquipScooter")
local RewardAction = Remotes:WaitForChild("RewardAction")
local Menus        = require(RS:WaitForChild("UITemplates"):WaitForChild("Menus"))

local playerGui  = Players.LocalPlayer:WaitForChild("PlayerGui")
local winGui     = playerGui:WaitForChild("ScootersWindow")
local dim        = winGui:WaitForChild("Dim")
local window     = winGui:WaitForChild("Window")
local winScale   = window:WaitForChild("Scale")
local panel      = window:WaitForChild("Panel")
local panelSweep = panel:WaitForChild("Sweep")
local grid       = panel:WaitForChild("Content")
local closeBtn   = panel:WaitForChild("CloseButton")
local title      = panel:WaitForChild("Title")
local titleEdge  = title:WaitForChild("UIStroke")
local settingsWin = playerGui:WaitForChild("SettingsWindow"):WaitForChild("Window")
local closeScale = closeBtn:WaitForChild("Scale")
local joinHint   = panel:WaitForChild("JoinHint")   -- "Join Group! Like game!" (the Ice scooter's unlock)
local JOIN_TILT  = joinHint.Rotation
local cross      = closeBtn:WaitForChild("Cross")
local badges     = grid:WaitForChild("Badges")   -- the FREE tag over a card; it scrolls with the grid

local DIM_MAX = 0.25        -- how far the world darkens, as Settings
local HINT_FADE = 24        -- px of scrolling over which the FREE tag and Join Group message fade out
local HINT_FOR  = "Ice"     -- the scooter they advertise: once it's theirs they go away
local hintShow  = 0         -- shown only once the server says it isn't theirs (no flash for owners)

local sfx   = Sfx.new(winGui:WaitForChild("Sfx"))
-- The FREE tag and the Join Group message are tilted, and a ScrollingFrame can't clip
-- tilted things (the message isn't in the grid at all), so as the grid scrolls they
-- fade out together: the "hint" group.
local function groupOf(obj)
	if obj == joinHint or obj:IsDescendantOf(joinHint) then return "join" end
	if obj:IsDescendantOf(badges) then return "hint" end
	return nil
end
local fader = Motion.fader(groupOf)
local cards = Cards.new(grid, winGui:WaitForChild("Templates"), fader, sfx)

-- The cards move about (Cards:arrange), so the FREE tag and the Join Group message follow
-- the Ice card. The tag sits on a placeholder in Badges.Layer, a copy of the grid's
-- layout: the placeholder takes the Ice card's slot, with blank spacers before it. The
-- message sits above the grid, built over the 2nd card: it moves along the top row with
-- the card, and only shows while the card is in the top row (lower down it would cover
-- the cards above).
local badgeLayer = badges:WaitForChild("Layer")
local badgeHome  = badgeLayer:WaitForChild(HINT_FOR)
local badgeFirst = badgeLayer:FindFirstChild("Red")   -- the placeholder for slot 1
local HINT_SLOT  = badgeHome.LayoutOrder             -- the slot both were built over (2)
local JOIN_POS   = joinHint.Position
local cellLayout = grid:FindFirstChildOfClass("UIGridLayout")
local COL_STEP   = cellLayout.CellSize.X.Offset + cellLayout.CellPadding.X.Offset
local spacers    = {}
local hintTopRow = true
local function placeHint()
	local slot = cards:slot(HINT_FOR) or HINT_SLOT
	if badgeFirst then badgeFirst.Visible = slot > 1 end
	for i = 2, slot - 1 do
		if not spacers[i] then
			local f = Instance.new("Frame")
			f.Name = "Spacer"
			f.BackgroundTransparency = 1
			f.LayoutOrder = i
			f.Parent = badgeLayer
			spacers[i] = f
		end
	end
	for i, f in pairs(spacers) do f.Visible = i < slot end
	badgeHome.LayoutOrder = slot
	local cols = cards.columns
	hintTopRow = slot <= cols
	local col = (slot - 1) % cols + 1
	joinHint.Position = JOIN_POS + UDim2.fromOffset((col - HINT_SLOT) * COL_STEP, 0)
end

local Menu = {}
local TITLE_TEXT = title.Text
local showCards, fetch            -- below
-- the Gift page (built before the window's fade is recorded, so it fades with it)
local gift = Gift.new({
	panel = panel, fader = fader, sfx = sfx,
	nameStyle = Cards.NameStyle,
	priceOf = function(id) return cards.price[id] end,
	onBack = function() showCards() end,
	onSent = function() Menu.Close() end,                       -- delivered: the window closes
	onReceived = function() if Menu.IsOpen() then task.spawn(fetch) end end,   -- a new skin to show
})
fader:trackTree(window)

function showCards()
	gift:hide()
	grid.Visible = true
	joinHint.Visible = true
	title.Text = TITLE_TEXT
end
local function showGift(id)
	if not gift:show(id) then return end
	grid.Visible = false
	joinHint.Visible = false
	title.Text = "Gift"
end
local slide = Menus.new(window, { dim = dim, onReplace = function() Menu.Close() end })

local isOpen = false
local winA = 0

-- On a touch screen the red X gets a bigger, invisible tap area, so it stays easy
-- to hit on a small window. It grows up and out, past the window's corner, where
-- there is nothing else to tap - never down over the top-right card. It looks
-- exactly the same; PC never has it.
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

-- The cards' texts (names, button labels) keep a smallest size meant for PC. On a
-- small touch window that size would no longer fit ("EQUIPPED" showed as "EQUIPP"),
-- so there they shrink to fit their box instead; PC keeps its own sizes.
local textMins = {}
for _, c in ipairs(grid:GetDescendants()) do
	if c:IsA("UITextSizeConstraint") then textMins[c] = c.MinTextSize end
end

local cCur, cVel, crossRot = 1, 0, 0
local closeHover, closePressed = false, false
local state            -- the last server-confirmed { Selected = id, Unlocked = { [id] = true } }
local pendingId        -- an equip on its way to the server
local fetchToken = 0

--------------------------------------------------------------------- responsive (as Settings)
local BASE_W = window.Size.X.Offset
local BASE_H = window.Size.Y.Offset + 30       -- the title rides above the panel
local TITLE_SIZE, TITLE_EDGE = title.TextSize, titleEdge.Thickness
-- how big the window sits on screen: about 830 x 490 on a 1080p screen (~43% of
-- its width), the size the owners picked from a reference; scales with the screen
local WINDOW_SIZE = 0.565
-- Touch screens (phones and tablets) also keep the whole window - title and close
-- button included - inside the screen under Roblox's top bar, with this much room
-- all round, and centre it in that space. PC never uses these.
local TOUCH_MARGIN_X = 0.08   -- of the screen's width, each side (clears a notch)
local TOUCH_MARGIN_Y = 0.10   -- of the height under the top bar, above and below
local TOUCH_TITLE_MAX = 1.6   -- the title grows with the Settings title at most this much
                              -- over the window's own scale (about PC's own ratio)
local BASE_HOME = slide.home  -- where the window sits on PC: the middle of the screen
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
	-- the title text matches the Settings title on screen: Settings grows to 1.3x
	-- (SettingsUI) while this bigger window stops at 1.15x, so the text makes up
	-- the difference (the window itself stays as it is)
	local sw = settingsWin.Size
	local settingsScale = math.min(math.clamp(raw, 0.75, 1.3), vp.X * 0.94 / sw.X.Offset, vp.Y * 0.9 / sw.Y.Offset)
	local k = settingsScale / rootScale
	if touch then k = math.min(k, TOUCH_TITLE_MAX) end   -- in step with the smaller window
	title.TextSize = math.round(TITLE_SIZE * k)
	titleEdge.Thickness = TITLE_EDGE * k
	closeHit.Visible = touch
	for c, min in pairs(textMins) do c.MinTextSize = touch and 1 or min end
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

--------------------------------------------------------------------- server state
local function apply(newState)
	if type(newState) == "table" and type(newState.Selected) == "string" then state = newState end
	cards:render(state, pendingId)
	placeHint()
end

function fetch()
	fetchToken += 1
	local mine = fetchToken
	local ok, result = pcall(GetScooters.InvokeServer, GetScooters)
	if mine == fetchToken and ok then apply(result) end
end

local function equip(id, joinPrompt)
	local ok, granted, newState = pcall(EquipScooter.InvokeServer, EquipScooter, id, joinPrompt)
	if ok then return granted, newState end
	return false, nil
end

-- JOIN GROUP: Roblox's own join prompt. If it says they joined (or already were in),
-- the scooter is asked for again. The server normally agrees at once, but Roblox can
-- take up to a minute to report a new member, so it keeps asking for a while.
local JOIN_RETRY = { 1, 1, 2, 2, 3, 4, 5, 6, 8, 10, 12, 12 }   -- seconds between asks (~1 min)
local function joinThenEquip(id, groupId)
	local ok, status = pcall(GroupService.PromptJoinAsync, GroupService, groupId)
	if not ok then warn("[Scooters] join prompt failed:", status) end
	if not ok or (status ~= Enum.GroupMembershipStatus.Joined
		and status ~= Enum.GroupMembershipStatus.AlreadyMember) then
		return false, nil
	end
	local granted, newState = equip(id, status.Name)
	for _, gap in ipairs(JOIN_RETRY) do
		if granted then break end
		task.wait(gap)
		granted, newState = equip(id, status.Name)
	end
	return granted, newState
end

-- A group reward (the Ice Scooter), from its card or the podium: ask the server
-- where the player stands (ScooterSelection.RewardAction, which can't grant). "join"
-- opens Roblox's join prompt, then asks again with its answer (Roblox can take a
-- while to report a new member). "owned" / "rejoin" the server shows its red notice.
local acting = false
local function ask(id, joinPrompt)
	local ok, result, newState = pcall(RewardAction.InvokeServer, RewardAction, id, joinPrompt)
	if not ok then return nil end
	apply(newState)
	return result
end
local function rewardFlow(id)
	if acting then return nil end
	acting = true
	local result = ask(id)
	if result == "join" then
		local def = Scooters.Get(id)
		local ok, status = pcall(GroupService.PromptJoinAsync, GroupService, def.Unlock.GroupId)
		if not ok then warn("[Scooters] join prompt failed:", status) end
		if ok and (status == Enum.GroupMembershipStatus.Joined or status == Enum.GroupMembershipStatus.AlreadyMember) then
			result = ask(id, status.Name)
			for _, gap in ipairs(JOIN_RETRY) do
				if result ~= "join" and result ~= "busy" then break end
				task.wait(gap)
				result = ask(id, status.Name)
			end
		end
	end
	acting = false
	return result
end

-- R$: Roblox's purchase prompt. The receipt is granted on the server (DonationHandler ->
-- ScooterSelection.GrantProduct), a moment after the prompt, so the scooter is asked
-- for every BUY_POLL seconds until it is theirs, the prompt says no sale, or BUY_WAIT.
local BUY_WAIT, BUY_POLL = 60, 1.5
local function buyThenEquip(id, productId)
	local player = Players.LocalPlayer
	local closed, bought = false, false
	local conn = MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, pid, purchased)
		if userId == player.UserId and pid == productId then closed, bought = true, purchased end
	end)
	local ok, err = pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, player, productId)
	if not ok then
		conn:Disconnect()
		warn("[Scooters] purchase prompt failed:", err)
		return false, nil
	end
	local granted, newState = false, nil
	local t0 = os.clock()
	while os.clock() - t0 < BUY_WAIT do
		task.wait(BUY_POLL)
		if closed and not bought then break end        -- closed without buying
		granted, newState = equip(id)
		if granted then break end
	end
	conn:Disconnect()
	return granted, newState
end

-- the real Robux prices, asked once (the registry's Price shows until then)
local pricesAsked = false
local function fetchPrices()
	if pricesAsked then return end
	pricesAsked = true
	for _, def in ipairs(Scooters.List) do
		local u = def.Unlock
		if u and u.Type == "Product" and u.ProductId then
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, u.ProductId, Enum.InfoType.Product)
			if ok and info and info.PriceInRobux then
				cards:setPrice(def.Id, info.PriceInRobux)
				cards:render(state, pendingId)   -- each price shows as soon as it arrives
			end
		end
	end
	cards:render(state, pendingId)
end

-- a card was clicked / tapped / pressed with A
cards.onPick = function(id)
	if not isOpen or pendingId or not state then return end
	if state.Selected == id then return end
	local def = Scooters.Get(id)
	local unlock = def and def.Unlock
	local unlocked = state.Unlocked and state.Unlocked[id]
	local groupId = not unlocked and unlock and unlock.Type == "Group" and unlock.GroupId
	local productId = not unlocked and unlock and unlock.Type == "Product" and unlock.ProductId
	-- a group reward, or a LIMITED Daily Rewards skin (the server says where it comes from)
	local reward = not unlocked and unlock and (unlock.Type == "GroupReward" or unlock.Type == "DailyReward" or unlock.Type == "Limited")
	if not unlocked and not groupId and not productId and not reward then
		if unlock and unlock.Type == "Product" then
			warn("[Scooters] " .. id .. " has no ProductId yet (ReplicatedStorage.ScooterSystem.Shared.Scooters)")
		end
		return                                         -- LOCKED does nothing
	end
	pendingId = id
	fetchToken += 1                    -- an older GetScooters answer must not draw over this one
	cards:render(state, pendingId)
	task.spawn(function()
		local granted, newState
		if reward then
			rewardFlow(id)                                 -- join / rejoin: never grants or equips
		elseif groupId then
			granted, newState = joinThenEquip(id, groupId)
		elseif productId then
			granted, newState = buyThenEquip(id, productId)
		else
			granted, newState = equip(id)
		end
		pendingId = nil
		apply(newState)
		if granted and state and state.Selected == id then
			-- no equip sound (the owners found it too loud): the card's own click is enough
			cards:celebrate(id)
		end
	end)
end

-- a card's gift button: the Gift page for that skin
cards.onGift = function(id)
	if not isOpen or gift.open then return end
	showGift(id)
end

--------------------------------------------------------------------- open / close
-- the lobby podium's prompt (ScootersUI): exactly what the card does
function Menu.RewardAction(id)
	local result = rewardFlow(id)
	-- a Robux skin's shop stand: the same purchase as its card's pill (one at a time)
	if result == "buy" and not acting and not pendingId then
		local def = Scooters.Get(id)
		local productId = def and def.Unlock and def.Unlock.ProductId
		if productId then
			acting = true
			local granted, newState = buyThenEquip(id, productId)
			acting = false
			apply(newState)
			if granted and state and state.Selected == id then cards:celebrate(id) end
		end
	end
	return result
end

function Menu.IsOpen()
	return isOpen
end

function Menu.Open()
	if isOpen then return end
	if not slide:open() then return false end  -- a blocking screen is up: the tile shakes and says why
	isOpen = true
	if gift.open then showCards() end      -- it always opens on the cards
	updateScale()
	if winA < 0.05 then
		task.delay(0.24, function() if isOpen then Motion.sweep(panelSweep, 0.75) end end)
	end
	-- no open / close whoosh here: the owners found it annoying (the tile's own click stays)
	window.Visible, dim.Visible = true, true
	apply(nil)                            -- what we already know, straight away
	task.spawn(fetch)                     -- then the server's word
	task.spawn(fetchPrices)
	if Motion.isGamepad() then GuiService.SelectedObject = cards:focus(state) end
	return true
end

function Menu.Close()
	if not isOpen then return end
	isOpen = false
	slide:close()
	closeHover, closePressed = false, false
	local sel = GuiService.SelectedObject
	if sel and sel:IsDescendantOf(winGui) then GuiService.SelectedObject = nil end
	-- the frame loop hides the window once it has faded out
end

-- what the Scooters tile does (UITemplates.Menus): false = the open was refused
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
	if isOpen and input.KeyCode == Enum.KeyCode.ButtonB then
		if gift.open then showCards() else Menu.Close() end   -- B on the Gift page: back to the cards
	end
end)

--------------------------------------------------------------------- frame loop
RunService.RenderStepped:Connect(function(dt)
	if not window.Visible then return end
	dt = math.min(dt, 1 / 30)

	-- slides in from above and back up (UITemplates.Menus); the fade and the dim follow it
	winScale.Scale = rootScale
	winA = slide:alpha()
	local owns = state and state.Unlocked and state.Unlocked[HINT_FOR] == true
	hintShow = Motion.approach(hintShow, (state and not owns) and 1 or 0, 10, dt)
	local hintA = hintShow * math.clamp(1 - grid.CanvasPosition.Y / HINT_FADE, 0, 1)
	fader:set(winA, { hint = hintA, join = hintTopRow and hintA or 0 })
	dim.BackgroundTransparency = 1 - DIM_MAX * winA

	-- close button: a spring pop, and the cross turns a quarter on hover (as Settings)
	cCur, cVel = Motion.spring(cCur, cVel, closePressed and 0.88 or (closeHover and 1.1 or 1), 300, 18, dt)
	closeScale.Scale = math.max(cCur, 0.01)
	crossRot = Motion.approach(crossRot, closeHover and 90 or 0, 12, dt)
	cross.Rotation = crossRot

	-- the green Join Group message sways a little (rotation only: scaling text shimmers)
	joinHint.Rotation = JOIN_TILT + math.sin(os.clock() * 2.2) * 1.8

	cards:update(dt, isOpen and not gift.open)
	gift:update(dt)

	if not isOpen and winA < 0.01 then
		winA = 0
		fader:set(0, {})
		window.Visible, dim.Visible = false, false
		if gift.open then showCards() end
	end
end)

return Menu
