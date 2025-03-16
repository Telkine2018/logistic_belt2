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
		stack_size = 20
	},
	{
		type = 'item',
		name = commons.sushi_name,
		icon_size = 64,
		icon = png('item/sushi'),
		subgroup = 'belt',
		order = '[logistic]-b',
		place_result = commons.sushi_name,
		stack_size = 20
	},
	{
		type = 'item',
		name = commons.overflow_name,
		icon_size = 64,
		icon = png('item/overflow'),
		subgroup = 'belt',
		order = '[logistic]-c',
		place_result = commons.overflow_name,
		stack_size = 20
	},
	{
		type = 'item',
		name = commons.uploader_name,
		icon_size = 64,
		icon = png('item/uploader'),
		subgroup = 'belt',
		order = '[logistic]-a',
		place_result = commons.uploader_name,
		stack_size = 20
	},

	-- Recipe
	{ type = 'recipe',
		name = commons.device_name,
		enabled = false,
		ingredients = {
			{ type = "item", name = 'electronic-circuit', amount = 1 },
			{ type = "item", name = 'iron-plate',         amount = 2 },
			{ type = "item", name = 'iron-gear-wheel',    amount = 2 }
		},
		results = { { type = 'item', name = commons.device_name, amount = 1 } }
	},
	{ type = 'recipe',
		name = commons.sushi_name,
		enabled = false,
		ingredients = {
			{ type = "item", name = 'electronic-circuit', amount = 1 },
			{ type = "item", name = 'iron-plate',         amount = 2 },
			{ type = "item", name = 'iron-gear-wheel',    amount = 2 }
		},
		results = { { type = 'item', name = commons.sushi_name, amount = 1 } }
	},
	{ type = 'recipe',
		name = commons.overflow_name,
		enabled = false,
		ingredients = {
			{ type = "item", name = 'electronic-circuit', amount = 1 },
			{ type = "item", name = 'iron-plate',         amount = 2 },
			{ type = "item", name = 'iron-gear-wheel',    amount = 2 }
		},
		results = { { type = 'item', name = commons.overflow_name, amount = 1 } }
	},
	{ type = 'recipe',
		name = commons.uploader_name,
		enabled = false,
		ingredients = {
			{ type = "item", name = 'electronic-circuit', amount = 1 },
			{ type = "item", name = 'iron-plate',         amount = 2 },
			{ type = "item", name = 'iron-gear-wheel',    amount = 2 }
		},
		results = { { type = 'item', name = commons.uploader_name, amount = 1 } }
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
	{ type = 'technology',
		name = prefix .. '-router-tech',
		icon_size = 128,
		icon = png('router-tech-1'),
		prerequisites = { prefix .. '-tech' },
		unit = {
			count_formula = "1000 + 2000 * L",
			ingredients   = {
				{ "automation-science-pack", 1 },
				{ "logistic-science-pack",   1 },
				{ "chemical-science-pack",   1 },
				{ "production-science-pack", 1 },
				{ "utility-science-pack",    1 }
			},
			time          = 60
		},
		max_level = 50,
		upgrade = true,
		order = 'a-d-d-z',
		effects = {}
	},
	{
		type = "sprite",
		name = prefix .. "-chain",
		filename = png("chain"),
		width = 64,
		height = 64
	}
}
