local Freeplay = require("scripts.freeplay")
local TeamMember = require("scripts.team-member")
local ExplosiveDelivery = require("scripts.explosive-delivery")
local MalfunctioningWeapon = require("scripts.malfunctioning-weapon")
local EventScheduler = require("utility.manager-libraries.event-scheduler")
local GiveItems = require("scripts.give-items")
local SpawnAroundPlayer = require("scripts.spawn-around-player")
local AggressiveDriver = require("scripts.aggressive-driver")
local CallForHelp = require("scripts.call-for-help")
local Teleport = require("scripts.teleport")
local PantsOnFire = require("scripts.pants-on-fire")
local PlayerDropInventory = require("scripts.player-drop-inventory")
local PlayerInventoryShuffle = require("scripts.player-inventory-shuffle")
local BuildingGhosts = require("scripts.building-ghosts")
local Common = require("scripts.common")
local DelayedLua = require("scripts.delayed-lua")

local function CreateGlobals()
    storage.originalPlayersPermissionGroup = storage.originalPlayersPermissionGroup or {} ---@type table<uint, LuaPermissionGroup> # Used to track the last non-modded permission group across all the features. So we restore back to it after jumping between modded permission groups. Reset upon the last feature expiring.

    ---@class MuppetStreamer_Forces
    storage.Forces = storage.Forces or {}

    TeamMember.CreateGlobals()
    BuildingGhosts.CreateGlobals()
    ExplosiveDelivery.CreateGlobals()
    MalfunctioningWeapon.CreateGlobals()
    GiveItems.CreateGlobals()
    SpawnAroundPlayer.CreateGlobals()
    AggressiveDriver.CreateGlobals()
    CallForHelp.CreateGlobals()
    Teleport.CreateGlobals()
    PantsOnFire.CreateGlobals()
    PlayerDropInventory.CreateGlobals()
    PlayerInventoryShuffle.CreateGlobals()
    PlayerInventoryShuffle.CreateGlobals()
    DelayedLua.CreateGlobals()
end

local function OnLoad()
    --Any Remote Interface registration calls can go in here or in root of control.lua
    remote.remove_interface("muppet_streamer_v2")
    remote.add_interface(
        "muppet_streamer_v2",
        {
            run_command = Common.CallCommandFromRemote,
            increase_team_member_level = TeamMember.RemoteIncreaseTeamMemberLevel,
            add_delayed_lua = DelayedLua.AddDelayedLua_Remote,
            remove_delayed_lua = DelayedLua.RemoveDelayedLua_Remote,
            get_delayed_lua_data = DelayedLua.GetDelayedLuaData_Remote,
            set_delayed_lua_data = DelayedLua.SetDelayedLuaData_Remote
        }
    )

    BuildingGhosts.OnLoad()
    TeamMember.OnLoad()
    ExplosiveDelivery.OnLoad()
    MalfunctioningWeapon.OnLoad()
    GiveItems.OnLoad()
    SpawnAroundPlayer.OnLoad()
    AggressiveDriver.OnLoad()
    CallForHelp.OnLoad()
    Teleport.OnLoad()
    PantsOnFire.OnLoad()
    PlayerDropInventory.OnLoad()
    PlayerInventoryShuffle.OnLoad()
    DelayedLua.OnLoad()
end

---@param event EventData.on_runtime_mod_setting_changed|nil
local function OnSettingChanged(event)
    TeamMember.OnSettingChanged(event)
    SpawnAroundPlayer.OnStartup()
end

local function OnStartup()
    CreateGlobals()
    OnLoad()
    OnSettingChanged(nil)

    Freeplay.OnStartup()
    BuildingGhosts.OnStartup()
    TeamMember.OnStartup()
    MalfunctioningWeapon.OnStartup()
    AggressiveDriver.OnStartup()

    -- Ensure our special enemy force is always present.
    if storage.Forces.muppet_streamer_v2_enemy == nil then
        storage.Forces.muppet_streamer_v2_enemy = game.forces["muppet_streamer_v2_enemy"]
        if storage.Forces.muppet_streamer_v2_enemy == nil then
            storage.Forces.muppet_streamer_v2_enemy = game.create_force("muppet_streamer_v2_enemy") -- No alliances set to any other force.
        end
    end
end

script.on_init(OnStartup)
script.on_configuration_changed(OnStartup)
script.on_event(defines.events.on_runtime_mod_setting_changed, OnSettingChanged)
script.on_load(OnLoad)
EventScheduler.RegisterScheduler()

-- Mod wide function interface table creation. Means EmmyLua can support it.
MOD = MOD or {} ---@class MOD
MOD.Interfaces = MOD.Interfaces or {} ---@class MOD_InternalInterfaces
MOD.Interfaces.Commands = MOD.Interfaces.Commands or {} ---@class MOD_InternalInterfaces_Commands
--[[
    Populate and use from within module's OnLoad() functions with simple table reference structures, i.e:
        MOD.Interfaces.Tunnel = MOD.Interfaces.Tunnel or {} ---@class InternalInterfaces_XXXXXX
        MOD.Interfaces.Tunnel.CompleteTunnel = Tunnel.CompleteTunnel
--]]
--
