--!strict

-- Services
local DataStoreService = game:GetService("DataStoreService")
-- Modules
local Key = require(script.Parent.Key)
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

function AbserdeSessionClass.new<T>(profile: types.ProfileOptions<T>, userid: number, slot: number, readOnly: boolean?): types.Session<T>
	assert(#profile.Name <= 24, "Profile names cannot exceed 24 characters")
	local self: _AbserdeSession<T> = setmetatable({}, AbserdeSessionClass.metatable) :: any

	local data = {}
	-- Datastore names are `{profile.Name}_{key}{slot - 1}`
	-- TODO: encode slot as base64 to allow for 64 slots instead of 10
	-- Datastore key is just userid

	-- The schema version will be stored as metadata for the key
	for key, options in profile.Keys :: { [string]: types.KeyOptions<any> } do
		assert(#key <= 24, "Profile key names cannot exceed 24 characters")
		local datastore = getDataStore(profile.Name, key, slot)

		data[key] = Key.new(options, datastore, userid, options.AutoLoad, readOnly)
	end

	self.Data = table.freeze(data)

	return self
end

return AbserdeSessionClass
