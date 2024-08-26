local commons = require("scripts.commons")
local tools = require("scripts.tools")

local prefix = commons.prefix
local png = commons.png


local tech_effects = {
	{ type = 'unlock-recipe', recipe = commons.device_name },
	{ type = 'unlock-recipe', recipe = commons.sushi_name },
	{ type = 'unlock-recipe', recipe = commons.overflow_name },
	{ type = 'unlock-recipe', recipe = commons.router_name },
	{ type = 'unlock-recipe', recipe = commons.uploader_name }
}

data:extend {

	-- Item
	{
		type = 'item',
		name = commons.device_name,
		icon_size = 64,
		icon = png('item/device'),
		subgroup = 'belt',
		order = '[logistic]-a',
		place_result = commons.device_name,
		stack_size = 50
	},
	{
		type = 'item',
		name = commons.sushi_name,
		icon_size = 64,
		icon = png('item/sushi'),
		subgroup = 'belt',
		order = '[logistic]-b',
		place_result = commons.sushi_name,
		stack_size = 50
	},
	{
		type = 'item',
		name = commons.overflow_name,
		icon_size = 64,
		icon = png('item/overflow'),
		subgroup = 'belt',
		order = '[logistic]-c',
		place_result = commons.overflow_name,
		stack_size = 50
	},
	{
		type = 'item',
		name = commons.uploader_name,
		icon_size = 64,
		icon = png('item/uploader'),
		subgroup = 'belt',
		order = '[logistic]-a',
		place_result = commons.uploader_name,
		stack_size = 50
	},

	-- Recipe
	{ type = 'recipe',
		name = commons.device_name,
		enabled = false,
		ingredients = {
			{ 'electronic-circuit', 1 },
			{ 'iron-plate',         2 },
			{ 'iron-gear-wheel',    2 }
		},
		result = commons.device_name
	},
	{ type = 'recipe',
		name = commons.sushi_name,
		enabled = false,
		ingredients = {
			{ 'electronic-circuit', 1 },
			{ 'iron-plate',         2 },
			{ 'iron-gear-wheel',    2 }
		},
		result = commons.sushi_name
	},
	{ type = 'recipe',
		name = commons.overflow_name,
		enabled = false,
		ingredients = {
			{ 'electronic-circuit', 1 },
			{ 'iron-plate',         2 },
			{ 'iron-gear-wheel',    2 }
		},
		result = commons.overflow_name
	},
	{ type = 'recipe',
		name = commons.uploader_name,
		enabled = false,
		ingredients = {
			{ 'electronic-circuit', 1 },
			{ 'iron-plate',         2 },
			{ 'iron-gear-wheel',    2 }
		},
		result = commons.uploader_name
	},

	-- Technology
	{ type = 'technology',
		name = prefix .. '-tech',
		icon_size = 128,
		icon = png('tech'),
		effects = tech_effects,
		prerequisites = { 'logistics' },
		unit = {
			count = 100,
			ingredients = {
				{ 'automation-science-pack', 1 }
			},
			time = 15
		},
		order = 'a-d-d-z'
	},
	{
		type = "sprite",
		name = prefix .. "-chain",
		filename = png("chain"),
		width = 64,
		height = 64
	}
}
