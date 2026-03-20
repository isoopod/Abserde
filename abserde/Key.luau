--!optimize 2

-- Services
local EncodingService = game:GetService("EncodingService")
local MemoryStoreService = game:GetService("MemoryStoreService")
-- Modules
local Promise = require(script.Parent.roblox_packages.Promise)
local Schemas = require(script.Parent.Schemas)
local Utils = require(script.Parent.Utils)
local types = require(script.Parent.types)

local PROJECT = Utils.PROJECT

local Key = {}
local KeyClass = { metatable = { __index = Key } }

export type _Key<T> = types.Key<T> & {
	_loading: boolean,
	_readOnly: boolean,
	_dirty: boolean, -- Do we have unsaved changes?
	_lastSaved: number?,
	_options: types.KeyOptions<T>,
	_datastore: DataStore,
	_memlock: MemoryStoreSortedMap,
	_user: number,
	_jobs: { thread },
	_data: T?,

	_Lock: (self: _Key<T>) -> Promise.TypedPromise<boolean>,
	_Unlock: (self: _Key<T>) -> Promise.Promise,
	_Save: (self: _Key<T>) -> Promise.Promise,
	_Load: (self: _Key<T>) -> Promise.TypedPromise<T?>,
	_EnsureLoaded: (self: _Key<T>) -> (),
	_Destroy: (self: _Key<T>) -> (),
}

Key.ClassName = "Key"

function Key._Lock<T>(self: _Key<T>): Promise.TypedPromise<boolean>
	if not self.Options.Lockable or self._readOnly then return Promise.resolve(false) end
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

function Key._Unlock<T>(self: _Key<T>): Promise.Promise
	if not (self.Options.Lockable and not self.Locked) then return Promise.resolve() end
	local user, memlock = tostring(self._user), self._memlock

	return Promise.new(function(resolve, reject)
		local success, err = pcall(memlock.RemoveAsync, memlock, user)
		if not success then
			warn(`Failed to release lock for key {self._datastore.Name} for user {self._user}: {err}`)
			return reject(err)
		end
		resolve()
	end)
end

local MAX_RETRIES = 5
local BACKOFF_TIME = 5

local function isErrorRecoverable(error: string)
	local e = string.lower(error)
	return string.find(e, "throttled")
		or string.find(e, "corrupted") -- 501
		or string.find(e, "rejected the request with error") -- 502
		or string.find(e, "successful but") -- 503 / 504
end

function Key._Save<T>(self: _Key<T>): Promise.Promise
	if not self._dirty or self._readOnly or (self.Options.Lockable and self.Locked) then return Promise.resolve() end

	return Promise.new(function(resolve, reject)
		local success, schemaInfo, dataToSave, err

		success, schemaInfo = pcall(Schemas.GetSchema, self.Options.Schema.name, nil)
		if not success then return reject(`Failed to get schema for key {self._datastore.Name} for user {self._user}: {schemaInfo}`) end

		assert(schemaInfo)
		success, dataToSave = pcall(schemaInfo.schema.Write, schemaInfo.schema, self._data)
		if not success then return reject(`Failed to encode data for key {self._datastore.Name} for user {self._user}: {dataToSave}`) end

		if self._options.Compression then
			dataToSave = EncodingService:CompressBuffer(dataToSave, self._options.Compression.algorithm, self._options.Compression.compressionLevel)
		end

		local metadata = {
			SchemaVersion = schemaInfo.version,
			CompressionAlgorithm = if self._options.Compression then self._options.Compression.algorithm.Name else nil,
		}

		local setOptions = Instance.new("DataStoreSetOptions")
		setOptions:SetMetadata(metadata)

		for attempt = 1, MAX_RETRIES do
			success, err = pcall(self._datastore.SetAsync, self._datastore, tostring(self._user), dataToSave, { self._user }, setOptions)
			if success or not isErrorRecoverable(err) then break end
			if attempt < MAX_RETRIES then task.wait(BACKOFF_TIME * 2 ^ attempt * (0.5 + math.random() * 0.5)) end
		end
		if not success then return reject(`Datastore SetAsync failed for key {self._datastore.Name} for user {self._user}: {err}`) end

		self._dirty = false
		self._lastSaved = time()
		resolve()
	end)
end

function Key._Load<T>(self: _Key<T>): Promise.TypedPromise<T?>
	-- If this is a lockable key and its our first time loading, start the lock loop
	if not self._loading and self._options.Lockable then
		self._loading = true
		table.insert(
			self._jobs,
			task.spawn(function()
				while true do
					self.Locked = not self:_Lock():expect()
					task.wait(self._options.LockInterval or 60)
				end
			end)
		)
	end

	return Promise.new(function(resolve, reject, onCancel)
		local cancelled = false
		onCancel(function()
			cancelled = true
		end)

		-- Attempt to load the datastore value. Will retry forever every 5 seconds until it succeeds, unless the promise is cancelled
		-- This is to handle transient datastore errors that can occur, especially with large data. We don't want to fail loading just because of a temporary error
		local success, data, info
		local attempt = 0
		while not success do
			if cancelled then return reject("Promise cancelled") end
			success, data, info = pcall(self._datastore.GetAsync, self._datastore, tostring(self._user), nil)
			if not success then
				attempt += 1
				warn(`[Attempt {attempt}] Datastore GetAsync failed for key {self._datastore.Name} for user {self._user}: {data}`)
				task.wait(5)
			end
		end
		assert(data and info)

		if data == nil then
			-- No existing data, start with default
			self._dirty = true
			return resolve(Utils.deepClone(self._options.Default))
		end
		if type(data) ~= "buffer" then return reject(`Expected existing data to be of type buffer Got {type(data)}`) end

		-- We save metadata in the datastore incase certain settings like compression change in the Profile. This allows us to still load old data correctly
		local metadata = info:GetMetadata()
		local schemaVersion = metadata.SchemaVersion
		local compressionAlgorithmName = metadata.CompressionAlgorithm

		-- If this data was compressed, decompress before decoding
		if compressionAlgorithmName then
			local compressionAlgorithm = Enum.CompressionAlgorithm:FromName(metadata.CompressionAlgorithm or "")
			if compressionAlgorithm then data = EncodingService:DecompressBuffer(data, compressionAlgorithm) end
		end

		local schema = Schemas.GetSchema(self.Options.Schema.name, schemaVersion)
		if not schema then return reject(`No schema found with version {schemaVersion}`) end

		local rawData = schema.schema:Read(data)

		-- Handle data transformations for version migrations
		-- Transformations apply based on the last saved version. Any transformations above that version will be applied in order until we are up to date
		local transformation = self.Options.TransformationFile
		local transformationFile = transformation and PROJECT.Transformations:FindFirstChild(transformation)
		if transformationFile then
			local s, transformations = pcall(require, transformationFile)
			if s then
				-- Since the transformation file might be sparse (missing some versions), we need to build an ordered list of versions to iterate over
				local versions = {}
				for v in transformations do
					table.insert(versions, v)
				end
				table.sort(versions)
				-- Apply transformations in order
				for _, version in versions do
					if version > schemaVersion then rawData = transformations[version](rawData) end
				end
			else
				warn(`Failed to load transformation file {transformationFile.Name}: {transformations}`)
			end
		elseif transformation then
			warn(`Transformation file {transformation} not found in project Transformations folder`)
		end

		-- Hydrate the existing data with the default value so that missing keys are filled in, but existing values are not overwritten
		if Utils.deepMerge(rawData, self._options.Default or {}) then self._dirty = true end

		resolve(rawData)
	end):catch(function(err)
		warn(`Failed to load key {self._datastore.Name} for user {self._user}: {err}`)
		return Utils.deepClone(self._options.Default)
	end)
end

function Key._EnsureLoaded<T>(self: _Key<T>)
	if self.Loaded then return end
	self._data = self:_Load():expect()
	self.Loaded = true
end

function Key._Destroy<T>(self: _Key<T> & { [any]: any })
	if getmetatable(self :: any) == "AbserdeTombstone" then return end

	local function deepClear(t: { [any]: any })
		for _, v in t do
			if type(v) == "table" then deepClear(t) end
		end
		table.clear(t)
		setmetatable(t, Utils.TOMBSTONE_METATABLE)
		table.freeze(t)
	end

	if self._data then
		deepClear(self._data)
		self._data = nil
	end

	table.clear(self)
	setmetatable(self, Utils.TOMBSTONE_METATABLE)
	table.freeze(self :: any)
end

function KeyClass.new<T>(options: types.KeyOptions<T>, datastore: DataStore, user: number, load: boolean?, readOnly: boolean?): types.Key<T>
	local self: _Key<T> = setmetatable({}, KeyClass.metatable) :: _Key<T>

	self._readOnly = not not readOnly
	self._options = options
	self._datastore = datastore
	self._memlock = MemoryStoreService:GetSortedMap(datastore.Name)
	self._user = user
	self._dirty = false
	self._lastSaved = time()

	if load then self:_EnsureLoaded() end

	local proxyCache = setmetatable({}, { __mode = "k" })
	local function createProxy(tbl: any, path: string)
		if type(tbl) ~= "table" then return tbl end
		if proxyCache[tbl] then return proxyCache[tbl] end

		local proxy = setmetatable({}, {
			__index = function(_, key: string)
				self:_EnsureLoaded()

				local targetTbl = if path == "" then self._data else tbl
				local val = targetTbl[key]

				if type(val) == "table" and rawget(val, "__value") and not next(val, "__value") then return val.__value end
				if type(val) == "table" then return createProxy(val, Utils.concatPath(path, key)) end
				return val
			end,
			__newindex = function(_, key: string, newVal: unknown)
				self:_EnsureLoaded()

				if self._options.Lockable and self.Locked then
					warn(`Attempted to write to locked key {self._datastore.Name} for user {self._user}`)
					return
				end

				local targetTbl = if path == "" then self._data else tbl
				local oldVal = targetTbl[key]

				if oldVal ~= newVal then
					targetTbl[key] = newVal
					self._dirty = true
				end
			end,
			__iter = function()
				self:_EnsureLoaded()

				local targetTbl = if path == "" then self._data else tbl
				return function(_, k)
					local nk, nv = next(targetTbl, k)
					return nk, nv
				end, nil, nil
			end,
		})

		proxyCache[tbl] = proxy
		return proxy
	end

	self.Loaded = not not load

	self.Data = createProxy({}, "")

	return self
end

return KeyClass
