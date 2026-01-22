-- Handles cross server messaging for concurrent updates

-- Services
local MemoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")
-- Modules
local Promise = require("../roblox_packages/Promise")

local Courier = {}

return Courier
