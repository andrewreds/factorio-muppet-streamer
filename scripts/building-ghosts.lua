local BuildingGhosts = {} ---@class BuildingGhosts
local Events = require("utility.manager-libraries.events")
local MathUtils = require("utility.helper-utils.math-utils")

BuildingGhosts.CreateGlobals = function()
    storage.buildingGhosts = storage.buildingGhosts or {} ---@class BuildingGhosts_Global
    storage.buildingGhosts.enabled = storage.buildingGhosts.enabled or false ---@type boolean
end

BuildingGhosts.OnStartup = function()
    -- Track changes in setting from last known and apply changes as required.
    if not storage.buildingGhosts.enabled and settings.startup["muppet_streamer_v2-enable_building_ghosts"].value then
        storage.buildingGhosts.enabled = true
        for _, force in pairs(game.forces) do
            BuildingGhosts.EnableForForce(force)
        end
    elseif storage.buildingGhosts.enabled and not settings.startup["muppet_streamer_v2-enable_building_ghosts"].value then
        storage.buildingGhosts.enabled = false
        for _, force in pairs(game.forces) do
            BuildingGhosts.DisableForForce(force)
        end
    end
end

BuildingGhosts.OnLoad = function()
    Events.RegisterHandlerEvent(defines.events.on_force_reset, "BuildingGhosts.OnForceChanged", BuildingGhosts.OnForceChanged)
    Events.RegisterHandlerEvent(defines.events.on_force_created, "BuildingGhosts.OnForceChanged", BuildingGhosts.OnForceChanged)
end

--- Called when a force is reset or created by a mod/editor and we need to re-apply the ghost setting if enabled.
---@param event EventData.on_force_reset|EventData.on_force_created
BuildingGhosts.OnForceChanged = function(event)
    if settings.startup["muppet_streamer_v2-enable_building_ghosts"].value then
        BuildingGhosts.EnableForForce(event.force)
    end
end

--- For specific force enable building ghosts on death. This will preserve any vanilla researched state as our value is greater than vanilla's value.
---@param force LuaForce
BuildingGhosts.EnableForForce = function(force)
    force.create_ghost_on_entity_death = true
end

--- For specific force disable building ghosts on death. This will preserve any vanilla researched state as our value is greater than vanilla's value.
---@param force LuaForce
BuildingGhosts.DisableForForce = function(force)
    force.create_ghost_on_entity_death = false
end

return BuildingGhosts
