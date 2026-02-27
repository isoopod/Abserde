--!strict

-- Services

-- Modules
local Promise = require(script.Parent.roblox_packages.Promise)
local types = require(script.Parent.types)

local AbserdeProfile = {}
local AbserdeProfileClass = { metatable = { __index = AbserdeProfile } }

type _AbserdeProfile<T> = types.Profile<T> & {
	_sessions: { [number]: types.Session<T> },
}

AbserdeProfile.ClassName = "AbserdeProfile"

function AbserdeProfile.Open<T>(self: _AbserdeProfile<T>, user: types.user): Promise.TypedPromise<types.Session<T>>
	local userid = type(user) == "number" and user or user.UserId
	return Promise.new(function(resolve, reject, onCancel) end)
end

function AbserdeProfile.Find<T>(self: _AbserdeProfile<T>, user: types.user): types.Session<T>?
	local userid = type(user) == "number" and user or user.UserId
	return self._sessions[userid]
end

function AbserdeProfileClass.new<T>(file: ModuleScript, options: types.ProfileOptions<T>): types.Profile<T>
	local self: _AbserdeProfile<T> = setmetatable({}, AbserdeProfileClass.metatable) :: any

	self._sessions = {}

	self.Name = file.Name
	self.Options = options

	return self
end

return AbserdeProfileClass
