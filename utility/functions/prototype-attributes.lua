-- Returns and caches prototype attributes as requested to save future API calls. Values stored in Lua global variable and populated as requested, as doesn't need persisting. Gets auto refreshed on game load and thus accounts for any change of attributes from mods.
local PrototypeAttributes = {} ---@class Utility_PrototypeAttributes

MOD = MOD or {} ---@class MOD
MOD.UTILITYPrototypeAttributes = MOD.UTILITYPrototypeAttributes or {} ---@type UtilityPrototypeAttributes_CachedTypes
MOD.Interfaces = MOD.Interfaces or {} ---@class MOD_InternalInterfaces
MOD.Interfaces.Commands = MOD.Interfaces.Commands or {} ---@class MOD_InternalInterfaces_Commands

--- Returns the request attribute of a prototype.
---
--- Obtains from the Lua global variable caches if present, otherwise obtains the result and caches it before returning it.
---@param prototypeType UtilityPrototypeAttributes_PrototypeType
---@param prototypeName string
---@param attributeName string
---@return any # attribute value, can include nil.
PrototypeAttributes.GetAttribute = function(prototypeType, prototypeName, attributeName)
    local utilityPrototypeAttributes = MOD.UTILITYPrototypeAttributes

    local typeCache
    if utilityPrototypeAttributes[prototypeType] ~= nil then
        typeCache = utilityPrototypeAttributes[prototypeType]
    else
        utilityPrototypeAttributes[prototypeType] = {}
        typeCache = utilityPrototypeAttributes[prototypeType]
    end

    local prototypeCache
    if typeCache[prototypeName] ~= nil then
        prototypeCache = typeCache[prototypeName]
    else
        typeCache[prototypeName] = {}
        prototypeCache = typeCache[prototypeName]
    end

    local attributeCache = prototypeCache[attributeName]
    if attributeCache ~= nil then
        return attributeCache.value
    else
        local resultPrototype
        if prototypeType == PrototypeAttributes.PrototypeTypes.entity then
            resultPrototype = prototypes.entity[prototypeName]
        elseif prototypeType == PrototypeAttributes.PrototypeTypes.item then
            resultPrototype = prototypes.item[prototypeName]
        elseif prototypeType == PrototypeAttributes.PrototypeTypes.fluid then
            resultPrototype = prototypes.fluid[prototypeName]
        elseif prototypeType == PrototypeAttributes.PrototypeTypes.tile then
            resultPrototype = prototypes.tile[prototypeName]
        elseif prototypeType == PrototypeAttributes.PrototypeTypes.equipment then
            resultPrototype = prototypes.equipment[prototypeName]
        elseif prototypeType == PrototypeAttributes.PrototypeTypes.recipe then
            resultPrototype = prototypes.recipe[prototypeName]
        elseif prototypeType == PrototypeAttributes.PrototypeTypes.technology then
            resultPrototype = prototypes.technology[prototypeName]
        end
        local resultValue = resultPrototype[attributeName] ---@type any
        prototypeCache[attributeName] = { value = resultValue }
        return resultValue
    end
end

---@enum UtilityPrototypeAttributes_PrototypeType # not all prototype types are supported at present as not needed before.
PrototypeAttributes.PrototypeTypes = {
    entity = "entity",
    item = "item",
    fluid = "fluid",
    tile = "tile",
    equipment = "equipment",
    recipe = "recipe",
    technology = "technology"
}

---@alias UtilityPrototypeAttributes_CachedTypes table<string, UtilityPrototypeAttributes_CachedPrototypes> # a table of each prototype type name (key) and the prototypes it has of that type.
---@alias UtilityPrototypeAttributes_CachedPrototypes table<string, UtilityPrototypeAttributes_CachedAttributes> # a table of each prototype name (key) and the attributes if has of that prototype.
---@alias UtilityPrototypeAttributes_CachedAttributes table<string, UtilityPrototypeAttributes_CachedAttribute> # a table of each attribute name (key) and their cached values stored in the container.
---@class UtilityPrototypeAttributes_CachedAttribute # Container for the cached value. If it exists the value is cached. An empty table signifies that the cached value is nil.
---@field value any # the value of the attribute. May be nil if that's the attributes real value.

return PrototypeAttributes
