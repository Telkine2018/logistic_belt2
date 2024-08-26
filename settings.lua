
local commons = require("scripts.commons")
local prefix = commons.prefix

data:extend(
    {
		{
			type = "int-setting",
			name = prefix .. "-request_count",
			setting_type = "runtime-global",
			default_value = 20
		},
		{
			type = "int-setting",
			name = prefix .. "_sushi_item_count",
			setting_type = "runtime-global",
			default_value = 10
		},
		{
			type = "int-setting",
			name = prefix .. "-router_inventory_size",
			setting_type = "startup",
			default_value = 50
		},		
		{
			type = "bool-setting",
			name = prefix .. "-add_filter",
			setting_type = "startup",
			default_value = true
		},
		{
			type = "int-setting",
			name = prefix .. "-max-router-entity",
			setting_type = "startup",
			default_value = 6
		}
})


