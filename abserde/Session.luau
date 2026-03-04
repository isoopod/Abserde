--!strict

-- Services
local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
-- Modules
local types = require(script.Parent.types)

local AbserdeSession = {}
local AbserdeSessionClass = { metatable = { __index = AbserdeSession } }
type _AbserdeSession<T> = types.Session<T> & {}

AbserdeSession.ClassName = "AbserdeSession"

local datastoreCache: { [string]: DataStore } = {}
local function getDataStore(profileName: string, key: string): DataStore
	local cacheKey = `{profileName}_{key}`
	if not datastoreCache[cacheKey] then datastoreCache[cacheKey] = DataStoreService:GetDataStore(cacheKey) end
	return datastoreCache[cacheKey]
end

function AbserdeSessionClass.new<T>(profile: types.ProfileOptions<T>, userid: number): types.Session<T>
	assert(#profile.Name <= 24, "Profile names cannot exceed 24 characters")
	local self: _AbserdeSession<T> = setmetatable({}, AbserdeSessionClass.metatable) :: any

	local data = {}
	-- TODO: Load each key, handle locking, versions refinement, etc.
	-- Datastore names are `{profile.Name}_{key}`
	-- Datastore key is just userid

	-- The schema version will be stored as metadata for the key
	for key, options in profile.Keys :: { [string]: types.KeyOptions<any> } do
		assert(#key <= 25, "Profile key names cannot exceed 25 characters")
		local datastore = getDataStore(profile.Name, key)

		if options.AutoLoad then
		end
	end

	self.Data = table.freeze(data)

	return self
end

return AbserdeSessionClass
