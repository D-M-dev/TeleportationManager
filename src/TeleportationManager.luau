--[[
    TeleportationManager Module
    
    A robust teleportation system for Roblox with destination management,
    cooldown system, and comprehensive error handling.
    
    Author: TACO
    Version: 1.0.0
    
    Features:
    - Player teleportation to named destinations
    - Dynamic destination management (add/remove)
    - Per-player cooldown system (5 seconds default)
    - Server-side validation and client support via RemoteEvents
    - Comprehensive logging and error handling
]]

local TeleportationManager = {}

-- Configuration
local CONFIG = {
	COOLDOWN_TIME = 5, -- Cooldown in seconds between teleports
	TELEPORT_HEIGHT_OFFSET = 3, -- Height offset to prevent clipping into ground
	ENABLE_LOGGING = true -- Enable/disable console logging
}

-- Internal data storage
local destinations = {} -- Store all teleport destinations {name = Vector3}
local playerCooldowns = {} -- Track cooldown for each player {userId = timestamp}

--[[
    Internal function to log messages
    @param message (string) - The message to log
    @param logType (string) - Type of log: "INFO", "WARNING", "ERROR"
]]
local function log(message, logType)
	if not CONFIG.ENABLE_LOGGING then return end

	logType = logType or "INFO"
	local timestamp = os.date("%H:%M:%S")
	print(string.format("[%s] [TeleportManager-%s] %s", timestamp, logType, message))
end

--[[
    Check if a player is currently on cooldown
    @param player (Player) - The player to check
    @return (boolean) - True if player is on cooldown, false otherwise
    @return (number) - Remaining cooldown time in seconds
]]
local function isOnCooldown(player)
	local userId = player.UserId
	local lastTeleport = playerCooldowns[userId]

	if not lastTeleport then
		return false, 0
	end

	local currentTime = tick()
	local timePassed = currentTime - lastTeleport

	if timePassed < CONFIG.COOLDOWN_TIME then
		local remainingTime = CONFIG.COOLDOWN_TIME - timePassed
		return true, math.ceil(remainingTime)
	end

	return false, 0
end

--[[
    Set cooldown for a player
    @param player (Player) - The player to set cooldown for
]]
local function setCooldown(player)
	playerCooldowns[player.UserId] = tick()
end

--[[
    Validate if a player object is valid
    @param player (Instance) - The player object to validate
    @return (boolean) - True if valid, false otherwise
]]
local function validatePlayer(player)
	if not player then
		return false
	end

	if not player:IsA("Player") then
		return false
	end

	if not player.Character then
		return false
	end

	local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return false
	end

	return true
end

--[[
    PUBLIC API: Add a new destination
    @param name (string) - Unique name for the destination
    @param position (Vector3) - Position where players will be teleported
    @return (boolean) - True if successful, false otherwise
    @return (string) - Error message if failed
]]
function TeleportationManager.AddDestination(name, position)
	-- Validate input
	if type(name) ~= "string" or name == "" then
		log("Failed to add destination: Invalid name provided", "ERROR")
		return false, "Destination name must be a non-empty string"
	end

	if typeof(position) ~= "Vector3" then
		log("Failed to add destination: Invalid position provided", "ERROR")
		return false, "Position must be a Vector3"
	end

	-- Check if destination already exists
	if destinations[name] then
		log(string.format("Destination '%s' already exists, updating position", name), "WARNING")
	end

	-- Add destination
	destinations[name] = position
	log(string.format("Destination '%s' added at position %s", name, tostring(position)), "INFO")

	return true
end

--[[
    PUBLIC API: Remove a destination
    @param name (string) - Name of the destination to remove
    @return (boolean) - True if successful, false otherwise
    @return (string) - Error message if failed
]]
function TeleportationManager.RemoveDestination(name)
	if type(name) ~= "string" or name == "" then
		log("Failed to remove destination: Invalid name provided", "ERROR")
		return false, "Destination name must be a non-empty string"
	end

	if not destinations[name] then
		log(string.format("Failed to remove destination: '%s' does not exist", name), "WARNING")
		return false, "Destination does not exist"
	end

	destinations[name] = nil
	log(string.format("Destination '%s' removed", name), "INFO")

	return true
end

--[[
    PUBLIC API: Get all available destinations
    @return (table) - Dictionary of all destinations {name = Vector3}
]]
function TeleportationManager.GetDestinations()
	local destinationList = {}

	for name, position in pairs(destinations) do
		destinationList[name] = position
	end

	log(string.format("Retrieved %d destination(s)", #destinationList), "INFO")
	return destinationList
end

--[[
    PUBLIC API: Get list of destination names only
    @return (table) - Array of destination names
]]
function TeleportationManager.GetDestinationNames()
	local names = {}

	for name, _ in pairs(destinations) do
		table.insert(names, name)
	end

	return names
end

--[[
    PUBLIC API: Teleport a player to a destination
    @param player (Player) - The player to teleport
    @param destinationName (string) - Name of the destination
    @return (boolean) - True if successful, false otherwise
    @return (string) - Error message if failed
]]
function TeleportationManager.Teleport(player, destinationName)
	-- Validate player
	if not validatePlayer(player) then
		log(string.format("Failed to teleport: Invalid player or missing character"), "ERROR")
		return false, "Invalid player or player character not loaded"
	end

	-- Validate destination name
	if type(destinationName) ~= "string" or destinationName == "" then
		log("Failed to teleport: Invalid destination name", "ERROR")
		return false, "Destination name must be a non-empty string"
	end

	-- Check if destination exists
	if not destinations[destinationName] then
		log(string.format("Failed to teleport: Destination '%s' does not exist", destinationName), "WARNING")
		return false, string.format("Destination '%s' not found", destinationName)
	end

	-- Check cooldown
	local onCooldown, remainingTime = isOnCooldown(player)
	if onCooldown then
		log(string.format("Player %s is on cooldown (%d seconds remaining)", player.Name, remainingTime), "WARNING")
		return false, string.format("Please wait %d seconds before teleporting again", remainingTime)
	end

	-- Perform teleportation
	local character = player.Character
	local humanoidRootPart = character.HumanoidRootPart
	local destination = destinations[destinationName]

	-- Add height offset to prevent clipping
	local targetPosition = destination + Vector3.new(0, CONFIG.TELEPORT_HEIGHT_OFFSET, 0)

	-- Teleport with pcall for error handling
	local success, err = pcall(function()
		humanoidRootPart.CFrame = CFrame.new(targetPosition)
	end)

	if not success then
		log(string.format("Failed to teleport player %s: %s", player.Name, tostring(err)), "ERROR")
		return false, "Teleportation failed due to an internal error"
	end

	-- Set cooldown
	setCooldown(player)

	-- Log successful teleportation
	log(string.format("Player '%s' teleported to destination '%s' at %s", 
		player.Name, destinationName, tostring(targetPosition)), "INFO")

	return true
end

--[[
    PUBLIC API: Check if a destination exists
    @param name (string) - Name of the destination to check
    @return (boolean) - True if destination exists, false otherwise
]]
function TeleportationManager.DestinationExists(name)
	return destinations[name] ~= nil
end

--[[
    PUBLIC API: Get the position of a specific destination
    @param name (string) - Name of the destination
    @return (Vector3 or nil) - Position of the destination, or nil if not found
]]
function TeleportationManager.GetDestinationPosition(name)
	return destinations[name]
end

--[[
    PUBLIC API: Clear all destinations
    @return (number) - Number of destinations removed
]]
function TeleportationManager.ClearAllDestinations()
	local count = 0
	for _ in pairs(destinations) do
		count = count + 1
	end

	destinations = {}
	log(string.format("Cleared %d destination(s)", count), "INFO")

	return count
end

--[[
    PUBLIC API: Get cooldown time for a player
    @param player (Player) - The player to check
    @return (number) - Remaining cooldown in seconds, or 0 if not on cooldown
]]
function TeleportationManager.GetPlayerCooldown(player)
	if not player or not player:IsA("Player") then
		return 0
	end

	local _, remainingTime = isOnCooldown(player)
	return remainingTime
end

--[[
    PUBLIC API: Clear cooldown for a specific player (admin function)
    @param player (Player) - The player to clear cooldown for
]]
function TeleportationManager.ClearPlayerCooldown(player)
	if player and player:IsA("Player") then
		playerCooldowns[player.UserId] = nil
		log(string.format("Cooldown cleared for player %s", player.Name), "INFO")
	end
end

--[[
    PUBLIC API: Update configuration
    @param configTable (table) - Table with config values to update
]]
function TeleportationManager.UpdateConfig(configTable)
	for key, value in pairs(configTable) do
		if CONFIG[key] ~= nil then
			CONFIG[key] = value
			log(string.format("Config updated: %s = %s", key, tostring(value)), "INFO")
		end
	end
end

-- Clean up cooldowns when players leave
game.Players.PlayerRemoving:Connect(function(player)
	playerCooldowns[player.UserId] = nil
	log(string.format("Cooldown data cleared for leaving player: %s", player.Name), "INFO")
end)

log("TeleportationManager module loaded successfully", "INFO")

return TeleportationManager