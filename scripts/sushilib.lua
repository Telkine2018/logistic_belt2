local commons = require("scripts.commons")
local tools = require("scripts.tools")
local locallib = require("scripts.locallib")

local sushilib = {}

local prefix = commons.prefix


local debug = tools.debug
local get_vars = tools.get_vars


local sushi_panel_name = commons.sushi_panel_name

---@param name string
local function np(name)
	return prefix .. "_sushi." .. name
end


local item_count_name = prefix .. "_sushi_item_count"

-----------------------------------------------------

local filter_name = commons.filter_name

local sushi_name = commons.sushi_name
local sushi_loader_name = commons.sushi_loader_name
local slow_scale = 100
local base_slow = math.pow(slow_scale, 1 / 19)

---@param slow number
---@return number
local function get_slow_value(slow)
	return math.pow(base_slow, slow - 1)
end

---@param slow number
---@return string
local function get_slow_text(slow)
	local percent = math.floor(100 / slow * 10) / 10
	return "" .. percent .. " %"
end

---@param sushi LuaEntity
---@param parameters Parameters
function sushilib.copy_sushi_items_to_filter(sushi, parameters)
	local qname
	local used = {}
	local index_filter = 1
	local index_lane = 1
	local current_lane = 1

	while (true) do
		qname = nil
		if current_lane == 1 then
			if parameters.lane1_items then
				qname = parameters.lane1_items[index_lane]
				index_lane = index_lane + 1
			end
			if not qname then
				current_lane = 2
				index_lane = 1
			end
		end

		if current_lane == 2 then
			if parameters.lane2_items then
				qname = parameters.lane2_items[index_lane]
				index_lane = index_lane + 1
			end
		end

		if not qname or not used[qname] then
			local item = tools.string_to_filter(qname)
			sushi.set_filter(index_filter, item)
			if index_filter == 5 then return end
			index_filter = index_filter + 1
		end

		if qname then
			used[qname] = true
		end
	end
end

---@param player LuaPlayer?
---@param sushi LuaEntity
---@return boolean
function sushilib.rebuild_sushi(player, sushi)
	local parameters = locallib.get_parameters(sushi, true)
	local inserters

	local speed = locallib.get_belt_speed(sushi)
	if not speed then
		if not parameters.speed then
			if player then
				player.print({ "message.cannot_find_belt" })
			end
			return false
		else
			speed = parameters.speed
		end
	else
		parameters.speed = speed
	end

	local slow = get_slow_value(parameters.slow --[[@as number?]] or 1)

	sushilib.copy_sushi_items_to_filter(sushi, parameters)

	-- Base cca
	local cc = locallib.create_combinator(sushi, "cc")
	local cb = cc.get_or_create_control_behavior() --[[@as LuaConstantCombinatorControlBehavior]]
	cb.get_section(1).set_slot(1, { value = { type = "virtual", name = "signal-A", comparator = "=", quality = "normal" }, min = 1, max = 1 })

	---@return LuaEntity
	local function create_counter()
		local counter = locallib.create_combinator(sushi, "dc")
		local cb = counter.get_or_create_control_behavior() --[[@as LuaDeciderCombinatorControlBehavior]]

		cb.set_condition(1, {
			first_signal = { type = "virtual", name = "signal-A" },
			second_signal = nil,
			constant = 0,
			comparator = "<"
		})

		cb.set_output(1, {
			signal = { type = "virtual", name = "signal-A" },
			copy_count_from_input = true
		})

		cc.get_wire_connector(defines.wire_connector_id.circuit_red, true).connect_to(
			counter.get_wire_connector(defines.wire_connector_id.combinator_input_red, true))
		counter.get_wire_connector(defines.wire_connector_id.combinator_output_green, true).connect_to(
			counter.get_wire_connector(defines.wire_connector_id.combinator_input_green, true))
		return counter
	end

	-- Advance 1/4 tile/s
	local tick_decal = 1 / speed / 4
	local stack_size = 1
	if (tick_decal < 1) then
		stack_size = math.ceil(1 / tick_decal)
		tick_decal = 1
	end

	debug("SPEED:" .. speed .. ",decal=" .. tick_decal .. ",stack_size" .. stack_size)

	---@param lane_items string[]
	---@param lane_position MapPosition[][]
	---@param counter LuaEntity
	---@param item_interval integer
	---@return integer
	local function create_sushi_lane(lane_items, lane_position, counter, item_interval)
		local inserter_index = 0
		if lane_items then
			if table_size(lane_items) == 1 and slow == 1 then
				local inserter_count = locallib.get_inserter_count_from_speed(speed or (1.0 / locallib.BELT_SPEED_FOR_60_PER_SECOND))
				inserters = locallib.create_inserters(sushi, sushi.direction, lane_position, inserter_count, filter_name)
				for _, inserter in pairs(inserters) do
					local item = tools.string_to_filter(lane_items[1])
					inserter.set_filter(1, item)
					inserter.use_filters = true
				end
				inserter_index = 1
			else
				inserters = locallib.create_inserters(sushi, sushi.direction, lane_position, #lane_items, filter_name)
				for index, inserter in pairs(inserters) do
					local lane_item = lane_items[index]

					if lane_item == 'deconstruction-planner' then
						inserter.destroy()
					else
						inserter.inserter_stack_size_override = stack_size
						inserter.set_filter(1, tools.string_to_filter(lane_item))
						local insert_decal        = math.floor(1 + slow * inserter_index * tick_decal)
						inserter.use_filters      = true

						local cb                  = inserter.get_or_create_control_behavior() --[[@as LuaInserterControlBehavior]]
						cb.circuit_enable_disable = true
						cb.circuit_condition      = {
							comparator = "=",
							first_signal = { type = "virtual", name = "signal-A" },
							constant = insert_decal
						}

						counter.get_wire_connector(defines.wire_connector_id.combinator_output_red, true)
							.connect_to(inserter.get_wire_connector(defines.wire_connector_id.circuit_red, true), false)
					end
					debug("DECAL[" .. index .. "]" .. inserter_index)
					inserter_index = inserter_index + 1
					if item_interval and item_interval > 0 then
						inserter_index = inserter_index + item_interval
					end
				end
			end
		end

		debug("TOTAL DECAL:" .. inserter_index)
		return math.ceil(1 + slow * inserter_index * tick_decal)
	end

	local counter1
	local cb1
	if parameters.lane1_items and table_size(parameters.lane1_items) then
		counter1 = create_counter()
		local decal = create_sushi_lane(parameters.lane1_items, { locallib.sushi_positions[1][1] }, counter1,
			parameters.lane1_item_interval)
		cb1 = counter1.get_or_create_control_behavior() --[[@as LuaDeciderCombinatorControlBehavior]]

		local condition = cb1.get_condition(1)
		condition.constant = decal
		cb1.set_condition(1, condition)
		sushi.get_wire_connector(defines.wire_connector_id.circuit_red, true)
			.connect_to(counter1.get_wire_connector(defines.wire_connector_id.combinator_output_red, true))
	end

	local counter2
	if parameters.lane2_items and table_size(parameters.lane2_items) > 0 then
		counter2 = create_counter()
		local decal = create_sushi_lane(parameters.lane2_items, { locallib.sushi_positions[1][2] }, counter2,
			parameters.lane2_item_interval)
		local cb2 = counter2.get_or_create_control_behavior() --[[@as LuaDeciderCombinatorControlBehavior]]

		local condition = cb2.get_condition(1)
		condition.constant = decal
		cb2.set_condition(1, condition)
	end
	return true
end

---@param player LuaPlayer?
---@param sushi LuaEntity
function sushilib.create_new_sushi(player, sushi)
	local loader = locallib.create_loader(sushi, sushi_loader_name)
	loader.active = false
	sushilib.rebuild_sushi(player, sushi)
end

---@param player LuaPlayer?
---@param sushi LuaEntity
function sushilib.clear_and_rebuild_sushi(player, sushi)
	locallib.clear_entities(sushi, commons.entities_to_clear)
	sushilib.rebuild_sushi(player, sushi)
end

---@param entity LuaEntity
---@param tags Tags
---@param player_index integer?
function sushilib.on_build(entity, tags, player_index)
	local player = player_index and game.players[player_index]

	local parameters = locallib.get_parameters(entity, true)
	if tags then
		parameters.lane1_items = (tags.lane1_items and helpers.json_to_table(tags.lane1_items --[[@as string]])) --[[@as string[] ]]
		parameters.lane2_items = tags.lane2_items and helpers.json_to_table(tags.lane2_items --[[@as string]]) --[[@as string[] ]]
		parameters.lane1_item_interval = tags.lane1_item_interval --[[@as number]]
		parameters.lane2_item_interval = tags.lane2_item_interval --[[@as number]]
		parameters.speed = tags.speed --[[@as number]]
		parameters.slow = tags.slow --[[@as number?]]
	else
		parameters = locallib.restore_saved_parameters(entity, parameters)
	end
	entity.active = false
	sushilib.create_new_sushi(player, entity)
end

---@param event EventData.on_gui_opened
local function on_gui_open_sushi_panel(event)
	local player = game.players[event.player_index]

	local entity = event.entity
	if not entity or not entity.valid or entity.name ~= sushi_name then
		return
	end
	locallib.close_ui(player)

	local vars       = get_vars(player)
	player.opened    = nil
	vars.selected    = entity

	local parameters = locallib.get_parameters(entity, true)

	local frame      = player.gui.left.add {
		type = "frame",
		name = commons.sushi_panel_name,
		direction = "vertical"
	}
	locallib.add_title(frame, np("title"))

	local inner_frame = frame.add {
		type = "frame",
		direction = "vertical",
		style = "inside_shallow_frame_with_padding"
	}

	local count = settings.global[item_count_name].value --[[@as integer]]

	local function create_lane_input(lane_items, name)
		local items_flow = inner_frame.add {
			type = "table",
			style_mods = { margin = 10 },
			column_count = count + 1,
			name = np(name .. "_item_table") }
		local f

		items_flow.add { type = "label", caption = { np(name .. "-items") } }

		for i = 1, count do
			local item_field = items_flow.add {
				type = "choose-elem-button",
				name = np("lane-item-" .. i),
				tooltip = { np("lane-item-tooltip") },
				elem_type = "item-with-quality"
			}
		end

		if lane_items then
			for i = 0, math.min(#lane_items, count) do
				local qname = lane_items[i]
				if qname then
					local item = tools.string_to_item(qname)
					if prototypes.item[item.name] then
						items_flow[np("lane-item-" .. i)].elem_value = item
					end
				end
			end
		end
	end

	create_lane_input(parameters.lane1_items, "lane1")
	create_lane_input(parameters.lane2_items, "lane2")

	local slider_flow = inner_frame.add { type = "flow", direction = "horizontal" }
	slider_flow.style.top_margin = 5
	slider_flow.style.bottom_margin = 5
	slider_flow.style.vertical_align = "center"
	slider_flow.add { type = "label", caption = { np("slow_label") } }
	local slider = slider_flow.add {
		type = "slider",
		name = np("slow"),
		minimum_value = 1,
		maximum_value = 20,
		value_step = 0.2,
		value = parameters.slow or 1
	}

	slider.style.width = 300
	local slow = get_slow_value(parameters.value or 1)
	local slow_info = slider_flow.add {
		type = "label",
		name = np("slow_label"),
		caption = get_slow_text(get_slow_value(parameters.slow --[[@as number?]] or 1))
	}
	slow_info.style.left_margin = 10

	local bflow = frame.add { type = "flow", direction = "horizontal" }
	local b = bflow.add {
		type = "button",
		name = np("save"),
		caption = { np("save") }
	}
	local bwidth = 100
	b.style.horizontally_stretchable = false
	b.style.width = bwidth
	player.opened = frame
end

tools.on_event(defines.events.on_gui_opened, on_gui_open_sushi_panel)

---@param e EventData.on_gui_value_changed
local function on_gui_value_changed(e)
	local player = game.players[e.player_index]
	local slow = e.element.slider_value
	local caption = get_slow_text(get_slow_value(slow or 1))
	local flow_label = tools.get_child(player.gui.left[commons.sushi_panel_name], np("slow_label"))
	flow_label.caption = caption
end

tools.on_named_event(np("slow"), defines.events.on_gui_value_changed, on_gui_value_changed)

---@param player LuaPlayer
---@return LuaEntity?
local function save_sushi_parameters(player)
	local selected = get_vars(player).selected --[[@as LuaEntity]]
	if not selected or not selected.valid or selected.name ~= sushi_name then return nil end

	local parameters = locallib.get_parameters(selected, true)
	local frame = player.gui.left[commons.sushi_panel_name]
	if not frame then return end

	local function save_lane(name)
		local f_item_table = tools.get_child(frame, np(name .. "_item_table"))
		if f_item_table ~= nil then
			local item_table = {}
			for i = 1, settings.global[item_count_name].value do
				local f_item = f_item_table[np("lane-item-" .. i)]
				if f_item then
					local item = f_item.elem_value
					if item then
						table.insert(item_table, tools.item_to_string(item))
					end
				end
			end
			parameters[name .. "_items"] = item_table
		end
	end

	save_lane("lane1")
	save_lane("lane2")
	local slider = tools.get_child(frame, np("slow"))
	parameters.slow = slider and slider.slider_value

	return selected
end

---@param e EventData.on_gui_click
local function on_save_sushi(e)
	local player = game.players[e.player_index]

	local sushi = save_sushi_parameters(player)
	if sushi then
		sushilib.clear_and_rebuild_sushi(player, sushi)
	end
	locallib.close_ui(game.players[e.player_index])
end

tools.on_gui_click(np("save"), on_save_sushi)

---@param src LuaEntity
---@param dst LuaEntity
---@param e any
function sushilib.do_paste(src, dst, e)
	local psrc = locallib.get_parameters(src, true)
	local pdst = locallib.get_parameters(dst, true)

	pdst.lane1_items = tools.table_copy(psrc.lane1_items)
	pdst.lane2_items = tools.table_copy(psrc.lane2_items)
	pdst.slow = psrc.slow
	local player = game.players[e.player_index]
	sushilib.clear_and_rebuild_sushi(player, dst)
	locallib.close_ui(game.players[e.player_index])
end

---@param e EventData.on_gui_confirmed
local function on_gui_confirmed(e)
	local player = game.players[e.player_index]
	local name = e.element.name
	local panel = player.gui.left[sushi_panel_name]
	if panel ~= nil and tools.get_child(panel, name) ~= nil then
		sushilib.on_save_sushi(e)
	end
end

---@param sushi LuaEntity
---@param parameters Parameters
function sushilib.update_parameters(sushi, parameters)
	local pdst = locallib.get_parameters(sushi, true)
	if pdst then
		pdst.lane1_items = parameters.lane1_items
		pdst.lane1_item_interval = parameters.lane1_item_interval
		pdst.lane2_items = parameters.lane2_items
		pdst.lane2_item_interval = parameters.lane2_item_interval
		pdst.slow = parameters.slow
		sushilib.rebuild_sushi(nil, sushi)
	end
end

tools.on_event(defines.events.on_gui_confirmed, on_gui_confirmed)

return sushilib
