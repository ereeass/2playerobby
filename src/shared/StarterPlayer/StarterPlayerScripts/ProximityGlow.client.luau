-- Highlights tagged "ProximityGlow" (the cacti's red DangerGlow on the dusty sand path)
-- are off by default and only switched on, on THIS player's screen, while this player
-- (or the scooter they ride) is within RANGE studs of the thing that glows. Far away
-- they stay off: nobody else's screen is affected, and it keeps well under Roblox's
-- limit on how many highlights can show at once.
-- Per-glow range: a "Range" number attribute on the Highlight overrides RANGE.

local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")

local TAG   = "ProximityGlow"
local RANGE = 90
local CHECK = 0.4

local player = Players.LocalPlayer

local function myPosition()
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local weld = root:FindFirstChild("ScooterRiderWeld")
	return (weld and weld.Part0 and weld.Part0.Position) or root.Position
end

local function targetPosition(h)
	local a = h.Adornee or h.Parent
	if a and a:IsA("Model") then return (a:GetBoundingBox()).Position end
	if a and a:IsA("BasePart") then return a.Position end
	return nil
end

while true do
	local me = myPosition()
	for _, h in ipairs(CollectionService:GetTagged(TAG)) do
		if h:IsA("Highlight") then
			local pos = targetPosition(h)
			local range = h:GetAttribute("Range") or RANGE
			local on = me ~= nil and pos ~= nil and (pos - me).Magnitude <= range
			if h.Enabled ~= on then h.Enabled = on end
		end
	end
	task.wait(CHECK)
end
