--=====================================================================
-- Menus   (ReplicatedStorage.UITemplates)
--
-- The standard behaviour for every menu window (the house panel is
-- UITemplates.PanelWindow): how it moves and when it closes. Settings, the
-- Scooters menu and the checkpoint picker all use it; new menus should too.
--
--   Opens    drops from above the screen into its place    (OPEN)
--   Closes   the same path in reverse, back up off the top (CLOSE)
--   Its icon TOGGLES it (menu:toggle): closed -> opens, open -> closes.
--   Closes ONLY on its X (B on a gamepad), its own icon, or another menu
--   opening and replacing it. The Dim only darkens: clicks outside the window
--   go straight through it, never close anything, and can open another menu.
--   Never two at once: opening one closes the open one, and while a BLOCKING
--   screen is up (Roblox's invite window, the booth's checkpoint picker) the
--   open menu closes and no menu can open until it is gone. A refused open is
--   never silent: the icon shakes and its hint says why (Menus.refusal), e.g.
--   "Close the invite window first" - Roblox gives games no way to close its
--   invite window, so the player does.
--
--   local Menus = require(ReplicatedStorage.UITemplates.Menus)
--   local menu = Menus.new(window, {
--       dim       = dimFrame,              -- darkening only (made click-through)
--       onReplace = function() myClose() end,  -- another screen is taking over: close
--       exclusive = true,                  -- default; false = never replaced
--       blocking  = false,                 -- true = while open, nothing covers it
--   })
--   if menu:open() then ... end  -- FIRST in your open(): false = a blocking screen
--                                   is up: refusal:trigger() and do nothing; true =
--                                   it slides in (and the open menu has closed)
--   menu:close()         -- slides out
--   menu:toggle(open, close) -- what the menu's icon does: your own open / close
--                           functions; false = the open was refused
--   Menus.CloseCurrent() -- a screen that is not one of these menus is opening:
--                           close the open menu
--   menu:alpha()         -- 0 off-screen .. 1 in place: drive the fade and dim
--   menu:setHome(pos)    -- the window's resting Position changed
--   Menus.Block(key [, message]) -- a screen that is not one of these menus is
--   Menus.Unblock(key)      up and must not be covered (Roblox's invite window);
--                           message = what a refused icon's hint says
--   Menus.IsBlocked([except]) -- something other than `except` is blocking: a
--                           screen that is not a menu should not open either
--   Menus.Modal(key, on)    -- a MODAL screen (the ride's controls popup) is up / gone:
--                           it blocks like Block, and on top of that every LOCKED
--                           button takes no input at all - no hover, no sound, no
--                           shake, no click - until the last modal goes
--   Menus.Lockable(button, onLock) -- this button is locked while a modal screen is
--                           up (the top-bar buttons: Invite Friends, the Settings
--                           gear); onLock() drops its hover / press, since a pointer
--                           resting on it never gets MouseLeave once it is locked
--
--   The button that opens a menu (the gear, the Scooters tile):
--   local refusal = Menus.refusal(hintLabel)   -- its hover hint pill
--   refusal:trigger()                   -- its menu:open() returned false
--   local wig, showHint = refusal:update(dt, hintAlpha)   -- every frame: add wig
--       to the button's rotation target; keep the hint up while showHint
--=====================================================================

local TweenService = game:GetService("TweenService")

local Menus = {}
Menus.OPEN   = TweenInfo.new(0.3,  Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
Menus.CLOSE  = TweenInfo.new(0.24, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
Menus.OFFSET = UDim2.fromScale(0, -1)     -- where a closed menu waits: one screen up

local current                             -- the open exclusive menu, if any
local blocks = {}                         -- [key] = true: blocking screens that are up
local modals = {}                         -- [key] = true: modal screens that are up
local lockable = {}                       -- [button] = onLock or true: locked while a modal is up

local Menu = {}
Menu.__index = Menu

function Menus.new(window, opts)
	opts = opts or {}
	local self = setmetatable({
		window    = window,
		home      = window.Position,
		isOpen    = false,
		onReplace = opts.onReplace,
		exclusive = opts.exclusive ~= false,
		blocking  = opts.blocking == true,
	}, Menu)
	window.Position = self.home + Menus.OFFSET
	if opts.dim then opts.dim.Interactable = false end
	return self
end

function Menu:_go(target, info)
	if self.tween then self.tween:Cancel() end
	self.tween = TweenService:Create(self.window, info, { Position = target })
	self.tween:Play()
end

-- is one of these menus open right now (read only)
function Menus.IsOpen() return current ~= nil end

function Menus.CloseCurrent()
	local other = current
	if not other then return end
	current = nil
	if other.onReplace then other.onReplace() else other:close() end
end

-- A blocking screen is up: the open menu goes, and none opens until Unblock.
function Menus.Block(key, message)
	blocks[key] = message or true
	Menus.CloseCurrent()
end

-- what a refused button's hint says (the first blocking screen that gave a reason)
function Menus.BlockMessage()
	for _, message in pairs(blocks) do
		if type(message) == "string" then return message end
	end
	return nil
end

function Menus.Unblock(key)
	blocks[key] = nil
end

function Menus.IsBlocked(except)
	for key in pairs(blocks) do
		if key ~= except then return true end
	end
	return false
end

-- Locked buttons are made non-Interactable: input goes straight past them, so none
-- of their own hover / press / click code ever runs, and nothing else about them
-- (look, visibility, animation) is touched.
local function applyLocks()
	local locked = next(modals) ~= nil
	for button, onLock in pairs(lockable) do
		if not button.Parent then
			lockable[button] = nil
		elseif button.Interactable == locked then
			button.Interactable = not locked
			if locked and type(onLock) == "function" then onLock() end
		end
	end
end

function Menus.Modal(key, on)
	if (modals[key] ~= nil) == (on == true) then return end
	if on then
		modals[key] = true
		Menus.Block(key)                  -- the open menu closes; none opens over it
	else
		modals[key] = nil
		Menus.Unblock(key)
	end
	applyLocks()
end

function Menus.IsModal()
	return next(modals) ~= nil
end

function Menus.Lockable(button, onLock)
	lockable[button] = onLock or true
	applyLocks()
end

function Menu:open()
	if self.blocking then
		Menus.Block(self)                 -- closes the open menu too
	elseif next(blocks) then
		return false                      -- never over a blocking screen
	elseif self.exclusive and current and current ~= self then
		Menus.CloseCurrent()
	end
	if self.exclusive then current = self end
	self.isOpen = true
	self:_go(self.home, Menus.OPEN)
	return true
end

-- A menu's icon: closed -> open(), open -> close(). open / close are the menu's
-- own functions (they do their extras and call menu:open() / menu:close()).
function Menu:toggle(open, close)
	if self.isOpen then
		close()
		return true
	end
	return open() ~= false
end

function Menu:close()
	if current == self then current = nil end
	if self.blocking then Menus.Unblock(self) end
	self.isOpen = false
	self:_go(self.home + Menus.OFFSET, Menus.CLOSE)
end

-- how far in the window is, from where it actually is (so it is right mid-move
-- and when a move is turned around)
function Menu:alpha()
	local travel = -Menus.OFFSET.Y.Scale
	local behind = self.home.Y.Scale - self.window.Position.Y.Scale
	return math.clamp(1 - behind / travel, 0, 1)
end

---------------------------------------------------------------- refused opens
-- The button shakes (the Invite button's "not yet" shake) and its hint pill
-- shows the reason for REFUSE_HINT_TIME, widening to fit it, then goes back to
-- its own text once it has faded out.
Menus.REFUSE_HINT_TIME = 2.2

local Refusal = {}
Refusal.__index = Refusal

function Menus.refusal(hint)
	local pad = Instance.new("UIPadding")     -- room round the reason when it widens
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
	pad.Parent = hint
	return setmetatable({ hint = hint, text = hint.Text, t = math.huge, showUntil = 0 }, Refusal)
end

function Refusal:trigger()
	self.t = 0
	local message = Menus.BlockMessage()
	if message then
		self.showUntil = os.clock() + Menus.REFUSE_HINT_TIME
		self.hint.Text = message
		self.hint.AutomaticSize = Enum.AutomaticSize.X
	end
end

function Refusal:update(dt, hintAlpha)
	local wig = 0
	if self.t < 1.6 then
		self.t += dt
		wig = math.sin(self.t * 26) * math.exp(-self.t * 4.5) * 5
	end
	local showing = os.clock() < self.showUntil
	if not showing and self.hint.Text ~= self.text and hintAlpha < 0.02 then
		self.hint.Text, self.hint.AutomaticSize = self.text, Enum.AutomaticSize.None
	end
	return wig, showing
end

function Menu:setHome(pos)
	if pos == self.home then return end
	self.home = pos
	local target = self.isOpen and pos or pos + Menus.OFFSET
	if self.tween and self.tween.PlaybackState == Enum.PlaybackState.Playing then
		self:_go(target, self.isOpen and Menus.OPEN or Menus.CLOSE)
	else
		self.window.Position = target
	end
end

return Menus
