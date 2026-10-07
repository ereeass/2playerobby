--=====================================================================
-- DeathClient
--
-- The death popup of a scooter run. The server (ServerScriptService.ScooterSystem.
-- DeathManager) owns everything that matters: when the popup is up, when the
-- countdown ends and the SKIP votes. This only draws them:
--   * the house panel, dropping in and lifting out like every menu
--     (UITemplates.Menus) - it is a blocking screen, so no menu opens over it
--   * danger that builds with the countdown: a red tint over the world and red
--     screen edges that start faint and deepen, and a heartbeat that quickens
--     and grows louder - all from the same server end time, so both riders see
--     and hear the same thing. All of it goes the moment the popup does.
--   * the countdown in hundredths (10.00 ... 0.00), read from that end time
--   * the camera frozen where it was the moment the rider went in: it does not
--     follow the dead body down, so the death plays out below it. No camera
--     control reaches Roblox meanwhile: its camera input (CameraContext: mouse
--     look and right-drag, wheel, touch, gamepad, Shift-lock) is switched off,
--     the camera keys are swallowed and the touch controls hidden - only the
--     popup's buttons answer. It stays put until the player is back (respawned in the
--     lobby), then Roblox's camera and its controls come back. (Position and
--     rotation only: the scooter's speed zoom still eases the field of view
--     back to normal, ScooterFx.)
--   * SKIP (n/2) and REVIVE: the checkpoint picker's buttons and sounds. REVIVE only asks
--     the server (Remotes.ReviveRequest): it opens the purchase, holds the countdown, and
--     revives on Roblox's receipt. While a purchase is open the countdown stands still and
--     the partner sees "Your friend is buying a revive..." on the line between the
--     countdown and the buttons; "Reviving..." while it is done. REVIVE says FREE REVIVE
--     when they have a revive saved from a purchase that couldn't be used, and its red
--     count (the shared UITemplates.CountBadge, as on Skip Stage) says how many.
--
--   * OTHER OPTIONS: 5x REVIVES and INFINITE REVIVES, two tiles under the box (REVIVE's own
--     button, green and orange), on a death with no revenge only - the revenge section takes
--     that place - and not for someone whose revives are infinite already (their REVIVE says
--     INFINITE REVIVE). They only ask the server (Remotes.ReviveRequest "five" / "infinite"),
--     which opens the purchase, holds the countdown and rewards on Roblox's receipt
--     (DeathManager). The price under each is the product's own; "..." while it is bought.
--   * EXPLODE BACK (REVENGE): a section under the box, only when another riding duo exploded
--     this one (the server's state carries Revenge: who, their avatar, and its status). It asks
--     the server (Remotes.RevengeRequest), which locks it, opens the purchase and holds the
--     countdown. While the revenge plays the popup slides away and the camera watches the
--     attackers' scooter blow up (ExplodeTimeline's watcher camera); then the popup is back.
--
-- While the player is queued or riding, Roblox's Reset Character is switched off
-- (the run's own death decides); back in the lobby it comes back.
--=====================================================================

local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local Lighting           = game:GetService("Lighting")
local StarterGui         = game:GetService("StarterGui")
local UserInputService   = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local MarketplaceService = game:GetService("MarketplaceService")
local RS                 = game:GetService("ReplicatedStorage")

local selector = RS:WaitForChild("CheckpointSelector")
local Motion   = require(selector:WaitForChild("Motion"))
local Sfx      = require(selector:WaitForChild("Sfx"))
local Menus    = require(RS:WaitForChild("UITemplates"):WaitForChild("Menus"))
local CountBadge = require(RS:WaitForChild("UITemplates"):WaitForChild("CountBadge"))
local HudSync  = require(RS:WaitForChild("HudSync"))
local Root     = RS:WaitForChild("ScooterSystem")
local Remotes  = Root:WaitForChild("Remotes")
local Config   = require(Root:WaitForChild("Shared"):WaitForChild("Config"))
local ControlHolds = require(Root:WaitForChild("ControlHolds"))

local player     = Players.LocalPlayer
local gui        = script.Parent
local window     = gui:WaitForChild("Window")
local panelSweep = window:WaitForChild("Panel"):WaitForChild("Sweep")
local count      = window:WaitForChild("Count")
local countScale = count:WaitForChild("Scale")
local actions    = window:WaitForChild("Actions")
local skipHolder = actions:WaitForChild("SkipButton")
local skipLabel  = skipHolder:WaitForChild("Face"):WaitForChild("Label")
local reviveHolder = actions:WaitForChild("ReviveButton")
local reviveLabel  = reviveHolder:WaitForChild("Face"):WaitForChild("Label")
local status     = window:WaitForChild("Status")
local heartbeat  = gui:WaitForChild("Heartbeat")
local steady     = heartbeat:WaitForChild("Steady")
local edges      = gui:WaitForChild("Vignette"):GetChildren()
local vignette   = gui.Vignette

--------------------------------------------------------------------- revenge section (built here,
-- before the fader learns the window, so it fades and slides with the box)
local ExplodeT      = require(RS:WaitForChild("TrollFx"):WaitForChild("ExplodeTimeline"))
local REVENGE_IMAGE = "rbxassetid://133513857622474"   -- the Explode troll's own picture
local FONT          = Font.new("rbxasset://fonts/families/FredokaOne.json")

local revenge = Instance.new("Frame")
revenge.Name = "Revenge"
revenge.BackgroundTransparency = 1
revenge.AnchorPoint = Vector2.new(0.5, 0)
revenge.Position = UDim2.new(0.5, 0, 1, 12)
revenge.Size = UDim2.new(1, 0, 0, 178)
revenge.Visible = false
revenge.Parent = window

local revIcons = Instance.new("Frame")
revIcons.Name = "Icons"
revIcons.BackgroundTransparency = 1
revIcons.AnchorPoint = Vector2.new(0.5, 0)
revIcons.Position = UDim2.new(0.5, 0, 0, 10)
revIcons.Size = UDim2.fromOffset(160, 70)
revIcons.ZIndex = 3
revIcons.Parent = revenge
-- a cartoon burst behind: the explosion picture, big and soft
local revBurst = Instance.new("ImageLabel")
revBurst.Name = "Burst"
revBurst.BackgroundTransparency = 1
revBurst.Image = REVENGE_IMAGE
revBurst.ImageTransparency = 0.55
revBurst.AnchorPoint = Vector2.new(0.5, 0.5)
revBurst.Position = UDim2.fromScale(0.5, 0.5)
revBurst.Size = UDim2.fromOffset(120, 120)
revBurst.ZIndex = 3
revBurst.Parent = revIcons
-- the explode icon
local revIcon = Instance.new("ImageLabel")
revIcon.Name = "Icon"
revIcon.BackgroundTransparency = 1
revIcon.Image = REVENGE_IMAGE
revIcon.AnchorPoint = Vector2.new(0.5, 0.5)
revIcon.Position = UDim2.new(0.5, -38, 0.5, 0)
revIcon.Size = UDim2.fromOffset(62, 62)
revIcon.ZIndex = 5
revIcon.Parent = revIcons
-- the avatar of whoever exploded them
local revAvatar = Instance.new("ImageLabel")
revAvatar.Name = "Avatar"
revAvatar.BackgroundColor3 = Color3.fromRGB(40, 12, 14)
revAvatar.BackgroundTransparency = 0.1
revAvatar.AnchorPoint = Vector2.new(0.5, 0.5)
revAvatar.Position = UDim2.new(0.5, 38, 0.5, 0)
revAvatar.Size = UDim2.fromOffset(62, 62)
revAvatar.ZIndex = 5
revAvatar.Parent = revIcons
Instance.new("UICorner", revAvatar).CornerRadius = UDim.new(1, 0)
local revAvatarEdge = Instance.new("UIStroke")
revAvatarEdge.Color = Color3.fromRGB(255, 80, 80)
revAvatarEdge.Thickness = 3
revAvatarEdge.Parent = revAvatar

-- SKIP's own red button, copied, so it is exactly the house style
local revHolder = skipHolder:Clone()
revHolder.Name = "RevengeButton"
revHolder.AnchorPoint = Vector2.new(0.5, 0)
revHolder.Position = UDim2.new(0.5, 0, 0, 88)
revHolder.Size = UDim2.new(1, -48, 0, 50)
revHolder.Parent = revenge
local revFace  = revHolder:WaitForChild("Face")
local revLabel = revFace:WaitForChild("Label")
revLabel.Text = "EXPLODE BACK (REVENGE)"
local revGrad  = revFace:FindFirstChildOfClass("UIGradient")
local revLip   = revHolder:WaitForChild("Lip")
local REV_RED_GRAD, REV_RED_LIP = revGrad and revGrad.Color, revLip.BackgroundColor3
local REV_GREY_GRAD = ColorSequence.new(Color3.fromRGB(150, 150, 156), Color3.fromRGB(104, 104, 110))
local REV_GREY_LIP  = Color3.fromRGB(64, 64, 70)

local revName = Instance.new("TextLabel")
revName.Name = "ByLine"
revName.BackgroundTransparency = 1
revName.FontFace = FONT
revName.TextColor3 = Color3.new(1, 1, 1)
revName.TextScaled = true
revName.AnchorPoint = Vector2.new(0.5, 0)
revName.Position = UDim2.new(0.5, 0, 0, 144)
revName.Size = UDim2.new(1, -40, 0, 24)
revName.Text = "Someone exploded you!"
revName.ZIndex = 4
revName.Parent = revenge
local revNameEdge = Instance.new("UIStroke")
revNameEdge.Color = Color3.fromRGB(40, 8, 10)
revNameEdge.Thickness = 2
revNameEdge.Parent = revName

--------------------------------------------------------------------- the revive offers (built here
-- too, so they fade and slide with the box): 5x REVIVES and INFINITE REVIVES
local ROBUX_ICON = "rbxassetid://102636344783074"   -- the Robux mark the shop stands use
local OFFER = 96                                      -- each tile, square
local OFFER_GAP = 28                                  -- between the two

local offers = Instance.new("Frame")
offers.Name = "Offers"
offers.BackgroundTransparency = 1
offers.AnchorPoint = Vector2.new(0.5, 0)
offers.Position = UDim2.new(0.5, 0, 1, 12)              -- where the revenge section goes (never both)
offers.Size = UDim2.new(1, 0, 0, 32 + OFFER + 36)
offers.Visible = false
offers.Parent = window

local offersTitle = Instance.new("TextLabel")
offersTitle.Name = "Title"
offersTitle.BackgroundTransparency = 1
offersTitle.FontFace = FONT
offersTitle.Text = "Other Options"
offersTitle.TextColor3 = Color3.new(1, 1, 1)
offersTitle.TextScaled = true
offersTitle.AnchorPoint = Vector2.new(0.5, 0)
offersTitle.Position = UDim2.new(0.5, 0, 0, 0)
offersTitle.Size = UDim2.new(1, -40, 0, 26)
offersTitle.ZIndex = 4
offersTitle.Parent = offers
local offersTitleEdge = Instance.new("UIStroke")
offersTitleEdge.Color = Color3.fromRGB(20, 6, 8)
offersTitleEdge.Thickness = 2.5
offersTitleEdge.Parent = offersTitle

-- one tile: REVIVE's own button (before its count badge goes on), its picture inside and its
-- price under it; `orange` recolours it (INFINITE)
local function buildOffer(name, side, image, orange, rect)
	local holder = reviveHolder:Clone()
	holder.Name = name
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, side * (OFFER + OFFER_GAP) / 2, 0, 32)
	holder.Size = UDim2.fromOffset(OFFER, OFFER)
	holder.Parent = offers
	local face = holder:WaitForChild("Face")
	local label = face:WaitForChild("Label")
	label.Text = ""
	if orange then
		local grad = face:FindFirstChildOfClass("UIGradient")
		if grad then grad.Color = ColorSequence.new(Color3.fromRGB(255, 200, 84), Color3.fromRGB(240, 138, 26)) end
		local ink = Color3.fromRGB(96, 42, 4)
		holder.Lip.BackgroundColor3 = Color3.fromRGB(168, 84, 12)
		for _, edge in ipairs(holder:GetDescendants()) do
			if edge:IsA("UIStroke") then edge.Color = ink end
		end
	end
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Image = image or ""
	icon.ScaleType = Enum.ScaleType.Fit
	if type(rect) == "table" and #rect == 3 then   -- just the artwork, so it sits in the middle
		icon.ImageRectOffset = Vector2.new(rect[1], rect[2])
		icon.ImageRectSize = Vector2.new(rect[3], rect[3])
	end
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(0.8, 0.8)
	icon.ZIndex = label.ZIndex
	icon.Parent = face
	label.ZIndex = label.ZIndex + 1             -- "..." over the picture while it is bought
	-- the price: the Robux mark and the amount, under the tile
	local price = Instance.new("Frame")
	price.Name = name .. "Price"
	price.BackgroundTransparency = 1
	price.AnchorPoint = Vector2.new(0.5, 0)
	price.Position = UDim2.new(0.5, side * (OFFER + OFFER_GAP) / 2, 0, 32 + OFFER + 8)
	price.Size = UDim2.fromOffset(OFFER + 24, 26)
	price.Parent = offers
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, 4)
	list.SortOrder = Enum.SortOrder.LayoutOrder   -- the Robux mark, then the amount
	list.Parent = price
	local mark = Instance.new("ImageLabel")
	mark.Name = "Robux"
	mark.BackgroundTransparency = 1
	mark.Image = ROBUX_ICON
	mark.Size = UDim2.fromOffset(22, 22)
	mark.LayoutOrder = 1
	mark.ZIndex = 4
	mark.Parent = price
	local amount = Instance.new("TextLabel")
	amount.Name = "Amount"
	amount.BackgroundTransparency = 1
	amount.FontFace = FONT
	amount.Text = ""
	amount.TextColor3 = Color3.new(1, 1, 1)
	amount.TextScaled = true
	amount.TextXAlignment = Enum.TextXAlignment.Left
	amount.AutomaticSize = Enum.AutomaticSize.X
	amount.Size = UDim2.fromOffset(0, 26)
	amount.LayoutOrder = 2
	amount.ZIndex = 4
	amount.Parent = price
	local amountEdge = Instance.new("UIStroke")
	amountEdge.Color = Color3.fromRGB(20, 6, 8)
	amountEdge.Thickness = 2
	amountEdge.Parent = amount
	return { holder = holder, face = face, label = label, icon = icon, amount = amount, mark = mark }
end
local offerList = {
	five     = buildOffer("FiveRevives", -1, Config.ReviveFiveImage, false, Config.ReviveFiveImageRect),
	infinite = buildOffer("InfiniteRevives", 1, Config.ReviveInfiniteImage, true, Config.ReviveInfiniteImageRect),
}
offerList.five.product = Config.ReviveFiveProductId or 0
offerList.infinite.product = Config.ReviveInfiniteProductId or 0

--------------------------------------------------------------------- consts
local SECONDS = Config.DeathSeconds or 10
-- Everything below goes from its CALM value (10 s left) to its PANIC value (0 s),
-- eased so the last seconds climb hardest.
local TINT_CALM,  TINT_PANIC  = Color3.fromRGB(255, 228, 228), Color3.fromRGB(255, 140, 140)
local DARK_CALM,  DARK_PANIC  = -0.03, -0.16    -- world brightness
local GREY_CALM,  GREY_PANIC  = -0.05, -0.30    -- world saturation
local EDGE_CALM,  EDGE_PANIC  = 0.12, 0.75      -- how solid the red screen edges are
local HEART_SLOW, HEART_FAST  = 0.8, 2.0        -- heartbeat speed (the pitch shift tops out at 2x)
local HEART_SOFT, HEART_LOUD  = 0.28, 0.55      -- heartbeat volume
local WHITE = Color3.new(1, 1, 1)

--------------------------------------------------------------------- pieces
local sfx   = Sfx.new(gui:WaitForChild("Sfx"))
-- REVIVE's red count of saved revives: on before the fader takes the window, so it fades with it
CountBadge.Attach(reviveHolder:WaitForChild("Face"), "ReviveCredits")
local fader = Motion.fader(nil)
fader:trackTree(window)
local slide = Menus.new(window, { exclusive = false, blocking = true })

-- the red tint: a colour correction on this player's view of the world only
local tint = Instance.new("ColorCorrectionEffect")
tint.Name = "DeathTint"
tint.Enabled = false
tint.Parent = Lighting

--------------------------------------------------------------------- state
local state            -- the server's last word: { EndsAt | Left, Skips, Needed, Voted, Buying, Reviving, Free }
local isOpen = false
local shownWhole       -- the whole second on screen (for the pop)
local statusText       -- the line under the countdown, or nil
local asked = 0        -- when REVIVE was last sent (until the server answers)

--------------------------------------------------------------------- camera
local CAM_STEP    = "DeathCameraHold"
local CAM_SINK    = "DeathCameraNoControls"   -- the cutscenes look for this (FinishCutscene)
local CAM_HOLD    = "DeathCamera"             -- its share of ScooterSystem.ControlHolds
local UNLOCK_WAIT = 5        -- the most it waits for the player to be back
local heldAt                 -- the CFrame the camera is held at while the popup is up
local holdToken = 0

-- Roblox's camera reads every camera control through its input context (the
-- PlayerModule's CameraContext: rotation by mouse / right-drag / touch / stick,
-- zoom by wheel / pinch, Shift-lock). ContextActionService cannot block those,
-- so the context itself is switched off while the camera is held, and the touch
-- controls hidden - shared with the cutscenes and windows (ScooterSystem.ControlHolds):
-- they come back once the last of them lets go.

-- Every camera control, swallowed before Roblox's camera sees it: nothing is
-- turned or zoomed now, and nothing is left zoomed for after. On-screen buttons
-- get their clicks and taps before this, so the popup still works.
local CAMERA_INPUTS = {
	Enum.UserInputType.MouseWheel, Enum.UserInputType.MouseButton2, Enum.UserInputType.MouseMovement,
	Enum.UserInputType.Touch,
	Enum.KeyCode.Thumbstick2, Enum.KeyCode.ButtonR3,
	Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.Up, Enum.KeyCode.Down,
	Enum.KeyCode.I, Enum.KeyCode.O, Enum.KeyCode.Comma, Enum.KeyCode.Period,
	Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift,
}
local function sinkInput() return Enum.ContextActionResult.Sink end

local function holdCamera()
	holdToken += 1                          -- a release still waiting is called off
	if heldAt then return end
	local cam = workspace.CurrentCamera
	heldAt = cam.CFrame
	cam.CameraType = Enum.CameraType.Scriptable   -- Roblox's camera stops following the body
	-- no camera input reaches Roblox's camera; the touch controls step aside
	ControlHolds.Hold(CAM_HOLD, { "CameraInput", "TouchControls" })
	ContextActionService:BindActionAtPriority(CAM_SINK, sinkInput, false,
		Enum.ContextActionPriority.High.Value + 100, table.unpack(CAMERA_INPUTS))
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default   -- out of Shift-lock
	-- and pinned every frame, last, after anything else that could touch the camera
	RunService:BindToRenderStep(CAM_STEP, Enum.RenderPriority.Last.Value, function()
		local c = workspace.CurrentCamera
		if c and heldAt then c.CFrame = heldAt end
	end)
end

-- the scooter this player is standing on (a revive puts them on a new one), if any
local function riderChassis()
	local ch   = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local weld = root and root:FindFirstChild("ScooterRiderWeld")
	return weld and weld.Part0
end

-- let go once the player is back: alive again (respawned in the lobby, or revived onto a new
-- scooter), or at the latest after UNLOCK_WAIT. After a revive the camera starts again behind
-- the scooter, looking down the road ahead, not where it was held over the old one.
local function releaseCamera(revived)
	if not heldAt then return end
	holdToken += 1
	local mine = holdToken
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < UNLOCK_WAIT do
			local ch  = player.Character
			local hum = ch and ch:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 and ch:FindFirstChild("HumanoidRootPart")
				and (not revived or riderChassis()) then break end
			task.wait(0.05)
		end
		if holdToken ~= mine then return end  -- a new popup took the camera meanwhile
		RunService:UnbindFromRenderStep(CAM_STEP)
		ContextActionService:UnbindAction(CAM_SINK)
		ControlHolds.Release(CAM_HOLD)             -- the controls as they were (unless still held)
		heldAt = nil
		local cam = workspace.CurrentCamera
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then cam.CameraSubject = hum end
		local chassis = revived and riderChassis()
		if chassis then
			local look = chassis.CFrame.LookVector
			local ahead = Vector3.new(look.X, 0, look.Z)
			ahead = ahead.Magnitude > 0.1 and ahead.Unit or Vector3.zAxis
			cam.CFrame = CFrame.lookAt(chassis.Position - ahead * 13 + Vector3.new(0, 6, 0),
				chassis.Position + ahead * 6 + Vector3.new(0, 2, 0))
		end
		cam.CameraType = Enum.CameraType.Custom
	end)
end
local danger  = 0      -- 0 with 10 s left .. 1 at 0; kept while the effects fade out
local present = 0      -- the effects fading in (open) and out (closed)

local skipBtn, reviveBtn
skipBtn = Motion.button(skipHolder, {
	fader = fader, sfx = sfx, hover = 1.04, press = 0.95, lift = 2, sink = 4,
	onActivate = function()
		if not state or state.Voted then skipBtn:shake() return end
		Remotes.DeathSkip:FireServer()     -- the server counts it (once) and tells both
	end,
})
reviveBtn = Motion.button(reviveHolder, {
	fader = fader, sfx = sfx, hover = 1.04, press = 0.95, lift = 2, sink = 4,
	onActivate = function()
		-- one purchase per pair at a time: while one is open (either rider's) or the revive is
		-- being done, or a moment after asking, it only shakes. The server checks it all again.
		if not state or state.Buying or state.Reviving or os.clock() - asked < 1.5
			or ((Config.ReviveProductId or 0) == 0 and not state.Free) then
			reviveBtn:shake()
			return
		end
		asked = os.clock()
		Remotes.ReviveRequest:FireServer()
	end,
})

-- the offers: one purchase per pair at a time, as REVIVE; a press while one is open, the revive
-- is being done, or a moment after asking only shakes. The server checks it all again.
local offerAsked = 0
for kind, o in pairs(offerList) do
	local btn
	btn = Motion.button(o.holder, {
		fader = fader, sfx = sfx, hover = 1.04, press = 0.95, lift = 2, sink = 4,
		onActivate = function()
			if not state or state.Buying or state.Reviving or state.Revenge or state.Infinite
				or os.clock() - offerAsked < 1.5 or o.product == 0 then
				btn:shake()
				return
			end
			offerAsked = os.clock()
			o.label.Text = "..."                 -- until the server answers
			Remotes.ReviveRequest:FireServer(kind)
		end,
	})
	o.btn = btn
end

-- each offer's real price, asked once
task.spawn(function()
	for _, o in pairs(offerList) do
		if o.product ~= 0 then
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, o.product, Enum.InfoType.Product)
			if ok and info and info.PriceInRobux then o.amount.Text = tostring(info.PriceInRobux) end
		end
	end
end)

-- the offers, from the server's state: only on a death with no revenge, and not for someone
-- whose revives are infinite already; dimmed while any purchase is open or the revive is done
local function applyOffers(s)
	local shown = s ~= nil and s.Revenge == nil and not s.Infinite
	offers.Visible = shown
	if not shown then return end
	local busy = s.Buying ~= nil or s.Reviving == true
	for kind, o in pairs(offerList) do
		local mine = s.Buying == "self" and s.BuyingKind == kind
		o.label.Text = mine and "..." or ""
		o.btn.enabled = not busy
		fader:setBase(o.face, "BackgroundTransparency", busy and 0.35 or 0)
		fader:setBase(o.icon, "ImageTransparency", busy and not mine and 0.4 or 0)
	end
	offerAsked = 0
end

local revAsked = 0
local revBtn = Motion.button(revHolder, {
	fader = fader, sfx = sfx, hover = 1.04, press = 0.95, lift = 2, sink = 4,
	onActivate = function()
		local rv = state and state.Revenge
		if not rv or rv.Status ~= "ready" or os.clock() - revAsked < 1.5 then
			revBtn:shake()
			return
		end
		revAsked = os.clock()
		Remotes:WaitForChild("RevengeRequest"):FireServer()   -- the server locks it and opens the purchase
	end,
})

-- The purchase window closed without a purchase: say so at once (a backup for the server's
-- own event), so the partner's "buying" message and the held countdown never outstay it.
MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
	if userId == player.UserId and productId == Config.ReviveProductId and not purchased
		and state and state.Buying == "self" then
		Remotes.ReviveRequest:FireServer("closed")
	end
	if userId == player.UserId and not purchased and state and state.Buying == "self"
		and ((productId == Config.ReviveFiveProductId and state.BuyingKind == "five")
			or (productId == Config.ReviveInfiniteProductId and state.BuyingKind == "infinite")) then
		Remotes.ReviveRequest:FireServer("closed")
	end
	if userId == player.UserId and productId == Config.RevengeProductId and not purchased
		and state and state.Revenge and state.Revenge.Buying == "self" then
		Remotes:WaitForChild("RevengeRequest"):FireServer("closed")
	end
end)

-- the revenge section, from the server's state
local shownAvatar
local function applyRevenge(s)
	local rv = s and s.Revenge
	revenge.Visible = rv ~= nil
	if not rv then return end
	revName.Text = ("%s exploded you!"):format(tostring(rv.By or "Someone"))
	if type(rv.UserId) == "number" and rv.UserId > 0 and rv.UserId ~= shownAvatar then
		shownAvatar = rv.UserId
		revAvatar.Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(rv.UserId)
	end
	local live = rv.Status == "ready"
	if live then
		revLabel.Text = "EXPLODE BACK (REVENGE)"
	elseif rv.Status == "buying" then
		revLabel.Text = rv.Buying == "self" and "GETTING REVENGE..." or "YOUR FRIEND IS GETTING REVENGE..."
	elseif rv.Status == "used" or rv.Status == "playing" then
		revLabel.Text = "REVENGE SENT!"
	else
		revLabel.Text = "UNABLE TO GET REVENGE!"
	end
	revBtn.enabled = live
	if revGrad then revGrad.Color = live and REV_RED_GRAD or REV_GREY_GRAD end
	revLip.BackgroundColor3 = live and REV_RED_LIP or REV_GREY_LIP
end

-- watching the revenge: the popup slides away and the camera goes to the attackers' scooter
local watching, watchInfo, heldBeforeWatch = false, nil, nil
local watchSide, watchSideFor = 1, nil

-- what the watch camera sees through: the scooter and everyone's characters
local function watchSkip(scooter)
	local list = { scooter }
	for _, p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(list, p.Character) end end
	return list
end

-- the scooter whose Explode show is playing nearest where the server said
local function findWatched(info)
	local at = info and typeof(info.At) == "Vector3" and info.At
	local sys = workspace:FindFirstChild("RideSystem")
	local folder = sys and sys:FindFirstChild("Scooters")
	if not (at and folder) then return nil end
	local best, bestD
	for _, s in ipairs(folder:GetChildren()) do
		if s:GetAttribute("Troll") == "Explode" and s.PrimaryPart then
			local d = (s.PrimaryPart.Position - at).Magnitude
			if d < 40 and (not bestD or d < bestD) then best, bestD = s, d end
		end
	end
	return best
end
local function setWatching(on, info)
	if on then
		watchInfo = info
		if watching then return end
		watching = true
		heldBeforeWatch = heldAt
		slide:close()
		heartbeat:Pause()
	elseif watching then
		watching, watchInfo = false, nil
		if heldAt and heldBeforeWatch then heldAt = heldBeforeWatch end
		heldBeforeWatch = nil
		if isOpen then
			window.Visible = true
			slide:open()
			heartbeat:Resume()
		end
	end
end

local function open()
	if isOpen then return end
	isOpen = true
	holdCamera()                            -- first: the moment the rider went in
	shownWhole = nil
	danger = 0
	window.Visible = true
	slide:open()                            -- blocking: an open menu closes, none opens over it
	sfx:play("Open")
	task.delay(0.24, function() if isOpen then Motion.sweep(panelSweep, 0.75) end end)
	heartbeat.TimePosition = 0
	heartbeat:Play()
end

local function close(revived)
	if not isOpen then return end
	isOpen = false
	setWatching(false)                      -- (the camera goes back to where it was held first)
	state = nil
	statusText = nil
	asked = 0
	revAsked = 0
	offerAsked = 0
	slide:close()
	heartbeat:Stop()                        -- at once; the red fades out in the frame loop
	releaseCamera(revived)
	skipBtn:reset()
	reviveBtn:reset()
	revBtn:reset()
	for _, o in pairs(offerList) do o.btn:reset(); o.label.Text = "" end
	-- the frame loop hides the window once it has lifted away
end

Remotes:WaitForChild("DeathState").OnClientEvent:Connect(function(s)
	if type(s) ~= "table" or not s.Active then close(type(s) == "table" and s.Revived == true) return end
	state = s
	asked = 0                               -- the server has answered
	skipLabel.Text = ("SKIP (%d/%d)"):format(s.Skips or 0, s.Needed or 2)
	skipBtn.enabled = not s.Voted and not s.Reviving
	fader:setBase(skipHolder.Face, "BackgroundTransparency", (s.Voted or s.Reviving) and 0.35 or 0)
	-- REVIVE dims while a purchase is open (either rider's) or the revive is being done
	reviveLabel.Text = (s.Infinite and "INFINITE REVIVE") or (s.Free and "FREE REVIVE") or "REVIVE"
	fader:setBase(reviveHolder.Face, "BackgroundTransparency", (s.Buying or s.Reviving) and 0.35 or 0)
	statusText = (s.Reviving and "Reviving...") or (s.Buying == "partner" and "Your friend is buying a revive...") or nil
	revAsked = 0
	applyRevenge(s)
	applyOffers(s)
	open()
	local rv = s.Revenge
	setWatching(rv ~= nil and rv.Status == "playing", rv and rv.Watch)
end)

-- back in the lobby by any route (skip, timer, a rider leaving): no popup.
-- Roblox's own Reset Character (Esc menu) is switched off everywhere, in a run and in the lobby
local function setReset(enabled)
	for _ = 1, 10 do
		if pcall(StarterGui.SetCore, StarterGui, "ResetButtonCallback", enabled) then return end
		task.wait(1)
	end
end
task.spawn(setReset, false)   -- from the moment they join
HudSync.OnInGame(function(inGame)
	if not inGame then close() end
	task.spawn(setReset, false)
end)

--------------------------------------------------------------------- frame loop
local function lerp(a, b, t) return a + (b - a) * t end

RunService.RenderStepped:Connect(function(dt)
	dt = math.min(dt, 1 / 30)

	if state then
		-- counted from the server's end time, so both riders see the same number; held
		-- (a revive being bought or done), it stands at what the server says is left
		local left = state.EndsAt and math.max(state.EndsAt - workspace:GetServerTimeNow(), 0)
			or math.max(tonumber(state.Left) or 0, 0)
		count.Text = string.format("%.2f", left)
		local whole = math.ceil(left)
		if whole ~= shownWhole then
			shownWhole = whole
			countScale.Scale = 1.12         -- a small pop on every whole second
		end
		danger = 1 - math.clamp(left / SECONDS, 0, 1)

		-- the heartbeat quickens and grows (faster, not higher: the pitch shift undoes that)
		local speed = lerp(HEART_SLOW, HEART_FAST, danger ^ 1.8)
		heartbeat.PlaybackSpeed = speed
		steady.Octave = 1 / speed
		heartbeat.Volume = lerp(HEART_SOFT, HEART_LOUD, danger ^ 1.4)
	end
	countScale.Scale = Motion.approach(countScale.Scale, 1, 12, dt)

	-- watching the revenge: the camera on the attackers' scooter, as a spectator sees the show
	if watching and heldAt then
		local scooter = watchInfo and watchInfo.Scooter
		-- not streamed in when the server named it: find it by its show (the one exploding
		-- nearest where the server said it was)
		if typeof(scooter) ~= "Instance" or not scooter.Parent then
			scooter = findWatched(watchInfo)
			if scooter and watchInfo then watchInfo.Scooter = scooter end
		end
		local base  = typeof(scooter) == "Instance" and scooter:GetAttribute("TrollBase")
		local start = typeof(scooter) == "Instance" and scooter:GetAttribute("TrollStart")
		local goal
		if typeof(base) == "CFrame" and type(start) == "number" then
			local t = workspace:GetServerTimeNow() - start
			-- the side with room (as every troll camera picks it), worked out once per show
			if watchSideFor ~= start then
				watchSideFor = start
				local ok, side = pcall(ExplodeT.BestSide, base, watchSkip(scooter), 0.35, 1)
				watchSide = (ok and (side == 1 or side == -1)) and side or 1
			end
			local look = base.Position + Vector3.new(0, 1.5, 0)
			local eye, target = ExplodeT.Camera(base, look, t, 0.35, watchSide)
			-- never through a wall: pulled in front of it (and up over it)
			local okClear, _, room = pcall(ExplodeT.Clear, eye, target, watchSkip(scooter), 4)
			if okClear and type(room) == "number" and room < 1 then eye = ExplodeT.Pulled(eye, target, room) end
			local shake = (ExplodeT.Shake and ExplodeT.Shake(t) or 0) * 0.35
			goal = CFrame.lookAt(eye, target) * CFrame.Angles(
				math.noise(os.clock() * 13, 1) * shake * 0.1, math.noise(os.clock() * 13, 2) * shake * 0.1, 0)
		else
			-- not streamed in yet: look at where the server said it was
			local at = (watchInfo and typeof(watchInfo.At) == "Vector3" and watchInfo.At)
				or (typeof(scooter) == "Instance" and scooter.PrimaryPart and scooter.PrimaryPart.Position)
			if at then goal = CFrame.lookAt(at + Vector3.new(10, 9, 12), at) end
		end
		if goal then heldAt = heldAt:Lerp(goal, 1 - math.exp(-7 * dt)) end
	end
	if offers.Visible then
		for _, o in pairs(offerList) do o.btn:update(dt) end
	end
	if revenge.Visible then
		revIcon.Rotation = math.sin(os.clock() * 5) * 8
		revBurst.Rotation = (os.clock() * 25) % 360
		revBtn:update(dt)
	end

	-- the red builds with the danger, and fades in / out with the popup (not while watching)
	local shownRed = isOpen and not watching
	present = Motion.approach(present, shownRed and 1 or 0, shownRed and 4 or 8, dt)
	if present < 0.002 and not shownRed then present = 0 end
	local e = danger ^ 1.6
	tint.Enabled = present > 0
	tint.TintColor  = WHITE:Lerp(TINT_CALM:Lerp(TINT_PANIC, e), present)
	tint.Brightness = lerp(DARK_CALM, DARK_PANIC, e) * present
	tint.Saturation = lerp(GREY_CALM, GREY_PANIC, e) * present
	vignette.Visible = present > 0
	local edge = 1 - lerp(EDGE_CALM, EDGE_PANIC, e) * present
	for _, f in ipairs(edges) do f.BackgroundTransparency = edge end

	if not window.Visible then return end
	local a = slide:alpha()
	-- the line under the countdown, breathing gently while it is up
	status.Visible = statusText ~= nil
	if statusText then
		status.Text = statusText
		fader:setBase(status, "TextTransparency", 0.3 - 0.25 * (0.5 + 0.5 * math.sin(os.clock() * 4)))
	end
	fader:set(a, {})
	skipBtn:update(dt)
	reviveBtn:update(dt)
	if not isOpen and a < 0.01 then window.Visible = false end
end)
