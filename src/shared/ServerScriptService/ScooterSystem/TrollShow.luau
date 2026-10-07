--=====================================================================
-- TrollShow   (ScooterSystem, server) - what every show-and-explode troll does on the server
--
-- Shared by the trolls that end in the cartoon explosion (ROCKET LAUNCH, EXPLODE PLAYERS): each
-- one's own module under TrollEffects is just TrollShow.Play with its own clock
-- (ReplicatedStorage.TrollFx.<Id>Timeline: EXPLODE and END). The show itself plays on every
-- machine (StarterPlayerScripts.TrollFx.<Id>). The server only does what has to be true for
-- everyone - and ONLY to this one ride: its scooter and its two riders. No other player,
-- scooter or ride is touched, and neither is the buyer.
--   wait       DELAY seconds after the purchase the duo just keeps riding; the ride is already
--              theirs (DeathManager.Claim, ride.Troll: nothing else can take it meanwhile)
--   start      the run is over for good (RunTimer.Invalidate: never a Fastest Duos time;
--              checkpoints untouched); nothing else can bring the ride down meanwhile (its
--              grace); controls and horn stop; and the scooter is frozen where it stands -
--              anchored, held by the server. On the server it never leaves the road, so
--              nothing is flown into anything and a revive later comes back at the right
--              place. The two riders are told (Remotes.TrollAlert: their banner, their HUD put
--              away, their camera - StarterGui.TrolledGui).
--   explosion  the scooter and its riders are gone (for everyone, even whoever streams in later)
--   end        the grace goes and DeathManager.Hit brings the ride down as an obstacle would:
--              both riders get the death popup (SKIP / REVIVE) and the game carries on as
--              always - back to the lobby, or revived onto a new scooter.
-- If the ride ends before that (a rider left), whatever was changed on characters still in the
-- game is put back and Play returns false: the buyer gets it back as a free one.
--=====================================================================

local RS = game:GetService("ReplicatedStorage")

local Remotes      = RS:WaitForChild("ScooterSystem"):WaitForChild("Remotes")
local RideManager  = require(script.Parent:WaitForChild("RideManager"))
local DeathManager = require(script.Parent:WaitForChild("DeathManager"))
local RunTimer     = require(script.Parent:WaitForChild("RunTimer"))

local TrollShow = {}

TrollShow.DELAY = 1.5   -- seconds from the purchase to the show starting (every show-and-explode troll)

-- Gone in the explosion: the scooter (it is never used again - the ride ends or a revive
-- brings a new one) and the riders' characters (saved, to put back on anyone who is still
-- alive if the ride ends another way).
local function vanish(ride, scooter)
	for _, d in ipairs(scooter:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture") then
			d.Transparency = 1
		elseif d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam") or d:IsA("Light")
			or d:IsA("SurfaceGui") or d:IsA("BillboardGui") then
			d.Enabled = false
		end
	end
	local saved = {}
	for _, h in pairs(ride.Riders) do
		local ch = h.Character
		if ch and ch.Parent then
			for _, d in ipairs(ch:GetDescendants()) do
				if (d:IsA("BasePart") or d:IsA("Decal")) and d.Transparency < 1 then
					saved[d] = d.Transparency
					d.Transparency = 1
				end
			end
			local hum = h.Humanoid
			if hum then
				saved[hum] = hum.DisplayDistanceType
				hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None   -- no name floating there
			end
		end
	end
	return saved
end

-- the ride ended another way (a rider left): a character still in the game is theirs again,
-- exactly as it was
local function giveBack(keep, saved)
	for inst, was in pairs(saved or {}) do
		if inst.Parent then
			if inst:IsA("Humanoid") then inst.DisplayDistanceType = was else inst.Transparency = was end
		end
	end
	for h, was in pairs(keep) do
		h.KeepOnDeath = was.KeepOnDeath
		if h.Humanoid and h.Humanoid.Parent and was.Break ~= nil then h.Humanoid.BreakJointsOnDeath = was.Break end
	end
end

-- ctx: { Ride, Scooter, Life (DeathManager.Claim's), Riders (players), BuyerName, Def }
-- effectId: the scooter's Troll attribute (which show every machine plays); timeline: its clock
-- (LEAD, EXPLODE, END); why: for RunTimer and the log.
-- opts (optional, for a show that plays on many rides at once - NUKE ALL):
--   Start  the server time the show starts (no DELAY: every ride on the same clock)
--   Quiet  the riders are not sent TrollAlert (their banner and camera): the show has its own
-- True once the ride is down (its riders on the death popup); false if it ended before that.
function TrollShow.Play(ctx, effectId, timeline, why, opts)
	opts = opts or {}
	local ride, scooter = ctx.Ride, ctx.Scooter
	-- a moment after the purchase: they ride on until then (gone meanwhile: the buyer gets it back)
	local due = os.clock() + math.max(TrollShow.DELAY - timeline.LEAD, 0)   -- the lead is part of the wait
	if opts.Start then due = os.clock() end
	while os.clock() < due and not ride._ended and scooter and scooter.Parent do task.wait() end
	local chassis = scooter and scooter.Parent and scooter.PrimaryPart
	if not chassis or ride._ended then return false end

	-- the run is over for good: it can never be a Fastest Duos time
	RunTimer.Invalidate(ride, why)
	-- nothing else brings this ride down while the show plays (DeathManager.Hit / Claim)
	local graceWas = ride.GraceUntil
	ride.GraceUntil = math.huge
	-- no driving, no horn
	if ride.Controller then pcall(function() ride.Controller:Stop() end) end
	RideManager.SilenceHorn(ride)
	-- frozen where it stands: the server holds the scooter, and the riders welded to it
	pcall(function() chassis:SetNetworkOwner(nil) end)
	chassis.AssemblyLinearVelocity = Vector3.zero
	chassis.AssemblyAngularVelocity = Vector3.zero
	for _, p in ipairs(scooter:GetDescendants()) do
		if p:IsA("BasePart") then p.Anchored = true end
	end
	-- the riders stay on it, in one piece, through what follows (as a landmine keeps them)
	local keep = {}
	for _, h in pairs(ride.Riders) do
		keep[h] = { KeepOnDeath = h.KeepOnDeath, Break = h.Humanoid and h.Humanoid.BreakJointsOnDeath }
		h.KeepOnDeath = true
		if h.Humanoid then h.Humanoid.BreakJointsOnDeath = false end
	end

	-- every machine plays the show from these (the start is a moment ahead, so all have it)
	local start = opts.Start or (workspace:GetServerTimeNow() + timeline.LEAD)
	scooter:SetAttribute("TrollBase", chassis.CFrame)
	scooter:SetAttribute("TrollStart", start)
	scooter:SetAttribute("TrollBy", ctx.BuyerName)
	scooter:SetAttribute("Troll", effectId)
	-- the two riders, and nobody else, are told
	for _, plr in ipairs(opts.Quiet and {} or ctx.Riders) do
		if plr.Parent then
			Remotes.TrollAlert:FireClient(plr, {
				Kind = "Trolled", Effect = effectId, Name = ctx.Def.Name, By = ctx.BuyerName,
				Start = start, Scooter = scooter,
				Revenge = ctx.Revenge and true or nil,   -- their banner: "<name> got REVENGE on you!"
			})
		end
	end

	local function live() return not ride._ended and scooter.Parent ~= nil end
	local function waitUntil(t)
		while live() and workspace:GetServerTimeNow() < t do task.wait() end
		return live()
	end

	local saved
	local ok = waitUntil(start + timeline.EXPLODE)
	if ok then
		saved = vanish(ride, scooter)
		ok = waitUntil(start + timeline.END)
	end
	if not ok then
		giveBack(keep, saved)
		if not ride._ended then ride.GraceUntil = graceWas end
		return false
	end

	-- the show is over: the duo leaves the spectate list and the ride goes down as an
	-- obstacle's would (the death popup for both riders)
	ride.TrollShow = nil
	ride.GraceUntil = graceWas
	-- ctx.Cause (TrollEffects): who did it, for REVENGE on the death popup
	DeathManager.Hit(ride, nil, ctx.Life, ctx.Cause)
	if not ride.Down and not ride._ended then
		-- never left frozen: ended as the popup's own timer would end it
		warn("[Troll] the " .. effectId .. " troll's ride didn't go down; ending it")
		DeathManager.Finish(ride, why)
	end
	return true
end

return TrollShow
