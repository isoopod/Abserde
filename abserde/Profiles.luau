--!strict

-- Services
local Players = game:GetService("Players")
-- Modules
local Promise = require(script.Parent.Parent.roblox_packages.Promise)
local Session = require(script.Parent.Session)
local types = require(script.Parent.types)

local AbserdeProfile = {}
local AbserdeProfileClass = { metatable = { __index = AbserdeProfile } }

type _AbserdeProfile<T> = types.Profile<T> & {
	_sessions: { [number]: { [number]: types.Session<T> } },
	_closingPromises: { [types.Session<T>]: Promise.TypedPromise<any> },
}

AbserdeProfile.ClassName = "AbserdeProfile"

function AbserdeProfile.Open<T>(self: _AbserdeProfile<T>, user: types.user, slot: number?): Promise.TypedPromise<types.Session<T>>
	slot = slot and slot // 1 or 1
	assert(slot >= 1 and slot <= (self.Options.SlotLimit or 1), "Invalid slot number")
	local userid = type(user) == "number" and user or user.UserId

	return Promise.new(function(resolve, reject)
		if self._sessions[slot or 1][userid] then return resolve(self._sessions[slot or 1][userid]) end
		local s, session = pcall(Session.new, self.Options, userid, slot or 1, nil)
		if not s then return reject(session) end
		self._sessions[slot or 1][userid] = session

		-- Remove the session from the cache when it closes
		session.Closing:Once(function()
			self._sessions[slot or 1][userid] = nil
		end)

		-- If we open a session with a Player object, we should automatically close it when they leave
		if type(user) ~= "number" then
			local connection = Players.PlayerRemoving:Connect(function(player)
				if player == user then
					if session then
						local closePromise = session:Close()
						self._closingPromises[session] = closePromise

						closePromise:finally(function()
							self._closingPromises[session] = nil
						end)
					end
				end
			end)
			session.Closing:Once(function()
				connection:Disconnect()
			end)
		end

		resolve(session)
	end)
end

function AbserdeProfile.Find<T>(self: _AbserdeProfile<T>, user: types.user, slot: number?): types.Session<T>?
	slot = slot and slot // 1 or 1
	assert(slot >= 1 and slot <= (self.Options.SlotLimit or 1), "Invalid slot number")
	local userid = type(user) == "number" and user or user.UserId
	return self._sessions[slot or 1][userid]
end

function AbserdeProfile.OpenLocked<T>(self: _AbserdeProfile<T>, user: types.user, slot: number?): Promise.TypedPromise<types.Session<T>>
	slot = slot and slot // 1 or 1
	assert(slot >= 1 and slot <= (self.Options.SlotLimit or 1), "Invalid slot number")
	local userid = type(user) == "number" and user or user.UserId

	-- Force a new read-only session to be opened, and do not cache it
	-- Since its read only, it doesn't matter if these dont get closed on server shutdown
	return Promise.new(function(resolve, reject)
		local s, session = pcall(Session.new, self.Options, userid, slot or 1, true)
		if not s then return reject(session) end
		resolve(session)
	end)
end

function AbserdeProfileClass.new<T>(options: types.ProfileOptions<T>): types.Profile<T>
	local self: _AbserdeProfile<T> = setmetatable({}, AbserdeProfileClass.metatable) :: any

	self._sessions = {}
	self._closingPromises = {}

	for i = 1, options.SlotLimit or 1 do
		self._sessions[i] = {}
	end

	self.Name = options.Name
	self.Options = options

	-- Ensure the server remains open until all open sessions are closed
	game:BindToClose(function()
		local promises: { any } = {}

		for _, slot in self._sessions do
			for _, session in slot do
				table.insert(promises, session:Close())
			end
		end

		for _, closePromise in self._closingPromises do
			table.insert(promises, closePromise)
		end

		if #promises > 0 then Promise.all(promises):expect() end
	end)

	return self
end

return AbserdeProfileClass
