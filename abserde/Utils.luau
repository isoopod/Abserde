--!optimize 2

-- Services
local ServerScriptService = game:GetService("ServerScriptService")
-- Modules
local types = require(script.Parent.types)

local utils = {}

-- stylua: ignore
utils.PROJECT = assert(ServerScriptService:FindFirstChild("abserde_project"), "No abserde_project found in ServerScriptService, create one with `abserde init`.") :: types.AbserdeProject

local function deepClone<T>(tbl: T): T
	if type(tbl) ~= "table" then return tbl end

	local copy = {}
	for key, value in tbl :: { [any]: any } do
		copy[key] = deepClone(value)
	end
	return copy :: any
end
utils.deepClone = deepClone

type table = { [any]: any }
local function deepMerge(target: table, source: table): boolean
	local modified = false
	for key, value in source do
		if type(value) == "table" then
			if target[key] == nil then
				target[key] = deepClone(value)
				modified = true
			elseif type(target[key]) == "table" then
				if deepMerge(target[key], value) then modified = true end
			end
		else
			if target[key] == nil then
				target[key] = value
				modified = true
			end
		end
	end
	return modified
end
utils.deepMerge = deepMerge :: <T, U>(target: T, source: U) -> boolean

local function concatPath(path: string, key: string): string
	if path == "" then return tostring(key) end
	return `{path}.{key}`
end
utils.concatPath = concatPath

local function getDeepValue(tbl: any, path: string, key: string): any
	local current = tbl
	for node in path:split(".") do
		current = current[node]
		if type(current) ~= "table" then return nil end
	end
	return current[key]
end
utils.getDeepValue = getDeepValue

return utils
