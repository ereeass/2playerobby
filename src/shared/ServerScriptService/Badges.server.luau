--=====================================================================
-- Badges   (server; the same script in every world)
--
--   Welcome!            just for joining (any world)
--   World 1 Completed!  crossing World 1's finish line
--   World 2 Completed!  crossing World 2's finish line
-- A finish is saved for good by WorldUnlock as the player's BeatWorld1 / BeatWorld2 attribute
-- (loaded from their save when they join), so the badge is given the moment that turns true -
-- and anyone who beat a world BEFORE badges existed gets it next time they join that world.
-- Never awarded twice (UserHasBadgeAsync first); a failed award (Roblox busy) is retried.
--=====================================================================

local Players      = game:GetService("Players")
local BadgeService = game:GetService("BadgeService")

local WELCOME = 4159524524379545
local FOR_UNLOCK = {                 -- WorldUnlock's saved key -> its badge
	BeatWorld1 = 2442153563445221,   -- World 1 Completed!
	BeatWorld2 = 4367923755592612,   -- World 2 Completed!
}

local busy = {}   -- ["userId:badgeId"] = true while it's being given

local function award(player, badgeId)
	local key = player.UserId .. ":" .. badgeId
	if busy[key] then return end
	busy[key] = true
	task.spawn(function()
		for attempt = 1, 4 do
			if player.Parent ~= Players then break end
			local okHas, has = pcall(BadgeService.UserHasBadgeAsync, BadgeService, player.UserId, badgeId)
			if okHas and has then break end
			if okHas then
				local ok, err = pcall(BadgeService.AwardBadge, BadgeService, player.UserId, badgeId)
				if ok then
					print(("[Badges] gave %s badge %d"):format(player.Name, badgeId))
					break
				end
				warn(("[Badges] couldn't give %s badge %d (try %d): %s"):format(player.Name, badgeId, attempt, tostring(err)))
			end
			task.wait(attempt * 3)
		end
		busy[key] = nil
	end)
end

local function onPlayer(player)
	award(player, WELCOME)
	for attr, badgeId in pairs(FOR_UNLOCK) do
		if player:GetAttribute(attr) == true then award(player, badgeId) end
		player:GetAttributeChangedSignal(attr):Connect(function()
			if player:GetAttribute(attr) == true then award(player, badgeId) end
		end)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(onPlayer, p) end
Players.PlayerRemoving:Connect(function(player)
	for key in pairs(busy) do
		if key:sub(1, #tostring(player.UserId) + 1) == player.UserId .. ":" then busy[key] = nil end
	end
end)
