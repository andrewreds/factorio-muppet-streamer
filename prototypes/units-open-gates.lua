if not settings.startup["muppet_streamer_v2-units_can_open_gates"].value then return end

for _, unit in pairs(data.raw["unit"] --[[@as Prototype.Unit[] ]]) do
    unit.can_open_gates = true
end
