
local commons = {}

commons.prefix = "logistic_belt2"

local prefix = commons.prefix

---@param name string
---@return string
local function np(name)
	return prefix .. "-" .. name
end
commons.np = np

local function png(name) return ('__logistic_belt2__/graphics/%s.png'):format(name) end

commons.debug_mode = false
commons.png = png
commons.item1 = "item1"

commons.device_name = np("device")
commons.inserter_name = np("inserter")
commons.filter_name = np("inserter-filter")
commons.device_loader_name = np("loader")
commons.chest_name = np("chest")
commons.slow_filter_name = np("inserter-filter-slow")
commons.device_panel_name = prefix .. "_device_frame"

commons.sushi_loader_name = np("loader-sushi")
commons.sushi_name = np("sushi")
commons.sushi_panel_name = prefix .. "_sushi_frame"

commons.router_name = np("router")
commons.background_router_name = np("background_router")
commons.pole_name = np("pole")

commons.overflow_name = np("overflow")
commons.overflow_loader_name = np("overflow-loader")
commons.overflow_panel_name = np("overflow-panel")

commons.debug_mode = false
commons.trace_inserter = false


commons.connector_name = prefix .. "_connector"


commons.entities_to_clear = {
	commons.inserter_name,
	commons.filter_name,
	commons.slow_filter_name,
	prefix .. "-cc",
	prefix .. "-dc",
	prefix .. "-ac",
	prefix .. "-cc2",
	commons.chest_name
}

commons.connector_chest_size = 40
commons.shift_button1_event = prefix .. "-shift-button1"

return commons

