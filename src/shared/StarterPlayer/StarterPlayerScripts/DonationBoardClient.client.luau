--=====================================================================
-- DonationBoardClient
--
-- Draws the donation board for this player and handles its clicks. Board
-- data arrives read-only through ReplicatedStorage.DonationSystem.BoardData
-- (the top 100 of each tab); scrolling further asks the server for the next
-- 100 (DonorPage, read only - it writes nothing). Donating goes straight
-- to Roblox's own purchase prompt. The server only counts a donation
-- once Roblox confirms the payment (see DonationHandler).
--=====================================================================

local Players            = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local HttpService        = game:GetService("HttpService")
local GuiService         = game:GetService("GuiService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local system    = ReplicatedStorage:WaitForChild("DonationSystem")
local Config    = require(system:WaitForChild("Config"))
local HoverLift   = require(script:WaitForChild("HoverLift"))
local BoardUI     = require(script:WaitForChild("BoardUI"))
local Celebration = require(script:WaitForChild("Celebration"))

local model = workspace:WaitForChild(Config.BoardModelName)
local parts = {
	Last   = model:WaitForChild("LastDonators"),
	Top    = model:WaitForChild("Leaderboard"),
	Donate = model:WaitForChild("DonateButtons"),
}

--------------------------------------------------------------------- actions
local ui
local promptToken                               -- the purchase prompt currently open, if any

local function donate(amount)
	local productId = Config.DonationProducts[amount]
	if not productId or productId == 0 then
		warn(("[Donations] No Developer Product ID for %d Robux yet (ReplicatedStorage.DonationSystem.Config)")
			:format(amount))
		ui:FlashButton(amount, "SOON")
		return
	end
	-- the prompt covers the board: let go of the button until it closes
	HoverLift.SetSuspended(true)
	local token = {}
	promptToken = token
	task.delay(120, function()                  -- safety net if the close is never reported
		if promptToken == token then HoverLift.SetSuspended(false) end
	end)
	local ok, err = pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, player, productId)
	if not ok then
		warn("[Donations] Could not open the purchase prompt: " .. tostring(err))
		promptToken = nil
		HoverLift.SetSuspended(false)
	end
end

MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId)
	if userId == player.UserId then
		promptToken = nil
		HoverLift.SetSuspended(false)
	end
end)

local function inspect(userId)
	if userId and userId > 0 then
		pcall(GuiService.InspectPlayerFromUserId, GuiService, userId)
	end
end

-- the next 100 donors of a tab: { list = { {u, a, n, v} }, more = bool }, or nil
local function fetchPage(tab, page)
	local remote = system:WaitForChild("DonorPage", 10)
	if not remote then return nil end
	local ok, result = pcall(remote.InvokeServer, remote, tab, page)
	return (ok and type(result) == "table" and type(result.list) == "table") and result or nil
end

ui = BoardUI.new(parts, player:WaitForChild("PlayerGui"), HoverLift, {
	Donate    = donate,
	Inspect   = inspect,
	FetchPage = fetchPage,
})
HoverLift.Start(model)

--------------------------------------------------------------------- celebration
-- The server only fires this after Roblox has confirmed a purchase.
local celebration = Celebration.new(parts, HoverLift.Axes)
task.spawn(function()
	system:WaitForChild("DonationCelebrate").OnClientEvent:Connect(function()
		celebration:Play()
	end)
end)

--------------------------------------------------------------------- data
local boardData = system:WaitForChild("BoardData")

local function applyData()
	local ok, data = pcall(HttpService.JSONDecode, HttpService, boardData.Value)
	ui:Apply((ok and type(data) == "table") and data or {})
end
boardData.Changed:Connect(applyData)
applyData()

--------------------------------------------------------------------- reload countdown
-- "Refreshes in Ns" under a board, counting down to its BoardData's NextRefresh
-- attribute (the server time of its next reload, stamped by the server after each one).
local function countdown(ui, data, every)
	while data.Parent do
		local nextAt = data:GetAttribute("NextRefresh")
		local left = every
		if type(nextAt) == "number" then
			left = math.clamp(math.ceil(nextAt - workspace:GetServerTimeNow()), 1, every)
		end
		ui:SetFooter(("Refreshes in %ds"):format(left))
		task.wait(0.2)
	end
end

--------------------------------------------------------------------- top playtime
-- The lobby's "playtime leaderboard" model: the same ranked board as Top Donators
-- (BoardUI.newTop), filled from ReplicatedStorage.PlaytimeSystem.BoardData (the
-- server's PlaytimeLeaderboard). Its big Board part holds the list, the small one
-- above it the title.
local function formatPlaytime(seconds)
	seconds = math.floor(tonumber(seconds) or 0)
	local h, m = seconds // 3600, (seconds % 3600) // 60
	if h >= 1000 then return h .. "h" end
	if h > 0 then return ("%dh %02dm"):format(h, m) end
	return m .. "m"
end

task.spawn(function()
	local ptModel = workspace:WaitForChild("playtime leaderboard", 60)
	if not ptModel then return end
	local main, header
	local t0 = os.clock()
	repeat
		for _, p in ipairs(ptModel:GetChildren()) do
			if p.Name == "Board" and p:IsA("BasePart") then
				if p.Size.Y > 3 then main = p else header = p end
			end
		end
		if not (main and header) then task.wait(0.5) end
	until (main and header) or os.clock() - t0 > 30
	if not main then return end
	HoverLift.AddIgnore(ptModel)
	local playtimeUI = BoardUI.newTop(main, player:WaitForChild("PlayerGui"), HoverLift, { Inspect = inspect }, {
		GuiName = "PlaytimeBoard", Title = "", DesignPPS = 70,
		Header = header, HeaderText = "TOP PLAYTIME",
		Format = formatPlaytime, NoIcon = true, Podium = "Stack",
		Empty = "No playtime yet. Keep riding!", EmptyShort = "Play to join the leaderboard!",
		Footer = true,   -- "Refreshes in Ns": the server reloads it every 30 s
	})
	local ptData = ReplicatedStorage:WaitForChild("PlaytimeSystem"):WaitForChild("BoardData")
	local function applyPlaytime()
		local ok, data = pcall(HttpService.JSONDecode, HttpService, ptData.Value)
		playtimeUI:ApplyTop((ok and type(data) == "table") and data or {})
	end
	ptData.Changed:Connect(applyPlaytime)
	applyPlaytime()
	countdown(playtimeUI, ptData, 30)
end)

--------------------------------------------------------------------- fastest duos
-- The lobby's "Fastest Finish Leaderboard" model, titled Fastest Duos: the Top
-- Playtime board's look, one row per duo (BoardUI.newDuo), filled from
-- ReplicatedStorage.FastestDuosSystem.BoardData (the server's FastestDuosLeaderboard).
-- The server reloads it every 30 s and stamps BoardData's NextRefresh attribute (server
-- time); the footer counts down to that.
task.spawn(function()
	local fdModel = workspace:WaitForChild("Fastest Finish Leaderboard", 60)
	if not fdModel then return end
	local main, header
	local t0 = os.clock()
	repeat
		for _, p in ipairs(fdModel:GetChildren()) do
			if p.Name == "Board" and p:IsA("BasePart") then
				if p.Size.Y > 3 then main = p else header = p end
			end
		end
		if not (main and header) then task.wait(0.5) end
	until (main and header) or os.clock() - t0 > 30
	if not main then return end
	HoverLift.AddIgnore(fdModel)

	local RunTime = require(ReplicatedStorage:WaitForChild("ScooterSystem"):WaitForChild("Shared"):WaitForChild("RunTime"))
	local duosUI = BoardUI.newDuo(main, player:WaitForChild("PlayerGui"), HoverLift, {
		GuiName = "FastestDuosBoard", DesignPPS = 70,
		Header = header, HeaderText = "FASTEST DUOS",
		HeaderSub = ("Finish World %d together from the start - No Skipping, No Giving up")
			:format(require(ReplicatedStorage:WaitForChild("WorldConfig")).Id),
		Format = RunTime.Format,
		Empty = "No duo has finished yet. Be the first!",
		-- the model's green frame covers the board's edges (left ~11 px, right ~1, top ~15,
		-- bottom 0 at 70 px/stud): clear that plus a 10 px gap all round
		Margin = { Left = 21, Right = 12, Top = 25, Bottom = 10 },
	})
	local fdData = ReplicatedStorage:WaitForChild("FastestDuosSystem"):WaitForChild("BoardData")
	local function applyDuos()
		local ok, data = pcall(HttpService.JSONDecode, HttpService, fdData.Value)
		duosUI:ApplyDuos((ok and type(data) == "table") and data or {})
	end
	fdData.Changed:Connect(applyDuos)
	applyDuos()

	countdown(duosUI, fdData, 30)
end)

local shownTotal = player:GetAttribute("DonatedRobux")
ui:SetMyTotal(shownTotal or 0)
player:GetAttributeChangedSignal("DonatedRobux"):Connect(function()
	local total = player:GetAttribute("DonatedRobux") or 0
	-- the first value is the saved total arriving on join, not a new donation
	ui:SetMyTotal(total, shownTotal ~= nil and total > shownTotal)
	shownTotal = total
end)
