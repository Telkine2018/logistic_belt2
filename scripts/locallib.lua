local commons = require("scripts.commons")
local tools = require("scripts.tools")

local locallib = {}

local prefix = commons.prefix
local debug = tools.debug
local cdebug = tools.cdebug
local get_vars = tools.get_vars
local strip = tools.strip

local get_front = tools.get_front
local get_back = tools.get_back
local get_opposite_direction = tools.get_opposite_direction

local BELT_SPEED_FOR_60_PER_SECOND = 60 / 60 / 8


locallib.BELT_SPEED_FOR_60_PER_SECOND = BELT_SPEED_FOR_60_PER_SECOND

locallib.belt_types = {
	"transport-belt",
	"underground-belt",
	"splitter",
	"linked-belt"
}

locallib.belt_and_loader_types = {
	"transport-belt",
	"underground-belt",
	"splitter",
	"linked-belt",
	"loader",
	"loader-1x1"
}


locallib.container_types = {
	"container",
	"infinity-container",
	"linked-container",
	"logistic-container",
	"assembling-machine"
}

locallib.container_type_map = {
}
for _, name in pairs(locallib.container_types) do
	locallib.container_type_map[name] = true
end

locallib.excluded_containers =
{
	["factory_graph-recipe-symbol"] = true,
	["factory_graph-product-symbol"] = true,
	["factory_graph-unresearched-symbol"] = true,
	["factory_graph-product-selector"] = true
}

locallib.sushi_positions = {
	{ { { 0, -1 }, { -0.25, 0.55 } }, { { 0, -1 }, { 0.25, 0.55 } } },
}


locallib.output_positions2 = {
	{ { { 0, 0 }, { -0.25, 0.55 } }, { { 0, 0 }, { 0.25, 0.55 } } },
}

locallib.input_positions2  = {
	{ { { -0.25, -0.1 }, { 0, 0 } }, { { 0.25, -0.1 }, { 0, 0 } } },
}

local entities_to_destroy  = tools.table_copy(commons.entities_to_clear) or {}
table.insert(entities_to_destroy, commons.device_loader_name)
table.insert(entities_to_destroy, commons.sushi_loader_name)
table.insert(entities_to_destroy, commons.overflow_loader_name)
locallib.entities_to_destroy = entities_to_destroy

---@param master LuaEntity
---@param loader_name string
---@return LuaEntity
function locallib.create_loader(master, loader_name)
	local loader = master.surface.create_entity {
		name = loader_name,
		position = master.position,
		force = master.force,
		direction = tools.get_opposite_direction(master.direction) --[[@as defines.direction]],
		create_build_effect_smoke = false
	}
	loader.loader_type = "output"
	return loader --[[@as LuaEntity]]
end

---@param master LuaEntity
---@return LuaEntity?
function locallib.find_loader(master)
	local entities = master.surface.find_entities_filtered { name = commons.device_loader_name, position = master.position }
	if #entities == 1 then return entities[1] end
	return nil
end

---@param device LuaEntity
---@param entity_names string[]?
function locallib.clear_entities(device, entity_names)
	if not entity_names then
		entity_names = commons.entities_to_clear
	end
	local entities = device.surface.find_entities_filtered { position = device.position, name = entity_names }
	for _, e in pairs(entities) do
		e.destroy()
	end
end

---@param entity LuaEntity
---@param direction integer | defines.direction
---@param positions MapPosition[][]
---@param count integer
---@param name string
---@return table
function locallib.create_inserters(entity, direction, positions, count, name)
	local position = entity.position
	local surface = entity.surface
	local inserters = {}
	for _, pick_drop in pairs(positions) do
		for i = 1, count do
			local inserter = surface.create_entity({
				name = name,
				position = entity.position,
				force = entity.force,
				direction = direction,
				create_build_effect_smoke = false
			}) --[[@as LuaEntity]]
			local pick = tools.get_local_disp(direction, pick_drop[1])
			inserter.pickup_position = { pick.x + position.x, pick.y + position.y }
			local drop = tools.get_local_disp(direction, pick_drop[2])
			inserter.drop_position = { drop.x + position.x, drop.y + position.y }
			inserter.operable = false
			inserter.destructible = false
			inserter.inserter_stack_size_override = 1

			cdebug(commons.trace_inserter,
				"create new: " .. inserter.name .. " direction=" .. direction .. ",stack=" .. inserter.inserter_stack_size_override)
			cdebug(commons.trace_inserter, "position: " ..
				strip(position) .. " pickup=" .. strip(inserter.pickup_position) .. " drop=" .. strip(inserter.drop_position))
			table.insert(inserters, inserter)
		end
	end
	return inserters
end

---@param device LuaEntity
---@param name string
---@return LuaEntity
function locallib.create_combinator(device, name)
	local combinator = device.surface.create_entity {
		name = prefix .. "-" .. name,
		position = device.position,
		force = device.force,
		create_build_effect_smoke = false
	}
	return combinator --[[@as LuaEntity]]
end

---@param belt_speed number
---@return integer
function locallib.get_inserter_count_from_speed(belt_speed)
	return math.ceil(belt_speed / BELT_SPEED_FOR_60_PER_SECOND)
end

function locallib.get_inserter_count(entity)
	return locallib.get_inserter_count_from_speed(entity.prototype.belt_speed)
end

---@param entity LuaEntity
function locallib.save_unit_number_in_circuit(entity)
	local cb = entity.get_or_create_control_behavior() --[[@as LuaInserterControlBehavior]]
	cb.circuit_condition = {
		condition = {
			comparator = "=",
			first_signal = { type = "virtual", name = "signal-A" },
			constant = entity.unit_number
		}
	}
end

---@param entity LuaEntity
---@param parameters Parameters
---@return Parameters
function locallib.restore_saved_parameters(entity, parameters)
	local cb = entity.get_or_create_control_behavior() --[[@as LuaInserterControlBehavior]]
	local found = false
	local condition = cb.circuit_condition
	if condition then
		local old_id = condition.condition.constant
		if old_id then
			if global.saved_parameters then
				local p = global.saved_parameters[old_id]
				if p then
					debug("Found saved parameters")
					parameters = p
					global.parameters[entity.unit_number] = p
					found = true
					global.saved_parameters[old_id] = nil
				end
			end
		end
	end

	locallib.save_unit_number_in_circuit(entity)
	return parameters
end

---@param frame LuaGuiElement
---@param caption string
---@param close_button_name string?
function locallib.add_title(frame, caption, close_button_name)
	local titlebar = frame.add { type = "flow", direction = "horizontal" }
	local title = titlebar.add {
		type = "label",
		style = "caption_label",
		caption = { caption }
	}
	local handle = titlebar.add {
		type = "empty-widget",
		style = "draggable_space"
	}
	handle.style.horizontally_stretchable = true
	handle.style.top_margin = 4
	handle.style.height = 26
	-- handle.style.width = width

	local flow_buttonbar = titlebar.add {
		type = "flow",
		direction = "horizontal"
	}
	flow_buttonbar.style.top_margin = 0
	if not close_button_name then
		close_button_name = prefix .. "_close_button"
	end
	flow_buttonbar.add {
		type = "sprite-button",
		name = close_button_name,
		style = "frame_action_button",
		sprite = "utility/close_white",
		mouse_button_filter = { "left" }
	}
end

---@param player LuaPlayer
function locallib.close_ui(player)
	local frame = player.gui.relative[commons.device_panel_name] or player.gui.left[commons.device_panel_name]
	if frame then
		frame.destroy()
	end
	frame = player.gui.left[commons.sushi_panel_name]
	if frame then
		frame.destroy()
	end
	frame = player.gui.left[commons.overflow_panel_name]
	if frame then
		frame.destroy()
	end
end

---@param event EventData.on_gui_closed
function locallib.on_gui_closed(event)
	local player = game.players[event.player_index]
	locallib.close_ui(player)
end

tools.on_gui_click(prefix .. "_close_button", locallib.on_gui_closed)

--- Used by sushilib
---@param master LuaEntity
---@param create boolean?
---@return Parameters
function locallib.get_parameters(master, create)
	local all = global.parameters
	if not all then
		all = {}
		global.parameters = all
	end
	local parameters = all[master.unit_number]
	if not parameters and create then
		parameters = {}
		all[master.unit_number] = parameters
	end
	return parameters
end

---@param device LuaEntity
---@param add_neighbors boolean?
function locallib.add_monitored_device(device, add_neighbors)
	if not global.monitored_devices then
		global.monitored_devices = {}
	end
	global.monitored_devices[device.unit_number] = device
	if tools.tracing then
		debug("ADD Monitored device: " .. tools.strip(device.position))
	end
	if add_neighbors then
		local context = locallib.get_context()
		local iopoint = context.iopoints[device.unit_number]
		if iopoint then
			for _, other in pairs(iopoint.connection.inputs) do
				global.monitored_devices[other.id] =  other.device
			end
			for _, other in pairs(iopoint.connection.outputs) do
				global.monitored_devices[other.id] =  other.device
			end
		end
	end
	global.monitoring = true
	global.structure_changed = true
	global.monitored_delay = nil
	local context = locallib.get_context()
	context.structure_tick = game.tick
end

local add_monitored_device = locallib.add_monitored_device

---@param surface LuaSurface
---@param position MapPosition
---@param add_neighbors boolean?
function locallib.add_device_in_range(surface, position, add_neighbors)
	local entities = surface.find_entities_filtered{position=position, name=commons.device_name, radius=6}
	if #entities == 0 then return end
	for _, entity in pairs(entities) do
		add_monitored_device(entity, add_neighbors)
	end
end

---@param iopoints table<int, IOPoint>
function locallib.add_monitored_iopoints(iopoints)
	if not iopoints then return end
	for _, iopoint in pairs(iopoints) do
		locallib.add_monitored_device(iopoint.device)
	end
end

---@param node Node
function locallib.add_monitored_node(node)
	locallib.add_monitored_iopoints(node.outputs)
	locallib.add_monitored_iopoints(node.inputs)
end

---@param container LuaEntity
function locallib.recompute_container(container)
	local pos = container.position
	local w = container.tile_width / 2 + 3
	local h = container.tile_height / 2 + 3

	local search_box = { { pos.x - w, pos.y - h }, { pos.x + w, pos.y + h } }
	local devices = container.surface.find_entities_filtered { name = { commons.device_name, commons.overflow_name }, area = search_box }
	for _, d in ipairs(devices) do
		locallib.add_monitored_device(d)
	end
end

--- @return Context
function locallib.get_context()
	return {}
end

---@param device LuaEntity
---@return boolean
---@return boolean?
function locallib.adjust_direction(device)
	local direction = device.direction
	local position = device.position
	local front_pos = get_front(direction, position)

	-- device.direction => belt
	local entities = device.surface.find_entities_filtered { position = front_pos, type = locallib.belt_types }
	if (#entities > 0) then
		debug("no change direction")
		return true, false
	end

	local opposite     = get_opposite_direction(direction) --[[@as defines.direction]]
	local opposite_pos = get_front(opposite, position)
	entities           = device.surface.find_entities_filtered { position = opposite_pos, type = locallib.belt_types }
	if (#entities > 0) then
		debug("invert direction:" .. opposite)
		device.direction = opposite
		return true, true
	end

	entities = device.surface.find_entities_filtered { position = front_pos, type = locallib.container_types }
	if (#entities > 0) then
		debug("invert direction (container):" .. opposite)
		device.direction = opposite
		return true, true
	end

	entities = device.surface.find_entities_filtered { position = opposite_pos, type = locallib.container_types }
	if (#entities > 0) then
		debug("no change direction")
		return true, false
	end

	debug("no entities found")
	return false
end

---@param iopoint IOPoint
function locallib.disconnect_overflow(iopoint)
	local node = iopoint.node
	if node then
		node.overflows[iopoint.id] = nil
		if not next(node.overflows) then
			node.overflows = nil
		end
	end
end

---@param entity LuaEntity
---@return number?
function locallib.get_belt_speed(entity)
	-- device.direction => belt
	local entities = entity.surface.find_entities_filtered {
		position = tools.get_front(entity.direction, entity.position),
		type = locallib.belt_and_loader_types
	}
	if (#entities == 0) then
		return nil
	else
		return entities[1].prototype.belt_speed
	end
end

---@param node Node
function locallib.update_buffer_size(node)
    local buffer_size = node.buffer_size
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
end


return locallib
