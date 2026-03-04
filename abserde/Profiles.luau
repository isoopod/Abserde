--!strict
local Players = game:GetService("Players")

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

	-- If we open a session with a Player object, we should automatically close it when they leave.
	if type(user) ~= "number" then
		local connection: RBXScriptConnection
		connection = Players.PlayerRemoving:Connect(function(player)
			if player == user then
				connection:Disconnect()
				local session = self._sessions[userid]
				if session then session:Close() end
			end
		end)
	end

	return Promise.new(function(resolve, reject, onCancel)
		if self._sessions[userid] then
			resolve(self._sessions[userid])
			return
		end
	end)
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
