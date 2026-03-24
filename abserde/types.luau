local Pack = require(script.Parent.roblox_packages.Pack)
local Promise = require(script.Parent.roblox_packages.Promise)
local Signal = require(script.Parent.roblox_packages.Signal)

export type Profile<T> = {
	ClassName: "AbserdeProfile",
	Name: string,
	Options: ProfileOptions<T>,

	-- Slot must be provided if the profile has multislot enabled.
	Open: <T>(self: Profile<T>, user: user, slot: number?) -> Promise.TypedPromise<Session<T>>, -- Finds or opens a session for the given user and slot.
	Find: <T>(self: Profile<T>, user: user, slot: number?) -> Session<T>?, -- Immediately fetches an existing session if there is one. Will not open a session.
	OpenLocked: <T>(self: Profile<T>, user: user, slot: number?) -> Promise.TypedPromise<Session<T>>, -- Opens a read only session (still supports atomic operations).
	-- This read only session will not automatically closed if opened with a player object.
	-- Will open a separate, read only session even if there is already a writable session for the same user and slot.
	-- A read only session cannot be found with Find, and will not be cached.
	-- Additionally, this will not automatically open keys that would be otherwise.
}

export type ProfileOptions<T> = {
	Name: string, -- The name of the profile, used to uniquely identify datastores by profile and key.
	Keys: T, -- Map of string -> KeyOptions.
	SlotLimit: number?, -- [nil; 1-10?] If a number between 1 and 10, this profile will have multislot enabled,
	-- allowing for selected keys to have independent save files.
}

export type Session<T> = {
	ClassName: "AbserdeSession",
	Profile: ProfileOptions<T>,
	User: number, -- Userid.
	Keys: T,
	Open: boolean,
	Closing: Signal.Signal<>,
	-- Manually saves all keys in the session (that have been modified).
	-- Only works if the session is not locked by another server.
	Save: (self: Session<T>) -> Promise.Promise,
	-- Releases any locked keys, without saving or closing the session.
	-- Keys may reobtain a lock automatically if the session remains open.
	Release: (self: Session<T>) -> Promise.Promise,
	-- Saves and releases (if possible), and removes the session from memory.
	-- This happens automatically when a player leaves if their session was created from the Player object instead of their UserId.
	Close: (self: Session<T>) -> Promise.Promise,

	-- Atomic methods work even if the session is locked by another server.
	-- Use these when you need to modify a session of a user that may not be in this server.
	-- Atomically adds a value to a key in the session.
	-- key is / separated and starts with a key in the profile, e.g. "Settings/Volume".
	-- Limitation: The value being modified cannot exceed 32KiB.
	-- The value is encoded with the relevant sub-schema of the key schema.
	-- Will modify the value in the read only session once the transaction is confirmed.
	AtomicSet: <T, U>(self: Session<T>, key: string, value: any) -> Promise.TypedPromise<boolean>,
	-- Fetches the latest for an existing session.
	Refresh: <T>(self: Session<T>) -> Promise.Promise,
}

export type CompressionSettings = {
	algorithm: Enum.CompressionAlgorithm,
	compressionLevel: number?,
}

export type KeyOptions<T> = {
	Schema: _AbserdeSchema<T>,
	Default: T,
	Lockable: boolean?, -- [true] A locked key cannot be modified by other servers.
	LockInterval: number?, -- [60] (seconds) How often to relock a key or obtain a lock.
	AutoLoad: boolean?, -- [true] Automatically loads the key when the session is opened, otherwise will be loaded when indexed.
	AutosaveInterval: number?, -- [5] (minutes) Automatically saves the data at this interval if the key is loaded and has unsaved changes. Set to 0 to disable autosave.
	Compression: CompressionSettings?,
	TransformationFile: string?, -- The name of a file in the Transformations folder that defines data transformations for this key for version migration.
	Multislot: boolean?, -- [false], if true, this key will have multiple slots allowing for different save files.
	-- This works by loading the session with the slot argument. A profile with multislot enabled does not require.
	-- all keys to be multislot.
	-- Keys that are not multislot will be shared across all slots.
	-- They are also saved in slot 1, incase you want to enable multislot later.
}

export type Key<T> = {
	ClassName: "Key",
	Options: KeyOptions<T>,
	Data: T,
	Loaded: boolean, -- Has the key been loaded from the datastore?
	Locked: boolean, -- Is the key currently locked by another server?
}

export type TransformationFile = {
	-- Number is the version we are migrating to.
	-- Data will be from some previous version, and before any new defaults have been applied.
	[number]: (data: any) -> any,
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
	Transformations: instNode<Folder, { [string]: ModuleScript }>,
}>

return nil
