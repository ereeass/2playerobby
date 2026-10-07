-- Starts this player's own background music (ReplicatedStorage.Music.MusicController).
-- StarterPlayerScripts run once per player session, not once per character, so
-- respawning never starts a second playlist.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MusicController = require(ReplicatedStorage:WaitForChild("Music"):WaitForChild("MusicController"))
MusicController:Start()
