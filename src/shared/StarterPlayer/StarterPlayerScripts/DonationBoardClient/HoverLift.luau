--=====================================================================
-- DonationBoardClient / HoverLift
--
-- The 3D pop-out. A SurfaceGui has no per-element depth, so a hovered
-- widget is lifted onto real geometry in front of the board:
--   * its Face is cloned onto a thin invisible "carrier" part laid
--     exactly over it (same pixels, so the hand-over cannot be seen),
--   * a glowing slab fills the gap between carrier and board, so from an
--     angle you see side walls instead of a floating sticker,
--   * the slot it left shows a dark Socket, the hole it came out of.
-- TweenService drives one NumberValue per lift (0 = flush, 1 = out).
-- Every frame the parts are rebuilt from that value and the widget's
-- CURRENT rect, so a lifted row keeps tracking its list while it scrolls.
--
-- Hover is hit-tested here (ray against the board plane) rather than
-- with MouseEnter/MouseLeave: the lifted parts sit in front of the board
-- and would steal those events, and the maths cannot miss a leave.
--
-- Every frame each lift is steered towards where it SHOULD be (held,
-- hovered or home), replacing its one tween when that changes, and a lift
-- that has arrived home is removed on the spot. Nothing waits on
-- Tween.Completed, so however fast the cursor sweeps across the buttons,
-- a button it has left always returns to normal.
--=====================================================================

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local GuiService        = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("DonationSystem"):WaitForChild("Config"))

local player = Players.LocalPlayer

local HoverLift = {}

--------------------------------------------------------------------- consts
local DESIGN_PPS = 50        -- layout units per stud (see BoardUI)
local FACE_T     = 0.02      -- thickness of the carrier part the face rides on
local FACE_GAP   = 0.004     -- keeps the carrier just proud of the board, no z-fighting
local MARGIN     = 8         -- layout px kept around a widget so its rim and halo are not clipped
local PRESS      = 0.35      -- lift fraction while held: the button sinks back in
local GLOW       = 0.22      -- extra brightness at full lift
local TAP_SLOP   = 12        -- px a touch may travel before it counts as a scroll
local UP_FRAMES  = 3         -- frames the mouse must read as released before a lost release is assumed
local POINTER    = "rbxasset://SystemCursors/PointingHand"

-- canvas axes for each vertical face: R = canvas +x, N = outward normal
local AXES = {
	Back  = { R =  Vector3.xAxis, N =  Vector3.zAxis },
	Front = { R = -Vector3.xAxis, N = -Vector3.zAxis },
	Right = { R = -Vector3.zAxis, N =  Vector3.xAxis },
	Left  = { R =  Vector3.zAxis, N = -Vector3.xAxis },
}

--------------------------------------------------------------------- state
local boards  = {}
local active  = {}          -- item -> lift record
local hovered = nil
local pressed = nil
local pressedByMouse = false
local upFrames = 0
local touch   = nil         -- { Input, Start } while a finger is down on a widget
local iconSet = false
local lastPlayed = {}       -- sound -> os.clock() of its last play
local suspended = false     -- a Roblox prompt owns the screen; the cursor we see is stale
local liftFolder, ignoreRoot
local alsoIgnore = {}         -- other board models (HoverLift.AddIgnore)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

--------------------------------------------------------------------- geometry
local function absVec(v)
	return Vector3.new(math.abs(v.X), math.abs(v.Y), math.abs(v.Z))
end

-- canvas pixel (px, py), pushed `off` studs out from the face -> part space
local function localPoint(b, px, py, off)
	return b.R * (px / b.PPS - b.W / 2)
		+ Vector3.yAxis * (b.H / 2 - py / b.PPS)
		+ b.N * (b.D / 2 + off)
end

-- ray -> canvas pixel on board b, plus distance along the ray
local function project(b, origin, dir)
	local cf = b.Part.CFrame
	local n = cf:VectorToWorldSpace(b.N)
	local denom = dir:Dot(n)
	if denom > -1e-3 then return nil end          -- from behind, or edge-on
	local t = (cf:PointToWorldSpace(b.N * (b.D / 2)) - origin):Dot(n) / denom
	if t <= 0 then return nil end
	local lp = cf:PointToObjectSpace(origin + dir * t)
	local px = (lp:Dot(b.R) + b.W / 2) * b.PPS
	local py = (b.H / 2 - lp.Y) * b.PPS
	if px < 0 or py < 0 or px > b.W * b.PPS or py > b.H * b.PPS then return nil end
	return px, py, t
end

local function contains(g, x, y)
	local p, s = g.AbsolutePosition, g.AbsoluteSize
	return x >= p.X and y >= p.Y and x < p.X + s.X and y < p.Y + s.Y
end

local function shown(g, stop)
	while g and g ~= stop do
		if g:IsA("GuiObject") and not g.Visible then return false end
		g = g.Parent
	end
	return g == stop
end

--------------------------------------------------------------------- occlusion
-- Something solid between the camera and the board?
local function blocked(origin, target)
	local filter = { ignoreRoot, liftFolder }
	for _, inst in ipairs(alsoIgnore) do table.insert(filter, inst) end
	if player.Character then table.insert(filter, player.Character) end
	rayParams.FilterDescendantsInstances = filter
	local dir = target - origin
	for _ = 1, 4 do
		local hit = workspace:Raycast(origin, dir, rayParams)
		if not hit then return false end
		if hit.Instance.Transparency < 0.9 then return true end
		rayParams:AddToFilter(hit.Instance)         -- see-through: look past it
	end
	return false
end

-- A visible 2D button or panel on top of the board at this screen point?
local function overScreenUi(x, y)
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then return false end
	for _, g in ipairs(pg:GetGuiObjectsAtPosition(x, y)) do
		local layer = g:FindFirstAncestorWhichIsA("LayerCollector")
		if layer and layer:IsA("ScreenGui") and layer.Enabled and g.Visible then
			if g:IsA("GuiButton") or g.BackgroundTransparency < 0.9
				or (g:IsA("ImageLabel") and g.ImageTransparency < 0.9) then
				return true
			end
		end
	end
	return false
end

-- screen point (GUI space, top-bar inset removed) -> widget under it
local function pick(x, y)
	if GuiService.MenuIsOpen then return nil end
	local cam = workspace.CurrentCamera
	if not cam then return nil end
	local ray = cam:ScreenPointToRay(x, y)

	local best, bx, by, bt
	for _, b in ipairs(boards) do
		local px, py, t = project(b, ray.Origin, ray.Direction)
		if px and t <= Config.InteractDistance and (not bt or t < bt) then
			best, bx, by, bt = b, px, py, t
		end
	end
	if not best then return nil end
	if overScreenUi(x, y) then return nil end
	if blocked(ray.Origin, ray.Origin + ray.Direction * bt) then return nil end

	for i = #best.Items, 1, -1 do
		local it = best.Items[i]
		if it.Enabled and contains(it.Holder, bx, by)
			and (not it.Viewport or contains(it.Viewport, bx, by))
			and shown(it.Holder, best.Gui) then
			return it
		end
	end
	return nil
end

--------------------------------------------------------------------- lift parts
local function makePart(name)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide, p.CanTouch, p.CanQuery = false, false, false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Size = Vector3.one * 0.05
	return p
end

local function cloneFace(item, rec)
	if rec.Clone then rec.Clone:Destroy() end
	local c = item.Face:Clone()
	c.Visible = true
	c.AnchorPoint = Vector2.zero
	c.Parent = rec.Root
	rec.Clone = c
	rec.Edge = c:FindFirstChild("Edge")
	rec.EdgeBase = rec.Edge and rec.Edge.Color
	rec.FillBase = c.BackgroundTransparency
	-- side walls glow in the widget's own colour, so the extrusion reads as the same object
	rec.Slab.Color = item.Face.BackgroundColor3
end

local function createLift(item)
	local b = item.Board
	local rec = { Value = Instance.new("NumberValue"), Target = 0 }

	rec.Slab = makePart("Slab")
	rec.Slab.Material = Enum.Material.Neon
	rec.Slab.Transparency = 1
	rec.Carrier = makePart("Carrier")
	rec.Carrier.Transparency = 1

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Lifted"
	gui.Face = b.Gui.Face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.LightInfluence = b.Gui.LightInfluence
	gui.Brightness = b.Gui.Brightness
	gui.MaxDistance = b.Gui.MaxDistance
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = rec.Carrier

	-- same layout units as the board, so the clone renders pixel-identical
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.ClipsDescendants = true
	root.Size = UDim2.fromScale(1 / b.Scale, 1 / b.Scale)
	local scale = Instance.new("UIScale")
	scale.Scale = b.Scale
	scale.Parent = root
	root.Parent = gui

	rec.Gui, rec.Root = gui, root
	cloneFace(item, rec)
	rec.Slab.Parent = liftFolder
	rec.Carrier.Parent = liftFolder
	return rec
end

local function drop(item)
	local rec = active[item]
	if not rec then return end
	active[item] = nil
	if rec.Tween then rec.Tween:Cancel() end
	rec.Carrier:Destroy()
	rec.Slab:Destroy()
	rec.Value:Destroy()
	item.Face.Visible = true
	item.Socket.Visible = false
	item.Socket.BackgroundTransparency = item.SocketBase
end

-- Rebuilds the lifted geometry from the tween value and the live rect.
local function place(item, rec)
	local b = item.Board
	local holder = item.Holder
	if not shown(holder, b.Gui) then
		drop(item)
		return
	end

	local p, s = holder.AbsolutePosition, holder.AbsoluteSize
	local m = Vector2.one * (MARGIN * b.Scale)
	local lo, hi = p, p + s                 -- the widget body
	local clo, chi = p - m, p + s + m       -- body plus room for its outline
	local vp = item.Viewport
	if vp then
		local vlo = vp.AbsolutePosition
		local vhi = vlo + vp.AbsoluteSize
		lo, hi = lo:Max(vlo), hi:Min(vhi)
		clo, chi = clo:Max(vlo), chi:Min(vhi)
	end
	local body, canvas = hi - lo, chi - clo
	if body.X < 1 or body.Y < 1 then
		-- scrolled out of its window: nothing to show
		rec.Gui.Enabled = false
		rec.Slab.Transparency = 1
		return
	end
	rec.Gui.Enabled = true

	local a = rec.Value.Value
	local k = 1 + Config.HoverScale * a
	local depth = Config.HoverDistance * item.Depth * a
	local cf, pps = b.Part.CFrame, b.PPS

	local cc = (clo + chi) * 0.5
	rec.Carrier.Size = b.RAbs * (canvas.X / pps * k) + Vector3.yAxis * (canvas.Y / pps * k) + b.NAbs * FACE_T
	rec.Carrier.CFrame = cf * CFrame.new(localPoint(b, cc.X, cc.Y, depth + FACE_GAP + FACE_T / 2))
	if rec.Gui.CanvasSize ~= canvas then rec.Gui.CanvasSize = canvas end
	rec.Clone.Position = UDim2.fromScale((p.X - clo.X) / canvas.X, (p.Y - clo.Y) / canvas.Y)
	rec.Clone.Size = UDim2.fromScale(s.X / canvas.X, s.Y / canvas.Y)

	local bc = (lo + hi) * 0.5
	local inset = item.Inset
	rec.Slab.Size = b.RAbs * math.max(body.X / pps * k - 2 * inset, 0.01)
		+ Vector3.yAxis * math.max(body.Y / pps * k - 2 * inset, 0.01)
		+ b.NAbs * math.max(depth, 0.001)
	rec.Slab.CFrame = cf * CFrame.new(localPoint(b, bc.X, bc.Y, depth / 2))
	rec.Slab.Transparency = (depth < 0.01) and 1 or 0.35

	-- The widget fills in as it rises, so it reads as lighting up, not as
	-- see-through. The socket fades with the lift: near flush it is gone, so a
	-- settling button already looks like its normal self instead of dark.
	local lit = math.clamp(a, 0, 1)
	rec.Clone.BackgroundTransparency = rec.FillBase * (1 - 0.6 * lit)
	item.Socket.BackgroundTransparency = 1 - (1 - item.SocketBase) * lit
	rec.Gui.Brightness = b.Gui.Brightness * (1 + GLOW * a)
	if rec.Edge then
		rec.Edge.Color = rec.EdgeBase:Lerp(Color3.new(1, 1, 1), 0.4 * lit)
	end
end

--------------------------------------------------------------------- tweening
-- One tween per lift: a new target cancels and replaces the old tween, so
-- two tweens can never fight over the same button.
local function tweenTo(rec, target, time, style)
	rec.Target = target
	if rec.Tween then rec.Tween:Cancel() end
	rec.Tween = TweenService:Create(rec.Value,
		TweenInfo.new(time, style, Enum.EasingDirection.Out), { Value = target })
	rec.Tween:Play()
end

-- Where a widget's lift belongs right now.
local function wanted(item)
	if item == pressed then return PRESS end
	if item == hovered then return 1 end
	return 0
end

-- Points a widget's lift at where it belongs, creating the lift if needed.
-- Safe to call any number of times: it only retargets on a real change.
local function steer(item)
	local want = wanted(item)
	local rec = active[item]
	if not rec then
		if want == 0 then return end
		rec = createLift(item)
		active[item] = rec
		item.Face.Visible = false
		item.Socket.Visible = true
		place(item, rec)
	end
	if rec.Target == want then return end
	if want == PRESS then
		tweenTo(rec, PRESS, 0.06, Enum.EasingStyle.Quad)
	elseif want == 1 then
		-- Back easing overshoots a touch, which is what makes it feel physical
		tweenTo(rec, 1, (rec.Target == PRESS) and 0.14 or Config.HoverTweenTime, Enum.EasingStyle.Back)
	else
		tweenTo(rec, 0, Config.HoverOutTime, Enum.EasingStyle.Quad)
	end
end

local function playSound(sound)
	if not sound then return end
	local now = os.clock()
	-- sweeping across a long list must not turn into a machine-gun of ticks
	if now - (lastPlayed[sound] or 0) < (sound:GetAttribute("MinGap") or 0) then return end
	lastPlayed[sound] = now
	sound.TimePosition = 0
	sound:Play()
end

local function setHovered(item)
	if item == hovered then return end
	local old = hovered
	hovered = item
	-- sliding off a held button cancels the press, like any normal button
	if pressed and pressed ~= item then pressed = nil end
	if old then steer(old) end
	if item then
		steer(item)
		playSound(item.HoverSound)              -- once on entry, never while resting on it
	end

	local wantIcon = item ~= nil and item.OnClick ~= nil
	if wantIcon ~= iconSet then
		UserInputService.MouseIcon = wantIcon and POINTER or ""
		iconSet = wantIcon
	end
end

local function fire(item)
	playSound(item.ClickSound)
	if item.OnClick then task.spawn(item.OnClick, item) end
end

--------------------------------------------------------------------- api
HoverLift.Axes = AXES

-- Registers a board face. Returns the board record BoardUI lays out on.
function HoverLift.AddBoard(part, face, gui, scale)
	local ax = AXES[face.Name] or AXES.Back
	local size = part.Size
	local b = {
		Part  = part,
		Gui   = gui,
		Scale = scale,                   -- canvas px per layout px
		PPS   = gui.PixelsPerStud,
		R = ax.R, N = ax.N,
		RAbs = absVec(ax.R), NAbs = absVec(ax.N),
		W = math.abs(ax.R:Dot(size)),    -- face width, studs
		H = size.Y,
		D = math.abs(ax.N:Dot(size)),    -- part thickness, studs
		Items = {},
	}
	table.insert(boards, b)
	return b
end

-- item fields:
--   Holder, Face, Socket  the widget (see BoardUI)
--   Depth     multiplier on Config.HoverDistance
--   Viewport  ScrollingFrame the widget lives in, if any (clips the lift)
--   OnClick   function(item), or nil for hover-only
--   Enabled   false for empty slots
--   HoverSound, ClickSound   optional Sounds (a "MinGap" attribute throttles repeats)
function HoverLift.AddItem(board, item)
	item.Board = board
	if item.Enabled == nil then item.Enabled = true end
	item.SocketBase = item.Socket.BackgroundTransparency
	-- pull the slab in from the rounded corners so it hides behind the face
	local corner = item.Face:FindFirstChildOfClass("UICorner")
	local radius = corner and corner.CornerRadius.Offset or 0
	item.Inset = 0.3 * radius / DESIGN_PPS
	table.insert(board.Items, item)
	return item
end

-- The widget's content changed: refresh a lifted copy in place, no re-pop.
function HoverLift.ContentChanged(item)
	if not item.Enabled then
		-- slot emptied under the cursor: release it (and the pointer icon) at once
		if pressed == item then pressed = nil end
		if hovered == item then setHovered(nil) end
		drop(item)
		return
	end
	local rec = active[item]
	if rec then cloneFace(item, rec) end
end

-- While a purchase prompt is open the game stops seeing the cursor, so the
-- button that opened it would otherwise stay lifted behind the prompt.
function HoverLift.SetSuspended(on)
	suspended = on
end

-- another board's model: its own parts never count as something in front of it
function HoverLift.AddIgnore(inst)
	table.insert(alsoIgnore, inst)
end

function HoverLift.Start(ignore)
	ignoreRoot = ignore
	liftFolder = Instance.new("Folder")
	liftFolder.Name = "DonationBoardLifts"
	liftFolder.Parent = workspace

	RunService.RenderStepped:Connect(function()
		-- a release we never heard about (focus lost, a prompt opened) must not pin a button down
		if pressed and pressedByMouse then
			if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
				upFrames = 0
			else
				upFrames += 1
				if upFrames >= UP_FRAMES then pressed = nil end
			end
		end

		if suspended then
			pressed = nil
			setHovered(nil)
		-- mouse hover, unless the player is on touch (no cursor to follow)
		elseif not touch and UserInputService:GetLastInputType() ~= Enum.UserInputType.Touch then
			local item
			if UserInputService.MouseEnabled then
				local m = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
				item = pick(m.X, m.Y)
			end
			setHovered(item)
		end

		-- steer every lift to where it belongs, and retire the ones that are home
		for item, rec in pairs(active) do
			steer(item)
			if rec.Target == 0 and rec.Value.Value <= 1e-3 then
				drop(item)
			else
				place(item, rec)
			end
		end
	end)

	UserInputService.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 then
			if hovered and hovered.OnClick then
				pressed, pressedByMouse, upFrames = hovered, true, 0
				steer(hovered)
			end
		elseif kind == Enum.UserInputType.Touch and not touch then
			local item = pick(input.Position.X, input.Position.Y)
			if item then
				touch = { Input = input, Start = input.Position }
				setHovered(item)
				if item.OnClick then
					pressed, pressedByMouse = item, false
					steer(item)
				end
			end
		end
	end)

	-- a finger that travels is scrolling the list, not tapping a row
	UserInputService.InputChanged:Connect(function(input)
		if touch and input == touch.Input
			and (input.Position - touch.Start).Magnitude > TAP_SLOP then
			touch = nil
			pressed = nil
			setHovered(nil)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 then
			local item = pressed
			pressed = nil
			if not item then return end
			steer(item)                             -- back up to hover height (or home)
			if item == hovered then fire(item) end
		elseif touch and input == touch.Input then
			local item = pressed
			touch, pressed = nil, nil
			if item then
				steer(item)
				fire(item)
			end
			-- let the tap read as a pop before it settles back
			task.delay(0.2, function()
				if not touch then setHovered(nil) end
			end)
		end
	end)
end

return HoverLift
