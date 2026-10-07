--=====================================================================
-- TrollFx   (StarterPlayerScripts)
--
-- The Troll effects as every player sees them, played on THIS machine - and only ever on the
-- one scooter a troll was bought onto. The server says which scooter and when (its Troll,
-- TrollStart and TrollBase attributes: ServerScriptService.ScooterSystem.TrollEffects); the
-- show plays here, frame by frame, so it is smooth on every screen. It is only a picture: on
-- the server that scooter stands still, and nothing about anyone else - their scooter,
-- character, camera, controls or screen - is touched here. (What only the two trolled riders
-- get - the banner, their camera, their HUD put away - is StarterGui.TrolledGui; the buyer's
-- view is the Troll window's spectate camera.)
--
-- One module per effect, named after the scooter's Troll attribute (Rocket), with
-- Play(scooter): a new troll's show is one more module here.
--=====================================================================

local shows = {}
for _, m in ipairs(script:GetChildren()) do
	if m:IsA("ModuleScript") then shows[m.Name] = require(m) end
end

local playing = setmetatable({}, { __mode = "k" })   -- [scooter] = true: its show has started here

local function check(scooter)
	if playing[scooter] then return end
	local show = shows[scooter:GetAttribute("Troll")]
	if not show then return end
	if type(scooter:GetAttribute("TrollStart")) ~= "number" or typeof(scooter:GetAttribute("TrollBase")) ~= "CFrame" then return end
	playing[scooter] = true
	task.spawn(function()
		local ok, err = pcall(show.Play, scooter)
		if not ok then warn("[TrollFx] " .. tostring(err)) end
	end)
end

local function watch(scooter)
	if not scooter:IsA("Model") then return end
	scooter:GetAttributeChangedSignal("Troll"):Connect(function() check(scooter) end)
	scooter:GetAttributeChangedSignal("TrollStart"):Connect(function() check(scooter) end)
	check(scooter)
end

local bin = workspace:WaitForChild("RideSystem"):WaitForChild("Scooters")
bin.ChildAdded:Connect(watch)
for _, scooter in ipairs(bin:GetChildren()) do watch(scooter) end
