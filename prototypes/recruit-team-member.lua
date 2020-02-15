local Constants = require("constants")

local recruitTeamMemberCost = tonumber(settings.startup["muppet_streamer-recruit_team_member_technology_cost"].value)
local recruitTeamMemberTitle = settings.startup["muppet_streamer-recruit_team_member_technology_title"].value
local recruitTeamMemberDescription = settings.startup["muppet_streamer-recruit_team_member_technology_description"].value

--Add the techs if cost is 0, but just hide them. Means other mods can use the info from the techs.
data:extend(
    {
        {
            type = "technology",
            name = "muppet_streamer-recruit_team_member-1",
            icon_size = 140,
            icon = Constants.AssetModName .. "/graphics/technology/recruit_team_member.png",
            prerequisites = {},
            unit = {
                count_formula = recruitTeamMemberCost,
                ingredients = {
                    {"automation-science-pack", 1}
                },
                time = 60
            },
            upgrade = true,
            max_level = 1,
            localised_name = recruitTeamMemberTitle,
            localised_description = recruitTeamMemberDescription,
            enabled = recruitTeamMemberCost ~= 0,
            order = "zzz"
        },
        {
            type = "technology",
            name = "muppet_streamer-recruit_team_member-2",
            icon_size = 140,
            icon = Constants.AssetModName .. "/graphics/technology/recruit_team_member.png",
            prerequisites = {"logistic-science-pack", "muppet_streamer-recruit_team_member-1"},
            unit = {
                count_formula = recruitTeamMemberCost,
                ingredients = {
                    {"automation-science-pack", 1},
                    {"logistic-science-pack", 1}
                },
                time = 60
            },
            upgrade = true,
            max_level = 2,
            localised_name = recruitTeamMemberTitle,
            localised_description = recruitTeamMemberDescription,
            enabled = recruitTeamMemberCost ~= 0,
            order = "zzz"
        },
        {
            type = "technology",
            name = "muppet_streamer-recruit_team_member-3",
            icon_size = 140,
            icon = Constants.AssetModName .. "/graphics/technology/recruit_team_member.png",
            prerequisites = {"muppet_streamer-recruit_team_member-2", "military-science-pack"},
            unit = {
                count_formula = recruitTeamMemberCost,
                ingredients = {
                    {"automation-science-pack", 1},
                    {"logistic-science-pack", 1},
                    {"military-science-pack", 1}
                },
                time = 60
            },
            upgrade = true,
            max_level = 3,
            localised_name = recruitTeamMemberTitle,
            localised_description = recruitTeamMemberDescription,
            enabled = recruitTeamMemberCost ~= 0,
            order = "zzz"
        },
        {
            type = "technology",
            name = "muppet_streamer-recruit_team_member-4",
            icon_size = 140,
            icon = Constants.AssetModName .. "/graphics/technology/recruit_team_member.png",
            prerequisites = {"muppet_streamer-recruit_team_member-3", "chemical-science-pack"},
            unit = {
                count_formula = recruitTeamMemberCost,
                ingredients = {
                    {"automation-science-pack", 1},
                    {"logistic-science-pack", 1},
                    {"military-science-pack", 1},
                    {"chemical-science-pack", 1}
                },
                time = 60
            },
            upgrade = true,
            max_level = 4,
            localised_name = recruitTeamMemberTitle,
            localised_description = recruitTeamMemberDescription,
            enabled = recruitTeamMemberCost ~= 0,
            order = "zzz"
        },
        {
            type = "technology",
            name = "muppet_streamer-recruit_team_member-5",
            icon_size = 140,
            icon = Constants.AssetModName .. "/graphics/technology/recruit_team_member.png",
            prerequisites = {"muppet_streamer-recruit_team_member-4", "production-science-pack"},
            unit = {
                count_formula = recruitTeamMemberCost,
                ingredients = {
                    {"automation-science-pack", 1},
                    {"logistic-science-pack", 1},
                    {"military-science-pack", 1},
                    {"chemical-science-pack", 1},
                    {"production-science-pack", 1}
                },
                time = 60
            },
            upgrade = true,
            max_level = 5,
            localised_name = recruitTeamMemberTitle,
            localised_description = recruitTeamMemberDescription,
            enabled = recruitTeamMemberCost ~= 0,
            order = "zzz"
        },
        {
            type = "technology",
            name = "muppet_streamer-recruit_team_member-6",
            icon_size = 140,
            icon = Constants.AssetModName .. "/graphics/technology/recruit_team_member.png",
            prerequisites = {"muppet_streamer-recruit_team_member-5", "utility-science-pack"},
            unit = {
                count_formula = recruitTeamMemberCost,
                ingredients = {
                    {"automation-science-pack", 1},
                    {"logistic-science-pack", 1},
                    {"military-science-pack", 1},
                    {"chemical-science-pack", 1},
                    {"production-science-pack", 1},
                    {"utility-science-pack", 1}
                },
                time = 60
            },
            upgrade = true,
            max_level = 6,
            localised_name = recruitTeamMemberTitle,
            localised_description = recruitTeamMemberDescription,
            enabled = recruitTeamMemberCost ~= 0,
            order = "zzz"
        },
        {
            type = "technology",
            name = "muppet_streamer-recruit_team_member-7",
            icon_size = 140,
            icon = Constants.AssetModName .. "/graphics/technology/recruit_team_member.png",
            prerequisites = {"muppet_streamer-recruit_team_member-6", "space-science-pack"},
            unit = {
                count_formula = "(2^(L-6))*" .. (recruitTeamMemberCost / 2),
                ingredients = {
                    {"automation-science-pack", 1},
                    {"logistic-science-pack", 1},
                    {"military-science-pack", 1},
                    {"chemical-science-pack", 1},
                    {"production-science-pack", 1},
                    {"utility-science-pack", 1},
                    {"space-science-pack", 1}
                },
                time = 60
            },
            upgrade = true,
            localised_name = recruitTeamMemberTitle,
            localised_description = recruitTeamMemberDescription,
            enabled = recruitTeamMemberCost ~= 0,
            order = "zzz"
        }
    }
)
