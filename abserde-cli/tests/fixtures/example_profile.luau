--!strict

-- Services
const ReplicatedStorage = game:GetService("ReplicatedStorage")
-- Modules
const Abserde = require(ReplicatedStorage.Packages.Abserde)

-- Require all schemas used by the profile here.
-- Do not require them inside the return constructor, or you may experience type issues.
const SCHEMAS = script.Parent.Parent.Schemas
const PrimarySchema = require(SCHEMAS.PrimarySchema)
const InventorySchema = require(SCHEMAS.InventorySchema)
const SettingsSchema = require(SCHEMAS.SettingsSchema)

return Abserde.Profile({
	Name = "MainProfile",
	SlotLimit = 3,
	SlotPath = "Settings/save_slot",
	Keys = {
		Main = Abserde.Key({
			Schema = PrimarySchema,
			Multislot = true,
			Default = {
				level = 0,
			},
		}),
		Inventory = Abserde.Key({
			Schema = InventorySchema,
			Multislot = true,
			Compression = {
				algorithm = Enum.CompressionAlgorithm.Zstd,
				compressionLevel = 22,
			},
			Default = {
				inventory = {},
			},
		}),
		Settings = Abserde.Key({
			Schema = SettingsSchema,
			Multislot = false,
			Default = {
				save_slot = 1,
			},
		}),
	},
})
