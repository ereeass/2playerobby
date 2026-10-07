--[[ AssetLoader

The real asset preload behind the loading screen, built so it can never hang it.

  local loader = AssetLoader.new(roots, skip)
      Scans the roots and starts preloading straight away, in the background:
      it never yields the caller. Objects that arrive under the roots later
      (the map streaming in, the character, its GUIs) are picked up too, until
      Finish(). skip = { [assetId] = true }.
  loader:Progress()  -> done, total
  loader:Finish()    -> { downloads, failed, pending }
      Stops counting. Anything still out is written off and the count reads
      total / total; the downloads themselves carry on in the background.

Every object under the roots is one item. An object that points at
downloadable content (images, meshes, sounds, animations) is done once Roblox
has reported all of its content back, loaded or failed; any other object is
done as soon as it is seen. Each asset is fetched once however many objects
share it, and counts once however many callbacks arrive for it. Assets are
requested in separate PreloadAsync calls, so one that never answers only holds
up the objects that use it - and Finish() writes those off.
]]

local ContentProvider = game:GetService("ContentProvider")

-- At most this many PreloadAsync calls out at once; the rest wait their turn. Firing one per
-- object all together (hundreds at join) made Roblox's servers refuse them ("HTTP 429 Too Many
-- Requests", timeouts, meshes that "could not fetch").
local MAX_IN_FLIGHT = 6

-- Every property that points at downloadable content.
local FIELDS = {
	Decal             = { "Texture" },
	Texture           = { "Texture" },
	ImageLabel        = { "Image" },
	ImageButton       = { "Image", "HoverImage", "PressedImage" },
	Sky               = { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp", "SunTextureId", "MoonTextureId" },
	ParticleEmitter   = { "Texture" },
	Beam              = { "Texture" },
	Trail             = { "Texture" },
	MaterialVariant   = { "ColorMap", "MetalnessMap", "NormalMap", "RoughnessMap" },
	SurfaceAppearance = { "ColorMap", "MetalnessMap", "NormalMap", "RoughnessMap" },
	Shirt             = { "ShirtTemplate" },
	Pants             = { "PantsTemplate" },
	ShirtGraphic      = { "Graphic" },
	MeshPart          = { "MeshId", "TextureID" },
	SpecialMesh       = { "MeshId", "TextureId" },
	FileMesh          = { "MeshId", "TextureId" },
	CharacterMesh     = { "MeshId", "BaseTextureId", "OverlayTextureId" },
	Sound             = { "SoundId" },
	Animation         = { "AnimationId" },
}

-- One key per asset, however it is spelled (rbxassetid://1, .../asset/?id=1, 1).
-- rbxasset:// files ship with the Roblox client, so there is nothing to fetch.
local function keyOf(id)
	if type(id) == "number" then return id > 0 and tostring(id) or nil end
	if type(id) ~= "string" or id == "" or id:sub(1, 11) == "rbxasset://" then return nil end
	local n = id:match("^rbxassetid://(%d+)")
	if not n and id:find("^https?://") then n = id:match("[?&][iI][dD]=(%d+)") end
	return n or id:lower()
end

-- The assets one object points at, each listed once.
local function contentKeys(inst, skip)
	local props = FIELDS[inst.ClassName]
	if not props then return nil end
	local keys, seen = {}, {}
	for _, prop in ipairs(props) do
		local ok, value = pcall(function() return inst[prop] end)
		local key = ok and keyOf(value) or nil
		if key and not skip[key] and not seen[key] then
			seen[key] = true
			table.insert(keys, key)
		end
	end
	return keys
end

local AssetLoader = {}
AssetLoader.__index = AssetLoader

-- preload is only passed in by tests (e.g. one that never answers).
function AssetLoader.new(roots, skip, preload)
	skip = skip or {}
	preload = preload or function(list, callback) ContentProvider:PreloadAsync(list, callback) end

	local self = setmetatable({ done = 0, total = 0, downloads = 0, failed = 0, finished = false }, AssetLoader)
	local counted = {}     -- object -> true once it is in the total
	local waitingOn = {}   -- asset key -> objects still waiting for it
	local reported = {}    -- asset key -> true once it has come back
	local left = {}        -- object -> how many of its assets are still out
	self._waitingOn, self._counted, self._conns = waitingOn, counted, {}

	-- An asset has come back (loaded, failed or timed out). Only its first report
	-- counts, however many callbacks arrive for it; after Finish() nothing counts.
	local function report(key, failed)
		local users = key and waitingOn[key]
		if not users then return end
		waitingOn[key] = nil
		reported[key] = true
		if failed then self.failed += 1 end
		if self.finished then return end
		for _, inst in ipairs(users) do
			left[inst] -= 1
			if left[inst] == 0 then self.done += 1 end
		end
	end

	-- the queue of preloads not sent yet, and how many are out now (MAX_IN_FLIGHT)
	local queue, head, tail, inFlight = {}, 1, 0, 0
	local function pump()
		while inFlight < MAX_IN_FLIGHT and queue[head] do
			local job = queue[head]
			queue[head] = nil
			head += 1
			inFlight += 1
			task.spawn(function()
				job()
				inFlight -= 1
				pump()
			end)
		end
	end

	local function request(inst, keys)
		tail += 1
		queue[tail] = function()
			local ok = pcall(preload, { inst }, function(id, status)
				report(keyOf(id), status ~= Enum.AssetFetchStatus.Success)
			end)
			-- the call has returned, so everything this object points at has been processed
			for _, key in ipairs(keys) do report(key, not ok) end
		end
		pump()
	end

	local function add(inst)
		if self.finished or counted[inst] then return end
		counted[inst] = true
		self.total += 1
		local out, fresh = {}, false
		for _, key in ipairs(contentKeys(inst, skip) or {}) do
			if not reported[key] then
				table.insert(out, key)
				if not waitingOn[key] then
					waitingOn[key] = {}
					self.downloads += 1
					fresh = true
				end
				table.insert(waitingOn[key], inst)
			end
		end
		if #out == 0 then
			self.done += 1
			return
		end
		left[inst] = #out
		if fresh then request(inst, out) end
	end

	for _, root in ipairs(roots) do
		table.insert(self._conns, root.DescendantAdded:Connect(add))
		for _, inst in ipairs(root:GetDescendants()) do add(inst) end
	end
	return self
end

function AssetLoader:Progress()
	return self.done, self.total
end

function AssetLoader:Finish()
	if not self.finished then
		self.finished = true
		self.done = self.total
		for _, c in ipairs(self._conns) do c:Disconnect() end
		table.clear(self._counted)
	end
	local pending = 0
	for _ in pairs(self._waitingOn) do pending += 1 end
	return { downloads = self.downloads, failed = self.failed, pending = pending }
end

return AssetLoader
