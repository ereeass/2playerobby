--=====================================================================
-- View
--
-- Builds the data-driven parts of CheckpointSelectorGui. Explorer holds ONE
-- card (Panel.Content.CardTemplate); it is cloned and filled in here for
-- every checkpoint in the data, so a new checkpoint is only ever a data
-- change. Restyle the cards by editing the template.
--=====================================================================

local View = {}

-- placeholder art (top, bottom colour) for cards whose checkpoint has no Image
View.PALETTE = {
	{ Color3.fromRGB(104, 184, 255), Color3.fromRGB(46, 98, 208) },   -- sky
	{ Color3.fromRGB(96, 216, 150),  Color3.fromRGB(28, 128, 110) },  -- meadow
	{ Color3.fromRGB(255, 188, 84),  Color3.fromRGB(224, 100, 46) },  -- sunset
	{ Color3.fromRGB(180, 136, 255), Color3.fromRGB(90, 58, 198) },   -- dusk
	{ Color3.fromRGB(255, 134, 172), Color3.fromRGB(198, 58, 112) },  -- berry
}

-- each area's own art (sky top, sky bottom, ground), picked by the checkpoint's Biome
-- so every card shows ITS location; a biome not listed falls back to PALETTE
View.BIOME_ART = {
	Town   = { Color3.fromRGB(104, 184, 255), Color3.fromRGB(46, 98, 208),  Color3.fromRGB(110, 200, 90) },  -- Hammer Hills
	Beach  = { Color3.fromRGB(255, 200, 110), Color3.fromRGB(232, 128, 60), Color3.fromRGB(246, 214, 150) }, -- Dusty Dunes
	Snow   = { Color3.fromRGB(176, 222, 255), Color3.fromRGB(88, 140, 214), Color3.fromRGB(240, 248, 255) }, -- Frozen Ruins
	Jungle = { Color3.fromRGB(110, 206, 140), Color3.fromRGB(24, 110, 70),  Color3.fromRGB(40, 120, 50) },   -- Spiked Forest
	Food   = { Color3.fromRGB(255, 150, 196), Color3.fromRGB(198, 70, 140), Color3.fromRGB(255, 226, 240) }, -- Sugar Rush
}
-- plus any biomes this world adds (ReplicatedStorage.WorldConfig.BiomeArt)
do
	local ok, World = pcall(function() return require(game:GetService("ReplicatedStorage"):WaitForChild("WorldConfig")) end)
	for name, art in pairs(ok and World.BiomeArt or {}) do View.BIOME_ART[name] = art end
end

function View.find(gui)
	local window  = gui:WaitForChild("Window")
	local panel   = window:WaitForChild("Panel")
	local content = panel:WaitForChild("Content")
	local actions = content:WaitForChild("Actions")
	return {
		gui = gui, dim = gui:WaitForChild("Dim"), sfx = gui:WaitForChild("Sfx"),
		window = window, winScale = window:WaitForChild("Scale"),
		panelSweep = panel:WaitForChild("Sweep"),
		cloth = panel:WaitForChild("Header"):WaitForChild("Flag"):WaitForChild("Cloth"),
		cards = content:WaitForChild("Cards"), cardTemplate = content:WaitForChild("CardTemplate"),
		actions = actions,
		start = actions:WaitForChild("StartButton"), leave = actions:WaitForChild("LeaveButton"),
	}
end

function View.nameOf(cp, index)
	return tostring(cp.Name or cp.DisplayName or ("Checkpoint " .. index))
end

function View.hasImage(image)
	return type(image) == "string" and image ~= ""
		and not string.find(string.upper(image), "PLACEHOLDER", 1, true)
end

-- a checkpoint that can't be started: not released yet (Unlocked = false, as in
-- Shared.Checkpoints: COMING SOON), or not unlocked by both players of the pair
-- (Locked = true: LOCKED). START won't take either.
function View.isLocked(cp)
	return cp.Unlocked == false or cp.Locked == true
end

-- what a card that can't be started says
function View.lockText(cp)
	return (cp.Unlocked ~= false and cp.Locked == true) and "LOCKED" or "COMING SOON"
end

-- one card for one checkpoint. Its picture sits over the placeholder art, so a
-- card whose image is missing, empty or fails to load still shows something
function View.newCard(template, cp, index)
	local holder = template:Clone()
	holder.Name = "Card" .. index
	holder.LayoutOrder = index
	holder.Visible = true
	local face = holder:WaitForChild("Face")
	local art  = face:WaitForChild("Art")
	local c = View.BIOME_ART[cp.Biome] or View.PALETTE[(index - 1) % #View.PALETTE + 1]
	art:WaitForChild("Tint").Color = ColorSequence.new(c[1], c[2])
	if c[3] then
		for _, n in ipairs({ "GroundBack", "GroundFront" }) do
			local g = art:FindFirstChild(n)
			if g then g.BackgroundColor3 = c[3] end
		end
	end
	art:WaitForChild("Number").Text = tostring(cp.Order or index)
	local image = face:WaitForChild("Image")
	local has = View.hasImage(cp.Image)
	image.Image = has and cp.Image or ""
	image.Visible = has
	-- the placeholder art is only for a card with no picture: never flashed while the picture
	-- is still loading (they're preloaded as the game loads: StarterGui.CheckpointImagePreload)
	if has and not image.IsLoaded then
		art.Visible = false
		-- a picture that never arrives: its placeholder comes back rather than an empty card
		task.delay(4, function()
			if art.Parent and not image.IsLoaded then art.Visible = true end
		end)
	end
	face:WaitForChild("CheckpointName").Text = View.nameOf(cp, index)
	local soon = face:WaitForChild("Soon")
	soon.Visible = View.isLocked(cp)
	local label = soon:FindFirstChild("Label", true)
	if label then label.Text = View.lockText(cp) end
	return holder, face, face:WaitForChild("Edge")
end

return View
