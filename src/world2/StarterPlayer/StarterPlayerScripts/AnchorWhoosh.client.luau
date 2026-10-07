-- The pirate anchors (Roads > Pirate Anchors, a copy of World 1's HammerWhoosh): a soft whoosh each time a hammer starts a swing, played on
-- THIS player's machine only, and only while they're within RANGE studs of it. The sound
-- comes from the hammer's head and fades with distance, so it stays subtle.
-- The server's HammerSwing script sets each hammer's "Swinging" attribute to true at the
-- start of every swing; this listens for that. Hammers are picked up whenever they
-- stream in.

local Sfx = require(game:GetService("ReplicatedStorage"):WaitForChild("ObstacleSfx"))   -- obstacle sound effects
local Players = game:GetService("Players")

local SOUND_ID = "rbxassetid://106820392025820"
local VOLUME   = 0.3
local RANGE    = 90

local player  = Players.LocalPlayer
local hammers = workspace:WaitForChild("Roads"):WaitForChild("Pirate Anchors")

local function soundFor(head)
	local s = head:FindFirstChild("Whoosh")
	if not s then
		s = Instance.new("Sound")
		s.Name = "Whoosh"
		s.SoundId = SOUND_ID
		s.Volume = VOLUME
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 10
		s.RollOffMaxDistance = RANGE
		s.Parent = head
	end
	return s
end

local hooked = setmetatable({}, { __mode = "k" })
local function hook(h)
	if hooked[h] or not h:IsA("Model") or not h.Name:match("^Anchor%d") then return end
	hooked[h] = true
	h:GetAttributeChangedSignal("Swinging"):Connect(function()
		if not h:GetAttribute("Swinging") then return end
		local head = h:FindFirstChild("Head")
		local ch = player.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		if head and root and (root.Position - head.Position).Magnitude <= RANGE then
			soundFor(head):Play()
			Sfx.Play("AnchorChain", head)
		end
	end)
	local head = h:FindFirstChild("Head")
	if head then soundFor(head) end   -- load it early so the first whoosh isn't late
end
for _, h in ipairs(hammers:GetChildren()) do hook(h) end
hammers.ChildAdded:Connect(hook)
