--=====================================================================
-- DonationSystem / Config
--
-- Every setting you are expected to change lives here. Shared by the
-- server (receipts, data stores) and the client (the 3D board).
--=====================================================================

local Config = {}

--------------------------------------------------------------------- products
-- [Robux amount] = Developer Product ID
--
-- Creator Dashboard -> this experience -> Monetization -> Developer
-- Products: make one product per amount, price it at that amount, and
-- paste its ID below. A button whose ID is still 0 says "SOON" when
-- clicked instead of opening a purchase prompt.
Config.DonationProducts = {
	[5]     = 3715215795,
	[10]    = 3715215920,
	[20]    = 3713999802,
	[50]    = 3714000057,
	[100]   = 3715215956,
	[200]   = 3714000103,
	[500]   = 3714000140,
	[1000]  = 3714000198,
	[2500]  = 3714000251,
	[5000]  = 3714000322,
	[10000] = 3714000357,
}

--------------------------------------------------------------------- images
-- Robux icon shown beside every amount. Use "rbxassetid://<id>" to swap
-- in your own upload.
Config.RobuxIcon = "rbxasset://textures/ui/common/robux.png"

--------------------------------------------------------------------- board
-- Workspace model holding the three board parts:
--   LastDonators, Leaderboard, DonateButtons
-- The UI is drawn on each part's Back face. Give a part a string
-- attribute "Face" (Front / Back / Left / Right) to use another side.
Config.BoardModelName = "DonationBoard"

Config.Titles = {
	Last   = "Last Donators",
	Top    = "Top Donators",
	Donate = "Donate",
}

Config.MaxLastDonators       = 6
Config.MaxLeaderboardEntries = 100    -- per tab (100 max); places 1-3 sit in the cards
Config.RecentDays            = 30     -- window of the "LAST 30 DAYS" tab

--------------------------------------------------------------------- hover
Config.HoverDistance    = 0.15   -- studs a donate button travels toward the player
Config.HoverScale       = 0.03   -- extra size while lifted (0.03 = +3%)
Config.HoverTweenTime   = 0.16   -- seconds to pop out
Config.HoverOutTime     = 0.2    -- seconds to settle back
Config.InteractDistance = 60     -- boards further than this from the camera ignore the mouse

--------------------------------------------------------------------- sounds
-- Id = any audio asset; MinGap = seconds before the same sound may play again.
Config.Sounds = {
	-- donate buttons: the same tick as the Invite button
	ButtonHover  = { Id = "rbxassetid://15675059323", Volume = 0.12, Speed = 1.45, MinGap = 0.04 },
	ButtonClick  = { Id = "rbxassetid://15675059323", Volume = 0.3,  Speed = 1 },
	-- leaderboard entries and tabs: much quieter, and throttled for fast sweeps
	EntryHover   = { Id = "rbxassetid://15675059323", Volume = 0.035, Speed = 1.7, MinGap = 0.09 },
	-- confirmed donation, played at the boards (Pro Sound Effects library)
	Celebration  = { Id = "rbxassetid://9113849583", Volume = 0.7, Speed = 1 },
}

--------------------------------------------------------------------- display
Config.PixelsPerStud      = 80    -- board sharpness; higher = crisper text, more memory
Config.MaxViewDistance    = 250   -- boards stop drawing beyond this many studs
Config.ThousandsSeparator = " "   -- "2 500" like the reference; "," gives "2,500"

--------------------------------------------------------------------- data
Config.RefreshInterval = 60              -- seconds between leaderboard reloads
-- !! DO NOT CHANGE once the game is live. The saved donations live under
-- !! this name; a different name starts every board from zero (the old
-- !! data is not deleted, just no longer read).
Config.DataStorePrefix = "Donations_v1"

-- Studio test purchases are free, so they are kept in memory unless this
-- is true. Leave it false, or Studio tests become real board entries.
Config.UseDataStoresInStudio = false

return Config
