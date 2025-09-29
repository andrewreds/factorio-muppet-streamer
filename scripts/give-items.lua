local GiveItems = {} ---@class GiveItems
local PlayerWeapon = require("utility.functions.player-weapon")
local CommandsUtils = require("utility.helper-utils.commands-utils")
local EventScheduler = require("utility.manager-libraries.event-scheduler")
local Common = require("scripts.common")
local MathUtils = require("utility.helper-utils.math-utils")

---@class GiveItems_GiveWeaponAmmoScheduled
---@field target string # Target player's name.
---@field ammoPrototype? LuaItemPrototype|nil # Nil if no ammo is being given.
---@field ammoCount? uint|nil # Nil if no ammo is being given.
---@field weaponPrototype? LuaItemPrototype|nil
---@field forceWeaponToSlot boolean
---@field selectWeapon boolean
---@field suppressMessages boolean

local CommandName = "muppet_streamer_v2_give_player_weapon_ammo"

GiveItems.CreateGlobals = function()
    storage.giveItems = storage.giveItems or {} ---@class GiveItems_Global
    storage.giveItems.nextId = storage.giveItems.nextId or 0 ---@type uint
end

GiveItems.OnLoad = function()
    CommandsUtils.Register("muppet_streamer_v2_give_player_weapon_ammo",
        {"api-description.muppet_streamer_v2_give_player_weapon_ammo"}, GiveItems.GivePlayerWeaponAmmoCommand, true)
    EventScheduler.RegisterScheduledEventType("GiveItems.GiveWeaponAmmoScheduled", GiveItems.GiveWeaponAmmoScheduled)
    MOD.Interfaces.Commands.GiveItems = GiveItems.GivePlayerWeaponAmmoCommand
end

---@param command CustomCommandData
GiveItems.GivePlayerWeaponAmmoCommand = function(command)
    local commandData = CommandsUtils.GetSettingsTableFromCommandParameterString(command.parameter, true, CommandName,
        {"delay", "target", "weaponType", "forceWeaponToSlot", "selectWeapon", "ammoType", "ammoCount",
         "suppressMessages"})
    if commandData == nil then
        return
    end

    local delaySeconds = commandData.delay
    if not CommandsUtils.CheckNumberArgument(delaySeconds, "double", false, CommandName, "delay", 0, nil,
        command.parameter) then
        return
    end ---@cast delaySeconds double|nil
    local scheduleTick = Common.DelaySecondsSettingToScheduledEventTickValue(delaySeconds, command.tick, CommandName,
        "delay")

    local target = commandData.target
    if not Common.CheckPlayerNameSettingValue(target, CommandName, "target", command.parameter) then
        return
    end ---@cast target string

    local weaponPrototype, valid = Common.GetItemPrototypeFromCommandArgument(commandData.weaponType, "gun", false,
        CommandName, "weaponType", command.parameter)
    if not valid then
        return
    end

    local forceWeaponToSlot = commandData.forceWeaponToSlot
    if not CommandsUtils.CheckBooleanArgument(forceWeaponToSlot, false, CommandName, "forceWeaponToSlot",
        command.parameter) then
        return
    end ---@cast forceWeaponToSlot boolean|nil
    if forceWeaponToSlot == nil then
        forceWeaponToSlot = false
    end

    local selectWeapon = commandData.selectWeapon
    if not CommandsUtils.CheckBooleanArgument(selectWeapon, false, CommandName, "selectWeapon", command.parameter) then
        return
    end ---@cast selectWeapon boolean|nil
    if selectWeapon == nil then
        selectWeapon = false
    end

    local ammoPrototype, valid = Common.GetItemPrototypeFromCommandArgument(commandData.ammoType, "ammo", false,
        CommandName, "ammoType", command.parameter)
    if not valid then
        return
    end

    local ammoCount = commandData.ammoCount
    if not CommandsUtils.CheckNumberArgument(ammoCount, "int", false, CommandName, "ammoCount", 1, MathUtils.uintMax,
        command.parameter) then
        return
    end ---@cast ammoCount uint|nil

    local suppressMessages = commandData.suppressMessages
    if not CommandsUtils.CheckBooleanArgument(suppressMessages, false, CommandName, "suppressMessages",
        command.parameter) then
        return
    end ---@cast suppressMessages boolean|nil
    if suppressMessages == nil then
        suppressMessages = false
    end

    storage.giveItems.nextId = storage.giveItems.nextId + 1
    ---@type GiveItems_GiveWeaponAmmoScheduled
    local giveWeaponAmmoScheduled = {
        target = target,
        ammoPrototype = ammoPrototype,
        ammoCount = ammoCount,
        weaponPrototype = weaponPrototype,
        forceWeaponToSlot = forceWeaponToSlot,
        selectWeapon = selectWeapon,
        suppressMessages = suppressMessages
    }
    if scheduleTick ~= -1 then
        EventScheduler.ScheduleEventOnce(scheduleTick, "GiveItems.GiveWeaponAmmoScheduled", storage.giveItems.nextId,
            giveWeaponAmmoScheduled)
    else
        ---@type UtilityScheduledEvent_CallbackObject
        local eventData = {
            tick = command.tick,
            name = "GiveItems.GiveWeaponAmmoScheduled",
            instanceId = storage.giveItems.nextId,
            data = giveWeaponAmmoScheduled
        }
        GiveItems.GiveWeaponAmmoScheduled(eventData)
    end
end

---@param eventData UtilityScheduledEvent_CallbackObject
GiveItems.GiveWeaponAmmoScheduled = function(eventData)
    local data = eventData.data ---@type GiveItems_GiveWeaponAmmoScheduled

    local targetPlayer = game.get_player(data.target)
    if targetPlayer == nil then
        CommandsUtils.LogPrintWarning(CommandName, nil, "Target player has been deleted since the command was run.", nil)
        return
    end
    if not (targetPlayer.controller_type == defines.controllers.character or targetPlayer.controller_type ==
        defines.controllers.remote) or targetPlayer.character == nil then
        if not data.suppressMessages then
            game.print({"message.muppet_streamer_v2_give_player_weapon_ammo_not_character_controller", data.target})
        end
        return
    end

    -- Check the weapon and ammo are still valid (unchanged).
    if data.weaponPrototype ~= nil and not data.weaponPrototype.valid then
        CommandsUtils.LogPrintWarning(CommandName, nil,
            "The in-game weapon prototype has been changed/removed since the command was run.", nil)
        return
    end
    if data.ammoPrototype ~= nil and not data.ammoPrototype.valid then
        CommandsUtils.LogPrintWarning(CommandName, nil,
            "The in-game ammo prototype has been changed/removed since the command was run.", nil)
        return
    end

    local ammoName ---@type string|nil
    if data.ammoPrototype ~= nil and data.ammoCount > 0 then
        ammoName = data.ammoPrototype.name
    end
    if data.weaponPrototype ~= nil then
        PlayerWeapon.EnsureHasWeapon(targetPlayer, data.weaponPrototype.name, data.forceWeaponToSlot, data.selectWeapon,
            ammoName)
    end
    if ammoName ~= nil then
        local inserted = targetPlayer.insert({
            name = ammoName,
            count = data.ammoCount
        })
        if inserted < data.ammoCount then
            targetPlayer.physical_surface.spill_item_stack({
                position = targetPlayer.position,
                stack = { name = ammoName, count = data.ammoCount - inserted },
                enable_looted = true,
                force = nil,
                allow_belts = false,
            })
        end
    end
end

return GiveItems
