--!optimize 2

-- Services
const EncodingService = game:GetService("EncodingService")
const MemoryStoreService = game:GetService("MemoryStoreService")
-- Modules
const Promise = require(script.Parent.Parent.roblox_packages.Promise)
const Schemas = require(script.Parent.Schemas)
const Scythe = require(script.Parent.Parent.roblox_packages.Scythe)
const Utils = require(script.Parent.Utils)
const types = require(script.Parent.types)

export type _Key<T> = types.Key<T> & {
	_readOnly: boolean,
	_dirty: boolean, -- Do we have unsaved changes?
	_savingPromise: Promise.TypedPromise<>?,
	_loadingPromise: Promise.TypedPromise<T?>?,
	_datastore: DataStore,
	_memlock: MemoryStoreSortedMap,
	_user: number,
	_data: T?,
	_scythe: number,

	_Save: (self: _Key<T>) -> Promise.Promise,
	_Load: (self: _Key<T>) -> Promise.TypedPromise<T?>,
	_Destroy: (self: _Key<T>) -> (),
}

const PROJECT = Utils.PROJECT

const Key = {}
const KeyClass = {
	metatable = {
		__index = Key,
		__newindex = function(self, key, value)
			assert(key ~= "Data", "Data cannot be reassigned. Use Key:Wipe to clear data")
			rawset(self, key, value)
		end,
	},
}

Key.ClassName = "Key"

const KeyCache: { [string]: _Key<any> } = {}

const MAX_RETRIES = 5
const BACKOFF_TIME = 5

const function isErrorRecoverable(error: string)
	const e = string.lower(error)
	return string.find(e, "throttled")
		or string.find(e, "corrupted") -- 501
		or string.find(e, "rejected the request with error") -- 502
		or string.find(e, "successful but") -- 503 / 504
end

function Key._Save<T>(self: _Key<T>): Promise.TypedPromise<>
	if getmetatable(self) == "AbserdeTombstone" then return Promise.resolve() end
	if self._savingPromise ~= nil then return self._savingPromise end
	-- Dont save if we dont have to or are in a locked state (from the key being locked by another server or read only)
	if not self._dirty or self._readOnly or (self.Options.Lockable ~= false and self.Locked) then return Promise.resolve() end

	local promise
	promise = Promise.new(function(resolve, reject, onCancel)
		self._savingPromise = promise

		local success, schemaInfo, dataToSave, err

		success, schemaInfo = pcall(Schemas.GetSchema, self.Options.Schema.name, nil)
		if not success then return reject(`Failed to get schema for key {self._datastore.Name} for user {self._user}: {schemaInfo}`) end

		assert(schemaInfo)
		success, dataToSave = pcall(schemaInfo.schema.Write, schemaInfo.schema, self._data)
		if not success then return reject(`Failed to encode data for key {self._datastore.Name} for user {self._user}: {dataToSave}`) end

		if self.Options.Compression then dataToSave = EncodingService:CompressBuffer(dataToSave, self.Options.Compression.algorithm, self.Options.Compression.compressionLevel) end

		const metadata = {
			SchemaVersion = schemaInfo.version,
			CompressionAlgorithm = if self.Options.Compression then self.Options.Compression.algorithm.Name else nil,
		}

		const setOptions = Instance.new("DataStoreSetOptions")
		setOptions:SetMetadata(metadata)

		local cancelled = false
		onCancel(function()
			cancelled = true
		end)

		for attempt = 1, MAX_RETRIES do
			success, err = pcall(self._datastore.SetAsync, self._datastore, tostring(self._user), dataToSave, { self._user }, setOptions)
			if cancelled then return end
			if success or not isErrorRecoverable(err) then break end
			if attempt < MAX_RETRIES then task.wait(BACKOFF_TIME * 2 ^ attempt * (0.5 + math.random() * 0.5)) end
		end
		if not success then return reject(`Datastore SetAsync failed for key {self._datastore.Name} for user {self._user}: {err}`) end
		if getmetatable(self :: any) == "AbserdeTombstone" then return resolve() end

		self._dirty = false
		resolve()
	end):finally(function()
		self._savingPromise = nil
	end)

	return promise
end

function Key._Load<T>(self: _Key<T>): Promise.TypedPromise<T?>
	if getmetatable(self) == "AbserdeTombstone" then return Promise.resolve(nil) end
	if self._loadingPromise then return self._loadingPromise end

	local promise
	promise = Promise.new(function(resolve, reject, onCancel)
		self._loadingPromise = promise

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
		const metadata = info:GetMetadata()
		const schemaVersion = metadata.SchemaVersion
		const compressionAlgorithmName = metadata.CompressionAlgorithm

		-- If this data was compressed, decompress before decoding
		if compressionAlgorithmName then
			const compressionAlgorithm = Enum.CompressionAlgorithm:FromName(metadata.CompressionAlgorithm or "")
			if compressionAlgorithm then data = EncodingService:DecompressBuffer(data, compressionAlgorithm) end
		end

		const schema = Schemas.GetSchema(self.Options.Schema.name, schemaVersion)
		if not schema then return reject(`No schema found with version {schemaVersion}`) end

		local rawData = schema.schema:Read(data)

		-- Handle data transformations for version migrations
		-- Transformations apply based on the last saved version. Any transformations above that version will be applied in order until we are up to date
		const transformation = self.Options.TransformationFile
		const transformationFile = transformation and PROJECT.Transformations:FindFirstChild(transformation)
		if transformationFile then
			const s, transformations = pcall(require, transformationFile)
			if s then
				-- Since the transformation file might be sparse (missing some versions), we need to build an ordered list of versions to iterate over
				const versions = {}
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
	end)
		:catch(function(err)
			warn(`Failed to load key {self._datastore.Name} for user {self._user}: {err}`)
			return Utils.deepClone(self.Options.Default)
		end)
		:finally(function()
			self._loadingPromise = nil
		end)

	return promise
end

function Key.Load<T>(self: _Key<T>)
	if self.Loaded then return end
	self._data = self:_Load():expect()
	self.Loaded = true
end

function Key.Wipe<T>(self: _Key<T>)
	if getmetatable(self) == "AbserdeTombstone" then return end
	if self._readOnly or (self.Options.Lockable ~= false and self.Locked) then
		warn(`Attempted to wipe locked key {self._datastore.Name} for user {self._user}`)
		return
	end

	self._data = Utils.deepClone(self.Options.Default or {})
	self._dirty = true
end

function Key._Destroy<T>(self: _Key<T> & { [any]: any })
	if getmetatable(self :: any) == "AbserdeTombstone" then return end

	KeyCache[`{self._datastore.Name}_{self._user}`] = nil

	const function deepClear(t: { [any]: any })
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

	Scythe.clean(self._scythe)

	-- TODO: Leave better error when accessing any dangling proxy interfaces
	table.clear(self)
	setmetatable(self, Utils.TOMBSTONE_METATABLE)
end

function KeyClass.new<T>(options: types.KeyOptions<T>, datastore: DataStore, user: number, load: boolean?, readOnly: boolean?): types.Key<T>
	const cacheKey = `{datastore.Name}_{user}`
	if not readOnly and KeyCache[cacheKey] then
		const self = KeyCache[cacheKey]
		if self._loadingPromise then self._loadingPromise:expect() end
		if load then self:Load() end
		return self
	end

	const self: _Key<T> = setmetatable({}, KeyClass.metatable) :: _Key<T>
	if not readOnly then KeyCache[cacheKey] = self end

	self._readOnly = not not readOnly
	self._datastore = datastore
	self._memlock = MemoryStoreService:GetSortedMap(datastore.Name)
	self._user = user
	self._dirty = false
	self._scythe = Scythe.scope()

	self.Options = options

	const ProxyMetatable = {}

	-- Proxy-private state, keyed by proxy identity rather than stored on the proxy
	-- itself. Weak keys mean an entry is collected as soon as nothing else holds
	-- the corresponding proxy — no state ever leaks into raw enumeration of the
	-- proxy, and no explicit cleanup is required.
	const ProxyState: { [any]: { path: { any }, children: { [any]: any } } } = setmetatable({}, { __mode = "k" })

	-- Builds a human readable path string for debugging.
	const function pathToString(pathKeys: { any }): string
		const parts = table.create(#pathKeys)
		for i, key in pathKeys do
			parts[i] = tostring(key)
		end
		return table.concat(parts, ".")
	end

	-- Walks down from the current `self._data` along `pathKeys`, returning the live
	-- table from that position, or nil if the path no longer resolves to a table
	-- (e.g. a parent was overwritten with a scalar or removed).
	const function resolveTable(pathKeys: { any }): any
		local targetTbl: any = self._data
		for _, key in pathKeys do
			const nextTbl = targetTbl[key]
			if type(nextTbl) ~= "table" then return nil end
			targetTbl = nextTbl
		end
		return targetTbl
	end

	const function createProxy(pathKeys: { any })
		const proxy: any = setmetatable({}, ProxyMetatable)
		ProxyState[proxy] = { path = pathKeys, children = setmetatable({}, { __mode = "v" }) } :: any
		return proxy
	end

	-- Given a value read from the live table at `key`, returns what a proxy consumer
	-- should see: scalars pass through unchanged, tables are wrapped in a cached
	-- child proxy so that further access (whether via __index or __iter) is
	-- consistently guarded and cache-coherent.
	const function getOrCreateChild(state: { path: { any }, children: { [any]: any } }, val: unknown, key: any): unknown
		if type(val) ~= "table" then return val end

		local child = state.children[key]
		if not child then
			const childPathKeys = table.clone(state.path)
			table.insert(childPathKeys, key)
			child = createProxy(childPathKeys)
			state.children[key] = child
		end
		return child
	end

	ProxyMetatable.__index = function(proxy, key: unknown): unknown
		assert(self.Loaded, "Key is not loaded. Call `Key:Load()` before reading or writing to it.")

		const state = ProxyState[proxy]
		const pathKeys = state.path
		const targetTbl = resolveTable(pathKeys)
		if targetTbl == nil then return nil end

		return getOrCreateChild(state, targetTbl[key], key)
	end

	ProxyMetatable.__newindex = function(proxy, key: unknown, newVal: unknown)
		assert(self.Loaded, "Key is not loaded. Call `Key:Load()` before reading or writing to it.")

		if self._readOnly or (self.Options.Lockable ~= false and self.Locked) then return warn(`Attempted to write to locked key {self._datastore.Name} for user {self._user}`) end

		const state = ProxyState[proxy]
		const targetTbl = resolveTable(state.path)
		if targetTbl == nil then error(`Cannot write to "{key}": parent path "{pathToString(state.path)} no longer resolves to a table."`) end

		-- If the value being assigned is itself one of our proxies, unwrap it to
		-- the live table it currently represents. This is what makes
		-- `data.X = data.Y or {}` work regardless of whether `data.Y` already
		-- exists: when it does, the read returns a proxy, which is unwrapped
		-- back to the same underlying table it already refers to, so the
		-- assignment is a harmless no-op. It also allows genuine cross-tree
		-- reference assignment, e.g. `data.A.Foo = data.B.Bar`.
		const newValState = ProxyState[newVal]
		const resolvedVal = if newValState then resolveTable(newValState.path) else newVal

		const oldVal = targetTbl[key]
		if oldVal ~= resolvedVal then
			targetTbl[key] = resolvedVal
			self._dirty = true
			state.children[key] = nil
		end
	end

	ProxyMetatable.__iter = function(proxy)
		assert(self.Loaded, "Key is not loaded. Call `Key:Load()` before reading or writing to it.")

		const state = ProxyState[proxy]
		const targetTbl = resolveTable(ProxyState[proxy].path) or {}

		return function(_, k): (unknown, unknown)
			const nk, nv = next(targetTbl, k)
			if nk == nil then return nil, nil end
			return nk, getOrCreateChild(state, nv, nk)
		end,
			nil,
			nil
	end

	ProxyMetatable.__len = function(proxy)
		assert(self.Loaded, "Key is not loaded. Call `Key:Load()` before reading or writing to it.")

		const targetTbl = resolveTable(ProxyState[proxy].path)
		return targetTbl and #targetTbl or 0
	end

	rawset(self :: any, "Data", createProxy({}))

	-- BLOCKING:

	self.Loaded = false
	if load then self:Load() end

	-- Handle autosave
	const autosaveInterval = options.AutosaveInterval or 300
	if autosaveInterval > 0 then
		Scythe.add(
			self._scythe,
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
