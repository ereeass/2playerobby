--=====================================================================
-- FinishCutscene / Fade
--
-- The cutscene's own screen on this machine: a black fade over everything (into and out
-- of the cinematic) and black letterbox bars while it plays. One ScreenGui in PlayerGui
-- above every other screen of the game's, removed when the cutscene ends.
--   fade:To(alpha, seconds)   0 = clear .. 1 = black
--   fade:Bars(on, seconds)    the letterbox bars in / out
--=====================================================================

local TweenService = game:GetService("TweenService")

local Fade = {}
Fade.__index = Fade

local function frame(name, parent, zIndex)
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.ZIndex = zIndex
	f.Parent = parent
	return f
end

-- letterbox: each bar's height as a share of the screen's (0 = no bars)
function Fade.new(playerGui, letterbox)
	local gui = Instance.new("ScreenGui")
	gui.Name = "FinishCutsceneFx"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10000
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local top = frame("BarTop", gui, 1)
	top.Size = UDim2.fromScale(1, 0)
	local bottom = frame("BarBottom", gui, 1)
	bottom.AnchorPoint = Vector2.new(0, 1)
	bottom.Position = UDim2.fromScale(0, 1)
	bottom.Size = UDim2.fromScale(1, 0)
	local black = frame("Black", gui, 2)
	black.Size = UDim2.fromScale(1, 1)
	black.BackgroundTransparency = 1

	gui.Parent = playerGui
	return setmetatable({ Gui = gui, black = black, top = top, bottom = bottom, letterbox = letterbox or 0, tweens = {} }, Fade)
end

function Fade:_tween(obj, seconds, props, style)
	local old = self.tweens[obj]
	if old then old:Cancel() end
	if seconds <= 0 then
		for k, v in pairs(props) do obj[k] = v end
		return
	end
	local tw = TweenService:Create(obj, TweenInfo.new(seconds, style, Enum.EasingDirection.InOut), props)
	self.tweens[obj] = tw
	tw:Play()
end

function Fade:To(alpha, seconds)
	self:_tween(self.black, seconds, { BackgroundTransparency = 1 - alpha }, Enum.EasingStyle.Sine)
end

-- The bars crop the screen to a CINEMA frame (CINEMA wide : 1 high) and no more: a screen
-- already that wide (most phones) gets none, a 16:9 one slim bars, and none ever more than
-- `letterbox` of the height (a tall iPad screen would otherwise lose a third of it).
local CINEMA = 2
local function barShare(max)
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize
	if not vp or vp.X < 1 or vp.Y < 1 then return max end
	return math.clamp((1 - (vp.X / vp.Y) / CINEMA) / 2, 0, max)
end

function Fade:Bars(on, seconds)
	local size = UDim2.fromScale(1, on and barShare(self.letterbox) or 0)
	self:_tween(self.top, seconds, { Size = size }, Enum.EasingStyle.Quad)
	self:_tween(self.bottom, seconds, { Size = size }, Enum.EasingStyle.Quad)
end

function Fade:Destroy()
	for _, tw in pairs(self.tweens) do tw:Cancel() end
	self.Gui:Destroy()
end

return Fade
