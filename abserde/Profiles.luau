--!strict

-- Services
local Players = game:GetService("Players")
-- Modules
local Key = require(script.Parent.Key)
local Promise = require(script.Parent.Parent.roblox_packages.Promise)
local Session = require(script.Parent.Session)
local types = require(script.Parent.types)

--[=[
	@class Profile
	A Profile in ABSERDE acts as the orchestration layer for player data between multiple datastore keys.
--]=]

local AbserdeProfile = {}
local AbserdeProfileClass = { metatable = { __index = AbserdeProfile } }

type _AbserdeProfile<T> = types.Profile<T> & {
	_openingPromises: { [number]: { Promise.TypedPromise<types.Session<unknown>> } },
	_sessions: { [number]: { [number]: types.Session<T> } },
	_closingPromises: { [types.Session<T>]: Promise.TypedPromise<any> },

	_ResolveSlot: (self: _AbserdeProfile<T>, userid: number, slot: number?, readonly: boolean?) -> number,
}

AbserdeProfile.ClassName = "AbserdeProfile"

--[[
	@method _ResolveSlot
	@param userid number
	@param slot number?
	@param readonly boolean?
	@return number
	Helper to get the resolve the slot to open a key with.
	If provided a slot directly, it will validate that.
	If this is a multislot profile, it resolves the SlotPath to find the slot to use.
	Defaults to 1 if no slot is given and the profile is not multislot.

	Resolving SlotPath will open the Key denoted in SlotPath. This Key is cached and will be reused when
	the rest of the session is initialized.
]]
function AbserdeProfile._ResolveSlot<T>(self: _AbserdeProfile<T>, userid: number, slot: number?, readOnly: boolean?)
	if slot then
		slot //= 1
		assert(slot >= 1 and slot <= (self.Options.SlotLimit or 1), "Invalid slot number")
		return slot
	elseif (self.Options.SlotLimit or 1) > 1 then
		assert(self.Options.SlotPath, "SlotPath must be set in the profile options to be able to open a session without providing a slot")
		local components = string.split(self.Options.SlotPath, "/") -- TODO: make delimiter escapable with backslash

		local keyOptions = (self.Options.Keys :: any)[components[1]] :: types.KeyOptions<unknown>?
		assert(keyOptions, `Invalid key {components[1]} for SlotPath {self.Options.SlotPath}`)
		local datastore = Session.getDataStore(self.Name, components[1], 1)
		local key = Key.new(keyOptions, datastore, userid, true, readOnly) :: Key._Key<unknown>

		local current: any = key.Data
		for i = 2, #components do
			current = current[components[i]]
		end

		-- Read only keys do not get cached so close it after we are done with it
		if readOnly then key:_Destroy() end

		assert(current, `Could not locate {self.Options.SlotPath}`)
		return self:_ResolveSlot(userid, current)
	end

	return 1
end

--[=[
	@method Open
	@within Profile
	@param user User
	@param slot number?
	@return Promise<Session>
	Opens a session for the user, or returns an existing one.
--]=]
function AbserdeProfile.Open<T>(self: _AbserdeProfile<T>, user: types.user, slot: number?): Promise.TypedPromise<types.Session<T>>
	local userid = type(user) == "number" and user or user.UserId
	slot = self:_ResolveSlot(userid, slot)

	if self._sessions[slot or 1][userid] then return Promise.resolve(self._sessions[slot or 1][userid]) end
	if self._openingPromises[slot or 1][userid] then return self._openingPromises[slot or 1][userid] end

	local promise = Promise.new(function(resolve, reject)
		local s, session = pcall(Session.new, self.Options, userid, slot or 1, nil)
		if not s then
			self._openingPromises[slot or 1][userid] = nil
			return reject(session)
		end
		self._sessions[slot or 1][userid] = session

		-- Remove the session from the cache when it closes
		session.Closing:Once(function()
			self._sessions[slot or 1][userid] = nil
		end)

		-- If we open a session with a Player object, we should automatically close it when they leave
		if type(user) ~= "number" then
			local connection = Players.PlayerRemoving:Connect(function(player)
				if player == user then
					if session and session.Open and not self._closingPromises[session] then
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

		self._openingPromises[slot or 1][userid] = nil
		resolve(session)
	end)

	self._openingPromises[slot or 1][userid] = promise
	return promise
end

--[=[
	@method Find
	@within Profile
	@param user User
	@param slot number?
	@return Session?
	Attempts to locate an existing session for the user. 
--]=]
function AbserdeProfile.Find<T>(self: _AbserdeProfile<T>, user: types.user, slot: number?): types.Session<T>?
	local userid = type(user) == "number" and user or user.UserId
	slot = self:_ResolveSlot(userid, slot)
	return self._sessions[slot or 1][userid]
end

--[=[
	@method OpenLocked
	@within Profile
	@param user User
	@param slot number?
	@return Promise<Session>
	Opens a new read-only copy of the session. These read-only sessions do not get cached so cannot be returned by Find or Open.
	Read-only sessions will not automatically pull new data and must be manually refreshed.
	You can safely modify data in a locked session with the atomic methods.
	OpenLocked should be used when interfacing with another user's profile when they may be in the same server.
--]=]
function AbserdeProfile.OpenLocked<T>(self: _AbserdeProfile<T>, user: types.user, slot: number?): Promise.TypedPromise<types.Session<T>>
	local userid = type(user) == "number" and user or user.UserId
	slot = self:_ResolveSlot(userid, slot, true)

	-- Force a new read-only session to be opened, and do not cache it
	-- Since its read only, it doesn't matter if these dont get closed on server shutdown
	return Promise.new(function(resolve, reject)
		local s, session = pcall(Session.new, self.Options, userid, slot or 1, true)
		if not s then return reject(session) end
		resolve(session)
	end)
end

--[=[
	@function new
	@within Profile
	@param options ProfileOptions
	@return Profile
	Constructs a new Profile from the given ProfileOptions.
	You should use the ABSERDE CLI template for creating and managing profiles.
--]=]
function AbserdeProfileClass.new<T>(options: types.ProfileOptions<T>): types.Profile<T>
	local self: _AbserdeProfile<T> = setmetatable({}, AbserdeProfileClass.metatable) :: any

	self._openingPromises = {}
	self._sessions = {}
	self._closingPromises = {}

	for i = 1, options.SlotLimit or 1 do
		self._openingPromises[i] = {}
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
