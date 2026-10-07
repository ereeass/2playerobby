-- A small "CHECKPOINT <n>" at the top of the screen over the location's name, big, in its
-- biome's colour (Shared.Checkpoints.Biomes). The server sends it
-- (Remotes.CheckpointUnlocked, from ScooterSystem.CheckpointProgress) only when a checkpoint
-- is genuinely new for THIS player - never for one they already had. Several in a row
-- show one after another.

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RS           = game:GetService("ReplicatedStorage")

local Remotes = RS:WaitForChild("ScooterSystem"):WaitForChild("Remotes")
local player  = Players.LocalPlayer

local HOLD    = 3.5          -- seconds on screen
local TOP     = 14           -- px below the top bar
local FONT    = Font.new("rbxasset://fonts/families/FredokaOne.json")

local gui = Instance.new("ScreenGui")
gui.Name = "CheckpointUnlockPopup"
gui.ResetOnSpawn = false
gui.DisplayOrder = 20
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local holder = Instance.new("Frame")
holder.Name = "Banner"
holder.AnchorPoint = Vector2.new(0.5, 0)
holder.Size = UDim2.fromOffset(560, 104)
holder.Position = UDim2.new(0.5, 0, 0, -130)
holder.BackgroundTransparency = 1
holder.Visible = false
holder.Parent = gui
local scale = Instance.new("UIScale"); scale.Parent = holder

local function label(name, text, y, h, color, stroke)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Position = UDim2.new(0.5, 0, 0, y)
	l.Size = UDim2.new(1, 0, 0, h)
	l.FontFace = FONT
	l.TextScaled = true
	l.Text = text
	l.TextColor3 = color
	l.Parent = holder
	local s = Instance.new("UIStroke"); s.Thickness = stroke; s.Color = Color3.fromRGB(24, 22, 32); s.Parent = l
	return l, s
end
-- small "CHECKPOINT 2" over the big location name ("DUSTY DUNES")
local title, titleStroke = label("Title", "CHECKPOINT", 4, 24, Color3.new(1, 1, 1), 2.5)
local name, nameStroke   = label("Name", "", 28, 74, Color3.new(1, 1, 1), 4)

-- phones get a smaller banner
local function fit()
	local cam = workspace.CurrentCamera
	if cam then scale.Scale = math.clamp(cam.ViewportSize.X / 900, 0.6, 1) end
end
fit()
if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit) end

local function fade(t, time)
	local info = TweenInfo.new(time, Enum.EasingStyle.Quad)
	for _, o in ipairs({ title, name }) do TweenService:Create(o, info, { TextTransparency = t }):Play() end
	for _, o in ipairs({ titleStroke, nameStroke }) do TweenService:Create(o, info, { Transparency = t }):Play() end
end

local queue, showing = {}, false

local function showNext()
	local info = table.remove(queue, 1)
	if not info then showing = false return end
	showing = true
	title.Text = info.Order and ("CHECKPOINT " .. tostring(info.Order)) or "CHECKPOINT"
	name.Text = string.upper(tostring(info.Name or "Checkpoint"))
	name.TextColor3 = typeof(info.Color) == "Color3" and info.Color or Color3.new(1, 1, 1)
	holder.Visible = true
	holder.Position = UDim2.new(0.5, 0, 0, -130)
	fade(1, 0)
	-- drops in with a little overshoot, holds, then lifts away
	TweenService:Create(holder, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0, TOP) }):Play()
	fade(0, 0.3)
	task.delay(0.55 + HOLD, function()
		TweenService:Create(holder, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(0.5, 0, 0, -130) }):Play()
		fade(1, 0.35)
		task.delay(0.45, function()
			holder.Visible = false
			showNext()
		end)
	end)
end

Remotes:WaitForChild("CheckpointUnlocked").OnClientEvent:Connect(function(info)
	if type(info) ~= "table" then return end
	table.insert(queue, info)
	if not showing then showNext() end
end)
