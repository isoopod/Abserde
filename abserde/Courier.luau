-- Cross-server Request-Reply system built on top of MessagingService and MemoryStoreService.

-- Services
local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")
-- Modules
local Promise = require(script.Parent.roblox_packages.Promise)

local DATA_EXPIRY = 60
local RETRY_INTERVAL = 5

local RequestStore = MemoryStoreService:GetSortedMap("Courier_RequestData")

local Courier = {}

--[=[
    Sends a message to a specific server
    @param targetJobId string -- The JobId of the target server
    @param topic string -- The communication channel
    @param ... -- any extra arguments (will be stored in a SortedMap instead of sent with the message)
]=]
function Courier.send(targetJobId: string, topic: string, ...): Promise.TypedPromise<boolean>
	local args = { ... }
	local requestId = HttpService:GenerateGUID(false)
	local replyTopic = `Reply_{requestId}`

	return Promise.new(function(resolve, reject, onCancel)
		local isActive = true

		local hasArgs = #args ~= 0
		if hasArgs then
			-- Attempt to store arugments in the memorystore
			local success, err = pcall(RequestStore.SetAsync, RequestStore, requestId, args, DATA_EXPIRY)
			if not success then return reject(`Failed to store request data: {err}`) end
		end

		-- Subscribe to the reply topic
		local connection
		connection = MessagingService:SubscribeAsync(replyTopic, function(message)
			isActive = false
			local result = message.Data :: boolean
			if connection then connection:Disconnect() end
			task.spawn(RequestStore.RemoveAsync, RequestStore, requestId)
			resolve(result)
		end)

		task.spawn(function()
			local startTime = os.clock()

			while isActive and (os.clock() - startTime) < DATA_EXPIRY do
				-- Broadcast the request signal
				MessagingService:PublishAsync(topic, {
					HasArgs = hasArgs,
					RequestId = requestId,
					ReplyTopic = replyTopic,
					TargetJobId = targetJobId,
				})
				task.wait(RETRY_INTERVAL)
			end

			if isActive then
				if connection then connection:Disconnect() end
				-- Dont need to remove as it would have expired by now
				reject("Request expired - server might have closed")
			end
		end)

		onCancel(function()
			isActive = false
			if connection then connection:Disconnect() end
			RequestStore:RemoveAsync(requestId)
		end)
	end)
end

-- Keep a set of all completed requests for a short time
local completedRequests: { [string]: number } = {}
local completedRequestValues: { [string]: boolean } = {}

local function addCompleted(key: string, value: boolean)
	local now = os.clock()
	for k, expiry in completedRequests do
		if now >= expiry then
			completedRequests[k] = nil
			completedRequestValues[k] = nil
		end
	end
	completedRequests[key] = now + DATA_EXPIRY
	completedRequestValues[key] = value
end

local ongoingRequests = {}
function Courier.listen(topic: string, callback: (...any) -> boolean?)
	return MessagingService:SubscribeAsync(topic, function(message)
		local data = message.Data

		-- Only process if meant for this server
		if data.TargetJobId ~= game.JobId then return end
		-- Ignore an ongoing request
		if ongoingRequests[data.RequestId] then return end
		-- If we have completed it already but the response was dropped, try again
		local completedValue = completedRequestValues[data.RequestId]
		if completedValue then return MessagingService:PublishAsync(data.ReplyTopic, completedValue) end

		-- Get extra args if there are any
		local success, args
		if data.HasArgs then
			success, args = pcall(RequestStore.GetAsync, RequestStore, data.RequestId)
			if not success then return end
		end

		ongoingRequests[data.RequestId] = true

		local status = not not callback(args and unpack(args))
		addCompleted(data.RequestId, status)
		MessagingService:PublishAsync(data.ReplyTopic, status)
		ongoingRequests[data.RequestId] = nil
	end)
end

return Courier
