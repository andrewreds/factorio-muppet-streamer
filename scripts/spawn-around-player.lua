local SpawnAroundPlayer = {} ---@class SpawnAroundPlayer
local CommandsUtils = require("utility.helper-utils.commands-utils")
local EventScheduler = require("utility.manager-libraries.event-scheduler")
local PositionUtils = require("utility.helper-utils.position-utils")
local BiomeTrees = require("utility.functions.biome-trees")
local Common = require("scripts.common")
local MathUtils = require("utility.helper-utils.math-utils")

---@enum SpawnAroundPlayer_ExistingEntities
local ExistingEntitiesTypes = {
    overlap = "overlap",
    avoid = "avoid"
}

---@class SpawnAroundPlayer_ScheduledDetails
---@field target string
---@field targetPosition MapPosition|nil
---@field targetOffset MapPosition|nil
---@field entityTypeName SpawnAroundPlayer_EntityTypeNames
---@field customEntityName? string
---@field customSecondaryDetail? string
---@field radiusMax uint
---@field radiusMin uint
---@field existingEntities SpawnAroundPlayer_ExistingEntities
---@field quantity uint|nil
---@field density double|nil
---@field ammoCount uint|nil
---@field followPlayer boolean|nil
---@field forceString string|nil
---@field removalTimeMinScheduleTick uint|nil
---@field removalTimeMaxScheduleTick uint|nil

---@enum SpawnAroundPlayer_EntityTypeNames
local EntityTypeNames = {
    tree = "tree",
    rock = "rock",
    laserTurret = "laserTurret",
    gunTurretRegularAmmo = "gunTurretRegularAmmo",
    gunTurretPiercingAmmo = "gunTurretPiercingAmmo",
    gunTurretUraniumAmmo = "gunTurretUraniumAmmo",
    wall = "wall",
    landmine = "landmine",
    fire = "fire",
    defenderBot = "defenderBot",
    distractorBot = "distractorBot",
    destroyerBot = "destroyerBot",
    custom = "custom"
}

---@class SpawnAroundPlayer_EntityTypeDetails
---@field ValidateEntityPrototypes fun(commandString?: string|nil): boolean # Checks that the LuaEntity for the entityName is as we expect; exists and correct type.
---@field GetDefaultForce fun(targetPlayer: LuaPlayer): LuaForce
---@field GetEntityName fun(surface: LuaSurface, position: MapPosition): string|nil # Should normally return something, but some advanced features may not, i.e. getting tree for void tiles.
---@field GetEntityAlignedPosition (fun(position: MapPosition): MapPosition)|nil
---@field FindValidPlacementPosition fun(surface: LuaSurface, entityName: string, position: MapPosition, searchRadius, double): MapPosition|nil
---@field PlaceEntity fun(data: SpawnAroundPlayer_PlaceEntityDetails):LuaEntity|nil # Will return the entity created if it worked.
---@field GetPlayersMaxBotFollowers? fun(targetPlayer: LuaPlayer): uint
---@field gridPlacementSize uint|nil # If the thing needs to be placed on a grid and how big that grid is. Used for things that can't go off grid and have larger collision boxes.

---@class SpawnAroundPlayer_PlaceEntityDetails
---@field surface LuaSurface
---@field entityName string # Prototype entity name.
---@field position MapPosition
---@field targetPlayer LuaPlayer
---@field ammoCount uint|nil
---@field followPlayer boolean
---@field force LuaForce

---@class SpawnAroundPlayer_RemoveEntityScheduled
---@field entity LuaEntity

SpawnAroundPlayer.quantitySearchRadius = 3
SpawnAroundPlayer.densitySearchRadius = 0.6
SpawnAroundPlayer.offGridPlacementJitter = 0.3

local CommandName = "muppet_streamer_v2_spawn_around_player"

SpawnAroundPlayer.CreateGlobals = function()
    storage.spawnAroundPlayer = storage.spawnAroundPlayer or {} ---@class SpawnAroundPlayer_Global
    storage.spawnAroundPlayer.nextId = storage.spawnAroundPlayer.nextId or 0 ---@type uint
    storage.spawnAroundPlayer.removeEntityNextId = storage.spawnAroundPlayer.removeEntityNextId or 0 ---@type uint
end

SpawnAroundPlayer.OnLoad = function()
    CommandsUtils.Register("muppet_streamer_v2_spawn_around_player",
        {"api-description.muppet_streamer_v2_spawn_around_player"}, SpawnAroundPlayer.SpawnAroundPlayerCommand, true)
    EventScheduler.RegisterScheduledEventType("SpawnAroundPlayer.SpawnAroundPlayerScheduled",
        SpawnAroundPlayer.SpawnAroundPlayerScheduled)
    EventScheduler.RegisterScheduledEventType("SpawnAroundPlayer.RemoveEntityScheduled",
        SpawnAroundPlayer.RemoveEntityScheduled)
    MOD.Interfaces.Commands.SpawnAroundPlayer = SpawnAroundPlayer.SpawnAroundPlayerCommand
end

SpawnAroundPlayer.OnStartup = function()
    BiomeTrees.OnStartup()
end

---@param command CustomCommandData
---@return LuaEntity[]|nil createdEntities
SpawnAroundPlayer.SpawnAroundPlayerCommand = function(command)
    local commandData = CommandsUtils.GetSettingsTableFromCommandParameterString(command.parameter, true, CommandName,
        {"delay", "target", "targetPosition", "targetOffset", "force", "entityName", "customEntityName",
         "customSecondaryDetail", "radiusMax", "radiusMin", "existingEntities", "quantity", "density", "ammoCount",
         "followPlayer", "removalTimeMin", "removalTimeMax"})
    if commandData == nil then
        return nil
    end

    local delaySeconds = commandData.delay
    if not CommandsUtils.CheckNumberArgument(delaySeconds, "double", false, CommandName, "delay", 0, nil,
        command.parameter) then
        return nil
    end ---@cast delaySeconds double|nil
    local scheduleTick = Common.DelaySecondsSettingToScheduledEventTickValue(delaySeconds, command.tick, CommandName,
        "delay")
    local commandEffectTick = scheduleTick > 0 and scheduleTick --[[@as uint]] or command.tick ---@type uint # The tick the command will be executed.

    local target = commandData.target
    if not Common.CheckPlayerNameSettingValue(target, CommandName, "target", command.parameter) then
        return nil
    end ---@cast target string

    local targetPosition = commandData.targetPosition
    if not CommandsUtils.CheckTableArgument(targetPosition, false, CommandName, "targetPosition",
        PositionUtils.MapPositionConvertibleTableValidKeysList, command.parameter) then
        return nil
    end ---@cast targetPosition MapPosition|nil
    if targetPosition ~= nil then
        targetPosition = PositionUtils.TableToProperPosition(targetPosition)
        if targetPosition == nil then
            CommandsUtils.LogPrintError(CommandName, "targetPosition", "must be a valid position table string",
                command.parameter)
            return nil
        end
    end

    local targetOffset = commandData.targetOffset ---@type MapPosition|nil
    if not CommandsUtils.CheckTableArgument(targetOffset, false, CommandName, "targetOffset",
        PositionUtils.MapPositionConvertibleTableValidKeysList, command.parameter) then
        return nil
    end ---@cast targetOffset MapPosition|nil
    if targetOffset ~= nil then
        targetOffset = PositionUtils.TableToProperPosition(targetOffset)
        if targetOffset == nil then
            CommandsUtils.LogPrintError(CommandName, "targetOffset", "must be a valid position table string",
                command.parameter)
            return nil
        end
    end

    local forceString = commandData.force
    if not CommandsUtils.CheckStringArgument(forceString, false, CommandName, "force", nil, command.parameter) then
        return nil
    end ---@cast forceString string|nil
    if forceString ~= nil then
        if game.forces[forceString] == nil then
            CommandsUtils.LogPrintError(CommandName, "force", "has an invalid force name: " .. tostring(forceString),
                command.parameter)
            return nil
        end
    end

    -- Just get these settings and make sure they are the right data type, validate their sanity later.
    local customEntityName = commandData.customEntityName
    if not CommandsUtils.CheckStringArgument(customEntityName, false, CommandName, "customEntityName", nil,
        command.parameter) then
        return nil
    end ---@cast customEntityName string|nil
    local customSecondaryDetail = commandData.customSecondaryDetail
    if not CommandsUtils.CheckStringArgument(customSecondaryDetail, false, CommandName, "customSecondaryDetail", nil,
        command.parameter) then
        return nil
    end ---@cast customSecondaryDetail string|nil

    local creationName = commandData.entityName
    if not CommandsUtils.CheckStringArgument(creationName, true, CommandName, "entityName", EntityTypeNames,
        command.parameter) then
        return nil
    end ---@cast creationName string
    local entityTypeName = EntityTypeNames[creationName]

    -- Populate the entityTypeDetails functions based on the entity type and command settings.
    local entityTypeDetails
    if entityTypeName ~= EntityTypeNames.custom then
        -- Lookup the predefined EntityTypeDetails.
        entityTypeDetails = SpawnAroundPlayer.GetBuiltinEntityTypeDetails(entityTypeName)

        -- Check the expected prototypes are present and roughly the right details.
        if not entityTypeDetails.ValidateEntityPrototypes(command.parameter) then
            return nil
        end

        -- Check no ignored custom settings for a non custom entityName.
        if customEntityName ~= nil then
            CommandsUtils.LogPrintWarning(CommandName, "customEntityName",
                "value was provided, but being ignored as the entityName wasn't 'custom'.", command.parameter)
        end
        if customSecondaryDetail ~= nil then
            CommandsUtils.LogPrintWarning(CommandName, "customSecondaryDetail",
                "value was provided, but being ignored as the entityName wasn't 'custom'.", command.parameter)
        end
    else
        -- Check just whats needed from the custom settings for the validation needed for this as no post validation can be done given its dynamic nature. Upon usage minimal validation will be done, but the creation details will be generated as not needed at this point.
        if customEntityName == nil then
            CommandsUtils.LogPrintError(CommandName, "customEntityName",
                "value wasn't provided, but is required as the entityName is 'custom'.", command.parameter)
            return nil
        end
        local customEntityPrototype = prototypes.entity[customEntityName]
        if customEntityPrototype == nil then
            CommandsUtils.LogPrintError(CommandName, "customEntityName",
                "entity '" .. customEntityName .. "' wasn't a valid entity name", command.parameter)
            return nil
        end

        local customEntityPrototype_type = customEntityPrototype.type
        local usedSecondaryData = false
        if customEntityPrototype_type == "ammo-turret" or customEntityPrototype_type == "artillery-turret" then
            if customSecondaryDetail ~= nil then
                usedSecondaryData = true
                local ammoItemPrototype = prototypes.item[customSecondaryDetail]
                if ammoItemPrototype == nil then
                    CommandsUtils.LogPrintError(CommandName, "customSecondaryDetail",
                        "item '" .. customSecondaryDetail .. "' wasn't a valid item name", command.parameter)
                    return nil
                end
                local ammoItemPrototype_type = ammoItemPrototype.type
                if ammoItemPrototype_type ~= 'ammo' then
                    CommandsUtils.LogPrintError(CommandName, "customSecondaryDetail",
                        "item '" .. customSecondaryDetail .. "' wasn't an ammo item type, instead it was a type: " ..
                            tostring(ammoItemPrototype_type), command.parameter)
                    return nil
                end
            end
        elseif customEntityPrototype_type == "fluid-turret" then
            if customSecondaryDetail ~= nil then
                usedSecondaryData = true
                local ammoFluidPrototype = prototypes.fluid[customSecondaryDetail]
                if ammoFluidPrototype == nil then
                    CommandsUtils.LogPrintError(CommandName, "customSecondaryDetail",
                        "fluid '" .. customSecondaryDetail .. "' wasn't a valid fluid name", command.parameter)
                    return nil
                end
                -- Can't check the required fluid count as missing fields in API, requested: https://forums.factorio.com/viewtopic.php?f=28&t=103311
            end
        end

        -- Check that customSecondaryDetail setting wasn't populated if it wasn't used.
        if not usedSecondaryData and customSecondaryDetail ~= nil then
            CommandsUtils.LogPrintWarning(CommandName, "customSecondaryDetail",
                "value was provided, but being ignored as the type of customEntityName didn't require it.",
                command.parameter)
        end
    end

    local radiusMax = commandData.radiusMax
    if not CommandsUtils.CheckNumberArgument(radiusMax, "int", true, CommandName, "radiusMax", 0, MathUtils.uintMax,
        command.parameter) then
        return nil
    end ---@cast radiusMax uint

    local radiusMin = commandData.radiusMin
    if not CommandsUtils.CheckNumberArgument(radiusMin, "int", false, CommandName, "radiusMin", 0, MathUtils.uintMax,
        command.parameter) then
        return nil
    end ---@cast radiusMin uint|nil
    if radiusMin == nil then
        radiusMin = 0
    else
        if radiusMin > radiusMax then
            CommandsUtils.LogPrintError(CommandName, "radiusMin", "can't be set larger than the maximum radius",
                command.parameter)
            return nil
        end
    end

    local existingEntitiesString = commandData.existingEntities
    if not CommandsUtils.CheckStringArgument(existingEntitiesString, true, CommandName, "existingEntities",
        ExistingEntitiesTypes, command.parameter) then
        return nil
    end ---@cast existingEntitiesString string
    local existingEntities = ExistingEntitiesTypes[existingEntitiesString] ---@type SpawnAroundPlayer_ExistingEntities

    local quantity = commandData.quantity
    if not CommandsUtils.CheckNumberArgument(quantity, "int", false, CommandName, "quantity", 0, MathUtils.uintMax,
        command.parameter) then
        return nil
    end ---@cast quantity uint|nil

    local density = commandData.density
    if not CommandsUtils.CheckNumberArgument(density, "double", false, CommandName, "density", 0, nil, command.parameter) then
        return nil
    end ---@cast density double|nil

    -- Check that either quantity or density is provided.
    if quantity == nil and density == nil then
        CommandsUtils.LogPrintError(CommandName, nil,
            "either quantity or density must be provided, otherwise the command will create nothing.", command.parameter)
        return nil
    end

    local ammoCount = commandData.ammoCount
    if not CommandsUtils.CheckNumberArgument(ammoCount, "int", false, CommandName, "ammoCount", 0, MathUtils.uintMax,
        command.parameter) then
        return nil
    end ---@cast ammoCount uint|nil

    local followPlayer = commandData.followPlayer
    if not CommandsUtils.CheckBooleanArgument(followPlayer, false, CommandName, "followPlayer", command.parameter) then
        return nil
    end ---@cast followPlayer boolean|nil

    local removalTimeMin_seconds = commandData.removalTimeMin
    if not CommandsUtils.CheckNumberArgument(removalTimeMin_seconds, "double", false, CommandName, "removalTimeMin", 0,
        nil, command.parameter) then
        return nil
    end ---@cast removalTimeMin_seconds double|nil
    local removalTimeMin_scheduleTick = Common.SecondsSettingToTickValue(removalTimeMin_seconds, commandEffectTick,
        CommandName, "removalTimeMin")

    local removalTimeMax_seconds = commandData.removalTimeMax
    if not CommandsUtils.CheckNumberArgument(removalTimeMax_seconds, "double", false, CommandName, "removalTimeMax", 0,
        nil, command.parameter) then
        return nil
    end ---@cast removalTimeMax_seconds double|nil
    local removalTimeMax_scheduleTick = Common.SecondsSettingToTickValue(removalTimeMax_seconds, commandEffectTick,
        CommandName, "removalTimeMax")

    -- Ensure the removal min and max tick are both populated if one is.
    if removalTimeMin_scheduleTick ~= nil and removalTimeMax_scheduleTick == nil then
        removalTimeMax_scheduleTick = removalTimeMin_scheduleTick
    elseif removalTimeMax_scheduleTick ~= nil and removalTimeMin_scheduleTick == nil then
        removalTimeMin_scheduleTick = removalTimeMax_scheduleTick ---@type uint
    end

    -- Ensure the removal min tick is not greater than the removal max tick.
    if removalTimeMin_scheduleTick ~= nil and removalTimeMin_scheduleTick > removalTimeMax_scheduleTick then
        CommandsUtils.LogPrintError(CommandName, "removalTimeMin", "can't be set larger than the maximum removal time",
            command.parameter)
        return nil
    end

    storage.spawnAroundPlayer.nextId = storage.spawnAroundPlayer.nextId + 1
    -- Can't transfer the Type object with the generated functions as it goes in to `global` for when there is a delay. So we just pass the name and then re-generate it at run time.
    ---@type SpawnAroundPlayer_ScheduledDetails
    local scheduledDetails = {
        target = target,
        targetPosition = targetPosition,
        targetOffset = targetOffset,
        entityTypeName = entityTypeName,
        customEntityName = customEntityName,
        customSecondaryDetail = customSecondaryDetail,
        radiusMax = radiusMax,
        radiusMin = radiusMin,
        existingEntities = existingEntities,
        quantity = quantity,
        density = density,
        ammoCount = ammoCount,
        followPlayer = followPlayer,
        forceString = forceString,
        removalTimeMinScheduleTick = removalTimeMin_scheduleTick,
        removalTimeMaxScheduleTick = removalTimeMax_scheduleTick
    }
    if scheduleTick ~= -1 then
        EventScheduler.ScheduleEventOnce(scheduleTick, "SpawnAroundPlayer.SpawnAroundPlayerScheduled",
            storage.spawnAroundPlayer.nextId, scheduledDetails)
        return nil
    else
        ---@type UtilityScheduledEvent_CallbackObject
        local eventData = {
            tick = command.tick,
            name = "SpawnAroundPlayer.SpawnAroundPlayerScheduled",
            instanceId = storage.spawnAroundPlayer.nextId,
            data = scheduledDetails
        }
        return SpawnAroundPlayer.SpawnAroundPlayerScheduled(eventData)
    end
end

---@param eventData UtilityScheduledEvent_CallbackObject
---@return LuaEntity[]|nil createdEntities
SpawnAroundPlayer.SpawnAroundPlayerScheduled = function(eventData)
    local data = eventData.data ---@type SpawnAroundPlayer_ScheduledDetails

    local targetPlayer = game.get_player(data.target)
    if targetPlayer == nil then
        CommandsUtils.LogPrintWarning(CommandName, nil, "Target player has been deleted since the command was run.", nil)
        return nil
    end
    local surface, followsLeft = targetPlayer.physical_surface, 0
    -- Calculate the target position.
    local targetPos = data.targetPosition or targetPlayer.physical_position
    if data.targetOffset ~= nil then
        targetPos.x = targetPos.x + data.targetOffset.x
        targetPos.y = targetPos.y + data.targetOffset.y
    end

    -- Check and generate the creation function object. Can't be transferred from before as it may sit in `global`.
    local entityTypeDetails
    if data.entityTypeName ~= EntityTypeNames.custom then
        -- Lookup the predefined EntityTypeDetails.
        entityTypeDetails = SpawnAroundPlayer.GetBuiltinEntityTypeDetails(data.entityTypeName)

        -- Check the expected prototypes are present and roughly the right details.
        if not entityTypeDetails.ValidateEntityPrototypes(nil) then
            return nil
        end
    else
        local customEntityPrototype = prototypes.entity[data.customEntityName --[[@as string]] ]
        if customEntityPrototype == nil then
            CommandsUtils.LogPrintError(CommandName, "customEntityName",
                "entity '" .. data.customEntityName .. "' wasn't valid at run time", nil)
            return nil
        end
        local customEntityPrototype_type = customEntityPrototype.type
        if customEntityPrototype_type == "fire" then
            entityTypeDetails = SpawnAroundPlayer.GenerateFireEntityTypeDetails(data.customEntityName)
        elseif customEntityPrototype_type == "combat-robot" then
            entityTypeDetails = SpawnAroundPlayer.GenerateCombatBotEntityTypeDetails(data.customEntityName)
        elseif customEntityPrototype_type == "ammo-turret" or customEntityPrototype_type == "artillery-turret" then
            if data.customSecondaryDetail ~= nil then
                local ammoItemPrototype = prototypes.item[data.customSecondaryDetail --[[@as string]] ]
                if ammoItemPrototype == nil then
                    CommandsUtils.LogPrintError(CommandName, "customSecondaryDetail", "item '" ..
                        data.customSecondaryDetail .. "' wasn't a valid item type at run time", nil)
                    return nil
                end
                local ammoItemPrototype_type = ammoItemPrototype.type
                if ammoItemPrototype_type ~= 'ammo' then
                    CommandsUtils.LogPrintError(CommandName, "customSecondaryDetail",
                        "item '" .. data.customSecondaryDetail ..
                            "' wasn't an ammo item type at run time, instead it was a type: " ..
                            tostring(ammoItemPrototype_type), nil)
                    return nil
                end
            end
            entityTypeDetails = SpawnAroundPlayer.GenerateAmmoFiringTurretEntityTypeDetails(data.customEntityName,
                data.customSecondaryDetail)
        elseif customEntityPrototype_type == "fluid-turret" then
            if data.customSecondaryDetail ~= nil then
                local ammoFluidPrototype = prototypes.fluid[data.customSecondaryDetail --[[@as string]] ]
                if ammoFluidPrototype == nil then
                    CommandsUtils.LogPrintError(CommandName, "customSecondaryDetail", "fluid '" ..
                        data.customSecondaryDetail .. "' wasn't a valid fluid at run time", nil)
                    return nil
                end
            end
            entityTypeDetails = SpawnAroundPlayer.GenerateFluidFiringTurretEntityTypeDetails(data.customEntityName,
                data.customSecondaryDetail)
        else
            entityTypeDetails = SpawnAroundPlayer.GenerateStandardTileEntityTypeDetails(data.customEntityName,
                customEntityPrototype_type)
        end
    end

    if data.followPlayer and entityTypeDetails.GetPlayersMaxBotFollowers ~= nil then
        followsLeft = entityTypeDetails.GetPlayersMaxBotFollowers(targetPlayer)
    end
    local force
    if data.forceString ~= nil then
        force = game.forces[data.forceString --[[@as string # Filtered nil out.]] ]
    else
        force = entityTypeDetails.GetDefaultForce(targetPlayer)
    end

    local createdEntities = {} ---@type LuaEntity[]
    if data.quantity ~= nil then
        local placed, targetPlaced, attempts, maxAttempts = 0, data.quantity, 0, data.quantity * 5
        while placed < targetPlaced do
            local position = PositionUtils.RandomLocationInRadius(targetPos, data.radiusMax, data.radiusMin)
            local entityName = entityTypeDetails.GetEntityName(surface, position)
            if entityName ~= nil then
                local entityAlignedPosition ---@type MapPosition|nil # While initially always set, it can be unset during its processing.
                entityAlignedPosition = entityTypeDetails.GetEntityAlignedPosition(position)
                if data.existingEntities == "avoid" then
                    entityAlignedPosition = entityTypeDetails.FindValidPlacementPosition(surface, entityName,
                        entityAlignedPosition, SpawnAroundPlayer.quantitySearchRadius)
                end
                if entityAlignedPosition ~= nil then
                    local thisOneFollows = false
                    if followsLeft > 0 then
                        thisOneFollows = true
                        followsLeft = followsLeft - 1
                    end

                    ---@type SpawnAroundPlayer_PlaceEntityDetails
                    local placeEntityDetails = {
                        surface = surface,
                        entityName = entityName,
                        position = entityAlignedPosition,
                        targetPlayer = targetPlayer,
                        ammoCount = data.ammoCount,
                        followPlayer = thisOneFollows,
                        force = force
                    }
                    local createdEntity = entityTypeDetails.PlaceEntity(placeEntityDetails)
                    if createdEntity ~= nil then
                        createdEntities[#createdEntities + 1] = createdEntity
                        if data.removalTimeMinScheduleTick ~= nil then
                            storage.spawnAroundPlayer.removeEntityNextId =
                                storage.spawnAroundPlayer.removeEntityNextId + 1
                            ---@type SpawnAroundPlayer_RemoveEntityScheduled
                            local removeEntityDetails = {
                                entity = createdEntity
                            }
                            EventScheduler.ScheduleEventOnce(
                                math.random(data.removalTimeMinScheduleTick, data.removalTimeMaxScheduleTick) --[[@as uint]] ,
                                "SpawnAroundPlayer.RemoveEntityScheduled", storage.spawnAroundPlayer.removeEntityNextId,
                                removeEntityDetails)
                        end
                    end

                    placed = placed + 1
                end
            end
            attempts = attempts + 1
            if attempts >= maxAttempts then
                break
            end
        end
    elseif data.density ~= nil then
        ---@class SpawnAroundPlayer_GroupPlacementDetails
        local groupPlacementDetails = {
            followsLeft = followsLeft
        } -- Do as table so it can be passed by reference in to functions and updated inline by each.
        local createdEntity1, createdEntity2

        -- Do outer perimeter first. Does a grid across the circle circumference.
        for yOffset = -data.radiusMax, data.radiusMax, entityTypeDetails.gridPlacementSize do
            createdEntity1, createdEntity2 = SpawnAroundPlayer.PlaceEntityAroundPerimeterOnLine(entityTypeDetails, data,
                targetPos, surface, targetPlayer, data.radiusMax, 1, yOffset, groupPlacementDetails, force)
            if createdEntity1 ~= nil then
                createdEntities[#createdEntities + 1] = createdEntity1
            end
            if createdEntity2 ~= nil then
                createdEntities[#createdEntities + 1] = createdEntity1
            end
            createdEntity1, createdEntity2 = SpawnAroundPlayer.PlaceEntityAroundPerimeterOnLine(entityTypeDetails, data,
                targetPos, surface, targetPlayer, data.radiusMax, -1, yOffset, groupPlacementDetails, force)
            if createdEntity1 ~= nil then
                createdEntities[#createdEntities + 1] = createdEntity1
            end
            if createdEntity2 ~= nil then
                createdEntities[#createdEntities + 1] = createdEntity1
            end
        end

        -- Fill inwards from the perimeter up to the required depth (max radius to min radius).
        if data.radiusMin ~= data.radiusMax then
            -- Fill in between circles
            for yOffset = -data.radiusMax, data.radiusMax, entityTypeDetails.gridPlacementSize do
                for xOffset = -data.radiusMax, data.radiusMax, entityTypeDetails.gridPlacementSize do
                    local placementPos = PositionUtils.ApplyOffsetToPosition({
                        x = xOffset,
                        y = yOffset
                    }, targetPos)
                    if PositionUtils.IsPositionWithinCircled(targetPos, data.radiusMax, placementPos) and
                        not PositionUtils.IsPositionWithinCircled(targetPos, data.radiusMin, placementPos) then
                        createdEntity1 = SpawnAroundPlayer.PlaceEntityNearPosition(entityTypeDetails, placementPos,
                            surface, targetPlayer, data, groupPlacementDetails, force)
                        if createdEntity1 ~= nil then
                            createdEntities[#createdEntities + 1] = createdEntity1
                        end
                    end
                end
            end
        end
    end

    return createdEntities
end

--- Place an entity where a straight line crosses the circumference of a circle. When done in a grid of lines across the circumference then the perimeter of the circle will have been filled in.
---@param entityTypeDetails SpawnAroundPlayer_EntityTypeDetails
---@param data SpawnAroundPlayer_ScheduledDetails
---@param targetPos MapPosition
---@param surface LuaSurface
---@param targetPlayer LuaPlayer
---@param radius uint
---@param lineSlope uint
---@param lineYOffset int
---@param groupPlacementDetails SpawnAroundPlayer_GroupPlacementDetails
---@param force LuaForce
---@return LuaEntity|nil createdEntity1
---@return LuaEntity|nil createdEntity2
SpawnAroundPlayer.PlaceEntityAroundPerimeterOnLine = function(entityTypeDetails, data, targetPos, surface, targetPlayer,
    radius, lineSlope, lineYOffset, groupPlacementDetails, force)
    local createdEntity1, createdEntity2
    local crossPos1, crossPos2 = PositionUtils.FindWhereLineCrossesCircle(radius, lineSlope, lineYOffset)
    if crossPos1 ~= nil then
        createdEntity1 = SpawnAroundPlayer.PlaceEntityNearPosition(entityTypeDetails,
            PositionUtils.ApplyOffsetToPosition(crossPos1, targetPos), surface, targetPlayer, data,
            groupPlacementDetails, force)
    end
    if crossPos2 ~= nil then
        createdEntity2 = SpawnAroundPlayer.PlaceEntityNearPosition(entityTypeDetails,
            PositionUtils.ApplyOffsetToPosition(crossPos2, targetPos), surface, targetPlayer, data,
            groupPlacementDetails, force)
    end
    return createdEntity1, createdEntity2
end

--- Place an entity near the targetted position.
---@param entityTypeDetails SpawnAroundPlayer_EntityTypeDetails
---@param position MapPosition
---@param surface LuaSurface
---@param targetPlayer LuaPlayer
---@param data SpawnAroundPlayer_ScheduledDetails
---@param groupPlacementDetails SpawnAroundPlayer_GroupPlacementDetails
---@param force LuaForce
---@return LuaEntity|nil createdEntity
SpawnAroundPlayer.PlaceEntityNearPosition = function(entityTypeDetails, position, surface, targetPlayer, data,
    groupPlacementDetails, force)
    if math.random() > data.density then
        return
    end
    local entityName = entityTypeDetails.GetEntityName(surface, position)
    if entityName == nil then
        -- no tree name is suitable for this tile, likely non land tile
        return
    end
    local entityAlignedPosition = entityTypeDetails.GetEntityAlignedPosition(position) ---@type MapPosition|nil
    if data.existingEntities == "avoid" then
        entityAlignedPosition =
            entityTypeDetails.FindValidPlacementPosition(surface, entityName, entityAlignedPosition --[[@as MapPosition]] ,
                SpawnAroundPlayer.densitySearchRadius)
    end
    local createdEntity
    if entityAlignedPosition ~= nil then
        local thisOneFollows = false
        if groupPlacementDetails.followsLeft > 0 then
            thisOneFollows = true
            groupPlacementDetails.followsLeft = groupPlacementDetails.followsLeft - 1
        end

        ---@type SpawnAroundPlayer_PlaceEntityDetails
        local placeEntityDetails = {
            surface = surface,
            entityName = entityName,
            position = entityAlignedPosition,
            targetPlayer = targetPlayer,
            ammoCount = data.ammoCount,
            followPlayer = thisOneFollows,
            force = force
        }
        createdEntity = entityTypeDetails.PlaceEntity(placeEntityDetails)
        if createdEntity ~= nil and data.removalTimeMinScheduleTick ~= nil then
            storage.spawnAroundPlayer.removeEntityNextId = storage.spawnAroundPlayer.removeEntityNextId + 1
            ---@type SpawnAroundPlayer_RemoveEntityScheduled
            local removeEntityDetails = {
                entity = createdEntity
            }
            EventScheduler.ScheduleEventOnce(math.random(data.removalTimeMinScheduleTick,
                data.removalTimeMaxScheduleTick) --[[@as uint]] , "SpawnAroundPlayer.RemoveEntityScheduled",
                storage.spawnAroundPlayer.removeEntityNextId, removeEntityDetails)
        end
    end
    return createdEntity
end

--- Get the details of a pre-defined entity type. So doesn't support `custom` type.
---@param entityTypeName SpawnAroundPlayer_EntityTypeNames
---@return SpawnAroundPlayer_EntityTypeDetails entityTypeDetails
SpawnAroundPlayer.GetBuiltinEntityTypeDetails = function(entityTypeName)
    if entityTypeName == EntityTypeNames.tree then
        return SpawnAroundPlayer.GenerateRandomTreeTypeDetails()
    elseif entityTypeName == EntityTypeNames.rock then
        return SpawnAroundPlayer.GenerateRandomRockTypeDetails()
    elseif entityTypeName == EntityTypeNames.laserTurret then
        return SpawnAroundPlayer.GenerateStandardTileEntityTypeDetails("laser-turret", "electric-turret")
    elseif entityTypeName == EntityTypeNames.gunTurretRegularAmmo then
        return SpawnAroundPlayer.GenerateAmmoFiringTurretEntityTypeDetails("gun-turret", "firearm-magazine")
    elseif entityTypeName == EntityTypeNames.gunTurretPiercingAmmo then
        return SpawnAroundPlayer.GenerateAmmoFiringTurretEntityTypeDetails("gun-turret", "piercing-rounds-magazine")
    elseif entityTypeName == EntityTypeNames.gunTurretUraniumAmmo then
        return SpawnAroundPlayer.GenerateAmmoFiringTurretEntityTypeDetails("gun-turret", "uranium-rounds-magazine")
    elseif entityTypeName == EntityTypeNames.wall then
        return SpawnAroundPlayer.GenerateStandardTileEntityTypeDetails("stone-wall", "wall")
    elseif entityTypeName == EntityTypeNames.landmine then
        return SpawnAroundPlayer.GenerateStandardTileEntityTypeDetails("land-mine", "land-mine")
    elseif entityTypeName == EntityTypeNames.fire then
        return SpawnAroundPlayer.GenerateFireEntityTypeDetails("fire-flame")
    elseif entityTypeName == EntityTypeNames.defenderBot then
        return SpawnAroundPlayer.GenerateCombatBotEntityTypeDetails("defender")
    elseif entityTypeName == EntityTypeNames.distractorBot then
        return SpawnAroundPlayer.GenerateCombatBotEntityTypeDetails("distractor")
    elseif entityTypeName == EntityTypeNames.destroyerBot then
        return SpawnAroundPlayer.GenerateCombatBotEntityTypeDetails("destroyer")
    else
        error("invalid entityTypeName provided to SpawnAroundPlayer.GetBuiltinEntityTypeDetails().")
    end
end

--- Handler for the random tree option.
---@return SpawnAroundPlayer_EntityTypeDetails
SpawnAroundPlayer.GenerateRandomTreeTypeDetails = function()
    ---@type SpawnAroundPlayer_EntityTypeDetails
    local entityTypeDetails = {
        ValidateEntityPrototypes = function()
            -- The BiomeTrees ensures it only returns valid trees and it will always find something, so nothing needs checking.
            return true
        end,
        GetDefaultForce = function()
            return game.forces["neutral"]
        end,
        GetEntityName = function(surface, position)
            return BiomeTrees.GetBiomeTreeName(surface, position)
        end,
        GetEntityAlignedPosition = function(position)
            return PositionUtils.RandomLocationInRadius(position, SpawnAroundPlayer.offGridPlacementJitter)
        end,
        gridPlacementSize = 1,
        FindValidPlacementPosition = function(surface, entityName, position, searchRadius)
            return surface.find_non_colliding_position(entityName, position, searchRadius, 0.2)
        end,
        ---@param data SpawnAroundPlayer_PlaceEntityDetails
        PlaceEntity = function(data)
            return data.surface.create_entity {
                name = data.entityName,
                position = data.position,
                force = data.force,
                create_build_effect_smoke = false,
                raise_built = true
            }
        end
    }
    return entityTypeDetails
end

--- Handler for the random minable rock option.
---@return SpawnAroundPlayer_EntityTypeDetails
SpawnAroundPlayer.GenerateRandomRockTypeDetails = function()
    ---@type SpawnAroundPlayer_EntityTypeDetails
    local entityTypeDetails = {
        ValidateEntityPrototypes = function(commandString)
            if Common.GetBaseGameEntityByName("rock-huge", "simple-entity", CommandName, commandString) == nil then
                return false
            end
            if Common.GetBaseGameEntityByName("rock-big", "simple-entity", CommandName, commandString) == nil then
                return false
            end
            if Common.GetBaseGameEntityByName("sand-rock-big", "simple-entity", CommandName, commandString) == nil then
                return false
            end
            return true
        end,
        GetDefaultForce = function()
            return game.forces["neutral"]
        end,
        GetEntityName = function()
            local random = math.random()
            if random < 0.2 then
                return "rock-huge"
            elseif random < 0.6 then
                return "rock-big"
            else
                return "sand-rock-big"
            end
        end,
        GetEntityAlignedPosition = function(position)
            return PositionUtils.RandomLocationInRadius(position, SpawnAroundPlayer.offGridPlacementJitter)
        end,
        gridPlacementSize = 2,
        FindValidPlacementPosition = function(surface, entityName, position, searchRadius)
            return surface.find_non_colliding_position(entityName, position, searchRadius, 0.2)
        end,
        ---@param data SpawnAroundPlayer_PlaceEntityDetails
        PlaceEntity = function(data)
            return data.surface.create_entity {
                name = data.entityName,
                position = data.position,
                force = data.force,
                create_build_effect_smoke = false,
                raise_built = true
            }
        end
    }
    return entityTypeDetails
end

--- Handler for the generic combat robot types.
---@param setEntityName string # Prototype entity name
---@return SpawnAroundPlayer_EntityTypeDetails
SpawnAroundPlayer.GenerateCombatBotEntityTypeDetails = function(setEntityName)
    local gridSize, searchOnlyInTileCenter = SpawnAroundPlayer.GetEntityTypeFunctionPlacementDetails(setEntityName)

    ---@type SpawnAroundPlayer_EntityTypeDetails
    local entityTypeDetails = {
        ValidateEntityPrototypes = function(commandString)
            if Common.GetBaseGameEntityByName(setEntityName, "combat-robot", CommandName, commandString) == nil then
                return false
            end
            return true
        end,
        GetDefaultForce = function(targetPlayer)
            return targetPlayer.force --[[@as LuaForce # Sumneko R/W workaround.]]
        end,
        GetEntityName = function()
            return setEntityName
        end,
        GetEntityAlignedPosition = function(position)
            return PositionUtils.RandomLocationInRadius(position, SpawnAroundPlayer.offGridPlacementJitter)
        end,
        gridPlacementSize = gridSize,
        FindValidPlacementPosition = function(surface, entityName, position, searchRadius)
            return surface.find_non_colliding_position(entityName, position, searchRadius, 0.2, searchOnlyInTileCenter)
        end,
        ---@param data SpawnAroundPlayer_PlaceEntityDetails
        PlaceEntity = function(data)
            local target
            if data.followPlayer then
                target = data.targetPlayer.character
            end
            local combatRobot = data.surface.create_entity {
                name = data.entityName,
                position = data.position,
                force = data.force,
                target = target,
                create_build_effect_smoke = false,
                raise_built = true
            }
            -- Set the robots orientation post creation, as setting direction during creation doesn't seem to do anything.
            combatRobot.orientation = math.random() --[[@as RealOrientation]]
            return combatRobot
        end,
        GetPlayersMaxBotFollowers = function(targetPlayer)
            return SpawnAroundPlayer.GetMaxBotFollowerCountForPlayer(targetPlayer)
        end
    }
    return entityTypeDetails
end

--- Handler for the ammo shooting gun and artillery turrets.
---@param turretName string # Prototype entity name
---@param ammoName? string|nil # Prototype item name
---@return SpawnAroundPlayer_EntityTypeDetails
SpawnAroundPlayer.GenerateAmmoFiringTurretEntityTypeDetails = function(turretName, ammoName)
        local gridSize, searchOnlyInTileCenter = SpawnAroundPlayer.GetEntityTypeFunctionPlacementDetails(turretName)

        ---@type SpawnAroundPlayer_EntityTypeDetails
        local entityTypeDetails = {
            ValidateEntityPrototypes = function(commandString)
                if Common.GetBaseGameEntityByName(turretName, {"ammo-turret", "artillery-turret"}, CommandName,
                    commandString) == nil then
                    return false
                end
                if ammoName ~= nil and Common.GetBaseGameItemByName(ammoName, "ammo", CommandName, commandString) == nil then
                    return false
                end
                return true
            end,
            GetDefaultForce = function(targetPlayer)
                return targetPlayer.force --[[@as LuaForce # Sumneko R/W workaround.]]
            end,
            GetEntityName = function()
                return turretName
            end,
            GetEntityAlignedPosition = function(position)
                return PositionUtils.RoundPosition(position, 0)
            end,
            gridPlacementSize = gridSize,
            FindValidPlacementPosition = function(surface, entityName, position, searchRadius)
                return
                    surface.find_non_colliding_position(entityName, position, searchRadius, 1, searchOnlyInTileCenter)
            end,
            ---@param data SpawnAroundPlayer_PlaceEntityDetails
            PlaceEntity = function(data)
                -- Turrets support just build direction reliably.
                local turret = data.surface.create_entity {
                    name = data.entityName,
                    position = data.position,
                    direction = math.random(0, 3) * 2 --[[@as defines.direction]] ,
                    force = data.force,
                    create_build_effect_smoke = false,
                    raise_built = true
                }
                if turret ~= nil and ammoName ~= nil and data.ammoCount ~= nil then
                    turret.insert({
                        name = ammoName,
                        count = data.ammoCount
                    })
                end
                return turret
            end
        }
        return entityTypeDetails
    end

--- Handler for the fluid firing turrets.
---@param turretName string # Prototype entity name
---@param fluidName? string|nil # Prototype item name
---@return SpawnAroundPlayer_EntityTypeDetails
SpawnAroundPlayer.GenerateFluidFiringTurretEntityTypeDetails = function(turretName, fluidName)
        local gridSize, searchOnlyInTileCenter = SpawnAroundPlayer.GetEntityTypeFunctionPlacementDetails(turretName)

        ---@type SpawnAroundPlayer_EntityTypeDetails
        local entityTypeDetails = {
            ValidateEntityPrototypes = function(commandString)
                if Common.GetBaseGameEntityByName(turretName, {"fluid-turret"}, CommandName, commandString) == nil then
                    return false
                end
                if fluidName ~= nil and Common.GetBaseGameFluidByName(fluidName, CommandName, commandString) == nil then
                    return false
                end
                return true
            end,
            GetDefaultForce = function(targetPlayer)
                return targetPlayer.force --[[@as LuaForce # Sumneko R/W workaround.]]
            end,
            GetEntityName = function()
                return turretName
            end,
            GetEntityAlignedPosition = function(position)
                return PositionUtils.RoundPosition(position, 0)
            end,
            gridPlacementSize = gridSize,
            FindValidPlacementPosition = function(surface, entityName, position, searchRadius)
                return
                    surface.find_non_colliding_position(entityName, position, searchRadius, 1, searchOnlyInTileCenter)
            end,
            ---@param data SpawnAroundPlayer_PlaceEntityDetails
            PlaceEntity = function(data)
                -- Turrets support just build direction reliably.
                local turret = data.surface.create_entity {
                    name = data.entityName,
                    position = data.position,
                    direction = math.random(0, 3) * 2 --[[@as defines.direction]] ,
                    force = data.force,
                    create_build_effect_smoke = false,
                    raise_built = true
                }
                if turret ~= nil and fluidName ~= nil and data.ammoCount ~= nil then
                    turret.insert_fluid({
                        name = fluidName,
                        amount = data.ammoCount
                    })
                end
                return turret
            end
        }
        return entityTypeDetails
    end

--- Handler for the generic fire type entities.
---@param setEntityName string # Prototype item name
---@return SpawnAroundPlayer_EntityTypeDetails
SpawnAroundPlayer.GenerateFireEntityTypeDetails = function(setEntityName)
    local gridSize = SpawnAroundPlayer.GetEntityTypeFunctionPlacementDetails(setEntityName)

    ---@type SpawnAroundPlayer_EntityTypeDetails
    local entityTypeDetails = {
        ValidateEntityPrototypes = function(commandString)
            if Common.GetBaseGameEntityByName(setEntityName, "fire", CommandName, commandString) == nil then
                return false
            end
            return true
        end,
        GetDefaultForce = function()
            return storage.Forces.muppet_streamer_v2_enemy
        end,
        GetEntityName = function()
            return setEntityName
        end,
        GetEntityAlignedPosition = function(position)
            return PositionUtils.RandomLocationInRadius(position, SpawnAroundPlayer.offGridPlacementJitter)
        end,
        gridPlacementSize = gridSize,
        FindValidPlacementPosition = function(surface, entityName, position, searchRadius)
            return surface.find_non_colliding_position(entityName, position, searchRadius, 0.2, false)
        end,
        ---@param data SpawnAroundPlayer_PlaceEntityDetails
        PlaceEntity = function(data)
            ---@type uint8|nil, boolean
            local flameCount, valueWasClamped
            if data.ammoCount ~= nil then
                flameCount, valueWasClamped = MathUtils.ClampToUInt8(data.ammoCount, 0, 250)
                if valueWasClamped then
                    CommandsUtils.LogPrintWarning(CommandName, "ammoCount",
                        "value was above the maximum of 250 for a fire type entity, so clamped to 250", nil)
                end
            end
            return data.surface.create_entity {
                name = data.entityName,
                position = data.position,
                force = data.force,
                initial_ground_flame_count = flameCount,
                create_build_effect_smoke = false,
                raise_built = true
            }
        end
    }
    return entityTypeDetails
end

--- Handler for the generic standard entities which have a placement size of 1 per tile area max (not dense like trees).
---@param entityName string
---@param entityType string
---@return SpawnAroundPlayer_EntityTypeDetails
SpawnAroundPlayer.GenerateStandardTileEntityTypeDetails = function(entityName, entityType)
    local gridSize, searchOnlyInTileCenter, placeInCenterOfTile =
        SpawnAroundPlayer.GetEntityTypeFunctionPlacementDetails(entityName)

    ---@type SpawnAroundPlayer_EntityTypeDetails
    local entityTypeDetails = {
        ValidateEntityPrototypes = function(commandString)
            if Common.GetBaseGameEntityByName(entityName, entityType, CommandName, commandString) == nil then
                return false
            end
            return true
        end,
        GetDefaultForce = function(targetPlayer)
            return targetPlayer.force --[[@as LuaForce # Sumneko R/W workaround.]]
        end,
        GetEntityName = function()
            return entityName
        end,
        gridPlacementSize = gridSize,
        FindValidPlacementPosition = function(surface, entityName, position, searchRadius)
            return surface.find_non_colliding_position(entityName, position, searchRadius, 1, searchOnlyInTileCenter)
        end,
        ---@param data SpawnAroundPlayer_PlaceEntityDetails
        PlaceEntity = function(data)
            -- Try and set the build direction and also its orientation post building. Some entities will respond to one or the other, occasionally both and sometimes none. But none should error or fail from this and is technically just a wasted API call.
            local createdEntity = data.surface.create_entity {
                name = data.entityName,
                position = data.position,
                direction = math.random(0, 3) * 2 --[[@as defines.direction]] ,
                force = data.force,
                create_build_effect_smoke = false,
                raise_built = true
            }
            createdEntity.orientation = math.random() --[[@as RealOrientation]]
            return createdEntity
        end,
    }

    if placeInCenterOfTile then
        entityTypeDetails.GetEntityAlignedPosition = function(position)
            return PositionUtils.RoundPosition(position, 0)
        end
    else
        entityTypeDetails.GetEntityAlignedPosition = function(position)
            return PositionUtils.RandomLocationInRadius(position, SpawnAroundPlayer.offGridPlacementJitter)
        end
    end

    return entityTypeDetails
end

--- Gets details about an entity's placement attributes. Used when making the EntityTypeDetails functions object.
---
--- Often only some of the results will be used by the calling function as many entity types have hard coded results, i.e. fire is always placed off-grid.
---@param entityName string
---@return uint gridSize
---@return boolean searchOnlyInTileCenter
---@return boolean placeInCenterOfTile
SpawnAroundPlayer.GetEntityTypeFunctionPlacementDetails = function(entityName)
    local entityPrototype = prototypes.entity[entityName]

    local collisionBox = entityPrototype.collision_box
    local gridSize = math.ceil(math.max((collisionBox.right_bottom.x - collisionBox.left_top.x),
        (collisionBox.right_bottom.x - collisionBox.left_top.x), 1)) --[[@as uint # Min of gridSize 1 and its rounded up to an integer.]]

    local searchOnlyInTileCenter
    if gridSize % 2 == 0 then
        -- grid size is a multiple of 2 (even number).
        searchOnlyInTileCenter = false
    else
        -- grid size is an odd number.
        searchOnlyInTileCenter = true
    end

    local placeInCenterOfTile
    if entityPrototype.flags["placeable-off-grid"] then
        placeInCenterOfTile = false
    else
        placeInCenterOfTile = true
    end

    return gridSize, searchOnlyInTileCenter, placeInCenterOfTile
end

---Get how many bots can be set to follow the player currently.
---@param targetPlayer LuaPlayer
---@return uint
SpawnAroundPlayer.GetMaxBotFollowerCountForPlayer = function(targetPlayer)
    if targetPlayer.character == nil then
        return 0
    end
    local max = targetPlayer.character_maximum_following_robot_count_bonus +
                    targetPlayer.force.maximum_following_robot_count
    local current = #targetPlayer.following_robots --[[@as uint # The game doesn't allow more than a uint max following robots, so the count can't be above a uint.]]
    return max - current
end

--- Called when an entities time has run out and it should be removed if it still exists.
---@param eventData UtilityScheduledEvent_CallbackObject
SpawnAroundPlayer.RemoveEntityScheduled = function(eventData)
    local data = eventData.data ---@type SpawnAroundPlayer_RemoveEntityScheduled
    local entity = data.entity
    if entity.valid then
        entity.destroy({
            raise_destroy = true
        })
    end
end

return SpawnAroundPlayer
