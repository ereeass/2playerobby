-- HudSync: one clock for the lobby HUD, so its pieces come and go together.
--
-- The Invite tile, the Scooters tile and the Settings gear each used to decide on
-- their own when to appear after the loading screen (one when it handed over, two
-- by polling for it to be gone every 0.2 s, one of those 0.15 s later still) and
-- when to step aside for a booth (one at once, one when its own spring ran down),
-- so they popped in and out at different moments. Now there is one signal each:
--
--   HudSync.WhenIntroDone(fn)  fn runs in the frame the loading screen hands the
--                              player control (LoadingClient sets IntroDone)
--   HudSync.OnInGame(fn)       fn(inGame) runs for every piece in the same frame
--                              when the player enters a booth or gets back to the
--                              lobby (queued, counting down and riding are in game)
--   HudSync.OnAside(fn)        fn(aside) likewise, for the lobby tiles that step aside
--                              (Skins, Daily, and Invite for its top-bar button): in game,
--                              OR watching a duo in the Troll window (SetSpectating)
--
-- and every piece moves on the same spring (STIFFNESS, DAMPING, the entrance pop
-- starting at POP_FROM with POP_VEL).
--
-- The lobby tiles also share one place: a 2 x 2 grid on the left of the screen
--   Skins  Troll
--   Daily  Invite
-- (a third row, centred under them, is kept free for a later tile).
--   HudSync.TileScale()               the tiles' UIScale (the 84 px tile's size)
--   HudSync.TileAt(gui, col, row, s)  a tile Container's Position (anchor 0.5, 0.5) in gui
--   HudSync.HintX(col, hintA)         its hint pill's X (Scale), to the right of the grid

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local HudSync = {}
HudSync.STIFFNESS, HudSync.DAMPING = 250, 19
HudSync.POP_FROM,  HudSync.POP_VEL = 0.32, 2.2

local INTRO_TIMEOUT = 120   -- no loading screen, or it never hands over: come in anyway

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

---------------------------------------------------------------- tile grid
-- Measured off the reference layout: on a 1080 px tall screen a tile is 112 px, 12 px
-- in from the left edge, 20 px between columns, 13 px between rows, and the first
-- row's centre sits 38% of the way down the whole screen (the reference's 42.5%, nudged up).
HudSync.TILE = 84                      -- a tile's unscaled size
local REF_TILE  = 112
local EDGE      = 12 / REF_TILE          -- left edge gap, in tiles
local PITCH_X   = 132 / REF_TILE         -- column to column, in tiles
local PITCH_Y   = 125 / REF_TILE         -- row to row, in tiles
local ROW1_Y    = 0.38                   -- of the screen's height
local TOUCH_ROW1_Y = 0.30                -- phones and tablets: the grid sits higher (PC keeps ROW1_Y)

-- a phone or tablet (touch, no mouse)
function HudSync.IsTouch()
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

local function viewport()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	if vp.X < 1 or vp.Y < 1 then vp = Vector2.new(1280, 720) end
	return vp
end

function HudSync.TileScale()
	local vp = viewport()
	local minAxis = math.min(vp.X, vp.Y)
	local s = minAxis * (REF_TILE / 1080) / HudSync.TILE
	local touch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	if touch and minAxis < 500 then s *= 1.15 end
	return math.clamp(s, 0.7, 1.45)
end

function HudSync.TileAt(gui, col, row, s)
	local vp = viewport()
	local tile = HudSync.TILE * (s or HudSync.TileScale())
	local x = tile * (EDGE + 0.5) + (col - 1) * tile * PITCH_X
	local y = vp.Y * (HudSync.IsTouch() and TOUCH_ROW1_Y or ROW1_Y) + (row - 1) * tile * PITCH_Y
	local o = gui.AbsolutePosition      -- the gui's safe-area inset, if it has one
	return UDim2.fromOffset(math.max(x - o.X, tile * (EDGE + 0.5)), y - o.Y)
end

-- hints slide out to the right of the whole grid, so a left-column tile's clears the right column
function HudSync.HintX(col, hintA)
	return 1 + (col == 1 and PITCH_X or 0) + (2 + 8 * hintA) / HudSync.TILE
end

---------------------------------------------------------------- intro
local introDone, introFns = false, {}
local function finishIntro()
	if introDone then return end
	introDone = true
	for _, fn in ipairs(introFns) do task.spawn(fn) end
	table.clear(introFns)
end
if playerGui:GetAttribute("IntroDone") then
	finishIntro()
else
	playerGui:GetAttributeChangedSignal("IntroDone"):Connect(function()
		if playerGui:GetAttribute("IntroDone") then finishIntro() end
	end)
	task.delay(INTRO_TIMEOUT, finishIntro)
end

function HudSync.WhenIntroDone(fn)
	if introDone then task.spawn(fn) else table.insert(introFns, fn) end
end

---------------------------------------------------------------- in game
local inGame, listeners = false, {}

function HudSync.InGame() return inGame end
function HudSync.OnInGame(fn) table.insert(listeners, fn) end

---------------------------------------------------------------- aside
local spectating, aside, asideListeners = false, false, {}

function HudSync.Aside() return aside end
function HudSync.OnAside(fn) table.insert(asideListeners, fn) end

local function updateAside()
	local now = inGame or spectating
	if now == aside then return end
	aside = now
	for _, fn in ipairs(asideListeners) do task.spawn(fn, aside) end
end

-- the Troll window is watching a duo (TrollUI.Menu)
function HudSync.SetSpectating(on)
	spectating = on == true
	updateAside()
end

ReplicatedStorage:WaitForChild("ScooterSystem"):WaitForChild("Remotes"):WaitForChild("StateChanged").OnClientEvent:Connect(function(state)
	local phase = type(state) == "table" and state.Phase or "None"
	local now = phase ~= "None" and phase ~= "Empty"
	if now == inGame then return end
	inGame = now
	for _, fn in ipairs(listeners) do task.spawn(fn, inGame) end
	updateAside()
end)

return HudSync
