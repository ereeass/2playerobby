-- Starts this player's settings (ReplicatedStorage.SettingsSystem.SettingsController):
-- loads them from their account and applies them (volumes, shadows).
-- StarterPlayerScripts run once per player session, not once per character, so
-- respawning never starts it twice.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Settings = require(ReplicatedStorage:WaitForChild("SettingsSystem"):WaitForChild("SettingsController"))
Settings:Start()
