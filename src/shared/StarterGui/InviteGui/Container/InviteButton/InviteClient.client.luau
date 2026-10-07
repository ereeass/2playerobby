--=====================================================================
-- InviteClient
--
-- Every animated property is COMPOSED each frame from independent
-- sources (idle float + hover lift + cursor parallax, etc.) instead of
-- being tweened directly, so no two effects can ever cancel each other.
-- Scale and rotation run on springs, which gives the press-pop and the
-- entrance overshoot for free.
--=====================================================================

local TweenService     = game:GetService("TweenService")
local RunService       = game:GetService("RunService")
local SocialService    = game:GetService("SocialService")
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService       = game:GetService("GuiService")

local player = Players.LocalPlayer

local btn       = script.Parent
local container = btn.Parent
local gui       = container.Parent

-- container level (unclipped: glow, badge and hint can overflow)
local rootScale  = container:WaitForChild("RootScale")
local scaleObj   = container:WaitForChild("Scale")
local glow       = container:WaitForChild("Glow")
local badge      = container:WaitForChild("Badge")
local badgeScale = badge:WaitForChild("BadgeScale")
local badgeRing  = container:WaitForChild("BadgeRing")
local ringStroke = badgeRing:WaitForChild("UIStroke")
local hint       = container:WaitForChild("Hint")
local hintStroke = hint:WaitForChild("UIStroke")

-- button level (clipped: ripple and sweep stay inside the rounded corners)
local stroke     = btn:WaitForChild("Edge")
local icon       = btn:WaitForChild("Icon")
local iconScale  = icon:WaitForChild("IconScale")
local label      = btn:WaitForChild("Label")
local labelScale = label:WaitForChild("LabelScale")
local studs      = btn:WaitForChild("Studs")
local sweep      = btn:WaitForChild("Sweep")
local sweepGrad  = sweep:WaitForChild("SweepGradient")

local sfxHover   = gui:WaitForChild("SfxHover")
local sfxPress   = gui:WaitForChild("SfxPress")
local sfxSuccess = gui:WaitForChild("SfxSuccess")

-- the small top-bar button that stands in for this one while the player is in a
-- game (StarterGui.InviteTopbar: styled and animated like the Settings button)
local compact      = gui.Parent:WaitForChild("InviteTopbar"):WaitForChild("Container")
local compactScale = compact:WaitForChild("Scale")
local compactBtn   = compact:WaitForChild("InviteButton")
local compactEdge  = compactBtn:WaitForChild("Edge")
local compactText  = compactBtn:WaitForChild("Label"):WaitForChild("LabelScale")
local compactSweep = compactBtn:WaitForChild("Sweep")
local compactGrad  = compactSweep:WaitForChild("SweepGradient")
local HudSync      = require(game:GetService("ReplicatedStorage"):WaitForChild("HudSync"))
local Menus        = require(game:GetService("ReplicatedStorage"):WaitForChild("UITemplates"):WaitForChild("Menus"))

--------------------------------------------------------------------- consts
local BASE_ICON_POS  = icon.Position
local BASE_LABEL     = "INVITE"
local LOCAL_SIZE     = 84                 -- unscaled button size, for ripple maths

local STROKE_COLOR   = stroke.Color
local REST_STROKE_T,  REST_STROKE_W  = 0.1, 3     -- clean dark outline that separates the button from the world
local HOVER_STROKE_T, HOVER_STROKE_W = 0,   3.5

local C_REST_T,  C_REST_W  = compactEdge.Transparency, compactEdge.Thickness   -- the Settings button's rim
local C_HOVER_T, C_HOVER_W = 0.45, 1.8

-- Glow is a circle + radial UIGradient falloff, so these drive BackgroundTransparency.
-- The gradient eats most of the alpha, so these read fainter than the raw numbers suggest.
local GLOW_IDLE_MIN  = 0.95               -- faint end of the idle breath
local GLOW_IDLE_MAX  = 0.88               -- bright end of the idle breath
local GLOW_HOVER     = 0.40
local GLOW_BUSY      = 0.97

local BG_ACTIVE = btn.BackgroundColor3
local BG_MUTED  = BG_ACTIVE:Lerp(Color3.fromRGB(140, 140, 145), 0.38)

local ATTENTION_AFTER = 40                -- idle seconds before the nudge
local BADGE_PULSES    = 4                 -- ring pulses in the arrival burst, then it stops
local BADGE_AUTO_ACK  = 45                -- seconds before the badge retires unprompted

--------------------------------------------------------------------- helpers
local function approach(cur, target, rate, dt)
	return cur + (target - cur) * (1 - math.exp(-rate * dt))
end

local function springStep(cur, vel, target, stiffness, damping, dt)
	vel += ((target - cur) * stiffness - vel * damping) * dt
	return cur + vel * dt, vel
end

local function isTouch()
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

local function pointer()
	return UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
end

--------------------------------------------------------------------- state
local hovering, pressed, busy = false, false, false
local solo         = true
local ready        = false
local lastInteract = os.clock()
local flashUntil   = 0
local wiggleT      = math.huge
-- The Roblox invite modal owns the screen but never fires MouseLeave on us, so
-- hover state would otherwise stick and leave the pill visible behind it.
local promptOpen   = false
local promptOpenAt = 0

-- smoothed / sprung values
local sCur,   sVel   = 0.32, 2.2          -- entrance starts small and springs up
local rotCur, rotVel = 0, 0
local bCur,   bVel   = 0, 0
local gCur           = 1
local liftCur        = 0
local lblCur         = 1
local parX,   parY   = 0, 0
local icoHover       = 1
local strT,   strW   = REST_STROKE_T, REST_STROKE_W
local hintA,  muteA  = 0, 0
local busyA          = 0
local wantIcon, wantLabel = 0, 0          -- entrance reveal targets
local revIcon,  revLabel  = 0, 0
local inGame           = false            -- queued or riding: the top-bar button stands in
local introDone        = false            -- the loading screen has handed over
local pCur,   pVel     = 0, 0              -- presence: pops in after the intro, steps aside for a booth
local baseRoot         = 1                 -- the responsive scale (updateScale)
local cHover, cPressed = false, false
local cCur,   cVel     = 0, 0              -- presence: springs in with a game, away after
local ciCur,  ciVel    = 1, 0              -- interaction: hover swell, press pop
local cRot,   cRotVel  = 0, 0
local cStrT,  cStrW    = C_REST_T, C_REST_W

-- Badge lifecycle. It is a notification, so it has to be answerable: it arrives,
-- says its piece a few times, and leaves once the player engages or enough time
-- passes. It only comes back when the situation genuinely changes again.
local acked       = true                  -- armBadge() flips this on
local armedAt     = 0
local pulsesLeft  = 0
local ackPopUntil = 0                     -- brief overshoot target on dismissal

local function armBadge()
	acked      = false
	armedAt    = os.clock()
	pulsesLeft = BADGE_PULSES
end

local function ackBadge(silent)
	if acked then return end
	acked      = true
	pulsesLeft = 0
	-- Pop by moving the TARGET, not by kicking velocity: with the target already
	-- at 0 the restoring force is a full k*1.0 and swallows any kick in one frame.
	if not silent then ackPopUntil = os.clock() + 0.09 end
end

--------------------------------------------------------------------- responsive
-- the lobby tile grid's size (HudSync), so the tiles always match
local function updateScale()
	baseRoot = HudSync.TileScale()
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

--------------------------------------------------------------------- effects
local sweepTween
local function playSweep(dur)
	if sweepTween then sweepTween:Cancel() end
	sweep.Visible = true
	sweepGrad.Offset = Vector2.new(-1.3, 0)
	sweepTween = TweenService:Create(sweepGrad,
		TweenInfo.new(dur or 0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Offset = Vector2.new(1.3, 0) })
	sweepTween:Play()
	sweepTween.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed then sweep.Visible = false end
	end)
end

local compactTween
local function playCompactSweep(dur)
	if compactTween then compactTween:Cancel() end
	compactSweep.Visible = true
	compactGrad.Offset = Vector2.new(-1.3, 0)
	compactTween = TweenService:Create(compactGrad,
		TweenInfo.new(dur or 0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Offset = Vector2.new(1.3, 0) })
	compactTween:Play()
	compactTween.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed then compactSweep.Visible = false end
	end)
end

local function ripple(x, y)
	local r = Instance.new("Frame")
	r.Name = "Ripple"
	r.AnchorPoint = Vector2.new(0.5, 0.5)
	r.Position = UDim2.fromOffset(x, y)
	r.Size = UDim2.fromOffset(0, 0)
	r.BackgroundColor3 = Color3.new(1, 1, 1)
	r.BackgroundTransparency = 0.70
	r.BorderSizePixel = 0
	r.ZIndex = 4
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = r
	r.Parent = btn
	TweenService:Create(r, TweenInfo.new(0.46, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(210, 210),
		BackgroundTransparency = 1,
	}):Play()
	task.delay(0.5, function() r:Destroy() end)
end

local function burst()
	for i = 1, 9 do
		local p = Instance.new("Frame")
		p.Name = "Spark"
		p.AnchorPoint = Vector2.new(0.5, 0.5)
		p.Position = UDim2.fromScale(0.5, 0.5)
		p.Size = UDim2.fromOffset(7, 7)
		p.BackgroundColor3 = (i % 2 == 0)
			and Color3.fromRGB(255, 226, 138)
			or  Color3.fromRGB(255, 255, 255)
		p.BorderSizePixel = 0
		p.ZIndex = 11
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = p
		p.Parent = container
		local ang  = (i / 9) * math.pi * 2 + math.random() * 0.5
		local dist = 48 + math.random() * 28
		TweenService:Create(p, TweenInfo.new(0.58, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, math.cos(ang) * dist, 0.5, math.sin(ang) * dist),
			Size = UDim2.fromOffset(2, 2),
			BackgroundTransparency = 1,
		}):Play()
		task.delay(0.62, function() p:Destroy() end)
	end
end

local function pulseRing()
	badgeRing.Visible = true
	badgeRing.Size = UDim2.fromOffset(24, 24)
	ringStroke.Transparency = 0.15
	local info = TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(badgeRing, info, { Size = UDim2.fromOffset(46, 46) }):Play()
	local t = TweenService:Create(ringStroke, info, { Transparency = 1 })
	t:Play()
	t.Completed:Once(function() badgeRing.Visible = false end)
end

local function celebrate(n)
	sfxSuccess:Play()
	burst()
	playSweep(0.45)
	flashUntil = os.clock() + 0.55
	label.Text = (n and n > 1) and ("SENT x" .. n) or "SENT!"
	task.delay(1.5, function()
		if not busy then label.Text = BASE_LABEL end
	end)
end

--------------------------------------------------------------------- solo state
local function refreshSolo()
	local wasSolo = solo
	solo = (#Players:GetPlayers() <= 1)
	hint.Text = solo and "Invite a friend to play!" or "Invite more friends"
	if solo and not wasSolo then
		armBadge()                         -- alone again: genuinely new information
		pulseRing()
	end
end

refreshSolo()
Players.PlayerAdded:Connect(function() task.defer(refreshSolo) end)
Players.PlayerRemoving:Connect(function() task.defer(refreshSolo) end)

--------------------------------------------------------------------- invite permission
-- Whether this player may send invites is a web call: often slow, and now and then
-- it fails. It used to run INSIDE the click, so the button sat on "..." while it
-- waited (ignoring every click made meanwhile) and opened nothing at all when the
-- call failed, so the player had to click again. It is asked ahead of time now and
-- remembered, so a click opens the invite straight away.
local canInvite      = nil        -- nil = not known yet (still checking, or the check failed)
local checkingInvite = false
local function refreshCanInvite()
	if checkingInvite then return end
	checkingInvite = true
	task.spawn(function()
		local ok, res = pcall(function()
			return SocialService:CanSendGameInviteAsync(player)
		end)
		if ok then canInvite = res end   -- a failed check keeps the last known answer
		checkingInvite = false
	end)
end
refreshCanInvite()

--------------------------------------------------------------------- entrance
local studParts = {}
for _, d in ipairs(studs:GetDescendants()) do
	if d:IsA("Frame") and d.BackgroundTransparency < 1 then
		table.insert(studParts, { obj = d, base = d.BackgroundTransparency })
	end
end

local function playEntrance()
	sCur, sVel = 0.32, 2.2
	wantIcon, wantLabel = 0, 0
	revIcon,  revLabel  = 0, 0
	for _, s in ipairs(studParts) do s.obj.BackgroundTransparency = 1 end

	-- studs wash in, staggered
	task.spawn(function()
		local n  = math.max(#studParts, 1)
		local t0 = os.clock()
		while true do
			local a = (os.clock() - t0) / 0.42
			if a >= 1 then break end
			for i, s in ipairs(studParts) do
				local off = (i / n) * 0.45
				local la  = math.clamp((a - off) / 0.55, 0, 1)
				local e   = 1 - (1 - la) ^ 3
				s.obj.BackgroundTransparency = 1 + (s.base - 1) * e
			end
			RunService.RenderStepped:Wait()
		end
		for _, s in ipairs(studParts) do s.obj.BackgroundTransparency = s.base end
	end)

	task.delay(0.12, function() wantIcon  = 1 end)
	task.delay(0.20, function() wantLabel = 1 end)
	task.delay(0.34, function()
		ready = true
		playSweep(0.6)
		if solo then
			armBadge()
			pulseRing()
		end
	end)
end

--------------------------------------------------------------------- frame loop
local t = 0
RunService.RenderStepped:Connect(function(dt)
	dt = math.min(dt, 1 / 30)
	t += dt

	-- coming and going: HudSync's shared spring, in step with the Scooters tile and
	-- the Settings gear. It rides on RootScale because only one UIScale per object
	-- takes effect (Container.Scale never shows).
	container.Position = HudSync.TileAt(gui, 2, 2, baseRoot)   -- the grid's right column, under Troll
	local present = introDone and not inGame
	pCur, pVel = springStep(pCur, pVel, present and 1 or 0, HudSync.STIFFNESS, HudSync.DAMPING, dt)
	rootScale.Scale = baseRoot * math.max(pCur, 0.01)
	container.Visible = present or pCur > 0.03

	-- scale: one spring covers entrance overshoot, hover swell and press pop
	local sTarget = 1
	if pressed then sTarget = 0.93
	elseif hovering then sTarget = 1.06 end
	sCur, sVel = springStep(sCur, sVel, sTarget, 250, 19, dt)
	scaleObj.Scale = math.max(sCur, 0.01)

	-- rotation: press tilt plus a damped-sine attention wiggle
	local wig = 0
	if wiggleT < 1.6 then
		wiggleT += dt
		wig = math.sin(wiggleT * 26) * math.exp(-wiggleT * 4.5) * 5
	end
	rotCur, rotVel = springStep(rotCur, rotVel, (pressed and 1.8 or 0) + wig, 320, 17, dt)
	btn.Rotation = rotCur

	busyA = approach(busyA, busy and 1 or 0, 10, dt)
	muteA = approach(muteA, solo and 0 or 1, 6, dt)

	-- glow: always-on breath, ramps up on hover, drops out while busy
	local breath  = GLOW_IDLE_MIN + (GLOW_IDLE_MAX - GLOW_IDLE_MIN) * (0.5 + 0.5 * math.sin(t * 1.9))
	local gTarget = breath
	if hovering then gTarget = GLOW_HOVER end
	if busy     then gTarget = GLOW_BUSY end
	if not ready then gTarget = 1 end
	gCur = approach(gCur, gTarget, 9, dt)
	if glow.Visible then glow.BackgroundTransparency = gCur end

	-- Idle motion is rotation + scale, NOT translation. Roblox rasterises GUI to
	-- whole device pixels, so a slow 4px bob only ever lands on ~5 rendered
	-- positions and ticks between them. Rotation and scale go through a filtered
	-- transform instead, so they stay smooth at tiny magnitudes.
	liftCur = approach(liftCur, hovering and -3.5 or 0, 12, dt)

	local pxT, pyT = 0, 0
	if hovering and not isTouch() then
		local m    = pointer()
		local c    = btn.AbsolutePosition + btn.AbsoluteSize * 0.5
		local half = math.max(btn.AbsoluteSize.X * 0.5, 1)
		pxT = math.clamp((m.X - c.X) / half, -1, 1) * 3
		pyT = math.clamp((m.Y - c.Y) / half, -1, 1) * 3
	end
	parX = approach(parX, pxT, 14, dt)
	parY = approach(parY, pyT, 14, dt)

	-- UDim.Offset is an INTEGER, so a ~2px travel quantises to 3 positions and
	-- reads as stutter no matter how smooth the maths feeding it is. Scale is a
	-- float, so routing the motion through it gives genuine sub-pixel travel.
	local invSize = 1 / LOCAL_SIZE
	icon.Position = UDim2.new(
		BASE_ICON_POS.X.Scale + parX * invSize,
		BASE_ICON_POS.X.Offset,
		BASE_ICON_POS.Y.Scale + (liftCur + parY) * invSize,
		BASE_ICON_POS.Y.Offset)

	-- gentle sway + breath, on slightly different periods so it feels organic
	icon.Rotation = math.sin(t * 1.15) * 1.2
	icoHover = approach(icoHover, hovering and 1.04 or 1, 12, dt)
	iconScale.Scale = icoHover + math.sin(t * 0.9) * 0.014

	-- label scale (UIScale, not TextSize -- no re-rasterising shimmer)
	lblCur = approach(lblCur, hovering and 1.07 or 1, 12, dt)
	labelScale.Scale = lblCur

	-- reveal + state transparency
	revIcon  = approach(revIcon,  wantIcon,  11, dt)
	revLabel = approach(revLabel, wantLabel, 11, dt)
	icon.ImageTransparency  = math.clamp(1 - revIcon, 0, 1)   -- icon stays solid (owners)
	label.TextTransparency  = math.clamp(1 - revLabel, 0, 1)   -- INVITE text stays solid white (owners)

	-- stroke: success flash overrides, then eases back to rest
	if os.clock() < flashUntil then
		strT, strW = 0, 4
		stroke.Color = Color3.new(1, 1, 1)
	else
		-- idle life lives in the rim now: contained by the button's own outline,
		-- so it can never throw a stray shape onto the scene behind it
		local restT = REST_STROKE_T + math.sin(t * 1.9) * 0.05
		strT = approach(strT, hovering and HOVER_STROKE_T or restT, 11, dt)
		strW = approach(strW, hovering and HOVER_STROKE_W or REST_STROKE_W, 11, dt)
		stroke.Color = stroke.Color:Lerp(STROKE_COLOR, 1 - math.exp(-8 * dt))
	end
	stroke.Transparency = strT
	stroke.Thickness    = strW

	-- top-bar button: the Settings button's own motion (spring pop, press tilt,
	-- breathing rim); it springs in when a game starts and away when it ends
	cCur,  cVel  = springStep(cCur,  cVel,  inGame and 1 or 0, 250, 19, dt)
	ciCur, ciVel = springStep(ciCur, ciVel, cPressed and 0.93 or (cHover and 1.06 or 1), 250, 19, dt)
	compactScale.Scale = math.max(cCur * ciCur, 0.01)
	-- Text is drawn at whole-pixel sizes, so swelling it snaps it a pixel (the
	-- up-and-down jump on hover). The pill swells; the text holds its size. The
	-- hair over 1 keeps float error from rounding the text down a pixel.
	compactText.Scale = 1.005 / ciCur
	compact.Visible = inGame or cCur > 0.05
	cRot, cRotVel = springStep(cRot, cRotVel, cPressed and 1.8 or 0, 320, 17, dt)
	compactBtn.Rotation = cRot
	local cRestT = C_REST_T + math.sin(t * 1.9) * 0.05
	cStrT = approach(cStrT, cHover and C_HOVER_T or cRestT, 11, dt)
	cStrW = approach(cStrW, cHover and C_HOVER_W or C_REST_W, 11, dt)
	compactEdge.Transparency = cStrT
	compactEdge.Thickness    = cStrW

	-- solo badge: retires on its own if they never engage with it
	if not acked and ready and (os.clock() - armedAt) > BADGE_AUTO_ACK then
		ackBadge(true)
	end
	local badgeTarget = (solo and not acked) and 1 or 0
	if os.clock() < ackPopUntil then badgeTarget = 1.3 end
	bCur, bVel = springStep(bCur, bVel, badgeTarget, 260, 18, dt)
	badgeScale.Scale = math.max(bCur, 0)

	-- hover hint pill: hover / gamepad selection only, never unprompted
	if promptOpen and (os.clock() - promptOpenAt) > 120 then promptOpen = false end
	local hintTarget = (hovering and not promptOpen) and 1 or 0
	hintA = approach(hintA, hintTarget, 14, dt)
	hint.Position            = UDim2.new(1 + (2 + 8 * hintA) / LOCAL_SIZE, 0, 0.5, 0)
	hint.BackgroundTransparency = 1 - 0.86 * hintA
	hint.TextTransparency    = 1 - hintA
	hintStroke.Transparency  = 1 - 0.75 * hintA

	-- solo reads full strength, paired reads quiet
	btn.BackgroundColor3 = BG_ACTIVE:Lerp(BG_MUTED, muteA)

	-- attention nudge when they are alone and idle
	if ready and solo and not acked and not hovering and not busy
		and (os.clock() - lastInteract) > ATTENTION_AFTER then
		lastInteract = os.clock()
		wiggleT = 0
		playSweep(0.6)
		pulseRing()
	end
end)

--------------------------------------------------------------------- input
local function noteInteract() lastInteract = os.clock() end

btn.MouseEnter:Connect(function()
	if isTouch() then return end
	hovering = true
	promptOpen = false        -- reaching us again means the modal is gone
	noteInteract()
	pulsesLeft = 0            -- they have looked at it; stop waving
	sfxHover:Play()
	playSweep(0.5)
end)

btn.MouseLeave:Connect(function()
	hovering = false
	pressed  = false
end)

btn.MouseButton1Down:Connect(function()
	pressed = true
	noteInteract()
	ackBadge()                -- they engaged; the notification has done its job
	sfxPress:Play()
	if isTouch() then hovering = true end

	local eff = btn.AbsoluteSize.X / LOCAL_SIZE
	if eff > 0 then
		local rel = (pointer() - btn.AbsolutePosition) / eff
		ripple(rel.X, rel.Y)
	else
		ripple(LOCAL_SIZE / 2, LOCAL_SIZE / 2)
	end
end)

btn.MouseButton1Up:Connect(function()
	pressed = false
end)

-- covers drag-off and touch release, which MouseButton1Up alone misses
btn.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		pressed = false
		if isTouch() then hovering = false end
	end
end)

btn.Selectable = true
btn.SelectionGained:Connect(function() hovering = true; pulsesLeft = 0; playSweep(0.5) end)
btn.SelectionLost:Connect(function() hovering = false end)

-- Roblox's invite window is a blocking screen (UITemplates.Menus): while it is up
-- the open menu closes and Settings / Scooters stay shut; their icon shakes and
-- its hint says "Close the invite window first". Roblox gives games no way to
-- close it, so it ends when Roblox says the player closed it; the timer only
-- covers that never arriving, so menus can never stay locked for long.
local INVITE_BLOCK_MSG = "Close the invite window first"
local inviteBlockToken = 0
local function unblockInvitePrompt()
	inviteBlockToken += 1
	Menus.Unblock("InvitePrompt")
end
local function blockInvitePrompt()
	inviteBlockToken += 1
	local mine = inviteBlockToken
	Menus.Block("InvitePrompt", INVITE_BLOCK_MSG)
	task.delay(60, function() if inviteBlockToken == mine then unblockInvitePrompt() end end)
end

local clickId = 0
local function openInvite()
	noteInteract()
	-- busy, or another blocking screen is up (the booth's checkpoint picker): the
	-- invite window must not open over it
	if busy or Menus.IsBlocked("InvitePrompt") then
		wiggleT = 0                        -- "not yet" shake instead of dead silence
		return
	end

	busy = true
	clickId += 1
	local myClick = clickId
	label.Text = "..."

	-- only a definite "no" stops the prompt; unknown still opens it
	if canInvite ~= false then
		local sent, sendErr = pcall(function()
			SocialService:PromptGameInvite(player)
		end)
		if sent then
			blockInvitePrompt()            -- the open menu closes; none opens over the invite
			-- modal is up: drop hover so the pill does not sit visible behind it
			promptOpen   = true
			promptOpenAt = os.clock()
			hovering     = false
			pressed      = false
			cHover, cPressed = false, false
		else
			warn("[Invite] PromptGameInvite failed: " .. tostring(sendErr))
		end
	else
		warn("[Invite] This account cannot send invites (expected in Studio)")
		refreshCanInvite()                 -- ask again, in case that changes
	end

	task.wait(0.6)
	-- the prompt can close and a new click start inside this wait; that click owns
	-- busy now, so this older one must not clear it early
	if clickId ~= myClick then return end
	busy = false
	if label.Text == "..." then label.Text = BASE_LABEL end
end
btn.MouseButton1Click:Connect(openInvite)

-- the top-bar button: same sounds, same invite
compactBtn.MouseEnter:Connect(function()
	if isTouch() then return end
	cHover = true
	promptOpen = false
	sfxHover:Play()
	playCompactSweep(0.5)
end)
compactBtn.MouseLeave:Connect(function() cHover, cPressed = false, false end)
compactBtn.MouseButton1Down:Connect(function()
	cPressed = true
	sfxPress:Play()
end)
compactBtn.MouseButton1Up:Connect(function() cPressed = false end)
compactBtn.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		cPressed = false
	end
end)
compactBtn.MouseButton1Click:Connect(openInvite)
-- the ride's controls popup is modal: this button takes no input while it is up
Menus.Lockable(compactBtn, function() cHover, cPressed = false, false end)

-- Lobby: the big button. Queued in a capsule or riding: the top-bar button.
-- The switch comes from HudSync, so this tile, the Scooters tile and the top-bar
-- button all move in the same frame on the same spring (see the frame loop).
local function setInGame(on)
	if on == inGame then return end
	inGame = on
	if on then
		hovering, pressed = false, false
		cCur, cVel = 0, 0
	else
		cHover, cPressed = false, false
		revIcon, revLabel = 0, 0           -- icon and text fade back in
		playSweep(0.6)
	end
end
HudSync.OnAside(setInGame)   -- in game, or watching a duo in the Troll window

-- real confirmation: this fires with the friends they actually picked
pcall(function()
	SocialService.GameInvitePromptClosed:Connect(function(plr, recipientIds)
		if plr ~= player then return end
		busy = false
		promptOpen = false
		unblockInvitePrompt()
		if recipientIds and #recipientIds > 0 then
			celebrate(#recipientIds)
		elseif label.Text == "..." then
			label.Text = BASE_LABEL
		end
	end)
end)

--------------------------------------------------------------------- ambient loops
-- idle specular sweep
task.spawn(function()
	while btn.Parent do
		task.wait(7 + math.random() * 2.5)
		if ready and not hovering and not busy then playSweep(0.6) end
		if inGame and not cHover then playCompactSweep(0.6) end
	end
end)

-- sweep keeps moving while the invite prompt is opening, so busy reads as "working"
task.spawn(function()
	while btn.Parent do
		if busy then playSweep(0.45); task.wait(0.5) else task.wait(0.2) end
	end
end)

-- badge ring keeps pulsing while they are alone
task.spawn(function()
	while btn.Parent do
		task.wait(4.5)
		if solo and ready and not acked and pulsesLeft > 0 and bCur > 0.6 then
			pulsesLeft -= 1
			pulseRing()
		end
	end
end)

-- in the frame the loading screen hands over, with the Scooters tile and the gear
HudSync.WhenIntroDone(function()
	introDone = true
	pCur, pVel = HudSync.POP_FROM, HudSync.POP_VEL
	playEntrance()
end)
