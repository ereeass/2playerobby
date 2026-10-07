--=====================================================================
-- GateSign   (server, both worlds)
--
-- Dresses the red see-through gate at the end of the lobby (Workspace.Map.Mountains.Rock):
-- diagonal stripes, the linked-chains icon and "Pair with someone to continue!" - on the
-- side facing the lobby ONLY (the face pointing at Workspace.LobbySpawnArea.SpawnLocation).
-- The gate itself is never changed: same part, colour, transparency and collision, and
-- its other side looks exactly as before. It is one SurfaceGui in the part, so it streams
-- in and out with it.
--=====================================================================

local TEXT  = "Pair with someone to continue!"
local ICON  = 126339967729074      -- the linked chains (decal)
local FONT  = Font.new("rbxasset://fonts/families/FredokaOne.json")

local PIXELS_PER_STUD = 50
local STRIPE_WIDTH    = 1.3         -- studs, each light stripe
local STRIPE_GAP      = 0.9         -- studs of the gate's own red between them
local STRIPE_COLOR    = Color3.fromRGB(255, 120, 120)
local STRIPE_SEE      = 0.5         -- how see-through the stripes are (0 solid .. 1 invisible)

local function findGate()
	local map = workspace:WaitForChild("Map", 60)
	local mountains = map and map:WaitForChild("Mountains", 60)
	local gate = mountains and mountains:WaitForChild("Rock", 60)
	return (gate and gate:IsA("BasePart")) and gate or nil
end

-- the gate's big face that looks towards the lobby (its thinnest axis, the lobby's side)
local function lobbyFace(gate)
	local size = gate.Size
	local spawnArea = workspace:FindFirstChild("LobbySpawnArea")
	local spawn = spawnArea and spawnArea:FindFirstChildWhichIsA("SpawnLocation", true)
	local rel = spawn and gate.CFrame:PointToObjectSpace(spawn.Position) or Vector3.new(0, 0, -1)
	if size.X <= size.Y and size.X <= size.Z then
		return rel.X >= 0 and Enum.NormalId.Right or Enum.NormalId.Left, Vector2.new(size.Z, size.Y)
	elseif size.Y <= size.Z then
		return rel.Y >= 0 and Enum.NormalId.Top or Enum.NormalId.Bottom, Vector2.new(size.X, size.Z)
	end
	return rel.Z < 0 and Enum.NormalId.Front or Enum.NormalId.Back, Vector2.new(size.X, size.Y)
end

local function build(gate)
	local old = gate:FindFirstChild("GateSign")
	if old then old:Destroy() end
	local face, studs = lobbyFace(gate)
	local w, h = studs.X * PIXELS_PER_STUD, studs.Y * PIXELS_PER_STUD

	local sign = Instance.new("SurfaceGui")
	sign.Name = "GateSign"
	sign.Face = face
	sign.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sign.PixelsPerStud = PIXELS_PER_STUD
	sign.LightInfluence = 0
	sign.ClipsDescendants = true

	-- the stripes: long thin bars at 45 degrees, clipped to the gate
	local stripes = Instance.new("Frame")
	stripes.Name = "Stripes"
	stripes.Size = UDim2.fromScale(1, 1)
	stripes.BackgroundTransparency = 1
	stripes.ClipsDescendants = true
	stripes.Parent = sign
	local period = (STRIPE_WIDTH + STRIPE_GAP) * PIXELS_PER_STUD * math.sqrt(2)   -- along the width
	local length = (w + h) * 3
	local x = -h
	while x < w + h do
		-- Roblox skips drawing a frame whose UNROTATED box lies off the gate, so every bar's
		-- centre is slid along its own line until it sits over the gate (the corners would
		-- otherwise go bare): Rotation 45 leans it "/", up-right is (+1, -1)
		local cx, cy = x, h / 2
		if cx < 0 then
			cx, cy = 0, h / 2 + x
		elseif cx > w then
			cx, cy = w, h / 2 + (x - w)
		end
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromOffset(cx, cy)
		bar.Size = UDim2.fromOffset(STRIPE_WIDTH * PIXELS_PER_STUD, length)
		bar.Rotation = 45
		bar.BorderSizePixel = 0
		bar.BackgroundColor3 = STRIPE_COLOR
		bar.BackgroundTransparency = STRIPE_SEE
		bar.Parent = stripes
		x += period
	end

	-- the icon, a little above the middle (icon and words sit together round the centre)
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.3)
	icon.Size = UDim2.fromScale(0.26, 0.26)
	icon.BackgroundTransparency = 1
	icon.Image = ("rbxthumb://type=Asset&id=%d&w=420&h=420"):format(ICON)   -- works for a decal id
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = 2
	local square = Instance.new("UIAspectRatioConstraint")
	square.AspectRatio = 1
	square.Parent = icon
	icon.Parent = sign

	-- the words, below it: kept well inside the gate's edges, white with a dark outline
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.fromScale(0.5, 0.45)
	label.Size = UDim2.fromScale(0.8, 0.26)
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	label.Text = TEXT
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.TextWrapped = true
	label.ZIndex = 2
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = math.floor(h * 0.12)
	limit.Parent = label
	local outline = Instance.new("UIStroke")
	outline.Color = Color3.fromRGB(40, 0, 0)
	outline.Thickness = math.max(2, math.floor(PIXELS_PER_STUD / 12))
	outline.LineJoinMode = Enum.LineJoinMode.Round
	outline.Parent = label
	label.Parent = sign

	sign.Adornee = gate
	sign.Parent = gate
end

local gate = findGate()
if gate then
	build(gate)
else
	warn("[GateSign] Workspace.Map.Mountains.Rock not found: the gate isn't dressed")
end
