--!strict

-- Modules
local Pack = require(script.roblox_packages.Pack)
local Profiles = require(script.Profiles)
local Schemas = require(script.Schemas)
local types = require(script.types)

local Abserde = {}

Abserde.Pack = Pack :: Pack.Datatypes

Abserde.Schema = Schemas.Schema
Abserde.Profile = Profiles.new

-- Recasts options to a key so we get typing as Keys instead of just data
function Abserde.Key<T>(options: types.KeyOptions<T>): types.Key<T>
	return options :: any
end

return Abserde
