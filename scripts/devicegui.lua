local commons = require "scripts.commons"
local tools = require "scripts.tools"
local locallib = require "scripts.locallib"
local sushilib = require "scripts.sushilib"
local routerlib = require "scripts.routerlib"
local inspectlib = require "scripts.inspect"
local devicelib = require "scripts.devicelib"
local structurelib = require "scripts.structurelib"
local nodelib = require "scripts.nodelib"
local config = require "scripts.config"

local prefix = commons.prefix

local debug = tools.debug
local get_vars = tools.get_vars
local strip = tools.strip

local device_name = commons.device_name
local sushi_name = commons.sushi_name

local device_panel_name = commons.device_panel_name

---@param name string
local function np(name)
	return prefix .. "." .. name
end

local devicegui = {}

local left_panel_names = {
	["memory-unit"] = true,
	-- ["supply-depot-chest"] = true
}

local delivery_fraction = 5

---@param stack_size number
local function stacksize_to_delivery(stack_size)
	return math.max(math.ceil(stack_size / delivery_fraction), 1)
end

--------------------------------------------------

---@param request_flow any
---@return LuaGuiElement
---@return LuaGuiElement
---@return LuaGuiElement
local function add_request_field(request_flow)
	local item_field = request_flow.add {
		type = "choose-elem-button",
		elem_type = "item",
	}
	local wfield = 70
	tools.set_name_handler(item_field, np("request_item"))

	local count_field = request_flow.add {
		type = "textfield",
		tooltip = { np("request_count_tooltip") },
		numeric = true,
		allow_negative = false
	}
	tools.set_name_handler(count_field, np("request_count"))
	count_field.style.width = wfield

	local delivery_field = request_flow.add {
		type = "textfield",
		tooltip = { np("delivery_tooltip") },
		numeric = true,
		allow_negative = false
	}
	tools.set_name_handler(count_field, np("delivery"))
	delivery_field.style.width = wfield

	return item_field, count_field, delivery_field
end

---@param request_flow LuaGuiElement
local function add_provide_field(request_flow)
	local item_field = request_flow.add {
		type = "choose-elem-button",
		elem_type = "item"
	}
	tools.set_name_handler(item_field, np("provide_item"))
	return item_field
end

---@param request_flow LuaGuiElement
local function add_restrictions_field(request_flow)
	local item_field = request_flow.add {
		type = "choose-elem-button",
		elem_type = "item"
	}
	tools.set_name_handler(item_field, np("restrictions_item"))
	return item_field
end

---@param player LuaPlayer
---@return LuaGuiElement
local function get_frame(player)
	return player.gui.relative[device_panel_name] or player.gui.left[device_panel_name]
end

---@param event EventData.on_gui_opened
local function on_gui_open_node_panel(event)
	local entity = event.entity
	local player = game.players[event.player_index]
	if not entity or not entity.valid then
		return
	end

	devicegui.open(player, entity)
end

---@param player LuaPlayer
---@param entity LuaEntity
function devicegui.open(player, entity)
	local node = structurelib.get_node(entity)
	if not node then
		if entity.name == device_name then
			player.opened = nil
		end
		return
	end

	locallib.close_ui(player)
	local vars = get_vars(player)
	vars.selected = entity
	vars.selected_node = node
	inspectlib.update(player, entity)

	local frame
	if left_panel_names[entity.name] then
		frame = player.gui.left.add { type = "frame", name = device_panel_name, direction = "vertical" }
	else
		local gui_type
		if entity.type == "linked-container" then
			gui_type = defines.relative_gui_type.linked_container_gui
		elseif entity.type == "assembling-machine" then
			gui_type = defines.relative_gui_type.assembling_machine_gui
		else
			gui_type = defines.relative_gui_type.container_gui
		end
		frame = player.gui.relative.add { type = "frame", name = device_panel_name,
			anchor = {
				gui = gui_type,
				position = defines.relative_gui_position.left
			},
			direction = "vertical"
		}
	end
	frame.style.minimal_width = 280

	local titleflow = frame.add { type = "flow" }
	titleflow.add {
		type = "label",
		caption = { "parameters_dialog.title" },
		style = "frame_title",
		ignored_by_interaction = true
	}

	local drag = titleflow.add {
		type = "empty-widget",
	}
	drag.style.horizontally_stretchable = true

	titleflow.add {
		type = "sprite-button",
		name = np("purge"),
		tooltip = { np("purge_tooltip") },
		style = "frame_action_button",
		mouse_button_filter = { "left" },
		sprite = prefix .. "_purge_white",
		hovered_sprite = prefix .. "_purge_black"
	}
	titleflow.add {
		type = "sprite-button",
		name = np("reset"),
		tooltip = { np("reset_tooltip") },
		style = "frame_action_button",
		mouse_button_filter = { "left" },
		sprite = prefix .. "_reset_white",
		hovered_sprite = prefix .. "_reset_black"
	}
	titleflow.add {
		type = "sprite-button",
		name = np("inspect"),
		tooltip = { np("inspect_tooltip") },
		style = "frame_action_button",
		mouse_button_filter = { "left" },
		sprite = prefix .. "_inspect_white",
		hovered_sprite = prefix .. "_inspect_black"
	}

	local inner_frame = frame.add {
		type = "frame",
		direction = "vertical",
		style = "inside_shallow_frame_with_padding"
	}

	local flow = inner_frame.add { type = "flow", direction = "horizontal" }
	local label = flow.add { type = "label", caption = { np("io_buffer_size") } }
	local slider = flow.add { type = "slider",
		name = np("io_buffer_size"),
		tooltip = tostring(node.buffer_size),
		value = node.buffer_size,
		minimum_value = 4,
		maximum_value = 40,
		value_step = 1,
		discrete_slider = true }

	local line = inner_frame.add { type = "line" }
	line.style.top_margin = 10
	inner_frame.add { type = "label", caption = { np("request-label") } }
	local request_flow = inner_frame.add {
		type = "table",
		style_mods = { margin = 10 },
		column_count = 6,
		name = np("request_table")
	}
	if node.requested then
		for item, request in pairs(node.requested) do
			local item_field, count_field, delivery_field = add_request_field(request_flow)
			item_field.elem_value = item
			count_field.text = tools.number_to_text(request.count)
			delivery_field.text = tools.number_to_text(request.delivery)
		end
	end
	add_request_field(request_flow)

	line = inner_frame.add { type = "line" }
	line.style.top_margin = 10
	inner_frame.add { type = "label", caption = { np("provide-label") } }
	local provide_flow = inner_frame.add {
		type = "table",
		style_mods = { margin = 10 },
		column_count = 6,
		name = np("provide_table")
	}
	if node.provided then
		for item, _ in pairs(node.provided) do
			local item_field      = add_provide_field(provide_flow)
			item_field.elem_value = item
		end
	end
	add_provide_field(provide_flow)

	line.style.top_margin = 10
	inner_frame.add { type = "label", caption = { np("restrictions-label") } }
	local restrictions_flow = inner_frame.add {
		type = "table",
		style_mods = { margin = 10 },
		column_count = 6,
		name = np("restrictions_table")
	}
	if node.restrictions then
		for item, _ in pairs(node.restrictions) do
			local item_field      = add_restrictions_field(restrictions_flow)
			item_field.elem_value = item
		end
	end
	add_restrictions_field(restrictions_flow)

	line = inner_frame.add { type = "line" }


	local bImport = inner_frame.add { type = "button", name = np("import-content"), caption = { np("import-content") } }
	bImport.style.top_margin = 5
end

tools.on_gui_click(np("import-content"),
	---@param e EventData.on_gui_click
	function(e)
		local player = game.players[e.player_index]
		local vars = get_vars(player)

		---@type Node
		local node = vars.selected_node
		if not node or not node.container.valid then return end

		local frame = get_frame(player)
		if not frame then return end

		local contents = node.inventory.get_contents()
		local provide_table = tools.get_child(frame, np("provide_table"))
		---@cast provide_table -nil

		local requests
		if e.shift then
			requests = nodelib.get_requests(node, true)
		elseif e.control then
			requests = nodelib.get_requests(node, true, true)
		end

		provide_table.clear()
		for item, _ in pairs(contents) do
			if not requests or requests[item] then
				local item_field      = add_provide_field(provide_table)
				item_field.elem_value = item
			end
		end
		add_provide_field(provide_table)
	end)

tools.on_gui_click(np("reset"),
	---@param e EventData.on_gui_click
	function(e)
		local player = game.players[e.player_index]
		local vars = get_vars(player)

		---@type Node
		local node = vars.selected_node
		if not node or not node.container.valid then return end

		if structurelib.is_orphan(node) then
			structurelib.delete_node(node, node.id)
			locallib.on_gui_closed(e --[[@as EventData.on_gui_closed]])
			player.print({ np("reset_deleted") })
		elseif node.disabled then
			local count = structurelib.start_network(node)
			locallib.add_monitored_node(node)
			player.print({ np("reset_started"), tostring(count) })
		else
			local count = structurelib.stop_network(node)
			player.print({ np("reset_stopped"), tostring(count) })
		end
	end)

tools.on_gui_click(np("inspect"),
	---@param e EventData.on_gui_click
	function(e)
		local player = game.players[e.player_index]
		local vars = get_vars(player)

		local node = vars.selected_node
		if not node or not node.container.valid then return end

		inspectlib.toogle_keep(player, node.container)
	end)

tools.on_gui_click(np("purge"),
	---@param e EventData.on_gui_click
	function(e)
		local player = game.players[e.player_index]
		local vars = get_vars(player)

		local node = vars.selected_node
		if not node or not node.container.valid then return end

		nodelib.purge(node)
	end)


tools.on_named_event(np("io_buffer_size"), defines.events.on_gui_value_changed,
	---@param e EventData.on_gui_value_changed
	function(e)
		e.element.tooltip = tostring(e.element.slider_value)

		local buffer_size = e.element.slider_value
		local player = game.players[e.player_index]
		local vars = get_vars(player)
		local node = vars.selected_node

		node.buffer_size = buffer_size
		if node.outputs then
			for _, output in pairs(node.outputs) do
				if output.inventory and output.inventory.valid then
					output.inventory.set_bar(buffer_size)
				end
			end
		end
		if node.inputs then
			for _, input in pairs(node.inputs) do
				if input.inventory and input.inventory.valid then
					input.inventory.set_bar(buffer_size)
				end
			end
		end
	end)

---@param player LuaPlayer
---@return Node?
local function save_node_parameters(player)
	local vars = get_vars(player)

	---@type Node
	local selected_node = vars.selected_node
	if not selected_node or not selected_node.container.valid then return nil end

	local frame = get_frame(player)
	if not frame then return end

	local request_table = tools.get_child(frame, np("request_table"))
	if request_table ~= nil then
		local old_requests = selected_node.requested
		selected_node.requested = nil

		local children = request_table.children
		local index = 1
		while index <= #children do
			local f_item = children[index]
			local f_count = children[index + 1]
			local f_delivery = children[index + 2]
			local item = f_item.elem_value --[[@as string]]
			local tcount = f_count.text
			local count = tonumber(tcount)
			local delivery = tools.text_to_number(f_delivery.text) or config.default_delivery

			if count and item then
				nodelib.add_request(selected_node, item, count, delivery, old_requests)
			end
			index = index + 3
		end
	end

	local provide_table = tools.get_child(frame, np("provide_table"))
	if provide_table ~= nil then
		---@type table<string, ProvidedItem>
		local provided = {}

		local children = provide_table.children
		local index = 1
		while index <= #children do
			local f_item = children[index]
			local item = f_item.elem_value

			if item then
				local existing = (selected_node.provided and selected_node.provided[item])
				if existing then
					provided[item] = existing
				else
					provided[item] = {
						item = item,
						min = 1,
						provided = 0
					}
				end
			end
			index = index + 1
		end
		selected_node.provided = nil
		if next(provided) then
			selected_node.provided = provided
		end
	end

	local restrictions_table = tools.get_child(frame, np("restrictions_table"))
	if restrictions_table ~= nil then
		---@type table<string, boolean>
		local restrictions = {}

		local children = restrictions_table.children
		local index = 1
		while index <= #children do
			local f_item = children[index]
			local item = f_item.elem_value

			if item then
				restrictions[item] = true
			end
			index = index + 1
		end
		selected_node.restrictions = nil
		if next(restrictions) then
			selected_node.restrictions = restrictions
		end
	end

	return selected_node
end


---@param e EventData.on_gui_click
local function on_close(e)
	local player = game.players[e.player_index]
	if not get_frame(player) then return end
	save_node_parameters(player)
	locallib.close_ui(player)

	local vars = get_vars(player)

	---@type Node
	vars.selected_node = nil
	vars.selected = nil
end

tools.on_event(defines.events.on_gui_opened, on_gui_open_node_panel)
tools.on_event(defines.events.on_gui_closed, on_close)

---@param e EventData.on_gui_elem_changed
local function on_request_item_changed(e)
	local player = game.players[e.player_index]
	if not e.element or not e.element.valid then return end

	local panel = get_frame(player)
	if not panel then return end

	local f_request_table = tools.get_child(panel, np("request_table"))
	if not f_request_table then return end

	local children = f_request_table.children
	local count = #children

	if e.element.elem_value then
		local index = tools.index_of(children, e.element)
		local stack_size = game.item_prototypes[e.element.elem_value].stack_size
		children[index + 1].text = tostring(stack_size)
		children[index + 2].text = tostring(stacksize_to_delivery(stack_size / delivery_fraction))
	end
	if e.element == children[count - 2] then
		if e.element.elem_value then
			add_request_field(f_request_table)
		end
	else
		if not e.element.elem_value then
			local index = tools.index_of(children, e.element)
			e.element.destroy()
			children[index + 1].destroy()
			children[index + 2].destroy()
		end
	end
end
tools.on_named_event(np("request_item"), defines.events.on_gui_elem_changed, on_request_item_changed)

---@param e EventData.on_gui_elem_changed
local function on_provided_item_changed(e)
	local player = game.players[e.player_index]
	if not e.element or not e.element.valid then return end

	local panel = get_frame(player)
	if not panel then return end

	local provide_table = tools.get_child(panel, np("provide_table"))
	if not provide_table then return end

	local children = provide_table.children
	local count = #children
	if e.element == children[count] then
		if e.element.elem_value then
			add_provide_field(provide_table)
		end
	else
		if not e.element.elem_value then
			if #children > 1 then
				e.element.destroy()
			end
		end
	end
end
tools.on_named_event(np("provide_item"), defines.events.on_gui_elem_changed, on_provided_item_changed)

---@param e EventData.on_gui_elem_changed
local function on_restrictions_changed(e)
	local player = game.players[e.player_index]
	if not e.element or not e.element.valid then return end

	local panel = get_frame(player)
	if not panel then return end

	local provide_table = tools.get_child(panel, np("restrictions_table"))
	if not provide_table then return end

	local children = provide_table.children
	local count = #children
	if e.element == children[count] then
		if e.element.elem_value then
			add_restrictions_field(provide_table)
		end
	else
		if not e.element.elem_value then
			if #children > 1 then
				e.element.destroy()
			end
		end
	end
end
tools.on_named_event(np("restrictions_item"), defines.events.on_gui_elem_changed, on_restrictions_changed)


---@param request_table table<string, table>
local function dup_request(request_table)
	if not request_table then return nil end
	request_table = tools.table_dup(request_table)
	for _, value in pairs(request_table) do
		if value.provided then
			value.provided = 0
		elseif value.remaining then
			value.remaining = 0
		end
	end
	return request_table
end

---@param bp LuaItemStack
---@param mapping LuaEntity[]
---@param surface LuaSurface
local function register_mapping(bp, mapping, surface)
	local parameter_map = global.parameters
	local context = structurelib.get_context()
	local is_processed = {}
	local bp_count = bp.get_blueprint_entity_count()

	if bp_count > 0 and mapping and next(mapping) then
		for index = 1, bp.get_blueprint_entity_count() do
			local entity = mapping[index]
			if entity and entity.valid then
				local name = entity.name
				if name == commons.router_name then
					if not is_processed[entity.link_id] then
						local node = structurelib.get_node(entity)
						is_processed[entity.link_id] = true
						local filters = routerlib.get_filters(entity.get_inventory(defines.inventory.chest) --[[@as LuaInventory]])
						bp.set_blueprint_entity_tags(index, {
							filters = filters and game.table_to_json(filters),
							logistic_belt2_node = true,
							provided = node and dup_request(node.provided) --[[@as table]],
							requested = node and dup_request(node.requested) --[[@as table]],
							restrictions = node and tools.table_dup(node.restrictions) --[[@as table]],
						})
					end
				elseif locallib.container_type_map[entity.type] then
					local node = structurelib.get_node(entity)
					if node then
						bp.set_blueprint_entity_tags(index, {
							logistic_belt2_node = true,
							provided = dup_request(node.provided) --[[@as table]],
							requested = dup_request(node.requested) --[[@as table]],
							restrictions = node and tools.table_dup(node.restrictions) --[[@as table]],
						})
					end
				elseif name == sushi_name then
					local parameters = parameter_map[entity.unit_number] --[[@as Parameters]]
					if parameters then
						bp.set_blueprint_entity_tags(index, {
							lane1_items = parameters.lane1_items and game.table_to_json(parameters.lane1_items),
							lane2_items = parameters.lane2_items and game.table_to_json(parameters.lane2_items),
							lane1_item_interval = parameters.lane1_item_interval,
							lane2_item_interval = parameters.lane2_item_interval,
							speed = parameters.speed,
							slow = parameters.slow
						})
					end
				elseif name == commons.overflow_name then
					local iopoint = context.iopoints[entity.unit_number]
					if iopoint then
						bp.set_blueprint_entity_tags(index, { overflows = iopoint.overflows })
					end
				end
			end
		end
	else
		local bp_entities = bp.get_blueprint_entities()
		if bp_entities then
			bp_count = #bp_entities
			for index = 1, bp_count do
				local bp_entity = bp_entities[index]
				if bp_entity then
					if bp_entity.name == commons.router_name then
						local router = (surface.find_entities_filtered { name = bp_entity.name, position = bp_entity.position, radius = 0.1 })[1]
						if router and not is_processed[router.link_id] then
							local node = structurelib.get_node(router)
							is_processed[router.link_id] = true
							local filters = routerlib.get_filters(router.get_inventory(defines.inventory.chest) --[[@as LuaInventory]])
							bp.set_blueprint_entity_tags(index, {
								logistic_belt2_node = (node ~= nil),
								filters = filters and game.table_to_json(filters),
								provided = node and dup_request(node.provided) --[[@as table]],
								requested = node and dup_request(node.requested) --[[@as table]],
								restrictions = node and tools.table_dup(node.restrictions) --[[@as table]],
							})
						end
					elseif locallib.container_type_map[game.entity_prototypes[bp_entity.name].type] then
						local container = (surface.find_entities_filtered { name = bp_entity.name, position = bp_entity.position, radius = 0.1 })[1]
						if container then
							local node = structurelib.get_node(container)
							if node then
								bp.set_blueprint_entity_tags(index, {
									logistic_belt2_node = true,
									provided = dup_request(node.provided) --[[@as table]],
									requested = dup_request(node.requested) --[[@as table]],
									restrictions = node and tools.table_dup(node.restrictions) --[[@as table]],
								})
							end
						end
					elseif bp_entity.name == sushi_name then
						local sushi = (surface.find_entities_filtered { name = bp_entity.name, position = bp_entity.position, radius = 0.1 })[1]
						if sushi then
							local parameters = locallib.get_parameters(sushi) --[[@as Parameters]]
							if parameters then
								bp.set_blueprint_entity_tags(index, {
									lane1_items = parameters.lane1_items and game.table_to_json(parameters.lane1_items),
									lane2_items = parameters.lane2_items and game.table_to_json(parameters.lane2_items),
									lane1_item_interval = parameters.lane1_item_interval,
									lane2_item_interval = parameters.lane2_item_interval,
									speed = parameters.speed,
									slow = parameters.slow
								})
							end
						end
					elseif bp_entity.name == commons.overflow_name then
						local overflow = (surface.find_entities_filtered { name = bp_entity.name, position = bp_entity.position, radius = 0.1 })[1]
						if overflow then
							local iopoint = context.iopoints[overflow.unit_number]
							if iopoint then
								bp.set_blueprint_entity_tags(index, { overflows = iopoint.overflows })
							end
						end
					end
				end
			end
		end
	end
end

local function on_register_bp(e)
	local player = game.get_player(e.player_index)
	---@cast player -nil
	local vars = tools.get_vars(player)
	if e.gui_type == defines.gui_type.item and e.item and e.item.is_blueprint and
		e.item.is_blueprint_setup() and player.cursor_stack and
		player.cursor_stack.valid_for_read and player.cursor_stack.is_blueprint and
		not player.cursor_stack.is_blueprint_setup() then
		vars.previous_bp = { blueprint = e.item, tick = e.tick }
	else
		vars.previous_bp = nil
	end
end

---@param player LuaPlayer
---@return LuaItemStack?
local function get_bp_to_setup(player)
	-- normal drag-select
	local bp = player.blueprint_to_setup
	if bp and bp.valid_for_read and bp.is_blueprint_setup() then return bp end

	-- alt drag-select (skips configuration dialog)
	bp = player.cursor_stack
	if bp and bp.valid_for_read and bp.is_blueprint and bp.is_blueprint_setup() then
		while bp.is_blueprint_book do
			bp = bp.get_inventory(defines.inventory.item_main)[bp.active_index]
		end
		return bp
	end

	-- update of existing blueprint
	local previous_bp = get_vars(player).previous_bp
	if previous_bp and previous_bp.tick == game.tick and previous_bp.blueprint and
		previous_bp.blueprint.valid_for_read and
		previous_bp.blueprint.is_blueprint_setup() then
		return previous_bp.blueprint
	end
end

---@param e EventData.on_player_setup_blueprint
tools.on_event(defines.events.on_player_setup_blueprint, function(e)
	local player = game.players[e.player_index]
	---@type table<integer, LuaEntity>
	local mapping = e.mapping.get()
	local bp = get_bp_to_setup(player)
	if bp then register_mapping(bp, mapping, player.surface) end
end)

tools.on_event(defines.events.on_player_rotated_entity,
	---@param e EventData.on_player_rotated_entity
	function(e)
		if e.entity.name == device_name then
			e.entity.direction = e.previous_direction
		end
	end)

tools.on_event(defines.events.on_gui_closed, on_register_bp)

---@param ev EventData.on_entity_cloned
local function on_entity_cloned(ev)
	local source = ev.source
	local dest = ev.destination
	local src_id = source.unit_number
	local source_name = source.name

	global.structure_changed = true
	local nsrc = structurelib.get_node(source)
	if nsrc then
		local ndst = structurelib.create_node(dest)
		ndst.requested = dup_request(nsrc.requested) --[[@as  table<string, RequestedItem>]]
		ndst.provided = dup_request(nsrc.provided) --[[@as  table<string, ProvidedItem>]]
		ndst.restrictions = tools.table_dup(nsrc.restrictions) --[[@as table]]
		locallib.recompute_container(ndst.container)
	elseif source_name == device_name or source_name == device_name then
		local entity = dest
		devicelib.initialize_device(entity)
	elseif source_name == commons.chest_name then
		dest.destroy()
	elseif not locallib.container_type_map[source.type] then
		dest.destroy()
	end
end

local clone_filter = tools.create_name_filter { { device_name, sushi_name }, devicelib.entities_to_destroy }
for _, name in pairs(locallib.container_types) do
	table.insert(clone_filter, { filter = 'type', type = name })
end

script.on_event(defines.events.on_entity_cloned, on_entity_cloned, clone_filter)

local picker_dolly_blacklist = function()
	if remote.interfaces["PickerDollies"] and remote.interfaces["PickerDollies"]["add_blacklist_name"] then
		for _, name in pairs({ device_name, sushi_name, commons.router_name }) do
			remote.call("PickerDollies", "add_blacklist_name", name)
		end
	end
end

local function on_init()
	picker_dolly_blacklist()
	global.clusters = {}
end

local function on_load()
	picker_dolly_blacklist()
end
tools.on_init(on_init)
tools.on_load(on_load)

---@param e EventData.on_entity_settings_pasted
local function on_entity_settings_pasted(e)
	local src = e.source
	local dst = e.destination

	if not src.valid or not dst.valid then return end

	local nsrc = structurelib.get_node(src)
	local ndst = structurelib.get_node(dst)

	if nsrc and ndst then
		ndst.requested = tools.table_deep_copy(nsrc.requested)
		ndst.provided = tools.table_deep_copy(nsrc.provided)
		ndst.restrictions = tools.table_dup(nsrc.restrictions)
	elseif src.name == sushi_name and dst.name == sushi_name then
		sushilib.do_paste(src, dst, e)
	elseif src.name == commons.overflow_name and dst.name == commons.overflow_name then
		local context = structurelib.get_context()
		local iopoint1 = context.iopoints[src.unit_number]
		local iopoint2 = context.iopoints[dst.unit_number]
		if iopoint1 and iopoint2 then
			iopoint2.overflows = iopoint1.overflows
		end
	end
end

tools.on_event(defines.events.on_entity_settings_pasted, on_entity_settings_pasted)

--------------------------------


-----------------------------------------------

---@param e EventData.on_gui_click
local function on_shift_button1(e)
	local player = game.players[e.player_index]

	local machine = player.entity_copy_source
	if machine and (machine.type == "assembling-machine" or machine.type == "furnace") then
		local selected = player.selected
		if not selected or not selected.valid then return end

		local node = structurelib.get_node(selected)
		if not node then
			return
		end

		local recipe = machine.get_recipe() or (machine.type == "furnace" and machine.previous_recipe)
		if not recipe then return end

		local requested = node.requested
		for _, ingredient in pairs(recipe.ingredients) do
			if ingredient.type == "item" then
				local item = ingredient.name
				local count = math.min(200, game.item_prototypes[item].stack_size)
				if not requested then
					requested = {}
					node.requested = requested
				end
				local req = tools.table_deep_copy(requested[item])
				if req then
					req.count = count
					req.delivery = stacksize_to_delivery(count)
				else
					requested[item] = {
						count = count,
						item = item,
						delivery = stacksize_to_delivery(count),
						remaining = 0
					}
				end
			end
		end
		locallib.add_monitored_node(node)
	end
end

script.on_event(commons.shift_button1_event, on_shift_button1)

---@param node Node
local function collect_node_entities(node)
	local context = structurelib.get_context()
	local entities = {}
	if not node then
		return
	end
	if node.inputs then
		for _, input in pairs(node.inputs) do
			table.insert(entities, input.device)
		end
	end
	if node.outputs then
		for _, output in pairs(node.outputs) do
			table.insert(entities, output.device)
		end
	end
	if node.container.name == commons.router_name then
		local cluster = context.clusters[node.container.link_id]
		if cluster then
			for _, router in pairs(cluster.routers) do
				table.insert(entities, router)
			end
		end
	else
		table.insert(entities, node.container)
	end
	return entities
end

local teleport_entities_to_clear = tools.table_copy(commons.entities_to_clear)
table.insert(teleport_entities_to_clear, commons.overflow_loader_name)
table.insert(teleport_entities_to_clear, commons.device_loader_name)
table.insert(teleport_entities_to_clear, commons.sushi_loader_name)

local function factory_organizer_install()
	if remote.interfaces["factory_organizer"] then
		remote.add_interface("logistic_belt2_move", {
			---@param entity LuaEntity
			---@return LuaEntity[] ?
			collect = function(entity)
				local name = entity.name
				local id = entity.unit_number

				local context = structurelib.get_context()
				if name == commons.device_name or name == commons.overflow_name then
					local iopoint = context.iopoints[id]
					if not iopoint then return nil end
					return collect_node_entities(iopoint.node)
				elseif name == commons.router_name then
					local cluster = context.clusters[entity.link_id]
					if cluster and cluster.node then
						return collect_node_entities(cluster.node)
					end
					return nil
				elseif locallib.container_type_map[entity.type] then
					local node = context.nodes[id]
					if not node then
						return nil
					end
					return collect_node_entities(node)
				end
			end,

			---@param entity LuaEntity
			preteleport = function(entity)
				local name = entity.name
				if name == commons.device_name or name == commons.overflow_name then
					locallib.clear_entities(entity, teleport_entities_to_clear)
					local context = structurelib.get_context()
					local iopoint = context.iopoints[entity.unit_number]
					if iopoint then
						if name == commons.device_name then
							structurelib.disconnect_iopoint(iopoint)
						else
							locallib.disconnect_overflow(iopoint)
						end
						iopoint.container = nil
						iopoint.inventory = nil
					end
				elseif name == commons.sushi_name then
					locallib.clear_entities(entity, teleport_entities_to_clear)
				end
			end,
			---@param data {entity:LuaEntity, old_pos:MapPosition, old_direction:number}
			teleport = function(data)
				local context = structurelib.get_context()
				local entity = data.entity
				local id = entity.unit_number
				local name = entity.name

				if name == commons.device_name then
					local iopoint = context.iopoints[id]
					if not iopoint then return end
					locallib.create_loader(entity, commons.device_loader_name)
					locallib.add_monitored_device(iopoint.device)
				elseif name == commons.sushi_name then
					sushilib.create_new_sushi(nil, entity)
				elseif name == commons.overflow_name then
					local iopoint = context.iopoints[id]
					if not iopoint then return end
					locallib.create_loader(entity, commons.overflow_loader_name)
					locallib.add_monitored_device(iopoint.device)
				elseif name == commons.router_name then
					local cluster = context.clusters[entity.link_id]
					if cluster and cluster.node then
						locallib.add_monitored_node(cluster.node)
					end
					return nil
				end
			end
		})
		remote.call("factory_organizer", "add_collect_method", commons.overflow_name, "logistic_belt2_move", "collect")
		remote.call("factory_organizer", "add_collect_method", commons.device_name, "logistic_belt2_move", "collect")
		remote.call("factory_organizer", "add_collect_method", commons.router_name, "logistic_belt2_move", "collect")
		remote.call("factory_organizer", "add_collect_method_by_type", "container", "logistic_belt2_move", "collect")
		remote.call("factory_organizer", "add_collect_method_by_type", "logistic-container", "logistic_belt2_move", "collect")
		remote.call("factory_organizer", "add_collect_method_by_type", "infinity-container", "logistic_belt2_move", "collect")
		remote.call("factory_organizer", "add_collect_method_by_type", "linked-container", "logistic_belt2_move", "collect")
		remote.call("factory_organizer", "add_preteleport_method", commons.device_name, "logistic_belt2_move", "preteleport")
		remote.call("factory_organizer", "add_preteleport_method", commons.sushi_name, "logistic_belt2_move", "preteleport")
		remote.call("factory_organizer", "add_preteleport_method", commons.overflow_name, "logistic_belt2_move", "preteleport")
		remote.call("factory_organizer", "add_teleport_method", commons.device_name, "logistic_belt2_move", "teleport")
		remote.call("factory_organizer", "add_teleport_method", commons.sushi_name, "logistic_belt2_move", "teleport")
		remote.call("factory_organizer", "add_teleport_method", commons.overflow_name, "logistic_belt2_move", "teleport")
		local names = tools.table_copy(commons.entities_to_clear)
		table.insert(names, commons.device_loader_name)
		table.insert(names, commons.sushi_loader_name)
		table.insert(names, commons.overflow_loader_name)
		remote.call("factory_organizer", "add_not_moveable", names)
	end
end

tools.on_load(factory_organizer_install)



return devicegui
