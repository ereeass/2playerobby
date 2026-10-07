--=====================================================================
-- SkinFx   (each player's own machine; looks only)
--
-- The moving parts of the scooter skins' looks. Each skin's body faces carry a Texture tagged
-- with its effect and how that face maps the scooter's length (FlowMode U / V / C, FlowSpt,
-- FlowCenter, FlowP, FlowSign - set when the model was built), so one phase moved along makes
-- the pattern travel nose to tail with no seams, at any angle. Works on ridden scooters and on
-- the Skins menu's previews alike.
--   RainbowFlow   the Rainbow Scooter's body rainbow, always flowing
--   GoldShine     the Gold Scooter's light streak, sweeping along the body every few seconds
-- Lights:
--   RainbowGlow   the Rainbow Scooter's underglow cycles through the rainbow
-- Nothing here touches physics or the server: it only moves texture offsets and a light's colour.
--=====================================================================

local CollectionService = game:GetService("CollectionService")
local RunService        = game:GetService("RunService")
local Players           = game:GetService("Players")

local FLOWS = {             -- tag = patterns a second passing any point
	RainbowFlow = 0.42,
	GoldShine   = 0.32,
}
local FAR      = 300        -- studs: a scooter farther than this from the camera isn't animated
local GLOW_SAT = 0.9

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

---------------------------------------------------------------- flowing faces
local faces = {}   -- [Texture] = { mode, spt, center, p, sign, speed, inWorld }

local function add(t, tag)
	if not t:IsA("Texture") or faces[t] then return end
	if not (t:IsDescendantOf(workspace) or t:IsDescendantOf(playerGui)) then return end
	local mode = t:GetAttribute("FlowMode")
	local spt  = t:GetAttribute("FlowSpt")
	if type(mode) ~= "string" or type(spt) ~= "number" or spt <= 0 then return end
	faces[t] = {
		mode = mode, spt = spt,
		center = t:GetAttribute("FlowCenter") or 0,
		p = t:GetAttribute("FlowP") or 0,
		sign = t:GetAttribute("FlowSign") or 1,
		speed = FLOWS[tag],
		inWorld = t:IsDescendantOf(workspace),
		view = t:FindFirstAncestorOfClass("ViewportFrame"),
	}
end
local function remove(t) faces[t] = nil end

for tag in pairs(FLOWS) do
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(t) add(t, tag) end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(remove)
	for _, t in ipairs(CollectionService:GetTagged(tag)) do add(t, tag) end
end
playerGui.DescendantAdded:Connect(function(d)
	if not d:IsA("Texture") then return end
	for tag in pairs(FLOWS) do
		if CollectionService:HasTag(d, tag) then add(d, tag) end
	end
end)

---------------------------------------------------------------- lights
local lights = {}  -- [PointLight] = true
local function watchLight(d)
	if d:IsA("PointLight") and d.Name == "RainbowGlow" then lights[d] = true end
end
local scooters = workspace:WaitForChild("RideSystem"):WaitForChild("Scooters")
scooters.DescendantAdded:Connect(watchLight)
for _, d in ipairs(scooters:GetDescendants()) do watchLight(d) end

---------------------------------------------------------------- every frame
local function frac(x) return x - math.floor(x) end

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position

	for t, f in pairs(faces) do
		if not t.Parent then
			faces[t] = nil
		else
			local near = not (f.view and f.view:GetAttribute("Still"))
			if near and f.inWorld and camPos then
				local part = t.Parent
				near = part:IsA("BasePart") and (part.Position - camPos).Magnitude < FAR
			end
			if near then
				local phase = frac(now * f.speed)
				local off = f.spt * frac(f.sign * (f.p + phase)) - f.center
				if f.mode == "V" then t.OffsetStudsV = off else t.OffsetStudsU = off end
			end
		end
	end

	local glow = Color3.fromHSV(1 - frac(now * FLOWS.RainbowFlow), GLOW_SAT, 1)
	for l in pairs(lights) do
		if l.Parent then l.Color = glow else lights[l] = nil end
	end
end)
