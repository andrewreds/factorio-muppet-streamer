local Constants = require("constants")

if tonumber(settings.startup["muppet_streamer_v2-recruit_team_member_technology_cost"].value) >= 0 then
    ---@type data.ShortcutPrototype
    local teamMemberGUIButton = {
        type = "shortcut",
        name = "muppet_streamer_v2-team_member_gui_button",
        action = "lua",
        toggleable = true,
        icon = Constants.AssetModName .. "/graphics/shortcuts/team_member32.png",
        icon_size = 32,
        small_icon = Constants.AssetModName .. "/graphics/shortcuts/team_member24.png",
        small_icon_size = 24,
        disabled_small_icon = Constants.AssetModName .. "/graphics/shortcuts/team_member24-disabled.png",
        disabled_small_icon_size = 24,

    }

    data:extend(
        {
            teamMemberGUIButton
        }
    )
end
