--=====================================================================
-- DonationBoardClient / Celebration
--
-- A confirmed donation: a coin sound and a spray of Robux icons spilling
-- out of the three boards, arcing up and falling away. One
-- ParticleEmitter per board, fired with :Emit in a few quick waves so it
-- spills rather than pops, plus a positional Sound at the Donate board.
-- Everything here exists only on this client.
--=====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("DonationSystem"):WaitForChild("Config"))

local Celebration = {}
Celebration.__index = Celebration

--------------------------------------------------------------------- consts
local TILT     = math.rad(38)          -- spray leans this far above horizontal
local WAVES    = { 1, 0.6, 0.35 }      -- size of each wave, relative to the first
local WAVE_GAP = 0.11                  -- seconds between waves

-- icons in the first wave, per board
local COUNTS = { Last = 10, Top = 16, Donate = 14 }

--------------------------------------------------------------------- pieces
-- Invisible strip across the board's face that the icons spray from,
-- turned so its +Z points out of the board and up.
local function makeStrip(part, axes)
	local ax = axes[part:GetAttribute("Face") or "Back"] or axes.Back
	local cf = part.CFrame
	local right = cf:VectorToWorldSpace(ax.R)
	local out = cf:VectorToWorldSpace(ax.N)
	local width = math.abs(ax.R:Dot(part.Size))
	local depth = math.abs(ax.N:Dot(part.Size))

	local dir = (out * math.cos(TILT) + Vector3.yAxis * math.sin(TILT)).Unit
	local center = cf.Position + out * (depth / 2 + 0.2) + Vector3.yAxis * (part.Size.Y * 0.1)

	local strip = Instance.new("Part")
	strip.Name = "RobuxBurst_" .. part.Name
	strip.Anchored = true
	strip.CanCollide, strip.CanTouch, strip.CanQuery = false, false, false
	strip.CastShadow = false
	strip.Transparency = 1
	strip.Size = Vector3.new(width * 0.8, 0.05, 0.05)
	strip.CFrame = CFrame.fromMatrix(center, right, dir:Cross(right), dir)
	return strip
end

local function makeEmitter(strip)
	local e = Instance.new("ParticleEmitter")
	e.Name = "RobuxIcons"
	e.Texture = Config.RobuxIcon
	e.Rate = 0                                   -- only ever fired by :Emit
	e.EmissionDirection = Enum.NormalId.Back     -- the strip's +Z: out and up
	e.SpreadAngle = Vector2.new(34, 22)
	e.Speed = NumberRange.new(10, 17)
	e.Acceleration = Vector3.new(0, -32, 0)      -- arcs over and falls away
	e.Drag = 0.8
	e.Lifetime = NumberRange.new(1.3, 1.9)
	e.Rotation = NumberRange.new(-180, 180)
	e.RotSpeed = NumberRange.new(-260, 260)
	-- pop in, hold, shrink away at the end
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.07, 0.62, 0.1),
		NumberSequenceKeypoint.new(0.8, 0.5, 0.08),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.75, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.LightEmission = 0.35                       -- a little glow, like the boards
	e.LightInfluence = 0.15
	e.Brightness = 1.4
	e.ZOffset = 0.5                              -- drawn in front of the board it leaves
	e.Parent = strip
	return e
end

local function makeSound(strip)
	local spec = Config.Sounds.Celebration
	local s = Instance.new("Sound")
	s.Name = "SfxCelebration"
	s.SoundId = spec.Id
	s.Volume = spec.Volume
	s.PlaybackSpeed = spec.Speed or 1
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 12
	s.RollOffMaxDistance = 90
	s.Parent = strip
	return s
end

--------------------------------------------------------------------- api
-- parts: { Last, Top, Donate } board parts; axes: HoverLift.Axes
function Celebration.new(parts, axes)
	local self = setmetatable({ Bursts = {} }, Celebration)
	local folder = Instance.new("Folder")
	folder.Name = "DonationBoardFx"
	folder.Parent = workspace

	for key, part in pairs(parts) do
		local strip = makeStrip(part, axes)
		strip.Parent = folder
		table.insert(self.Bursts, { Emitter = makeEmitter(strip), Count = COUNTS[key] or 12 })
		if key == "Donate" then self.Sound = makeSound(strip) end
	end
	return self
end

function Celebration:Play()
	if self.Sound then
		self.Sound.TimePosition = 0
		self.Sound:Play()
	end
	for w, scale in ipairs(WAVES) do
		task.delay((w - 1) * WAVE_GAP, function()
			for _, burst in ipairs(self.Bursts) do
				burst.Emitter:Emit(math.max(1, math.round(burst.Count * scale)))
			end
		end)
	end
end

return Celebration
