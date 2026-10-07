--=====================================================================
-- CourseProgressUI   (StarterGui.CourseProgressGui)
--
-- The course progress bar in the middle of the top bar: this player's percentage and green
-- fill, and every player in the server as their avatar along the track. It only DRAWS: how
-- far everyone is comes from the server (ServerScriptService.CourseProgress) as each
-- player's CourseProgress attribute (0 = the start gate, 1 = the finish), a few times a
-- second. Each avatar and the fill glide to that value (FOLLOW), so they move smoothly
-- between updates and always settle exactly where the server says - 100% only on a finish.
--   * avatars are just the avatar (no background, no rim), all on the bar's middle line;
--     this player's is a little bigger and always on top of the others
--   * the percentage sits in the middle of the bar, the finish flag at its end (its
--     white squares filled in, so it reads as a checkered flag on the dark bar)
--   * players joining or leaving are added / removed straight away
-- Styled as the top bar's pills (the Invite pill's gradient and rim), the pill itself being the
-- dark studded track the green fills. It sits in the middle of the top bar, as wide as the room between Roblox's
-- buttons and ours allows (less while riding, when the stopwatch and Invite pill are there);
-- on a phone it is drawn smaller (FIT_PHONE) and never wider than PHONE_MAX_W.
--=====================================================================

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HudSync = require(ReplicatedStorage:WaitForChild("HudSync"))

local player     = Players.LocalPlayer
local gui        = script.Parent
local container  = gui:WaitForChild("Container")
local scaleObj   = container:WaitForChild("Scale")
local bar        = container:WaitForChild("Bar")
local fitObj     = bar:WaitForChild("Fit")
local pctLabel   = bar:WaitForChild("Percent")
local track      = bar:WaitForChild("Track")
local trackStuds = track:WaitForChild("Studs")
local fill       = track:WaitForChild("Fill")
local fillStuds  = fill:WaitForChild("Studs")
local iconsRoot  = bar:WaitForChild("Icons")
local template   = gui:WaitForChild("IconTemplate")

local ATTRIBUTE  = "CourseProgress"
local HEIGHT     = 44                 -- the top bar's pills
local TRACK_LEFT, TRACK_RIGHT = 5, 5     -- edge to edge (the finish flag sits over the end)
local MAX_W      = 560
local FIT_PHONE  = 0.72               -- a phone (touch, no mouse, short screen) draws it at this size...
local PHONE_MAX_W = 360               -- ...and never wider than this (on screen)
local MIN_W      = 150
local CENTRED_MIN = 240               -- narrower than this in the screen's middle: use the free room's middle
local RESERVE_LOBBY, RESERVE_RIDE = 60, 244   -- our buttons at the top bar's right: the gear (+ stopwatch, Invite pill)
local EDGE_GAP   = 10
local ICON, ICON_ME = 32, 40
local FOLLOW     = 7                  -- 1/s: how fast the avatars and the fill glide to the server's value
local STUD, STUD_GAP = 5, 7           -- a grid of small studs over the whole track...
local STUD_ROWS  = 4
local SHOW_STUDS = false              -- plain bar, no studs
local TRACK_H    = 34                 -- ...which is the pill less 5 px top and bottom

local WHITE   = Color3.new(1, 1, 1)
local BLACK   = Color3.new(0, 0, 0)
local GREEN   = fill.BackgroundColor3
-- each stud like the map's: a rounded square the colour of what it's on, lit top-left and
-- shadowed bottom-right so it looks raised: { shadow, face } as colour + transparency
local STUD_DARK  = { BLACK, 0.3, WHITE, 0.9 }
local STUD_GREEN = { GREEN:Lerp(BLACK, 0.3), 0, GREEN:Lerp(WHITE, 0.18), 0 }

local function approach(cur, target, rate, dt)
	return cur + (target - cur) * (1 - math.exp(-rate * dt))
end

---------------------------------------------------------------- studs
local function round(frame)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 1)
	c.Parent = frame
end

local function part(holder, x, y, color, transparency, z)
	local s = Instance.new("Frame")
	s.AnchorPoint = Vector2.new(0.5, 0.5)
	s.Position = UDim2.new(0, x, 0.5, y)
	s.Size = UDim2.fromOffset(STUD, STUD)
	s.BorderSizePixel = 0
	s.BackgroundColor3, s.BackgroundTransparency, s.ZIndex = color, transparency, z
	round(s)
	s.Parent = holder
end

-- a grid of small studs over the whole track, dim on the dark part and green on the fill (the
-- fill's grid lines up with the track's, and the fill uncovers it as it grows); the rounded
-- ends leave out the studs that would poke past them
local trackW = 0
local function layStuds(w)
	trackStuds:ClearAllChildren()
	fillStuds:ClearAllChildren()
	fillStuds.Size = UDim2.new(0, w, 1, 0)
	if not SHOW_STUDS then return end
	local r = TRACK_H / 2
	local n = math.max(0, math.floor((w - 8) / STUD_GAP) + 1)
	local x0 = (w - (n - 1) * STUD_GAP) / 2
	for i = 0, n - 1 do
		local x = x0 + i * STUD_GAP
		local cx = math.clamp(x, r, w - r)
		for row = 0, STUD_ROWS - 1 do
			local y = (row - (STUD_ROWS - 1) / 2) * STUD_GAP
			if Vector2.new(x - cx, y).Magnitude + STUD * 0.75 <= r - 1 then
				for _, h in ipairs({ { trackStuds, STUD_DARK, 3 }, { fillStuds, STUD_GREEN, 5 } }) do
					local holder, c, z = h[1], h[2], h[3]
					part(holder, x + 1, y + 1, c[1], c[2], z)
					part(holder, x, y, c[3], c[4], z)
				end
			end
		end
	end
end

---------------------------------------------------------------- where it sits
local inGame = HudSync.InGame()

local function layout()
	local cam = workspace.CurrentCamera
	local safeW, safeH = gui.AbsoluteSize.X, gui.AbsoluteSize.Y
	if not cam or safeW < 1 then return end
	-- in this ScreenGui's own space (the top bar's safe area, right of Roblox's buttons)
	local left = EDGE_GAP
	local right = safeW - (inGame and RESERVE_RIDE or RESERVE_LOBBY) - EDGE_GAP
	local centre = cam.ViewportSize.X / 2 - gui.AbsolutePosition.X
	local w, x = math.min(MAX_W, 2 * math.min(centre - left, right - centre)), centre
	if w < CENTRED_MIN then
		w, x = math.min(MAX_W, right - left), (left + right) / 2
	end
	-- a phone: smaller all round, and never too wide
	local short = math.min(cam.ViewportSize.X, cam.ViewportSize.Y)
	local phone = UserInputService.TouchEnabled and not UserInputService.MouseEnabled and short < 600
	local fit = phone and FIT_PHONE or 1
	if phone then w = math.min(w, PHONE_MAX_W) end
	w = math.max(MIN_W * fit, math.floor(w))
	fitObj.Scale = fit
	-- the pill is laid out at full size and drawn at `fit` about its middle: w on screen
	local design = math.floor(w / fit)
	container.Position = UDim2.fromOffset(math.floor(x), math.floor(safeH / 2))
	container.Size = UDim2.fromOffset(design, HEIGHT)
	local tw = design - TRACK_LEFT - TRACK_RIGHT
	if tw ~= trackW then
		trackW = tw
		layStuds(tw)
	end
end

local function watchCamera()
	local cam = workspace.CurrentCamera
	if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(layout) end
	layout()
end
watchCamera()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
gui:GetPropertyChangedSignal("AbsolutePosition"):Connect(layout)
HudSync.OnInGame(function(now)
	inGame = now
	layout()
end)

---------------------------------------------------------------- avatars
local icons = {}   -- [player] = { frame, me, size, shown, target }

local function addIcon(plr)
	if icons[plr] then return end
	local me = plr == player
	local size = me and ICON_ME or ICON
	local f = template:Clone()
	f.Name = "Avatar_" .. plr.UserId
	f.Size = UDim2.fromOffset(size, size)
	f.ZIndex = me and 12 or 8
	f.Avatar.ZIndex = f.ZIndex + 1
	f.More.Visible = false
	f.Avatar.Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=60&h=60"):format(plr.UserId)
	f.Visible = false
	f.Parent = iconsRoot
	local v = plr:GetAttribute(ATTRIBUTE) or 0
	icons[plr] = { frame = f, me = me, size = size, shown = v, target = v }
end

local function removeIcon(plr)
	local i = icons[plr]
	if not i then return end
	icons[plr] = nil
	i.frame:Destroy()
end

Players.PlayerAdded:Connect(addIcon)
Players.PlayerRemoving:Connect(removeIcon)
for _, plr in ipairs(Players:GetPlayers()) do addIcon(plr) end

---------------------------------------------------------------- every frame
local sCur, sVel, entering = 1, 0, false

RunService.RenderStepped:Connect(function(dt)
	if not container.Visible then return end
	dt = math.min(dt, 1 / 15)

	-- the entrance pop, on the HUD's shared spring (HudSync)
	if entering then
		sVel += ((1 - sCur) * HudSync.STIFFNESS - sVel * HudSync.DAMPING) * dt
		sCur += sVel * dt
		if math.abs(1 - sCur) < 0.001 and math.abs(sVel) < 0.01 then sCur, entering = 1, false end
		scaleObj.Scale = math.max(sCur, 0.01)
	end

	-- everyone glides to where the server says they are, all on the middle line (this
	-- player's drawn on top of anyone at the same spot)
	for plr, i in pairs(icons) do
		local target = plr:GetAttribute(ATTRIBUTE) or 0
		i.target = target
		i.shown = approach(i.shown, target, FOLLOW, dt)
		if math.abs(i.shown - target) < 0.0002 then i.shown = target end
		-- on the fill's front edge: the middle of its rounded end (see the fill below)
		-- (everyone else sits lower, their feet on the pill's bottom edge)
		i.frame.Position = UDim2.new(0, TRACK_H / 2 + i.shown * math.max(0, trackW - TRACK_H), 0.5,
			i.me and 0 or (HEIGHT - i.size) / 2)
		i.frame.Visible = true
	end

	-- this player's fill and percentage (100 only once the server says finished)
	local mine = icons[player]
	local p = mine and mine.shown or 0
	fill.Visible = p > 0.001
	-- never narrower than it is tall, so it starts as a full round end that sits inside the
	-- pill's own rounded end instead of a thin sliver poking above it
	fill.Size = UDim2.new(0, TRACK_H + p * math.max(0, trackW - TRACK_H), 1, 0)
	local pct = (mine and mine.target >= 1 and p >= 0.995) and 100 or math.min(99, math.floor(p * 100 + 1e-6))
	local text = pct .. "%"
	if pctLabel.Text ~= text then pctLabel.Text = text end
end)

---------------------------------------------------------------- start
-- in with the rest of the HUD once the loading screen hands over (HudSync)
HudSync.WhenIntroDone(function()
	layout()
	sCur, sVel, entering = HudSync.POP_FROM, HudSync.POP_VEL, true
	scaleObj.Scale = sCur
	container.Visible = true
end)
