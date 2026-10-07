--=====================================================================
-- GiftedSkins   (ScooterSystem, server)
--
-- Skins given to named players for good: when one of them joins, each skin listed for them
-- is granted through the Skins system's own ScooterSelection.GrantSkin (saved to their
-- OwnedScooters, so it stays theirs even if this list is later emptied). Owning it already
-- changes nothing. Add a player: their UserId and the skin Ids (Shared.Scooters).
--=====================================================================

local Players = game:GetService("Players")

local ScooterSelection = require(script.Parent:WaitForChild("ScooterSelection"))

local GIFTS = {
	[7415418006] = { "Rainbow" },   -- Ereeass
	[476180958]  = { "Rainbow" },   -- Vexerixx
}

local function give(player)
	local skins = GIFTS[player.UserId]
	if not skins then return end
	for _, id in ipairs(skins) do
		-- their Skins session loads a moment after joining: keep trying for a minute
		local t0 = os.clock()
		while player.Parent == Players and os.clock() - t0 < 60 do
			local ok, given, isNew = pcall(ScooterSelection.GrantSkin, player, id)
			if ok and given then
				if isNew then print(("[GiftedSkins] gave %s the %s scooter"):format(player.Name, id)) end
				break
			end
			task.wait(2)
		end
	end
end

Players.PlayerAdded:Connect(function(p) task.spawn(give, p) end)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(give, p) end
