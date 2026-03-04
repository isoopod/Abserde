--!optimize 2

local utils = {}

local function deepClone<T>(tbl: T): T
	if type(tbl) ~= "table" then return tbl end

	local copy = {}
	for key, value in tbl :: { [any]: any } do
		copy[key] = deepClone(value)
	end
	return copy :: any
end
utils.deepClone = deepClone

return utils
