--[[
    Used to get tile (biome) appropriate trees, rather than just select any old tree. Means they will generally fit in to the map better, although vanilla forest types don't always fully match the biome they are in.
    Will only nicely handle vanilla and Alien Biomes tiles and trees, modded tiles will get a random tree if they are a land-ish type tile.
    Usage:
        - Require the file at usage locations.
        - Call the BiomeTrees.OnStartup() for script.on_init and script.on_configuration_changed. This will load the meta tables of the mod fresh from the current tiles and trees. This is needed as on large mods it may take a few moments and we don't want to lag the game on first usage.
        - Call the desired public functions when needed. These are the ones at the top of the file without an "_" at the start of the function name.
    Supports specifically coded modded trees with meta data. If a tree has tile restrictions this is used for selection after temp and water, otherwise the tags of tile and tree are checked. This logic comes from supporting alien biomes.
]]
--
-- CODE NOTES: Some of these objects aren't terribly well typed or even named fields. This is a legacy code and doesn't really ever get touched so left as minimal typing for time being.

local MathUtils = require("utility.helper-utils.math-utils")
local TableUtils = require("utility.helper-utils.table-utils")
local LoggingUtils = require("utility.helper-utils.logging-utils")

-- At present these sub files aren't typed at all.
local BaseGameData = require("utility.functions.biome-trees-data.base-game")
local AlienBiomesData = require("utility.functions.biome-trees-data.alien-biomes")

local BiomeTrees = {} ---@class Utility_BiomeTrees

--- Debug testing/logging options. Al should be false in releases.
local LogNonPositives = false
local LogPositives = false
local LogData = false
local LogTags = false -- @Enable with other logging options to include details about tag checking.

---@class UtilityBiomeTrees_EnvironmentData
---@field moistureRangeAttributeNames UtilityBiomeTrees_MoistureRangeAttributeNames
---@field tileTemperatureCalculationSettings UtilityBiomeTrees_TileTemperatureCalculationSettings
---@field tileData UtilityBiomeTrees_TilesDetails
---@field treesMetaData UtilityBiomeTrees_TreesMetaData
---@field deadTreeNames string[]
---@field randomTreeLastResort string

---@class UtilityBiomeTrees_MoistureRangeAttributeNames
---@field optimal string
---@field range string

---@class UtilityBiomeTrees_TileTemperatureCalculationSettings
---@field scaleMultiplier? double|nil
---@field min? double|nil
---@field max? double|nil

---@alias UtilityBiomeTrees_TreesMetaData table<string, UtilityBiomeTrees_TreeMetaData> # Key'd by tree name.
---@class UtilityBiomeTrees_TreeMetaData
---@field [1] table<string, string> # Tag color string as key and value.
---@field [2] table<string, string> # The names of tiles that the tree can only go on, tile name is the key and value in table.

---@alias UtilityBiomeTrees_TilesDetails table<string, UtilityBiomeTrees_TileDetails> # Key'd by tile name.

---@class UtilityBiomeTrees_TileDetails
---@field name string
---@field type UtilityBiomeTrees_TileType
---@field tempRanges UtilityBiomeTrees_valueRange[]
---@field moistureRanges UtilityBiomeTrees_valueRange[]
---@field tag string|nil

---@class UtilityBiomeTrees_RawTileData
---@field [1] UtilityBiomeTrees_TileType
---@field [2] UtilityBiomeTrees_valueRange[]|nil # tempRanges
---@field [3] UtilityBiomeTrees_valueRange[]|nil # moistureRanges
---@field [4] string|nil # tag

---@class UtilityBiomeTrees_valueRange
---@field [1] double # Min in this range.
---@field [2] double # Max in this range.

---@class UtilityBiomeTrees_TreeDetails
---@field name string
---@field tempRange UtilityBiomeTrees_valueRange
---@field moistureRange UtilityBiomeTrees_valueRange
---@field probability double
---@field tags table<string, string>|nil # Tag color string as key and value.
---@field exclusivelyOnNamedTiles table<string, string>|nil # The names of tiles that the tree can only go on, tile name is the key and value in table.

---@class UtilityBiomeTrees_suitableTree
---@field chanceStart double
---@field chanceEnd double
---@field tree UtilityBiomeTrees_TreeDetails

---@enum UtilityBiomeTrees_TileType
local TileType = {
    ["allow-trees"] = "allow-trees",
    ["water"] = "water",
    ["no-trees"] = "no-trees"
}

----------------------------------------------------------------------------------
--                          PUBLIC FUNCTIONS
----------------------------------------------------------------------------------

--- Called from Factorio script.on_init and script.on_configuration_changed events to parse over the tile and trees and make the lookup tables we'll need at run time.
BiomeTrees.OnStartup = function()
    -- Always recreate on game startup/config changed to handle any mod changed trees, tiles, etc.
    storage.UTILITYBIOMETREES = {}
    storage.UTILITYBIOMETREES.treeNoiseMapping = BiomeTrees._GetTreeNoiseMapping()
    storage.UTILITYBIOMETREES.treeNoiseFuncions = {}
    for noiseFunction, _ in pairs(storage.UTILITYBIOMETREES.treeNoiseMapping) do
        table.insert(storage.UTILITYBIOMETREES.treeNoiseFuncions, noiseFunction)
    end
    if LogData then
        LoggingUtils.ModLog(serpent.block(storage.UTILITYBIOMETREES.treeNoiseMapping), false)
        LoggingUtils.ModLog(serpent.block(storage.UTILITYBIOMETREES.treeNoiseFuncions), false)
    end
end

--- Get a biome appropriate tree's name or nil if one isn't allowed there.
---@param surface LuaSurface
---@param position MapPosition
---@return string|nil treeName
BiomeTrees.GetBiomeTreeName = function(surface, position)
    -- Returns the tree name or nil if tile isn't land type
    local tile = surface.get_tile(position --[[@as TilePosition # handled equally by Factorio in this API function.]])
    if tile == nil or tile.collides_with("player") then
        -- Is a non-land tile
        return nil
    end

    local largestValue = nil
    local largestNoiseName = nil
    for noiseName, values in pairs(surface.calculate_tile_properties(storage.UTILITYBIOMETREES.treeNoiseFuncions, {position})) do
        if largestValue == nil or values[1] > largestValue then
            largestValue = values[1]
            largestNoiseName = noiseName
         end
    end
    if largestNoiseName == nil then
        -- There is no noise function?
        return nil
    end
    
    -- Pick a random tree that uses the winning noise function
    local chosenNoiseList = storage.UTILITYBIOMETREES.treeNoiseMapping[largestNoiseName]
    return chosenNoiseList[math.random(#chosenNoiseList)]
end

--- Add a biome appropriate tree to a spare space near the target position.
---@param surface LuaSurface
---@param position MapPosition
---@param distance double
---@return LuaEntity|nil createdTree
BiomeTrees.AddBiomeTreeNearPosition = function(surface, position, distance)
    -- Returns the tree entity if one found and created or nil
    local treeType = BiomeTrees.GetBiomeTreeName(surface, position)
    if treeType == nil then
        LoggingUtils.ModLog("no tree was found", true, LogNonPositives)
        return nil
    end
    local newPosition = surface.find_non_colliding_position(treeType, position, distance, 0.2)
    if newPosition == nil then
        LoggingUtils.ModLog("No position for new tree found", true, LogNonPositives)
        return nil
    end
    local newTree = surface.create_entity { name = treeType, position = newPosition, force = "neutral", raise_built = true, create_build_effect_smoke = false }
    if newTree == nil then
        LoggingUtils.LogPrintError("Failed to create tree at found position", LogPositives or LogNonPositives)
        return nil
    end
    LoggingUtils.ModLog("tree added successfully, type: " .. treeType .. "    position: " .. newPosition.x .. ", " .. newPosition.y, true, LogPositives)
    return newTree
end


----------------------------------------------------------------------------------
--                          PRIVATE FUNCTIONS
----------------------------------------------------------------------------------


--- Gets the runtime tree data from the prototype data.
BiomeTrees._GetTreeNoiseMapping = function()
    local treeNoiseMapping = {}
    local treeEntities = prototypes.get_entity_filtered({ { filter = "type", type = "tree" }, { mode = "and", filter = "autoplace" } })
    for _, prototype in pairs(treeEntities) do
        if LogData then
            LoggingUtils.ModLog(prototype.name, false)
        end
        local noiseFunction = prototype.autoplace_specification.probability_expression
        -- TODO: What about autoplace_specification.tile_restriction?
        if treeNoiseMapping[noiseFunction] == nil then
            treeNoiseMapping[noiseFunction] = {}
        end
        table.insert(treeNoiseMapping[noiseFunction], prototype.name)
    end
    return treeNoiseMapping
end

return BiomeTrees
