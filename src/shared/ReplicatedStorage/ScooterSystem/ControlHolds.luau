--=====================================================================
-- ControlHolds   (ScooterSystem, on each player's machine)
--
-- The player's own controls that cutscenes and windows switch off while they are up,
-- shared out fairly between them:
--   CameraInput    Roblox's camera input (the PlayerModule's CameraContext: mouse look,
--                  right-drag, wheel, touch, gamepad, Shift-lock)
--   TouchControls  Roblox's thumbstick and jump button (touch screens only)
--   Pointer        the mouse pointer
-- Any number of holders may hold the same one at once (the death popup over a troll, a
-- nuke over the Troll window...). It goes off with the first and comes back only when
-- the LAST lets go - exactly as it was before the first took it, whatever order they
-- end in. (Each one putting back what IT found would leave it off for good whenever
-- the one that started second ended last.)
--
--   ControlHolds.Hold(key, { "CameraInput", "TouchControls", "Pointer" })
--       switch them off for `key` (one hold per key: holding again changes nothing)
--   ControlHolds.Release(key)   let go of everything `key` holds
--=====================================================================

local GuiService       = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local ControlHolds = {}

-- Roblox's camera reads its controls through this input context
local function cameraContext()
	local pm   = game:GetService("StarterPlayer"):FindFirstChild("PlayerModule")
	local ctxs = pm and pm:FindFirstChild("InputContexts")
	local ctx  = ctxs and ctxs:FindFirstChild("CameraContext")
	return (ctx and ctx:IsA("InputContext")) and ctx or nil
end

-- find(): what is switched (nil = nothing to switch here); get / set on that
local SWITCHES = {
	CameraInput = {
		find = cameraContext,
		get  = function(ctx) return ctx.Enabled end,
		set  = function(ctx, on) if ctx.Parent then ctx.Enabled = on end end,
	},
	TouchControls = {
		find = function() return UserInputService.TouchEnabled and GuiService or nil end,
		get  = function() return GuiService.TouchControlsEnabled end,
		set  = function(_, on) GuiService.TouchControlsEnabled = on end,
	},
	Pointer = {
		find = function() return UserInputService end,
		get  = function() return UserInputService.MouseIconEnabled end,
		set  = function(_, on) UserInputService.MouseIconEnabled = on end,
	},
}

local held = {}   -- [switch name] = { target, was (before the first holder), holders = { [key] = true } }

function ControlHolds.Hold(key, names)
	for _, name in ipairs(names) do
		local switch = SWITCHES[name]
		if not switch then
			warn("[ControlHolds] no such control: " .. tostring(name))
			continue
		end
		local h = held[name]
		if h and h.holders[key] then continue end
		if not h then
			local target = switch.find()
			if not target then continue end
			h = { target = target, was = switch.get(target), holders = {} }
			held[name] = h
		end
		h.holders[key] = true
		switch.set(h.target, false)
	end
end

function ControlHolds.Release(key)
	for name, h in pairs(held) do
		if h.holders[key] then
			h.holders[key] = nil
			if next(h.holders) == nil then
				held[name] = nil
				SWITCHES[name].set(h.target, h.was)
			end
		end
	end
end

return ControlHolds
