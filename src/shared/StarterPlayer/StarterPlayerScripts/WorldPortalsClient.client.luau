-- WorldPortalsClient   (StarterPlayerScripts)
--
-- For every portal tagged "WorldPortal": the E prompt always shows and the old
-- "Beat This World To Unlock World 2" sign never does. Pressing E before beating World 1
-- (the Player attribute BeatWorld1) shows the red notice at the bottom instead - the server
-- (the portal's PortalTeleport) checks and says so.

local Players           = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local KEY    = "BeatWorld1"
local TAG    = "WorldPortal"

local function apply(portal)
	local open = player:GetAttribute(KEY) == true
	local trigger = portal:FindFirstChild("PortalTrigger")
	local prompt = trigger and trigger:FindFirstChild("WorldPrompt")
	if prompt then prompt.Enabled = true end   -- always: pressing it while locked shows the red notice (the server)
	local label = portal:FindFirstChild("LockLabel")
	local gui = label and label:FindFirstChild("LockGui")
	if gui then gui.Enabled = false end        -- no lock sign: the notice says it instead
end

local function watch(portal)
	apply(portal)
	-- with streaming, the prompt or sign may arrive after the model
	portal.DescendantAdded:Connect(function(d)
		if d.Name == "WorldPrompt" or d.Name == "LockGui" or d.Name == "LockLabel" then apply(portal) end
	end)
end

for _, portal in ipairs(CollectionService:GetTagged(TAG)) do watch(portal) end
CollectionService:GetInstanceAddedSignal(TAG):Connect(watch)

player:GetAttributeChangedSignal(KEY):Connect(function()
	for _, portal in ipairs(CollectionService:GetTagged(TAG)) do apply(portal) end
end)
