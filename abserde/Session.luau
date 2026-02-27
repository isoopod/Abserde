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

function AbserdeSessionClass.new<T>(profile: types.Profile<T>, userid: number): types.Session<T>
	local self: _AbserdeSession<T> = setmetatable({}, AbserdeSessionClass.metatable) :: any

	local data = {}
	-- TODO: Load each key, handle locking, versions refinement, etc.
	-- Datastore names are `{profile.Name}_{key}`
	-- Datastore key is just userid

	self.Data = table.freeze(data)

	return self
end

return AbserdeSessionClass
