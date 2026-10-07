--=====================================================================
-- AnimatorRestartFix   (each player's own machine)
--
-- RiderPose (server) restarts a rider's Animator when a ride starts and ends, so Roblox's
-- Animator takes up / lets go of the ride's IKControls. Every restart makes Roblox play the
-- face's mood animation (Animate.mood) again without stopping the copy already playing, so
-- copies piled up - measured: two more every ride, and at 256 tracks an Animator stops
-- playing new animations at all. This keeps only the newest copy of each mood animation on
-- this player's own character (its animations are this machine's, so the others see the same).
--=====================================================================

local Players = game:GetService("Players")
local player  = Players.LocalPlayer

local CHECK_EVERY = 2   -- seconds: a quick look at the character's playing tracks

local function dedupe(animator)
	local newest = {}   -- [AnimationId] = the copy started last (it has played the shortest time)
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		local anim = track.Animation
		local folder = anim and anim.Parent
		if folder and folder.Name == "mood" then
			local id = anim.AnimationId
			local keep = newest[id]
			if not keep then
				newest[id] = track
			elseif track.TimePosition < keep.TimePosition then
				keep:Stop(0)
				newest[id] = track
			else
				track:Stop(0)
			end
		end
	end
end

local function animatorOf(char)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum and hum:FindFirstChildOfClass("Animator")
end

local function watch(char)
	local hum = char:WaitForChild("Humanoid", 10)
	local an = hum and (hum:FindFirstChildOfClass("Animator") or hum:WaitForChild("Animator", 10))
	if not an then return end
	-- straight after a restart, when it's seen
	an.AncestryChanged:Connect(function(_, parent)
		if parent == hum then
			task.delay(0.5, function() if an.Parent == hum then dedupe(an) end end)
		end
	end)
end

player.CharacterAdded:Connect(watch)
if player.Character then task.spawn(watch, player.Character) end

-- and a regular look, in case a restart wasn't seen as a change here
while true do
	task.wait(CHECK_EVERY)
	local an = animatorOf(player.Character)
	if an then pcall(dedupe, an) end
end
