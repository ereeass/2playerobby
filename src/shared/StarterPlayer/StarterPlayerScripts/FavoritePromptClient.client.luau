-- FavoritePromptClient: shows Roblox's "Favorite this experience?" prompt when the server
-- says so (ServerScriptService.FavoritePrompt decides when: once per player, ever).
local AvatarEditorService = game:GetService("AvatarEditorService")
local RS = game:GetService("ReplicatedStorage")

local remote = RS:WaitForChild("ScooterSystem"):WaitForChild("Remotes"):WaitForChild("FavoritePrompt")
remote.OnClientEvent:Connect(function()
	local ok, err = pcall(AvatarEditorService.PromptSetFavorite, AvatarEditorService, game.PlaceId, Enum.AvatarItemType.Asset, true)
	if not ok then warn("[Favorite] couldn't show the prompt:", err) end
end)
