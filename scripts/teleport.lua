local Teleport = {} ---@class Teleport
local CommandsUtils = require("utility.helper-utils.commands-utils")
local LoggingUtils = require("utility.helper-utils.logging-utils")
local EventScheduler = require("utility.manager-libraries.event-scheduler")
local Events = require("utility.manager-libraries.events")
local PlayerTeleport = require("utility.functions.player-teleport")
local DirectionUtils = require("utility.helper-utils.direction-utils")
local PositionUtils = require("utility.helper-utils.position-utils")
local Common = require("scripts.common")

---@enum Teleport_DestinationTypeSelection
local DestinationTypeSelection = {
    random = "random",
    biterNest = "biterNest",
    enemyUnit = "enemyUnit",
    spawn = "spawn",
    position = "position",
    player_position = "physical_position"
}

---@enum Teleport_DestinationTypeSelectionDescription
local DestinationTypeSelectionDescription = {
    random = "Random Location",
    biterNest = "Nearest Biter Nest",
    enemyUnit = "Enemy Unit",
    spawn = "spawn",
    position = "Set Position",
    player_position = "Set the Physical Position of the Player"
}

local MaxTargetAttempts = 5
local MaxRandomPositionsAroundTargetToTry = 50 -- Was 10, but upped to reduce odd vehicle rotation issues.
local MaxDistancePositionAroundTarget = 10

---@class Teleport_CommandDetails # The details for a specific teleport event in an an RCON command.
---@field delay UtilityScheduledEvent_UintNegative1
---@field target string # Target player's name.
---@field arrivalRadius double
---@field minDistance double
---@field maxDistance double
---@field destinationType Teleport_DestinationTypeSelection
---@field destinationTargetPosition? MapPosition|nil
---@field reachableOnly boolean
---@field backupTeleportSettings? Teleport_CommandDetails|nil
---@field destinationTypeDescription Teleport_DestinationTypeSelectionDescription
---@field suppressMessages boolean

---@class Teleport_TeleportDetails # The data on a teleport action being undertaken. This includes the attributes from the first Teleport_CommandDetails within it directly.
---@field teleportId uint
---@field target string
---@field targetPlayer? LuaPlayer
---@field targetPlayer_surface? LuaSurface
---@field targetPlayer_force? LuaForce
---@field targetPlayerPlacementEntity? LuaEntity # A player character or teleportable vehicle.
---@field arrivalRadius double
---@field minDistance double
---@field maxDistance double
---@field destinationType Teleport_DestinationTypeSelection
---@field destinationTargetPosition? MapPosition|nil
---@field reachableOnly boolean
---@field targetAttempt uint
---@field backupTeleportSettings? Teleport_CommandDetails|nil
---@field destinationTypeDescription Teleport_DestinationTypeSelectionDescription
---@field thisAttemptPosition? MapPosition|nil # The map position of the current teleport attempt.
---@field spawnerDistances table<uint, Teleport_TargetPlayerSpawnerDistanceDetails> # If destinationType is biterNest then populated when looking for a spawner to target, otherwise empty. Key'd as a gappy numerical order. The enemy spawners found on this surface from our spawner list and the distance they are from the player's current position.
---@field suppressMessages boolean

---@class Teleport_TargetPlayerSpawnerDistanceDetails
---@field distance double
---@field spawnerDetails Teleport_SpawnerDetails

---@class Teleport_SpawnerDetails
---@field unitNumber uint
---@field entity LuaEntity
---@field position MapPosition
---@field forceName string

---@alias surfaceForceBiterNests table<uint, table<string, table<uint, Teleport_SpawnerDetails>>> # A table of surface index numbers, to tables of force names, to spawner's details keyed by their unit number. Allows easy filtering to current surface and then batch ignoring of non-enemy spawners.

local CommandName = "muppet_streamer_v2_teleport"

Teleport.CreateGlobals = function()
    storage.teleport = storage.teleport or {} ---@class Teleport_Global
    storage.teleport.nextId = storage.teleport.nextId or 0 ---@type uint
    storage.teleport.pathingRequests = storage.teleport.pathingRequests or {} ---@type table<uint, Teleport_TeleportDetails> # The path request Id to its teleport details for when the path request completes.
    storage.teleport.surfaceBiterNests = storage.teleport.surfaceBiterNests or
                                             Teleport.FindExistingSpawnersOnAllSurfaces() ---@type surfaceForceBiterNests
    storage.teleport.chunkGeneratedId = storage.teleport.chunkGeneratedId or 0 ---@type uint
end

Teleport.OnLoad = function()
    CommandsUtils.Register("muppet_streamer_v2_teleport", {"api-description.muppet_streamer_v2_teleport"},
        Teleport.TeleportCommand, true)
    EventScheduler.RegisterScheduledEventType("Teleport.PlanTeleportTarget", Teleport.PlanTeleportTarget)
    Events.RegisterHandlerEvent(defines.events.on_script_path_request_finished, "Teleport.OnScriptPathRequestFinished",
        Teleport.OnScriptPathRequestFinished)
    Events.RegisterHandlerEvent(defines.events.on_biter_base_built, "Teleport.OnBiterBaseBuilt",
        Teleport.OnBiterBaseBuilt)
    Events.RegisterHandlerEvent(defines.events.script_raised_built, "Teleport.ScriptRaisedBuilt",
        Teleport.ScriptRaisedBuilt, {{
            filter = "type",
            type = "unit-spawner"
        }})
    Events.RegisterHandlerEvent(defines.events.on_chunk_generated, "Teleport.OnChunkGenerated",
        Teleport.OnChunkGenerated)
    Events.RegisterHandlerEvent(defines.events.on_entity_died, "Teleport.OnEntityDied", Teleport.OnEntityDied, {{
        filter = "type",
        type = "unit-spawner"
    }})
    Events.RegisterHandlerEvent(defines.events.script_raised_destroy, "Teleport.ScriptRaisedDestroy",
        Teleport.ScriptRaisedDestroy, {{
            filter = "type",
            type = "unit-spawner"
        }})
    EventScheduler.RegisterScheduledEventType("Teleport.OnChunkGenerated_Scheduled", Teleport.OnChunkGenerated_Scheduled)
    MOD.Interfaces.Commands.Teleport = Teleport.TeleportCommand
end

--- Triggered when the RCON command is run.
---@param command CustomCommandData
Teleport.TeleportCommand = function(command)
    local commandData = CommandsUtils.GetSettingsTableFromCommandParameterString(command.parameter, true, CommandName,
        {"delay", "target", "destinationType", "arrivalRadius", "minDistance", "maxDistance", "reachableOnly",
         "backupTeleportSettings", "suppressMessages"})
    if commandData == nil then
        return
    end

    local commandValues = Teleport.GetCommandData(commandData, 0, command.parameter, false)
    if commandValues == nil then
        return
    end

    Teleport.ScheduleTeleportCommand(commandValues)
end

--- Validates the data from an RCON commands's arguments in to a table of details.
---@param commandData table<string, any> # Table of arguments passed in to the RCON command.
---@param depth uint # Used when looping recursively in to backup settings. Populate as 0 for the initial calling of the function in the raw RCON command handler.
---@param commandStringText string # The raw command text sent via RCON.
---@param suppressMessagesDefault boolean
---@return Teleport_CommandDetails|nil commandDetails # Command details are returned if no errors hit, otherwise nil is returned.
Teleport.GetCommandData = function(commandData, depth, commandStringText, suppressMessagesDefault)
    local depthErrorMessage = ""
    if depth > 0 then
        depthErrorMessage = " at depth " .. depth .. " - "
    end

    -- Any errors raised need to include the depth message so we know how many backups it has got in to when it errored. So we add it to the end of the passed command name as this gets it to the right place in the produced error messages.
    local delaySeconds = commandData.delay
    if not CommandsUtils.CheckNumberArgument(delaySeconds, "double", false, CommandName, "delay" .. depthErrorMessage,
        0, nil, commandStringText) then
        return nil
    end ---@cast delaySeconds double|nil
    -- Don't pass the current tick value as we will add it later.
    local delayTicks = Common.DelaySecondsSettingToScheduledEventTickValue(delaySeconds, 0, CommandName,
        "delay " .. depthErrorMessage)

    local target = commandData.target
    if not Common.CheckPlayerNameSettingValue(target, CommandName, "target" .. depthErrorMessage, commandStringText) then
        return nil
    end ---@cast target string

    -- Can't check type in standard way as might be a string or table.
    local destinationTypeRaw = commandData.destinationType
    if destinationTypeRaw == nil then
        CommandsUtils.LogPrintError(CommandName, "destinationType" .. depthErrorMessage,
            "is Mandatory and must be populated", commandData.parameter)
        return nil
    end
    ---@type Teleport_DestinationTypeSelection, MapPosition|nil
    local destinationType, destinationTargetPosition
    if type(destinationTypeRaw) == "string" then
        if not CommandsUtils.CheckStringArgument(destinationTypeRaw, true, CommandName,
            "destinationType" .. depthErrorMessage, DestinationTypeSelection, commandData.parameter) then
            return nil
        end
        destinationType = DestinationTypeSelection[destinationTypeRaw]
    elseif type(destinationTypeRaw) == "table" then
        destinationTargetPosition = PositionUtils.TableToProperPosition(destinationTypeRaw)
        if destinationTargetPosition == nil then
            CommandsUtils.LogPrintError(CommandName, "destinationType" .. depthErrorMessage,
                "must be a valid map position object", commandData.parameter)
            return nil
        else
            -- TODO: Check if valid default
            destinationType = DestinationTypeSelection.position
        end
    else
        CommandsUtils.LogPrintError(CommandName, "destinationType",
            "must be a string or a map position object, but was a: " .. type(destinationTypeRaw), commandData.parameter)
        return nil
    end

    local destinationTypeDescription = DestinationTypeSelectionDescription[destinationType] ---@type Teleport_DestinationTypeSelectionDescription

    local arrivalRadius = commandData.arrivalRadius
    if not CommandsUtils.CheckNumberArgument(arrivalRadius, "double", false, CommandName,
        "arrivalRadius" .. depthErrorMessage, 0, nil, commandData.parameter) then
        return nil
    end ---@cast arrivalRadius double|nil
    if arrivalRadius == nil then
        arrivalRadius = 10.0
    end

    local minDistance = commandData.minDistance
    if not CommandsUtils.CheckNumberArgument(minDistance, "double", false, CommandName,
        "minDistance" .. depthErrorMessage, 0, nil, commandData.parameter) then
        return nil
    end ---@cast minDistance double|nil
    if minDistance == nil then
        minDistance = 0.0
    end

    local maxDistance = commandData.maxDistance
    if destinationType == DestinationTypeSelection.position or destinationType == DestinationTypeSelection.spawn or
        DestinationTypeSelection.player_position then
        if maxDistance ~= nil then
            CommandsUtils.LogPrintWarning(CommandName, "maxDistance" .. depthErrorMessage,
                "maxDistance setting is populated but will be ignored as the destinationType is either spawn, a set map position or a player position.",
                commandData.parameter)
        end
        maxDistance = 0
    else
        if not CommandsUtils.CheckNumberArgument(maxDistance, "double", true, CommandName,
            "maxDistance" .. depthErrorMessage, 0, nil, commandData.parameter) then
            return nil
        end ---@cast maxDistance double
    end

    local reachableOnly = commandData.reachableOnly
    if (destinationType == DestinationTypeSelection.biterNest or destinationType == DestinationTypeSelection.random) then
        if not CommandsUtils.CheckBooleanArgument(reachableOnly, false, CommandName,
            "reachableOnly" .. depthErrorMessage, commandData.parameter) then
            return
        end ---@cast reachableOnly boolean|nil
        if reachableOnly == nil then
            reachableOnly = false
        end
    else
        if reachableOnly ~= nil then
            CommandsUtils.LogPrintWarning(CommandName, "reachableOnly" .. depthErrorMessage,
                "reachableOnly setting is populated but will be ignored as the destinationType is either spawn or a set map position.",
                commandData.parameter)
        end
        reachableOnly = false
    end

    local suppressMessages = commandData.suppressMessages
    if not CommandsUtils.CheckBooleanArgument(suppressMessages, false, CommandName,
        "suppressMessages" .. depthErrorMessage, commandData.parameter) then
        return
    end ---@cast suppressMessages boolean|nil
    if suppressMessages == nil then
        -- Use the default inherited from the parent teleport command. Just so it doesn't have to be provided on every nested one.
        suppressMessages = suppressMessagesDefault
    end

    ---@type any, Teleport_CommandDetails|nil
    local backupTeleportSettingsRaw, backupTeleportSettings = commandData.backupTeleportSettings, nil
    if backupTeleportSettingsRaw ~= nil then
        if type(backupTeleportSettingsRaw) == "table" then
            backupTeleportSettings = Teleport.GetCommandData(backupTeleportSettingsRaw, depth + 1, commandStringText,
                suppressMessages)
            if backupTeleportSettings == nil then
                -- The error will have been already reported to screen during the function handling the contents, so just stop the command from executing here.
                return nil
            end
        else
            CommandsUtils.LogPrintError(CommandName, "backupTeleportSettings" .. depthErrorMessage,
                "backupTeleportSettings setting is populated but isn't a table of extra teleport settings, its type is: " ..
                    type(backupTeleportSettings), commandData.parameter)
            return nil
        end
    end

    ---@type Teleport_CommandDetails
    local commandDetails = {
        delay = delayTicks,
        target = target,
        arrivalRadius = arrivalRadius,
        minDistance = minDistance,
        maxDistance = maxDistance,
        destinationType = destinationType,
        destinationTargetPosition = destinationTargetPosition,
        reachableOnly = reachableOnly,
        backupTeleportSettings = backupTeleportSettings,
        destinationTypeDescription = destinationTypeDescription,
        suppressMessages = suppressMessages
    }
    return commandDetails
end

--- Schedule a commands details to occur after the set delay.
---@param commandValues Teleport_CommandDetails
Teleport.ScheduleTeleportCommand = function(commandValues)
    storage.teleport.nextId = storage.teleport.nextId + 1
    local currentTick = game.tick
    local scheduleTick = commandValues.delay > 0 and currentTick + commandValues.delay or (-1) --[[@as UtilityScheduledEvent_UintNegative1]]
    ---@type UtilityScheduledEvent_UintNegative1
    ---@type Teleport_TeleportDetails
    local teleportDetails = {
        teleportId = storage.teleport.nextId,
        target = commandValues.target,
        arrivalRadius = commandValues.arrivalRadius,
        minDistance = commandValues.minDistance,
        maxDistance = commandValues.maxDistance,
        destinationType = commandValues.destinationType,
        destinationTargetPosition = commandValues.destinationTargetPosition,
        reachableOnly = commandValues.reachableOnly,
        targetAttempt = 0,
        backupTeleportSettings = commandValues.backupTeleportSettings,
        destinationTypeDescription = commandValues.destinationTypeDescription,
        thisAttemptPosition = nil,
        spawnerDistances = {},
        suppressMessages = commandValues.suppressMessages
    }
    if scheduleTick ~= -1 then
        EventScheduler.ScheduleEventOnce(scheduleTick, "Teleport.PlanTeleportTarget", storage.teleport.nextId,
            teleportDetails)
    else
        ---@type UtilityScheduledEvent_CallbackObject
        local eventData = {
            tick = currentTick,
            name = "Teleport.PlanTeleportTarget",
            instanceId = storage.teleport.nextId,
            data = teleportDetails
        }
        Teleport.PlanTeleportTarget(eventData)
    end
end

--- When the actual teleport action needs to be planned and done (post scheduled delay).
--- Refreshes all player data on each load as waiting for pathfinder requests can make subsequent executions have different player state data.
---@param eventData UtilityScheduledEvent_CallbackObject
Teleport.PlanTeleportTarget = function(eventData)
    local data = eventData.data ---@type Teleport_TeleportDetails

    -- Get the Player object and confirm its valid.
    local targetPlayer = game.get_player(data.target)
    if targetPlayer == nil then
        CommandsUtils.LogPrintWarning(CommandName, nil, "Target player has been deleted since the command was run.", nil)
        return
    end

    -- Check the player is alive (not dead) and not in editor mode. If they are just end the attempt.
    if not (targetPlayer.controller_type == defines.controllers.character or targetPlayer.controller_type ==
        defines.controllers.remote) or targetPlayer.character == nil then
        if not data.suppressMessages then
            game.print({"message.muppet_streamer_v2_teleport_not_character_controller", data.target})
        end
        return
    end

    -- Get the key data about the players current situation.
    local targetPlayer_surface = targetPlayer.physical_surface
    local targetPlayer_force = targetPlayer.force --[[@as LuaForce # Work around for R/W limitation]]
    -- Sumneko limitation workaround on R/W types.
    local targetPlayer_position = targetPlayer.physical_position

    -- Increment the attempt counter for trying to find a target to teleport too.
    data.targetAttempt = data.targetAttempt + 1

    -- Find a target based on the command settings.
    if data.destinationType == DestinationTypeSelection.spawn then
        data.destinationTargetPosition = targetPlayer_force.get_spawn_position(targetPlayer_surface)
    elseif data.destinationType == DestinationTypeSelection.position then
        data.destinationTargetPosition = data.destinationTargetPosition
    elseif data.destinationType == DestinationTypeSelection.random then
        data.destinationTargetPosition = PositionUtils.RandomLocationInRadius(targetPlayer_position, data.maxDistance,
            data.minDistance)
    elseif data.destinationType == DestinationTypeSelection.biterNest then
        local targetPlayer_surface_index = targetPlayer_surface.index
        local targetPlayer_force_name = targetPlayer_force.name

        -- Populate data.spawnerDistance with valid enemy spawners on the player's current surface if needed, otherwise handle last bad result.
        if data.targetAttempt > 1 then
            -- This target position has been found to be bad so remove any spawners too close to this bad location for this player.
            ---@type double, double, double
            local distanceXDiff, distanceYDiff, spawnerDistance
            ---@type uint
            for index, spawnerDistanceDetails in pairs(data.spawnerDistances) do
                -- CODE NOTE: Do locally rather than via function call as we call this a lot and its so simple logic.
                distanceXDiff = targetPlayer_position.x - spawnerDistanceDetails.spawnerDetails.position.x
                distanceYDiff = targetPlayer_position.y - spawnerDistanceDetails.spawnerDetails.position.y
                spawnerDistance = math.sqrt(distanceXDiff * distanceXDiff + distanceYDiff * distanceYDiff)
                -- if PositionUtils.GetDistance(data.destinationTargetPosition, spawnerDistanceDetails.spawnerDetails.position) < 30 then
                if spawnerDistance < 30 then
                    -- Potential spawner is too close to a bad previous target attempt, so remove it from our list.
                    data.spawnerDistances[index] = nil
                end
            end
        else
            -- Is a first loop for this target player so build up the spawner list.
            ---@type double, double, double
            local spawnerDistance, distanceXDiff, distanceYDiff
            for spawnersForceName, forcesSpawnerDetails in pairs(
                storage.teleport.surfaceBiterNests[targetPlayer_surface_index]) do
                -- Check the force is an enemy. So we ignore all non-enemy spawners in bulk.
                if targetPlayer_force_name ~= spawnersForceName and spawnersForceName ~= "neutral" and
                    not targetPlayer_force.get_cease_fire(spawnersForceName) and
                    not targetPlayer_force.get_friend(spawnersForceName) then
                    for _, spawnerDetails in pairs(forcesSpawnerDetails) do
                        -- Work out it's distance from the target player and add it to our table.

                        -- CODE NOTE: Do locally rather than via function call as we call this a lot and its so simple logic.
                        distanceXDiff = targetPlayer_position.x - spawnerDetails.position.x
                        distanceYDiff = targetPlayer_position.y - spawnerDetails.position.y
                        spawnerDistance = math.sqrt(distanceXDiff * distanceXDiff + distanceYDiff * distanceYDiff)
                        -- spawnerDistance = PositionUtils.GetDistance(targetPlayer_position, spawnerDetails.position)

                        if spawnerDistance <= data.maxDistance and spawnerDistance >= data.minDistance then
                            ---@type Teleport_TargetPlayerSpawnerDistanceDetails
                            local spawnerDistanceDetails = {
                                distance = spawnerDistance,
                                spawnerDetails = spawnerDetails
                            }
                            -- While this is inserted as consistent key ID's it can be manipulated later to be gappy.
                            data.spawnerDistances[#data.spawnerDistances + 1 --[[@as uint]] ] = spawnerDistanceDetails
                        end
                    end
                end
            end
        end

        -- Handle if no valid spawners to try.
        if next(data.spawnerDistances) == nil then
            if not data.suppressMessages then
                game.print({"message.muppet_streamer_v2_teleport_no_biter_nest_found", targetPlayer.name})
            end
            Teleport.DoBackupTeleport(data)
            return
        end

        -- Sort the spawners to find the nearest one and set it as the target position.
        if data.targetAttempt == 1 then
            table.sort(data.spawnerDistances, function(a, b)
                return a.distance < b.distance
            end)
        end

        -- Check the nearest one is still valid. Do this way as unless its the spawner we are aiming for it doesn't matter if its invalid.
        local firstSpawnerDistancesIndex ---@type uint|nil
        local nearestSpawnerDistanceDetails ---@type Teleport_TargetPlayerSpawnerDistanceDetails|nil
        while nearestSpawnerDistanceDetails == nil do
            firstSpawnerDistancesIndex, nearestSpawnerDistanceDetails = next(data.spawnerDistances)
            if nearestSpawnerDistanceDetails == nil then
                -- Have already removed the last possible spawner as its invalid, so no valid targets.
                if not data.suppressMessages then
                    game.print({"message.muppet_streamer_v2_teleport_no_biter_nest_found", targetPlayer.name})
                end
                Teleport.DoBackupTeleport(data)
                return
            end

            -- Check if the nearest spawner is still valid. Its possible to remove spawners without us knowing about it, i.e. via Editor or via script and not raising an event for it. So we have to check.
            if not nearestSpawnerDistanceDetails.spawnerDetails.entity.valid then
                -- Remove the spawner from this search.
                ---@diagnostic disable-next-line: need-check-nil
                data.spawnerDistances[firstSpawnerDistancesIndex] = nil

                -- Remove the spawner from the global spawner list.
                storage.teleport.surfaceBiterNests[targetPlayer_surface_index][nearestSpawnerDistanceDetails.spawnerDetails
                    .forceName][nearestSpawnerDistanceDetails.spawnerDetails.unitNumber] = nil

                -- Clear the spawner result so the while loop continues to look at the nearest remaining one.
                nearestSpawnerDistanceDetails = nil
            end
        end

        -- Set the target position to the valid spawner.
        data.destinationTargetPosition = nearestSpawnerDistanceDetails.spawnerDetails.position
    elseif data.destinationType == DestinationTypeSelection.enemyUnit then
        local nearestEnemy = targetPlayer_surface.find_nearest_enemy {
            position = targetPlayer_position,
            max_distance = data.maxDistance,
            force = targetPlayer_force
        }
        if nearestEnemy == nil then
            if not data.suppressMessages then
                game.print({"message.muppet_streamer_v2_teleport_no_enemy_unit_found", targetPlayer.name})
            end
            Teleport.DoBackupTeleport(data)
            return
        end
        data.destinationTargetPosition = nearestEnemy.position
    end

    -- Store the key data for checking/using later. We update on every loop so that any change of key data that triggers a re-loop starts fresh.
    data.targetPlayer = targetPlayer
    data.targetPlayer_surface = targetPlayer_surface
    data.targetPlayer_force = targetPlayer_force

    -- Make the teleport request to near by the target identified.
    local teleportResponse = PlayerTeleport.RequestTeleportToNearPosition(targetPlayer, targetPlayer_surface,
        data.destinationTargetPosition, data.arrivalRadius, MaxRandomPositionsAroundTargetToTry,
        MaxDistancePositionAroundTarget, data.reachableOnly and targetPlayer_position or nil)

    -- Handle the teleport response.
    local pathRequestId = teleportResponse.pathRequestId -- Variables existence is a workaround for Sumneko missing object field nil detection.
    if teleportResponse.teleportSucceeded == true then
        -- All completed.
        return
    elseif pathRequestId ~= nil then
        -- A pathing request has been made, monitor it and react when it completes.
        data.targetPlayerPlacementEntity, data.thisAttemptPosition = teleportResponse.targetPlayerTeleportEntity,
            teleportResponse.targetPosition
        storage.teleport.pathingRequests[pathRequestId] = data
        return
    elseif teleportResponse.errorNoValidPositionFound then
        -- No valid position was found to try and teleport too.
        if data.targetAttempt > MaxTargetAttempts then
            if not data.suppressMessages then
                game.print({"message.muppet_streamer_v2_teleport_no_teleport_location_found", targetPlayer.name})
            end
            Teleport.DoBackupTeleport(data)
            return
        else
            Teleport.PlanTeleportTarget({
                data = data
            })
            return
        end
    elseif teleportResponse.errorTeleportFailed then
        -- Failed to teleport the entity to the specific position.
        CommandsUtils.LogPrintWarning(CommandName, nil,
            "Teleport action for player " .. targetPlayer.name .. " to position " ..
                LoggingUtils.PositionToString(teleportResponse.targetPosition) .. " failed (Factorio request rejected).",
            nil)
        Teleport.DoBackupTeleport(data)
        return
    end
end

--- React to path requests being completed. If the path request was for a teleport request then we need to validate things again as there could be a significant gap between the path request being made and the response coming back.
---@param event EventData.on_script_path_request_finished
Teleport.OnScriptPathRequestFinished = function(event)
    -- Check if this path request related to a Teleport.
    local data = storage.teleport.pathingRequests[event.id]
    if data == nil then
        -- Not our path request.
        return
    end

    -- Update the globals.
    storage.teleport.pathingRequests[event.id] = nil

    -- Check some key LuaObjects still exist. This is to avoid risk of crashes during any checks for changes.
    if not data.targetPlayer_surface.valid or not data.targetPlayer_force.valid then
        -- Something critical isn't valid, so we should always retry to get fresh data.
        data.targetAttempt = data.targetAttempt - 1
        Teleport.PlanTeleportTarget({
            data = data
        })
        return
    end

    if event.path == nil then
        -- Path request failed.
        if data.targetAttempt > MaxTargetAttempts then
            if not data.suppressMessages then
                game.print({"message.muppet_streamer_v2_teleport_no_teleport_location_found", data.targetPlayer.name})
            end
            Teleport.DoBackupTeleport(data)
        else
            Teleport.PlanTeleportTarget({
                data = data
            })
        end
    else
        -- Path request succeeded.

        -- CODE NOTE: As this has an unknown delay between request and result we need to validate everything important is unchanged before accepting the result and teleporting the player there. If something critical has changed we repeat the entire target selection to avoid complicated code. But we subtract 1 from the attempts so its a free retry.

        -- Check the player is still alive and in a suitable game state (not editor) to be teleported. If they aren't suitable just abandon the teleport.
        if data.targetPlayer.controller_type ~= defines.controllers.character then
            if not data.suppressMessages then
                game.print({"message.muppet_streamer_v2_teleport_not_character_controller", data.target})
            end
            return
        end

        -- Check the player's surface is the same as start of pathing request.
        if data.targetPlayer.surface ~= data.targetPlayer_surface then
            data.targetAttempt = data.targetAttempt - 1
            Teleport.PlanTeleportTarget({
                data = data
            })
            return
        end

        -- Check the player's force is the same as start of pathing request.
        if data.targetPlayer.force ~= data.targetPlayer_force then
            data.targetAttempt = data.targetAttempt - 1
            Teleport.PlanTeleportTarget({
                data = data
            })
            return
        end

        -- Get the players current placement entity and vehicle facing.
        local currentPlayerPlacementEntity, currentPlayerPlacementEntity_isVehicle =
            PlayerTeleport.GetPlayerTeleportPlacementEntity(data.targetPlayer, nil)
        if currentPlayerPlacementEntity == nil then
            -- If the target player doesn't have an entity then nothing further to do.
            if not data.suppressMessages then
                game.print({"message.muppet_streamer_v2_teleport_no_character", data.targetPlayer.name})
            end
            return
        end
        -- If a vehicle get its current nearest cardinal (4) direction to orientation.
        local currentPlayerPlacementEntity_vehicleDirectionFacing ---@type defines.direction|nil
        if currentPlayerPlacementEntity_isVehicle then
            currentPlayerPlacementEntity_vehicleDirectionFacing =
                DirectionUtils.OrientationToNearestCardinalDirection(currentPlayerPlacementEntity.orientation)
        end

        -- Check the player's character/vehicle is still as expected.
        if currentPlayerPlacementEntity ~= data.targetPlayerPlacementEntity then
            data.targetAttempt = data.targetAttempt - 1
            Teleport.PlanTeleportTarget({
                data = data
            })
            return
        end

        -- Check the target location hasn't been blocked since we made the path request. This also checks the entity can be placed with its current orientation rounded to a direction, so if its changed from when the pathfinder request was made it will either be confirmed as being fine or fail and be retried.
        if not data.targetPlayer_surface.can_place_entity {
            name = currentPlayerPlacementEntity.name,
            position = data.thisAttemptPosition,
            direction = currentPlayerPlacementEntity_vehicleDirectionFacing,
            force = data.targetPlayer_force,
            build_check_type = defines.build_check_type.manual
        } then
            data.targetAttempt = data.targetAttempt - 1
            Teleport.PlanTeleportTarget({
                data = data
            })
            return
        end
        if currentPlayerPlacementEntity_vehicleDirectionFacing ~= nil then
            -- Change the vehicles orientation to match the direction we checked. This will be a slight angle change, but the teleport should hide it.
            currentPlayerPlacementEntity.orientation = currentPlayerPlacementEntity_vehicleDirectionFacing / 8 --[[@as RealOrientation]]
        end

        -- Everything is as expected still, so teleport can commence.
        local teleportSucceeded = PlayerTeleport.TeleportToSpecificPosition(data.targetPlayer,
            data.targetPlayer_surface, data.thisAttemptPosition)

        -- If the teleport of the player's entity/vehicle to the specific position failed then do next action if there is one.
        if not teleportSucceeded then
            CommandsUtils.LogPrintWarning(CommandName, nil,
                "Teleport action for player " .. data.targetPlayer.name .. " to position " ..
                    LoggingUtils.PositionToString(data.thisAttemptPosition) .. " failed (Factorio request rejected).",
                nil)
            Teleport.DoBackupTeleport(data)
        end
    end
end

--- Called when a higher priority teleport has failed. If there's a backup teleport action that will be tried next.
---@param data Teleport_TeleportDetails
Teleport.DoBackupTeleport = function(data)
    if data.backupTeleportSettings ~= nil then
        if not data.suppressMessages then
            game.print({"message.muppet_streamer_v2_teleport_doing_backup",
                        data.backupTeleportSettings.destinationTypeDescription, data.backupTeleportSettings.target})
        end
        Teleport.ScheduleTeleportCommand(data.backupTeleportSettings)
    end
end

---@param event EventData.on_biter_base_built
Teleport.OnBiterBaseBuilt = function(event)
    local entity = event.entity
    if not entity.valid or entity.type ~= "unit-spawner" then
        return
    end
    Teleport.SpawnerCreated(entity)
end

---@param event EventData.script_raised_built
Teleport.ScriptRaisedBuilt = function(event)
    local entity = event.entity
    if not entity.valid or entity.type ~= "unit-spawner" then
        return
    end
    Teleport.SpawnerCreated(entity)
end

---@param event EventData.on_chunk_generated
Teleport.OnChunkGenerated = function(event)
    storage.teleport.chunkGeneratedId = storage.teleport.chunkGeneratedId + 1
    -- Check the chunk in 1 ticks time to let any other mod or scenario complete its actions first.
    EventScheduler.ScheduleEventOnce(event.tick + 1, "Teleport.OnChunkGenerated_Scheduled",
        storage.teleport.chunkGeneratedId, event)
end

--- When a chunk is generated we wait for 1 tick and then this function is called. Lets any other mod/scenario mess with the spawner prior to use caching its details.
---@param eventData any
Teleport.OnChunkGenerated_Scheduled = function(eventData)
    local event = eventData.data ---@type EventData.on_chunk_generated
    local spawners = event.surface.find_entities_filtered {
        area = event.area,
        type = "unit-spawner"
    }
    for _, spawner in pairs(spawners) do
        Teleport.SpawnerCreated(spawner)
    end
end

---@param event EventData.on_entity_died
Teleport.OnEntityDied = function(event)
    local entity = event.entity
    if not entity.valid or entity.type ~= "unit-spawner" then
        return
    end
    Teleport.SpawnerRemoved(entity)
end

---@param event EventData.script_raised_destroy
Teleport.ScriptRaisedDestroy = function(event)
    local entity = event.entity
    if not entity.valid or entity.type ~= "unit-spawner" then
        return
    end
    Teleport.SpawnerRemoved(entity)
end

--- Called when a spawner has been created and we need to add it to our records.
---@param spawner LuaEntity
Teleport.SpawnerCreated = function(spawner)
    -- Create the surface table if it doesn't exist. Happens when the surface is created adhoc during play.
    local spawner_surface_index = spawner.surface.index
    storage.teleport.surfaceBiterNests[spawner_surface_index] =
        storage.teleport.surfaceBiterNests[spawner_surface_index] or {}
    -- Record the spawner.
    local spawner_unitNumber, spawner_force_name = spawner.unit_number, spawner.force.name ---@cast spawner_unitNumber -nil # Spawner entities always have a unit_number field.
    storage.teleport.surfaceBiterNests[spawner_surface_index][spawner_force_name] =
        storage.teleport.surfaceBiterNests[spawner_surface_index][spawner_force_name] or {}
    storage.teleport.surfaceBiterNests[spawner_surface_index][spawner_force_name][spawner_unitNumber] = {
        unitNumber = spawner_unitNumber,
        entity = spawner,
        forceName = spawner_force_name,
        position = spawner.position
    }
end

--- Called when a spawner has been removed from the map and we need to remove it from our records.
---@param spawner LuaEntity
Teleport.SpawnerRemoved = function(spawner)
    local thisSurfaceBiterNests = storage.teleport.surfaceBiterNests[spawner.surface.index]
    if thisSurfaceBiterNests == nil then
        -- No records for this surface so nothing to remove. Shouldn't be possible to reach, but is safer.
        return
    end
    local thisSurfaceForceBiterNests = thisSurfaceBiterNests[spawner.force.name]
    if thisSurfaceForceBiterNests == nil then
        -- No records for this force on this surface so nothing to remove. Shouldn't be possible to reach, but is safer.
        return
    end
    thisSurfaceForceBiterNests[spawner.unit_number --[[@as uint # Spawner entity always has a unit_number.]] ] = nil
end

--- Find all existing spawners on all surfaces and record them. For use at mods initial load to handle being added to a map mid game.
---@return surfaceForceBiterNests surfacesSpawners
Teleport.FindExistingSpawnersOnAllSurfaces = function()
    local surfacesSpawners = {} ---@type surfaceForceBiterNests
    for _, surface in pairs(game.surfaces) do
        local surface_index = surface.index
        surfacesSpawners[surface_index] = {}
        local spawners = surface.find_entities_filtered {
            type = "unit-spawner"
        }
        for _, spawner in pairs(spawners) do
            local spawner_unitNumber, spawner_force_name = spawner.unit_number, spawner.force.name ---@cast spawner_unitNumber -nil # Spawner entities always have a unit_number field.
            surfacesSpawners[surface_index][spawner_force_name] =
                surfacesSpawners[surface_index][spawner_force_name] or {}
            surfacesSpawners[surface_index][spawner_force_name][spawner_unitNumber] = {
                unitNumber = spawner_unitNumber,
                entity = spawner,
                forceName = spawner_force_name,
                position = spawner.position
            }
        end
    end
    return surfacesSpawners
end

return Teleport
