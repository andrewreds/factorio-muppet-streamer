----------------------------------------------------------------------------------
--                            STARTUP SETTINGS
----------------------------------------------------------------------------------

---@type data.ModBoolSettingPrototype
local enable_building_ghosts = {
    name = "muppet_streamer_v2-enable_building_ghosts",
    type = "bool-setting",
    default_value = false,
    setting_type = "startup",
    order = "1001"
}

---@type data.ModBoolSettingPrototype
local units_can_open_gates = {
    name = "muppet_streamer_v2-units_can_open_gates",
    type = "bool-setting",
    default_value = false,
    setting_type = "startup",
    order = "1002"
}

---@type data.ModBoolSettingPrototype
local disable_intro_message = {
    name = "muppet_streamer_v2-disable_intro_message",
    type = "bool-setting",
    default_value = false,
    setting_type = "startup",
    order = "2001"
}

---@type data.ModBoolSettingPrototype
local disable_rocket_win = {
    name = "muppet_streamer_v2-disable_rocket_win",
    type = "bool-setting",
    default_value = false,
    setting_type = "startup",
    order = "2002"
}

---@type data.ModIntSettingPrototype
local starting_reveal = {
    name = "muppet_streamer_v2-starting_reveal",
    type = "int-setting",
    default_value = -1,
    minimum_value = -1,
    setting_type = "startup",
    order = "2003"
}

---@type data.ModIntSettingPrototype
local recruit_team_member_technology_cost = {
    name = "muppet_streamer_v2-recruit_team_member_technology_cost",
    type = "int-setting",
    default_value = -1,
    min_value = -1,
    setting_type = "startup",
    order = "3001"
}

---@type data.ModStringSettingPrototype
local recruit_team_member_technology_title = {
    name = "muppet_streamer_v2-recruit_team_member_technology_title",
    type = "string-setting",
    default_value = "Recruit Team Member",
    allow_blank = true,
    setting_type = "startup",
    order = "3002"
}

---@type data.ModStringSettingPrototype
local recruit_team_member_technology_description = {
    name = "muppet_streamer_v2-recruit_team_member_technology_description",
    type = "string-setting",
    default_value = "Recruit another team member to increase your maximum concurrent team size",
    allow_blank = true,
    setting_type = "startup",
    order = "3003"
}

----------------------------------------------------------------------------------
--                            RUNTIME GLOBAL SETTINGS
----------------------------------------------------------------------------------

---@type data.ModStringSettingPrototype
local recruited_team_member_gui_title = {
    name = "muppet_streamer_v2-recruited_team_member_gui_title",
    type = "string-setting",
    default_value = "Active team members",
    allow_blank = true,
    setting_type = "runtime-global",
    order = "2001"
}

----------------------------------------------------------------------------------
--                            ADD SETTING PROTOTYPES
----------------------------------------------------------------------------------

data:extend(({ enable_building_ghosts, units_can_open_gates, disable_intro_message, disable_rocket_win, starting_reveal, recruit_team_member_technology_cost, recruit_team_member_technology_title, recruit_team_member_technology_description, recruited_team_member_gui_title }))