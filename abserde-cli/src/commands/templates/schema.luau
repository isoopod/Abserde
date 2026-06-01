--!strict

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- Modules
local Abserde = require(ReplicatedStorage.Abserde)
local Pack = Abserde.Pack

-- NOTE: The internal datatype of an Abserde Schema is a Pack Transform<Dictionary<{ ... }>>
-- You can add the encode and decode functions after the format definition if desired.
return Abserde.Schema(script, {
	-- This is a Pack Dictionary
	Level = Pack.UInt32,
})
