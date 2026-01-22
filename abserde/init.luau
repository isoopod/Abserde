-- Modules
local Pack = require(script.roblox_packages.Pack)

local abserde = {}

abserde.Pack = Pack :: Pack.Datatypes

function abserde.Schema<T, U>(format: U, encode: ((T) -> U)?, decode: ((U) -> T)?)
	local schema = Pack:Define(Pack.Transformer(Pack.Struct(format), encode, decode))
end

return abserde
