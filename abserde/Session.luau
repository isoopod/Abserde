--!strict

-- Services
local DataStoreService = game:GetService("DataStoreService")
local TestService = game:GetService("TestService")
-- Modules
local Key = require(script.Parent.Key)
local Promise = require(script.Parent.roblox_packages.Promise)
local Utils = require(script.Parent.Utils)
local types = require(script.Parent.types)

local AbserdeSession = {}
local AbserdeSessionClass = { metatable = { __index = AbserdeSession } }
type _AbserdeSession<T> = types.Session<T> & {}

AbserdeSession.ClassName = "AbserdeSession"

local datastoreCache: { [string]: DataStore } = {}
local function getDataStore(profileName: string, key: string, slot: number): DataStore
	local cacheKey = `{profileName}_{key}{slot - 1}`
	if not datastoreCache[cacheKey] then datastoreCache[cacheKey] = DataStoreService:GetDataStore(cacheKey) end
	return datastoreCache[cacheKey]
end

function AbserdeSession.Save<T>(self: types.Session<T>)
	local promises: { any } = {}
	for name, key in self.Keys :: { [string]: Key._Key<unknown> } do
		table.insert(
			promises,
			key:_Save():andThen(function()
				return { success = true, name = name }
			end, function(err)
				warn(`[Abserde]: Save failed for key {name}: {err}`)
				return { success = false, name = name }
			end)
		)
	end

	return Promise.all(promises):andThen(function(results)
		local failed: { any } = {}
		for _, result in results do
			if not result.success then table.insert(failed, result.name) end
		end
		if #failed ~= 0 then return Promise.reject(`Failed to save all keys: {table.concat(failed, ", ")}`) end
		return Promise.resolve()
	end)
end

function AbserdeSession.Release<T>(self: types.Session<T>)
	local promises: { any } = {}
	for name, key in self.Keys :: { [string]: Key._Key<unknown> } do
		table.insert(
			promises,
			key:_Unlock():andThen(function()
				return { success = true, name = name }
			end, function(err)
				warn(`[Abserde]: Release failed for key {name}: {err}`)
				return { success = false, name = name }
			end)
		)
	end

	return Promise.all(promises):andThen(function(results)
		local failed: { any } = {}
		for _, result in results do
			if not result.success then table.insert(failed, result.name) end
		end
		if #failed ~= 0 then return Promise.reject(`Failed to release all keys: {table.concat(failed, ", ")}`) end
		return Promise.resolve()
	end)
end

function AbserdeSession.Close<T>(self: types.Session<T>)
	return Promise.new(function(resolve)
		local success, err
		success, err = self:Save():await()
		if not success then TestService:Error(`[Abserde]: Error saving profile {self.Profile}<{self.User}> while closing: {err}`) end
		success, err = self:Release():await()
		if not success then TestService:Error(`[Abserde]: Error releasing profile {self.Profile}<{self.User}> while closing: {err}`) end

		self.Closing:Fire()
		self.Closing:Destroy()

		for _, key in self.Keys :: { [string]: Key._Key<unknown> } do
			key:_Destroy()
		end

		table.clear(self)
		self.Open = false
		setmetatable(self, Utils.TOMBSTONE_METATABLE)
		table.freeze(self)
		resolve()
	end)
end

function AbserdeSessionClass.new<T>(profile: types.ProfileOptions<T>, userid: number, slot: number, readOnly: boolean?): types.Session<T>
	assert(#profile.Name <= 24, "Profile names cannot exceed 24 characters")
	local self: _AbserdeSession<T> = setmetatable({}, AbserdeSessionClass.metatable) :: any

	self.Profile = profile.Name
	self.User = userid

	local keys = {}
	-- Datastore names are `{profile.Name}_{key}{slot - 1}`
	-- TODO: encode slot as base64 to allow for 64 slots instead of 10
	-- Datastore key is just userid

	-- The schema version will be stored as metadata for the key
	for key, options in profile.Keys :: { [string]: types.KeyOptions<any> } do
		assert(#key <= 24, "Profile key names cannot exceed 24 characters")
		local datastore = getDataStore(profile.Name, key, slot)

		keys[key] = Key.new(options, datastore, userid, not readOnly and options.AutoLoad, readOnly)
	end

	self.Keys = table.freeze(keys)
	self.Open = true

	return self
end

return AbserdeSessionClass
