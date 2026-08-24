--!strict

-- Services
local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local TestService = game:GetService("TestService")
-- Modules
local Courier = require(script.Parent.Courier)
local Key = require(script.Parent.Key)
local Pack = require(script.Parent.Parent.roblox_packages.Pack)
local Promise = require(script.Parent.Parent.roblox_packages.Promise)
local Scythe = require(script.Parent.Parent.roblox_packages.Scythe)
local Signal = require(script.Parent.Parent.roblox_packages.Signal)
local Utils = require(script.Parent.Utils)
local types = require(script.Parent.types)

local AbserdeSession = {}
local AbserdeSessionClass = { metatable = { __index = AbserdeSession } }
type _AbserdeSession<T> = types.Session<T> & {
	_closingPromise: Promise.TypedPromise<>?,
	_readOnly: boolean,
	_memlock: MemoryStoreSortedMap,
	_Lock: (self: _AbserdeSession<T>) -> Promise.TypedPromise<boolean>,
	_Unlock: (self: _AbserdeSession<T>) -> Promise.TypedPromise<>,
	_scythe: number,
}

AbserdeSession.ClassName = "AbserdeSession"

local datastoreCache: { [string]: DataStore } = {}
function AbserdeSessionClass.getDataStore(profileName: string, key: string, slot: number): DataStore
	local cacheKey = `{profileName}_{key}{slot - 1}`
	if not datastoreCache[cacheKey] then datastoreCache[cacheKey] = DataStoreService:GetDataStore(cacheKey) end
	return datastoreCache[cacheKey]
end

function AbserdeSession._Lock<T>(self: _AbserdeSession<T>): Promise.TypedPromise<boolean>
	if getmetatable(self) == "AbserdeTombstone" then return Promise.resolve(false) end
	if self._readOnly then return Promise.resolve(false) end
	local interval, user, memlock = self.Profile.LockInterval or 60, tostring(self.User), self._memlock

	return Promise.retryWithDelay(function()
		return Promise.new(function(resolve, reject)
			local jobId
			local success, result = pcall(memlock.UpdateAsync, memlock, user, function(oldValue: string?)
				jobId = oldValue
				-- Return JobId to lock, or nil if already locked by someone else
				return if jobId == nil or jobId == game.JobId then game.JobId else nil
			end, interval + 30)

			if not success then
				return reject(result) -- Triggers the retry
			end

			if not result then
				-- This means the lock is held by another JobId
				return resolve(false)
			end

			resolve(true)
		end)
	end, 3, 1):catch(function(err)
		warn(`Failed to acquire lock for key {self.Profile.Name} for user {self.User}: {err}`)
		return false
	end)
end

function AbserdeSession._Unlock<T>(self: _AbserdeSession<T>): Promise.TypedPromise<>
	if getmetatable(self) == "AbserdeTombstone" then return Promise.resolve() end
	if not self.Locked then return Promise.resolve() end
	local user, memlock = tostring(self.User), self._memlock

	return Promise.new(function(resolve, reject)
		local success, err = pcall(memlock.RemoveAsync, memlock, user)
		if not success then
			warn(`Failed to release lock for session {self.Profile.Name}:{self.User}: {err}`)
			return reject(err)
		end
		self.Locked = false
		resolve()
	end)
end

function AbserdeSession.Save<T>(self: _AbserdeSession<T>)
	if getmetatable(self :: any) == "AbserdeTombstone" then return Promise.resolve() end
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

function AbserdeSession.Release<T>(self: _AbserdeSession<T>)
	if getmetatable(self :: any) == "AbserdeTombstone" then return Promise.resolve() end

	local promise = self:_Unlock()

	promise:andThen(function()
		for _, key in self.Keys :: { Key._Key<unknown> } do
			key.Locked = false
		end
	end)

	return promise
end

function AbserdeSession.Close<T>(self: _AbserdeSession<T>)
	if getmetatable(self :: any) == "AbserdeTombstone" then return Promise.resolve() end

	if self._closingPromise ~= nil then return self._closingPromise end

	self._closingPromise = Promise.new(function(resolve)
		Scythe.clean(self._scythe)

		-- If there are ongoing saves in any keys, cancel them so the latest data is saved on close
		for _, key in self.Keys :: { [string]: Key._Key<unknown> } do
			if key._savingPromise and key._savingPromise:getStatus() == "Started" then key._savingPromise:cancel() end
		end

		local success, err
		success, err = self:Save():await()
		if not success then TestService:Error(`[Abserde]: Error saving profile {self.Profile.Name}<{self.User}> while closing: {err}`) end
		success, err = self:Release():await()
		if not success then TestService:Error(`[Abserde]: Error releasing profile {self.Profile.Name}<{self.User}> while closing: {err}`) end

		if getmetatable(self :: any) == "AbserdeTombstone" then return resolve() end

		self.Closing:Fire()
		self.Closing:Destroy()

		for _, key in self.Keys :: { [string]: Key._Key<unknown> } do
			key:_Destroy()
		end

		table.clear(self)
		self.Open = false
		setmetatable(self, Utils.TOMBSTONE_METATABLE)
		resolve()
	end)
	return self._closingPromise :: any
end

function AbserdeSession.AtomicSet<T>(self: types.Session<T>, key: string, value: any)
	warn("[Abserde]: AtomicSet is not yet implemented. This method will be fleshed out in a future update.")
	return Promise.new(function(resolve, reject)
		local keyPath: string, path: string = (string.match :: any)(key, "([^/]+)/?(.*)")
		local sKey = assert((self.Profile.Keys :: { [string]: types.KeyOptions<unknown> })[keyPath], `Unable to find session key {keyPath}`)

		-- If a session is already open or we can open one right now, use that

		-- If a session is already open in another server, send a message through Courier
		-- TODO: Get lock JobId, send message and wait for completion
		-- Resolve the subschema for the value so we can encode it for transmission
		local schema = sKey.Schema.schema
		local subSchema = Pack:Reflect(schema, path)
		-- Attempt to encode the value using the reflected subschema
		if not subSchema then return reject(`[Abserde]: Could not resolve the subschema for {key}. Check reflection limitations`) end
		local s, encoded = pcall(subSchema.Write, subSchema, value)
		if not s then return reject(`[Abserde]: Error encoding value {value} for subschema {key}: {encoded}`) end
		-- Message the existing server to update the value.

		-- Modify the value in this read only session
	end)
end

function AbserdeSession.Refresh<T>(self: types.Session<T>)
	warn("[Abserde]: Refresh is not yet implemented. This method will be fleshed out in a future update.")
	return Promise.resolve()
end

function AbserdeSessionClass.new<T>(profile: types.ProfileOptions<T>, userid: number, slot: number, readOnly: boolean?): types.Session<T>
	assert(#profile.Name <= 24, "Profile names cannot exceed 24 characters")
	local self: _AbserdeSession<T> = setmetatable({}, AbserdeSessionClass.metatable) :: any

	self.Profile = profile
	self.User = userid
	self.Closing = Signal.new()
	self._readOnly = not not readOnly
	self._memlock = MemoryStoreService:GetSortedMap(profile.Name)
	self.Locked = nil :: any -- We block the thread until the lock has been initialized
	self._scythe = Scythe.scope()

	if not readOnly then
		Scythe.add(
			self._scythe,
			task.spawn(function()
				while true do
					self.Locked = not self:_Lock():expect()

					if self.Keys then
						for _, key in self.Keys :: { Key._Key<unknown> } do
							key.Locked = self.Locked
						end
					end

					task.wait(profile.LockInterval or 60)
				end
			end)
		)
	end

	local keys = {}
	-- Datastore names are `{profile.Name}_{key}{slot - 1}`
	-- TODO: encode slot as base64 to allow for 64 slots instead of 10
	-- Datastore key is just userid

	-- The schema version will be stored as metadata for the key
	for key, options in profile.Keys :: { [string]: types.KeyOptions<any> } do
		assert(#key <= 24, "Profile key names cannot exceed 24 characters")
		local datastore = AbserdeSessionClass.getDataStore(profile.Name, key, slot)

		-- TODO: Make Key.new return a promise and block with Promise.all to speed things up with many AutoLoad keys
		keys[key] = Key.new(options, datastore, userid, not readOnly and options.AutoLoad ~= false, readOnly)
	end

	self.Keys = table.freeze(keys)

	-- Ensure the lock has been established
	if self.Locked == nil then
		repeat
			task.wait()
		until self.Locked ~= nil
	end

	for _, key in self.Keys :: { Key._Key<unknown> } do
		key.Locked = self.Locked
	end

	self.Open = true
	self._closingPromise = nil

	return self
end

return AbserdeSessionClass
