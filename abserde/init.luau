-- Services
local ServerScriptService = game:GetService("ServerScriptService")
-- Modules
local Pack = require(script.roblox_packages.Pack)
local Schemas = require(script.Schemas)
local types = require(script.types)

local PROJECT = assert(ServerScriptService:FindFirstChild("abserde_project"), "No abserde_project found in ServerScriptService, create one with `abserde init`.")

local Abserde = {}

Abserde.Pack = Pack :: Pack.Datatypes

Abserde.Schema = Schemas.Schema

-- Recasts options to a key so we get typing as Keys instead of just data
function Abserde.Key<T>(options: types.KeyOptions<T>): types.Key<T>
	return options :: any
end

return Abserde
