-- Swinging spiked-log traps, swung on THIS player's screen. The server
-- (Workspace > Jungle Log Road > Swinging Logs > SwingingLogServer) does the knocking from
-- the same shared clock; this swings each log (and its ropes) about its pivot so it moves
-- smoothly, and plays a soft whoosh as it sweeps through the bottom when you're nearby.
-- Traps are found by their "SwingingLog" tag, whenever they stream in.

local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")

local SOUND_ID = "rbxassetid://106820392025820"
local VOLUME   = 0.3
local RANGE    = 80

local player = Players.LocalPlayer
local traps  = {}

local function add(m)
	if traps[m] or not m:IsA("Model") then return end
	local pivot, swing = m:FindFirstChild("Pivot"), m:FindFirstChild("Swing")
	if not (pivot and swing) then return end
	local parts = {}
	for _, p in ipairs(swing:GetDescendants()) do
		if p:IsA("BasePart") then table.insert(parts, { p, pivot.CFrame:ToObjectSpace(p.CFrame) }) end
	end
	local sound = Instance.new("Sound")
	sound.SoundId = SOUND_ID
	sound.Volume = VOLUME
	sound.PlaybackSpeed = 0.8
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 10
	sound.RollOffMaxDistance = RANGE
	sound.Parent = pivot
	traps[m] = { pivot = pivot, parts = parts, sound = sound, lastSide = nil }
end

for _, m in ipairs(CollectionService:GetTagged("SwingingLog")) do add(m) end
CollectionService:GetInstanceAddedSignal("SwingingLog"):Connect(function(m) task.defer(add, m) end)
CollectionService:GetInstanceRemovedSignal("SwingingLog"):Connect(function(m) traps[m] = nil end)

RunService.RenderStepped:Connect(function()
	local now = workspace:GetServerTimeNow()
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	for m, s in pairs(traps) do
		if not m.Parent or not s.pivot.Parent then traps[m] = nil continue end
		local period = m:GetAttribute("Period") or 3.6
		local amp    = math.rad(m:GetAttribute("SwingDeg") or 55)
		local t      = (now + (m:GetAttribute("Phase") or 0)) % period   -- wrapped: CFrame angles need small numbers
		local a      = amp * math.sin(t / period * math.pi * 2)
		local cf = s.pivot.CFrame * CFrame.Angles(0, 0, a)
		for _, pr in ipairs(s.parts) do pr[1].CFrame = cf * pr[2] end
		-- whoosh each time it swings through the bottom
		local side = a >= 0
		if s.lastSide ~= nil and side ~= s.lastSide and root and (root.Position - s.pivot.Position).Magnitude <= RANGE then
			s.sound:Play()
		end
		s.lastSide = side
	end
end)
