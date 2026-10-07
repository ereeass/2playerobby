-- The checkpoint selector's pictures (Shared.Checkpoints' Image), fetched as the game loads
-- instead of the first time the selector opens: each one is a near-invisible 1 px image kept
-- on screen here, so the loading screen (it preloads everything in PlayerGui) downloads it
-- and it stays ready. The cards then show their picture straight away.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider   = game:GetService("ContentProvider")

local gui = script.Parent
local ok, list = pcall(function()
	return require(ReplicatedStorage:WaitForChild("ScooterSystem"):WaitForChild("Shared"):WaitForChild("Checkpoints"))
end)
if not ok or type(list) ~= "table" then return end

local images = {}
local function scan(t, depth)
	if depth > 3 or type(t) ~= "table" then return end
	for _, v in pairs(t) do
		if type(v) == "table" then
			if type(v.Image) == "string" and v.Image:find("^rbxassetid://%d+") then
				local img = Instance.new("ImageLabel")
				img.Name = "Checkpoint" .. tostring(v.Order or #images + 1)
				img.Image = v.Image
				img.BackgroundTransparency = 1
				img.ImageTransparency = 0.99      -- drawn (so it stays loaded), but never seen
				img.Size = UDim2.fromOffset(1, 1)
				img.Parent = gui
				table.insert(images, img)
			else
				scan(v, depth + 1)
			end
		end
	end
end
scan(list, 0)
if #images > 0 then task.spawn(function() pcall(ContentProvider.PreloadAsync, ContentProvider, images) end) end
