--=====================================================================
-- CountBadge   (ReplicatedStorage.UITemplates)
--
-- The red count on a button's top-right corner: how many of an item this player owns -
-- saved Skip Stages, saved revives, and any item added later (login rewards, ...). Every
-- button gets the same badge, this module's Badge (the Skip Stage button's own), so they
-- all look and behave alike:
--   Shows    the count, "99+" past 99; hidden at 0
--   Follows  a number attribute on the local player that the SERVER keeps (SkipCredits,
--            ReviveCredits, ...) - how many anyone owns is never decided here
--   Sits     over the button's top-right corner, above everything else on it, and grows,
--            shrinks and fades with the button
--
--   local CountBadge = require(ReplicatedStorage.UITemplates.CountBadge)
--   CountBadge.Attach(button, "ReviveCredits")   -- returns the badge
--
-- A new item: the server keeps a count attribute on each player for it, and its button
-- calls Attach with that attribute's name. Restyling Badge here restyles every button.
--=====================================================================

local Players = game:GetService("Players")

local template = script:WaitForChild("Badge")

local CountBadge = {}

-- how a count reads on the badge
function CountBadge.Text(n)
	return n > 99 and "99+" or tostring(n)
end

-- the badge on `button`, showing the local player's `attr`
function CountBadge.Attach(button, attr)
	local player = Players.LocalPlayer
	local badge  = template:Clone()
	local count  = badge:WaitForChild("Count")
	-- above everything else on the button
	local top = 0
	for _, c in ipairs(button:GetChildren()) do
		if c:IsA("GuiObject") then top = math.max(top, c.ZIndex) end
	end
	badge.ZIndex  = math.max(badge.ZIndex, top + 1)
	count.ZIndex  = badge.ZIndex + 1
	badge.Visible = false
	badge.Parent  = button

	local function refresh()
		local n = math.max(math.floor(tonumber(player:GetAttribute(attr)) or 0), 0)
		badge.Visible = n > 0
		local text = CountBadge.Text(n)
		if count.Text ~= text then count.Text = text end
	end
	local conn = player:GetAttributeChangedSignal(attr):Connect(refresh)
	badge.Destroying:Connect(function() conn:Disconnect() end)
	refresh()
	return badge
end

return CountBadge
