local Pack = require(script.Parent.roblox_packages.Pack)
local Promise = require(script.Parent.roblox_packages.Promise)

export type Profile<T> = {
	ClassName: "AbserdeProfile",
	Name: string,
	Options: ProfileOptions<T>,

	Open: <T>(self: Profile<T>, user: user) -> Promise.TypedPromise<Session<T>>,
	Find: <T>(self: Profile<T>, user: user) -> Session<T>?, -- Immediately fetches an existing session if there is one. Will not open a session.
	OpenLocked: <T>(self: Profile<T>, user: user) -> Promise.TypedPromise<Session<T>>, -- Opens a read only session (still supports atomic operations).
}

export type ProfileOptions<T> = {
	Name: string, -- The name of the profile, used to uniquely identify datastores by profile and key.
	Keys: T, -- Map of string -> KeyOptions
}

export type Session<T> = {
	ClassName: "AbserdeSession",
	Data: T,
	-- Will be true if the session has been locked by another server
	Locked: boolean,
	-- Saves data and closes the session, removing the lock and removing it from memory
	-- Only works if the session is not locked by another server
	Release: (self: Session<T>) -> Promise.Promise,
	-- Manually saves all keys in the session (that have been modified)
	-- Only works if the session is not locked by another server
	Save: (self: Session<T>) -> Promise.Promise,
	-- Saves and releases (if possible), and removes the session from memory.
	-- This happens automatically when a player leaves if their session was created from the Player object instead of their UserId.
	Close: (self: Session<T>) -> Promise.Promise,

	-- Atomic methods work even if the session is locked by another server
	-- Use these when you need to modify a session of a user that may not be in this server
	-- Atomically adds a value to a key in the session
	-- key is / separated and starts with a key in the profile, e.g. "Settings/Volume"
	AtomicSet: <T, U>(self: Session<T>, key: string, value: U, transactionSchema: U?) -> Promise.TypedPromise<boolean>,
	-- Atomically removes a key
	AtomicRemove: (self: Session<T>, key: string) -> Promise.TypedPromise<boolean>,
}

export type CompressionSettings = {
	algorithm: Enum.CompressionAlgorithm,
	compressionLevel: number?,
}

export type KeyOptions<T> = {
	Schema: _AbserdeSchema<T>,
	Default: T,
	Lockable: boolean?, -- [true] A locked key cannot be modified by other servers
	LockInterval: number?, -- [60] (seconds) How often to relock a key or obtain a lock.
	AutoLoad: boolean?, -- [true] Automatically loads the key when the session is opened, otherwise will be loaded when indexed
	AutosaveInterval: number?, -- [5] (minutes) Automatically saves the data at this interval if the key is loaded and has unsaved changes. Set to 0 to disable autosave.
	Compression: CompressionSettings?,
}

export type Key<T> = {
	ClassName: "Key",
	Options: KeyOptions<T>,
	Data: T,
	Loaded: boolean, -- Has the key been loaded from the datastore?
	Locked: boolean, -- Is the key currently locked by another server?
}

export type _AbserdeSchema<T> = {
	schema: Pack.Schema<T>,
	name: string,
	version: number,
}

export type user = Player | number

export type Abserde = {}

type instNode<T, V> = V & T
export type AbserdeProject = instNode<Folder, {
	Schemas: instNode<Folder, {
		Snapshots: instNode<Folder, { [string]: { [string]: ModuleScript } }>,
		[string]: ModuleScript,
	}>,
	Profiles: instNode<Folder, { [string]: ModuleScript }>,
}>

return nil
