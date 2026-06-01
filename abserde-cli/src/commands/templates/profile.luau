--!strict

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- Modules
local Abserde = require(ReplicatedStorage.Abserde)

-- Require all schemas used by the profile here.
-- Do not require them inside the return constructor, or you may experience type issues.
local SCHEMAS = script.Parent.Parent.Schemas
local ExampleSchema = require(SCHEMAS.ExampleSchema)

return Abserde.Profile({
	Name = "ExampleProfile",
	Keys = {
		Main = Abserde.Key({
			Schema = ExampleSchema,
			Default = {
				Level = 1,
			},
		}),
	},
})
