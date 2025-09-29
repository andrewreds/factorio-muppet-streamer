--[[
    All data stage prototype related utils functions.

    These were started to be documented, but it was just too painful and so it was stopped. As they are all data stage there are no Sumneko classes pre-defined for anything.
    Some of these functions include tables that take a bunch of numbered fields. If this code is used in new projects these should really be reviewed and replaced with named fields for ease of us. Only used in legacy mods at present so not being redone at present.
]]
--

-- Sumneko should skip checking this file for certain checks at present.
---@diagnostic disable: no-unknown

local PrototypeUtils = {} ---@class Utility_PrototypeUtils
local TableUtils = require("utility.helper-utils.table-utils")
local math_ceil = math.ceil

--- This is a temporary class until factorio-api gets updated to include a full RotatedSprite class.
---@class EmptyRotatedSprite
---@field direction_count uint
---@field filename string
---@field width uint
---@field height uint
---@field repeat_count uint

--- Returns an empty rotated sprite prototype object. For use in data stage.
---@param repeat_count? int|nil # Defaults to 1 if not provided
---@return EmptyRotatedSprite
PrototypeUtils.MakeEmptyRotatedSpritePrototype_DataStage = function(repeat_count)
    return {
        direction_count = 1,
        filename = "__core__/graphics/empty.png",
        width = 1,
        height = 1,
        repeat_count = repeat_count or 1
    }
end

--- Returns the value of the requested attributeName from the recipe for the recipeCodeType "cost" if available, otherwise the inline/ingredients value is returned.
---@param recipe data.RecipePrototype
---@param attributeName string
---@param recipeCostType? 'ingredients'|'normal'|'expensive'|nil # Defaults to the 'ingredients' if not provided. The 'ingredients' option will return any inline value first, then the value from the ingredients field.
---@param defaultValue? any # The default value to return if nothing is found in the hierarchy of "costs" checked.
---@return any|nil value
PrototypeUtils.GetRecipeAttribute = function(recipe, attributeName, recipeCostType, defaultValue)
    recipeCostType = recipeCostType or "ingredients"
    if recipeCostType == "ingredients" and recipe[attributeName] ~= nil then
        return recipe[attributeName]
    elseif recipe[recipeCostType] ~= nil and recipe[recipeCostType][attributeName] ~= nil then
        return recipe[recipeCostType][attributeName]
    end

    if recipe[attributeName] ~= nil then
        return recipe[attributeName]
    elseif recipe["normal"] ~= nil and recipe["normal"][attributeName] ~= nil then
        return recipe["normal"][attributeName]
    elseif recipe["expensive"] ~= nil and recipe["expensive"][attributeName] ~= nil then
        return recipe["expensive"][attributeName]
    end

    return defaultValue -- may well be nil
end

PrototypeUtils.DoesRecipeResultsIncludeItemName = function(recipePrototype, itemName)
    for _, recipeBase in pairs({ recipePrototype, recipePrototype.normal, recipePrototype.expensive }) do
        if recipeBase ~= nil then
            if recipeBase.result ~= nil and recipeBase.result == itemName then
                return true
            elseif recipeBase.results ~= nil and #TableUtils.GetTableKeyWithInnerKeyValue(recipeBase.results, "name", itemName) > 0 then
                return true
            end
        end
    end
    return false
end

--[[
    From the provided technology list remove all provided recipes from being unlocked that create an item that can place a given entity prototype.
    Returns a table of the technologies affected or a blank table if no technologies are affected.
]]
PrototypeUtils.RemoveEntitiesRecipesFromTechnologies = function(entityPrototype, recipes, technologies)
    local technologiesChanged = {}
    local placedByItemName
    if entityPrototype.minable ~= nil and entityPrototype.minable.result ~= nil then
        placedByItemName = entityPrototype.minable.result
    else
        return technologiesChanged
    end
    for _, recipePrototype in pairs(recipes) do
        if PrototypeUtils.DoesRecipeResultsIncludeItemName(recipePrototype, placedByItemName) then
            recipePrototype.enabled = false
            for _, technologyPrototype in pairs(technologies) do
                if technologyPrototype.effects ~= nil then
                    for effectIndex, effect in pairs(technologyPrototype.effects) do
                        if effect.type == "unlock-recipe" and effect.recipe ~= nil and effect.recipe == recipePrototype.name then
                            table.remove(technologyPrototype.effects, effectIndex)
                            table.insert(technologiesChanged, technologyPrototype)
                        end
                    end
                end
            end
        end
    end
    return technologiesChanged
end

--- Doesn't handle mipmaps at all presently. Also ignores any of the extra data in an icons table of "Types/IconData". Think this should just duplicate the target icons table entry.
---@param entityToClone table # Any entity prototype.
---@param newEntityName string
---@param subgroup string
---@param collisionMask CollisionMask
---@return table # A simple entity prototype.
PrototypeUtils.CreatePlacementTestEntityPrototype = function(entityToClone, newEntityName, subgroup, collisionMask)
    local clonedIcon = entityToClone.icon
    local clonedIconSize = entityToClone.icon_size
    if clonedIcon == nil then
        clonedIcon = entityToClone.icons[1].icon
        clonedIconSize = entityToClone.icons[1].icon_size
    end
    return {
        type = "simple-entity",
        name = newEntityName,
        subgroup = subgroup,
        order = "zzz",
        icons = {
            {
                icon = clonedIcon,
                icon_size = clonedIconSize
            },
            {
                icon = "__core__/graphics/cancel.png",
                icon_size = 64,
                scale = (clonedIconSize / 64) * 0.5
            }
        },
        flags = entityToClone.flags,
        selection_box = entityToClone.selection_box,
        collision_box = entityToClone.collision_box,
        collision_mask = collisionMask,
        picture = {
            filename = "__core__/graphics/cancel.png",
            height = 64,
            width = 64
        }
    }
end

PrototypeUtils.CreateLandPlacementTestEntityPrototype = function(entityToClone, newEntityName, subgroup)
    subgroup = subgroup or "other"
    return PrototypeUtils.CreatePlacementTestEntityPrototype(entityToClone, newEntityName, subgroup, {layers = { "water-tile", "colliding-with-tiles-only" }})
end

PrototypeUtils.CreateWaterPlacementTestEntityPrototype = function(entityToClone, newEntityName, subgroup)
    subgroup = subgroup or "other"
    return PrototypeUtils.CreatePlacementTestEntityPrototype(entityToClone, newEntityName, subgroup, {layers = { "ground-tile", "colliding-with-tiles-only" }})
end

return PrototypeUtils
