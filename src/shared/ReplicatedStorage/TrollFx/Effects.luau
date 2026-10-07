--=====================================================================
-- Effects   (ReplicatedStorage.TrollFx)
--
-- Every Troll effect the Troll window offers, as both sides see it: its button (image, tilt,
-- words), the name it goes by on screen and in the Discord log, and the player attribute that
-- counts the free ones someone has saved. What it costs is its Developer Product
-- (ScooterSystem.Shared.Config.TrollProducts); what it does is on the server
-- (ServerScriptService.ScooterSystem.TrollEffects). A new troll is one more entry here, one
-- more there, and its product id.
--=====================================================================

return {
	{
		Id       = "Freeze",
		Name     = "Freeze Players",
		Emoji    = "\u{1F9CA}",
		Label    = "Freeze Players",                 -- white, under the image
		Tag      = "Freeze Them!",                   -- yellow, tilted, top right of the image
		TagAt    = UDim2.new(1, -14, 0, 38),
		Image    = "rbxassetid://127097172612201",
		Rotation = 0,
		BannerImage = "rbxassetid://127097172612201", -- the trolled riders' banner
		Credits  = "FreezeCredits",
		Outcome  = "Frozen!",
	},
	{
		Id       = "Rocket",
		Name     = "Rocket Launch",
		Emoji    = "\u{1F680}",
		Label    = "Rocket Launch",                 -- white, under the image
		Tag      = "Launch Players\nTo The Sky!",   -- yellow, tilted, top right of the image (\n: new line)
		Deal     = "80%\nOff",                       -- red, top left of the image (nil: none)
		Image    = "rbxassetid://96535114733820",
		Rotation = 45,                 -- degrees, clockwise
		Credits  = "RocketCredits",    -- the attribute (and save key) of their saved free ones
		Outcome  = "Launched!",          -- the Discord log, once it has started
	},
	{
		Id       = "Explode",
		Name     = "Explode Players",
		Emoji    = "\u{1F4A5}",
		Label    = "Explode Players",                -- white, under the image
		Tag      = "Explode Them!",                  -- yellow, tilted, top right of the image
		TagAt    = UDim2.new(1, -14, 0, 38),         -- down onto the dynamite's top right
		Image    = "rbxassetid://133513857622474",
		Rotation = 0,
		BannerImage = "rbxassetid://133513857622474", -- the trolled riders' banner (the rocket keeps its own)
		Credits  = "ExplodeCredits",
		Outcome  = "Exploded!",
	},
	{
		Id       = "Ufo",
		Name     = "UFO Abduction",
		Emoji    = "\u{1F6F8}",
		Label    = "UFO Abduction",                  -- white, under the image
		Tag      = "Abduct Them!",                   -- yellow, tilted, top right of the image
		TagAt    = UDim2.new(1, -14, 0, 38),
		Image    = "rbxassetid://108379779226333",
		Rotation = 0,
		Side     = "Right",                          -- its button goes down the right side of the screen
		BannerImage = "rbxassetid://108379779226333", -- the trolled riders' banner
		Credits  = "UfoCredits",
		Outcome  = "Abducted!",
	},
	{
		Id       = "Slap",
		Name     = "Giant Slap",
		Emoji    = "\u{1F44B}",
		Label    = "Giant Slap",                     -- white, under the image
		Tag      = "Slap Them!",                     -- yellow, tilted, top right of the image
		TagAt    = UDim2.new(1, -14, 0, 38),
		Image    = "rbxassetid://96231066842281",
		Rotation = 0,
		Side     = "Right",                          -- under UFO Abduction, down the right side
		BannerImage = "rbxassetid://96231066842281",  -- the trolled riders' banner
		Credits  = "SlapCredits",
		Outcome  = "Slapped!",
	},
	{
		Id       = "BlackHole",
		Name     = "Black Hole",
		Emoji    = "\u{1F573}",
		Label    = "Black Hole",                     -- white, under the image
		Tag      = "Pull Them In!",                  -- yellow, tilted, top right of the image
		TagAt    = UDim2.new(1, -14, 0, 38),
		Image    = "rbxassetid://129627908168770",
		Rotation = 0,
		Side     = "Right",                          -- under Giant Slap, down the right side
		BannerImage = "rbxassetid://129627908168770", -- the trolled riders' banner
		Credits  = "BlackHoleCredits",
		Outcome  = "Sucked in!",
	},
}
