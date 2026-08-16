--!optimize 2

-- Services
local EncodingService = game:GetService("EncodingService")
local MemoryStoreService = game:GetService("MemoryStoreService")
-- Modules
local Promise = require(script.Parent.Parent.roblox_packages.Promise)
local Schemas = require(script.Parent.Schemas)
local Utils = require(script.Parent.Utils)
local types = require(script.Parent.types)

local PROJECT = Utils.PROJECT

local Key = {}
local KeyClass = {
	metatable = {
		__index = Key,
		__newindex = function(self, key, value)
			assert(key ~= "Data", "Data cannot be reassigned. Use Key:Wipe to clear data")
			rawset(self, key, value)
		end,
	},
}

export type _Key<T> = types.Key<T> & {
	_loading: boolean,
	_readOnly: boolean,
	_dirty: boolean, -- Do we have unsaved changes?
	_lastSaved: number?,
	_datastore: DataStore,
	_memlock: MemoryStoreSortedMap,
	_user: number,
	_jobs: { thread },
	_data: T?,

	_Lock: (self: _Key<T>) -> Promise.TypedPromise<boolean>,
	_Unlock: (self: _Key<T>) -> Promise.Promise,
	_Save: (self: _Key<T>) -> Promise.Promise,
	_Load: (self: _Key<T>) -> Promise.TypedPromise<T?>,
	_Destroy: (self: _Key<T>) -> (),
}

Key.ClassName = "Key"

function Key._Lock<T>(self: _Key<T>): Promise.TypedPromise<boolean>
	if self.Options.Lockable == false or self._readOnly then return Promise.resolve(false) end
	local interval, user, memlock = self.Options.LockInterval or 60, tostring(self._user), self._memlock

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
	-- Only unlock if the key is lockable and we possess the lock (self.Locked == false)
	if not (self.Options.Lockable ~= false and not self.Locked) then return Promise.resolve() end
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
	-- Dont save if we dont have to or are in a locked state (from the key being locked by another server or read only)
	if not self._dirty or self._readOnly or (self.Options.Lockable ~= false and self.Locked) then return Promise.resolve() end

	return Promise.new(function(resolve, reject)
		local success, schemaInfo, dataToSave, err

		success, schemaInfo = pcall(Schemas.GetSchema, self.Options.Schema.name, nil)
		if not success then return reject(`Failed to get schema for key {self._datastore.Name} for user {self._user}: {schemaInfo}`) end

		assert(schemaInfo)
		success, dataToSave = pcall(schemaInfo.schema.Write, schemaInfo.schema, self._data)
		if not success then return reject(`Failed to encode data for key {self._datastore.Name} for user {self._user}: {dataToSave}`) end

		if self.Options.Compression then dataToSave = EncodingService:CompressBuffer(dataToSave, self.Options.Compression.algorithm, self.Options.Compression.compressionLevel) end

		local metadata = {
			SchemaVersion = schemaInfo.version,
			CompressionAlgorithm = if self.Options.Compression then self.Options.Compression.algorithm.Name else nil,
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
	if not self._loading and self.Options.Lockable ~= false then
		self._loading = true
		table.insert(
			self._jobs,
			task.spawn(function()
				while true do
					self.Locked = not self:_Lock():expect()
					task.wait(self.Options.LockInterval or 60)
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

		if data == nil then
			-- No existing data, start with default
			self._dirty = true
			return resolve(Utils.deepClone(self.Options.Default))
		end

		assert(info)
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
		if Utils.deepMerge(rawData, self.Options.Default or {}) then self._dirty = true end

		resolve(rawData)
	end):catch(function(err)
		warn(`Failed to load key {self._datastore.Name} for user {self._user}: {err}`)
		return Utils.deepClone(self.Options.Default)
	end)
end

function Key.Load<T>(self: _Key<T>)
	if self.Loaded then return end
	self._data = self:_Load():expect()
	self.Loaded = true
end

function Key.Wipe<T>(self: _Key<T>)
	if self._readOnly or (self.Options.Lockable ~= false and self.Locked) then
		warn(`Attempted to wipe locked key {self._datastore.Name} for user {self._user}`)
		return
	end

	self._data = Utils.deepClone(self.Options.Default or {})
	self._dirty = true
end

function Key._Destroy<T>(self: _Key<T> & { [any]: any })
	if getmetatable(self :: any) == "AbserdeTombstone" then return end

	local function deepClear(t: { [any]: any })
		for _, v in t do
			if type(v) == "table" then deepClear(v) end
		end
		table.clear(t)
		setmetatable(t, Utils.TOMBSTONE_METATABLE)
	end

	if self._data then
		deepClear(self._data)
		self._data = nil
	end

	for _, job in self._jobs do
		pcall(task.cancel, job)
	end

	table.clear(self)
	setmetatable(self, Utils.TOMBSTONE_METATABLE)
end

function KeyClass.new<T>(options: types.KeyOptions<T>, datastore: DataStore, user: number, load: boolean?, readOnly: boolean?): types.Key<T>
	local self: _Key<T> = setmetatable({}, KeyClass.metatable) :: _Key<T>

	self._readOnly = not not readOnly
	self._datastore = datastore
	self._memlock = MemoryStoreService:GetSortedMap(datastore.Name)
	self._user = user
	self._dirty = false
	self._lastSaved = time()
	self._jobs = {}

	self.Options = options

	if load then self:Load() end

	local ProxyMetatable = {}

	-- Proxy-private state, keyed by proxy identity rather than stored on the proxy
	-- itself. Weak keys mean an entry is collected as soon as nothing else holds
	-- the corresponding proxy — no state ever leaks into raw enumeration of the
	-- proxy, and no explicit cleanup is required.
	local ProxyState: { [any]: { path: { any }, children: { [any]: any } } } = setmetatable({}, { __mode = "k" })

	-- Builds a human readable path string for debugging.
	local function pathToString(pathKeys: { any }): string
		local parts = table.create(#pathKeys)
		for i, key in pathKeys do
			parts[i] = tostring(key)
		end
		return table.concat(parts, ".")
	end

	-- Walks down from the current `self._data` along `pathKeys`, returning the live
	-- table from that position, or nil if the path no longer resolves to a table
	-- (e.g. a parent was overwritten with a scalar or removed).
	local function resolveTable(pathKeys: { any }): any
		local targetTbl: any = self._data
		for _, key in pathKeys do
			local nextTbl = targetTbl[key]
			if type(nextTbl) ~= "table" then return nil end
			targetTbl = nextTbl
		end
		return targetTbl
	end

	local function createProxy(pathKeys: { any })
		local proxy: any = setmetatable({}, ProxyMetatable)
		ProxyState[proxy] = { path = pathKeys, children = setmetatable({}, { __mode = "v" }) } :: any
		return proxy
	end

	-- Given a value read from the live table at `key`, returns what a proxy consumer
	-- should see: scalars pass through unchanged, tables are wrapped in a cached
	-- child proxy so that further access (whether via __index or __iter) is
	-- consistently guarded and cache-coherent.
	local function getOrCreateChild(state: { path: { any }, children: { [any]: any } }, val: unknown, key: any): unknown
		if type(val) ~= "table" then return val end

		local child = state.children[key]
		if not child then
			local childPathKeys = table.clone(state.path)
			table.insert(childPathKeys, key)
			child = createProxy(childPathKeys)
			state.children[key] = child
		end
		return child
	end

	ProxyMetatable.__index = function(proxy, key: unknown): unknown
		assert(self.Loaded, "Key is not loaded. Call `Key:Load()` before reading or writing to it.")

		local state = ProxyState[proxy]
		local pathKeys = state.path
		local targetTbl = resolveTable(pathKeys)
		if targetTbl == nil then return nil end

		return getOrCreateChild(state, targetTbl[key], key)
	end

	ProxyMetatable.__newindex = function(proxy, key: unknown, newVal: unknown)
		assert(self.Loaded, "Key is not loaded. Call `Key:Load()` before reading or writing to it.")

		if self._readOnly or (self.Options.Lockable ~= false and self.Locked) then return warn(`Attempted to write to locked key {self._datastore.Name} for user {self._user}`) end

		local state = ProxyState[proxy]
		local targetTbl = resolveTable(state.path)
		if targetTbl == nil then error(`Cannot write to "{key}": parent path "{pathToString(state.path)} no longer resolves to a table."`) end

		-- If the value being assigned is itself one of our proxies, unwrap it to
		-- the live table it currently represents. This is what makes
		-- `data.X = data.Y or {}` work regardless of whether `data.Y` already
		-- exists: when it does, the read returns a proxy, which is unwrapped
		-- back to the same underlying table it already refers to, so the
		-- assignment is a harmless no-op. It also allows genuine cross-tree
		-- reference assignment, e.g. `data.A.Foo = data.B.Bar`.
		local newValState = ProxyState[newVal]
		local resolvedVal = if newValState then resolveTable(newValState.path) else newVal

		local oldVal = targetTbl[key]
		if oldVal ~= resolvedVal then
			targetTbl[key] = resolvedVal
			self._dirty = true
			state.children[key] = nil
		end
	end

	ProxyMetatable.__iter = function(proxy)
		assert(self.Loaded, "Key is not loaded. Call `Key:Load()` before reading or writing to it.")

		local state = ProxyState[proxy]
		local targetTbl = resolveTable(ProxyState[proxy].path) or {}

		return function(_, k): (unknown, unknown)
			local nk, nv = next(targetTbl, k)
			if nk == nil then return nil, nil end
			return nk, getOrCreateChild(state, nv, nk)
		end,
			nil,
			nil
	end

	ProxyMetatable.__len = function(proxy)
		assert(self.Loaded, "Key is not loaded. Call `Key:Load()` before reading or writing to it.")

		local targetTbl = resolveTable(ProxyState[proxy].path)
		return targetTbl and #targetTbl or 0
	end

	self.Loaded = not not load
	rawset(self :: any, "Data", createProxy({}))

	-- Handle autosave
	local autosaveInterval = options.AutosaveInterval or 300
	if autosaveInterval > 0 then
		table.insert(
			self._jobs,
			task.spawn(function()
				while task.wait(autosaveInterval) do
					self:_Save():catch(function(err)
						warn(`[Abserde]: Autosave failed for {datastore.Name}: {err}`)
					end)
				end
			end)
		)
	end

	return self
end

return KeyClass
