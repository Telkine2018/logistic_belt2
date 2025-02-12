
local commons = require("scripts.commons")


if settings.startup["logistic_belt2-add_filter"].value then
	for _, type in pairs({"container","logistic-container","infinity-container"}) do
		for name, chest in pairs(data.raw[type]) do
			chest.inventory_type = "with_filters_and_bar"
			data:extend { chest }
		end
	end
end

if data.raw["linked-container"]["logistic_belt-router"] then
	data.raw["linked-container"]["logistic_belt-router"].localised_description = {"entity-description.logistic_belt2-router"}
end

data:extend
{
    {
        type = "custom-input",
        name = commons.shift_button1_event,
        key_sequence = "SHIFT + mouse-button-1",
        consuming = "none"
    }
}
