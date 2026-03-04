--!strict
local EncodingService = game:GetService("EncodingService")
local MemoryStoreService = game:GetService("MemoryStoreService")

-- Services

-- Modules
local Promise = require(script.Parent.roblox_packages.Promise)
local Schemas = require(script.Parent.Schemas)
local Utils = require(script.Parent.Utils)
local types = require(script.Parent.types)

local Key = {}
local KeyClass = { metatable = { __index = Key } }

type _Key<T> = types.Key<T> & {
	_dirty: boolean, -- Do we have unsaved changes?
	_lastSaved: number?,
	_options: types.KeyOptions<T>,
	_datastore: DataStore,
	_memlock: MemoryStoreSortedMap,
	_user: number,
	_jobs: { thread },

	_Lock: (self: _Key<T>) -> Promise.TypedPromise<boolean>,
	_Load: <T>(self: _Key<T>) -> Promise.TypedPromise<T?>,
}

Key.ClassName = "Key"

function Key._Lock<T>(self: _Key<T>): Promise.TypedPromise<boolean>
	local interval, user, memlock = self._options.LockInterval or 60, tostring(self._user), self._memlock

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
		warn(`Failed to acquire lock for key {self._datastore.Name} for user {self._user}: {err}`)
		return false
	end)
end

function Key._Load<T>(self: _Key<T>): Promise.TypedPromise<T?>
	if not self.Loaded and self._options.Lockable then
		table.insert(
			self._jobs,
			task.spawn(function()
				while true do
					self.Locked = not self:_Lock()
					task.wait(self._options.LockInterval or 60)
				end
			end)
		)
	end

	return Promise.new(function(resolve, reject)
		local success, data, info = pcall(self._datastore.GetAsync, self._datastore, tostring(self._user), nil)
		if not success then return reject(`Datastore GetAsync failed: {data}`) end

		if type(data) ~= "buffer" then return reject(`Expected existing data to be of type buffer Got {type(data)}`) end

		local metadata = info:GetMetadata()
		local schemaVersion = metadata.SchemaVersion
		local compressionAlgorithmName = metadata.CompressionAlgorithm

		if compressionAlgorithmName then
			local compressionAlgorithm = Enum.CompressionAlgorithm:FromName(metadata.CompressionAlgorithm or "")
			if compressionAlgorithm then data = EncodingService:DecompressBuffer(data, compressionAlgorithm) end
		end

		local schema = Schemas.GetSchema(self.Options.Schema.name, schemaVersion)
		if not schema then return reject(`No schema found with version {schemaVersion}`) end

		resolve(schema.schema:Read(data))
	end):catch(function(err)
		warn(`Failed to load key {self._datastore.Name} for user {self._user}: {err}`)
		return Utils.deepClone(self._options.Default)
	end)
end

function KeyClass.new<T>(options: types.KeyOptions<T>, datastore: DataStore, user: number, load: boolean?): types.Key<T>
	local self: _Key<T> = setmetatable({}, KeyClass.metatable) :: _Key<T>

	self._options = options
	self._datastore = datastore
	self._memlock = MemoryStoreService:GetSortedMap(datastore.Name)
	self._user = user
	self._dirty = false
	self._lastSaved = time()

	local data = if load then self:_Load():await() else nil

	-- TODO Make a deepproxy for data so that we can set the dirty flag and prevent direct modification when locked
	-- Also needs to load the datastore if it hasnt been loaded yet

	self.Loaded = not not load

	return self
end

return KeyClass
