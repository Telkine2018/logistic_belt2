local commons = require "scripts.commons"
local tools = require "scripts.tools"
local locallib = require "scripts.locallib"
local sushilib = require "scripts.sushilib"
local routerlib = require "scripts.routerlib"
local inspectlib = require "scripts.inspect"
local structurelib = require "scripts.structurelib"
local nodelib = require "scripts.nodelib"
local overflowlib = require "scripts.overflow"

local prefix = commons.prefix
local trace_scan = false
local SAVED_SCAVENGE_DELAY = 120 * 60

local debug = tools.debug
local cdebug = tools.cdebug
local get_vars = tools.get_vars
local strip = tools.strip

-----------------------------------------------------

local devicelib = {}

local device_name = commons.device_name
local inserter_name = commons.inserter_name
local filter_name = commons.filter_name
local device_loader_name = commons.device_loader_name
local slow_filter_name = commons.slow_filter_name
local sushi_name = commons.sushi_name
local sushi_loader_name = commons.sushi_loader_name
local overflow_name = commons.overflow_name

local device_panel_name = commons.device_panel_name
local sushi_panel_name = commons.sushi_panel_name

local link_to_output_chest_name = prefix .. "-link_to_output_chest"
local is_input_filtered_name = prefix .. "-is_input_filtered"
local request_count_name = prefix .. "-request_count"

local container_types_map = tools.table_map(locallib.container_types, function(key, value) return value, true end)

local entities_to_clear = commons.entities_to_clear
local entities_to_destroy = locallib.entities_to_destroy

local get_front = tools.get_front
local get_back = tools.get_back
local get_opposite_direction = tools.get_opposite_direction


local create_loader = locallib.create_loader
local clear_entities = locallib.clear_entities
local adjust_direction = locallib.adjust_direction

local function process_parameters()
	if global.saved_parameters ~= nil and next(global.saved_parameters) then
		local tick = game.tick
		if not global.saved_time then
			global.saved_time = tick
		elseif global.saved_time < tick - SAVED_SCAVENGE_DELAY then
			global.saved_time = tick
			local removed = {}
			local limit = tick - SAVED_SCAVENGE_DELAY
			for id, parameters in pairs(global.saved_parameters) do
				if parameters.tick < limit then
					table.insert(removed, id)
				end
			end
			if #removed > 0 then
				for _, id in pairs(removed) do
					global.saved_parameters[id] = nil
				end
			end
		end
	end
end

local function process_monitored_object()
	if not global.structure_changed and not global.monitoring then return end

	if not global.monitored_delay then
		global.monitored_delay = 12
		return
	end
	global.monitored_delay = global.monitored_delay - 1
	if global.monitored_delay > 0 then
		return
	end

	local saved_tracing = tools.is_tracing()
	tools.set_tracing(false)
	local context = structurelib.get_context()

	---@type table<integer, Node>
	local nodes = global.monitored_nodes
	if not nodes then
		nodes                  = {}
		global.monitored_nodes = nodes
	end

	local monitored_new_list = global.monitored_new_list
	if not monitored_new_list then
		monitored_new_list = {}
		global.monitored_new_list = monitored_new_list
	end

	local monitored_devices = global.monitored_devices

	local monitored_err_ids = global.monitored_err_ids 
	if not monitored_err_ids then
		monitored_err_ids = {}
		global.monitored_err_ids = monitored_err_ids
	end

	if monitored_devices then
		local done_map = global.monitored_done_map
		if not done_map then
			done_map = {}
			global.monitored_done_map = done_map
		end

		local key, device
		for i = 1, 2 do
			key, device = next(monitored_devices)

			---@cast device LuaEntity
			if device == nil then
				global.monitored_devices = nil
				goto node_scan
			end
			monitored_devices[key] = nil

			if not done_map[key] then
				if device.valid then
					if device.name == device_name then
						local success, _, ids = nodelib.rebuild_network(device)
						if not success then
							monitored_new_list[device.unit_number] = device
						elseif ids then
							local iopoint = context.iopoints[device.unit_number]
							if iopoint then
								nodes[iopoint.id] = iopoint.node
							end
							for _, id in pairs(ids) do
								done_map[id] = true
								if monitored_err_ids[id]  then
									rendering.destroy(monitored_err_ids[id])
									monitored_err_ids[id] = nil
								end
							end
						end
					elseif device.name == commons.overflow_name then
						local iopoint = context.iopoints[device.unit_number]
						if iopoint and not overflowlib.try_connect(iopoint) then
							monitored_new_list[device.unit_number] = device
							nodes[iopoint.id] = iopoint.node
						else
							done_map[device.unit_number] = true
						end
					end
				end
			end
		end
		tools.set_tracing(saved_tracing)
		if next(monitored_devices) then
			return
		end
	end

	::node_scan::
	for _, node in pairs(nodes) do
		structurelib.reset_network(node)
	end

	if global.update_map then
		for id, parameters in pairs(global.update_map) do
			local iopoint = context.iopoints[id]
			if iopoint then
				---@cast parameters UpdateDeviceParameters
				if iopoint.overflows then
					if parameters.request_table then
						for _, request in pairs(parameters.request_table) do
							iopoint.overflows[request.item] = request.count
						end
					end
				elseif parameters.request_table then
					local node
					if iopoint.is_output then
						local connection = iopoint.connection
						local _, input = next(connection.inputs)
						if input then
							node = input.node
						end
					else
						node = iopoint.node
					end
					if node then
						for _, request in pairs(parameters.request_table) do
							nodelib.add_request(node, request.item, request.count, nil, node.requested)
						end
					end
				end
			end
		end
		global.update_map = nil
	end

	global.structure_changed = nil
	global.monitoring = nil
	global.monitored_devices = monitored_new_list
	global.monitored_new_list = nil
	global.monitored_nodes = nil
	global.monitored_done_map = nil
	if next(monitored_new_list) then
		for id, device in pairs(monitored_new_list) do
			if not monitored_err_ids[id] and device.valid then
				monitored_err_ids[id] = rendering.draw_sprite {
					target = device,
					surface = device.surface,
					sprite = prefix .. "_error",
					x_scale = 0.6, y_scale = 0.6, target_offset = { -0.2, 0.2 } }
			end
		end
	end
	debug("STOP MONITORING")
	tools.set_tracing(saved_tracing)
end

tools.on_nth_tick(10, process_monitored_object)

tools.on_nth_tick(60 * 60, process_parameters)

---@param device Device
local function initialize_device(device)
	device.rotatable = false
	device.active = false
	create_loader(device, device_loader_name)
	if not nodelib.rebuild_network(device) then
		locallib.add_monitored_device(device)
	end
end


---@param entity LuaEntity
---@param tags Tags
---@param player_index integer?
local function on_build(entity, tags, player_index)
	if not entity or not entity.valid then return end

	global.structure_changed = true
	local name = entity.name
	if name == device_name then
		entity.active = false
		if not adjust_direction(entity) then
			entity.rotatable = false
			create_loader(entity, device_loader_name)
			locallib.add_monitored_device(entity)
			return
		end
		initialize_device(entity)
	elseif name == overflow_name then
		overflowlib.on_built_entity(entity, tags)
	elseif name == sushi_name then
		sushilib.on_build(entity, tags, player_index)
	elseif name == commons.router_name then
		routerlib.on_build(entity, tags)
	elseif name == commons.uploader_name then
		local loader = entity
		loader.loader_type = "input"
	elseif locallib.container_type_map[entity.type] then
		if tags and tags.logistic_belt2_node then
			local node = structurelib.create_node(entity)
			node.requested = tags.requested --[[@as table<string, RequestedItem> ]]
			node.provided = tags.provided --[[@as table<string, ProvidedItem> ]]
			node.restrictions = tags.restrictions --[[@as table<string, boolean> ]]
			node.buffer_size = tags.buffer_size or 4 --[[@as integer ]]
		end
		locallib.recompute_container(entity)
	else
		locallib.recompute_container(entity)
		locallib.add_device_in_range(entity.surface, entity.position)
	end
end

---@param ev EventData.on_robot_built_entity
local function on_robot_built(ev)
	local entity = ev.created_entity

	on_build(entity, ev.tags)
end

---@param ev EventData.script_raised_built
local function on_script_built(ev)
	local entity = ev.entity

	on_build(entity, ev.tags)
end

---@param ev EventData.script_raised_revive
local function on_script_revive(ev)
	local entity = ev.entity

	on_build(entity, ev.tags)
end

---@param ev EventData.on_built_entity
local function on_player_built(ev)
	local entity = ev.created_entity

	on_build(entity, ev.tags, ev.player_index)
end

local build_filter = tools.table_concat {
	{
		{ filter = 'name', name = device_name },
		{ filter = 'name', name = sushi_name },
		{ filter = 'name', name = overflow_name },
		{ filter = 'name', name = commons.router_name },
		{ filter = 'name', name = commons.uploader_name }
	},
	tools.table_imap(locallib.container_types, function(v) return { filter = 'type', type = v } end),
	tools.table_imap(locallib.belt_types, function(v) return { filter = 'type', type = v } end)
}

tools.on_event(defines.events.on_built_entity, on_player_built, build_filter)
tools.on_event(defines.events.on_robot_built_entity, on_robot_built, build_filter)
tools.on_event(defines.events.script_raised_built, on_script_built, build_filter)
tools.on_event(defines.events.script_raised_revive, on_script_revive)



local function on_mined(ev)
	---@type LuaEntity
	local entity = ev.entity
	if not entity.valid then return end

	local name = entity.name
	if name == device_name or name == sushi_name then
		tools.close_ui(entity.unit_number, locallib.close_ui)

		-- local buffer = ev.buffer and ev.buffer.valid and ev.buffer
		clear_entities(entity, entities_to_destroy)
		structurelib.on_mined_iopoint(entity)
	elseif name == commons.router_name then
		routerlib.on_mined(ev)
	elseif name == overflow_name then
		overflowlib.on_mined(entity)
	elseif locallib.container_type_map[entity.type] then
		structurelib.on_mined_container(entity)
	else
		locallib.add_device_in_range(entity.surface, entity.position, true)
	end
end

local function on_player_mined_entity(ev)
	on_mined(ev)
end

local mine_filter = tools.table_concat {
	{
		{ filter = 'name', name = device_name },
		{ filter = 'name', name = sushi_name },
		{ filter = 'name', name = commons.overflow_name },
		{ filter = 'name', name = commons.router_name }
	},
	tools.table_imap(locallib.container_types, function(v) return { filter = 'type', type = v } end),
	tools.table_imap(locallib.belt_types, function(v) return { filter = 'type', type = v } end)
}

script.on_event(defines.events.on_player_mined_entity, on_player_mined_entity, mine_filter)
script.on_event(defines.events.on_robot_mined_entity, on_mined, mine_filter)
script.on_event(defines.events.on_entity_died, on_mined, mine_filter)
script.on_event(defines.events.script_raised_destroy, on_mined, mine_filter)

---@param surface_index integer
local function delete_all_from_surface(surface_index)
	local context = structurelib.get_context()

	---@type IOPoint[]
	local iopoints_to_delete = {}
	for _, iopoint in pairs(context.iopoints) do
		if iopoint.device.surface_index == surface_index then
			table.insert(iopoints_to_delete, iopoint)
		end
	end

	---@type Node[]
	local node_to_delete = {}
	for _, node in pairs(context.nodes) do
		if node.container.surface_index == surface_index then
			table.insert(node_to_delete, node)
		end
	end

	for _, iopoint in pairs(iopoints_to_delete) do
		structurelib.on_mined_iopoint(iopoint.device)
	end

	for _, node in pairs(node_to_delete) do
		structurelib.delete_node(node, node.id)
	end
end

tools.on_event(defines.events.on_pre_surface_cleared,
	---@param e EventData.on_pre_surface_cleared
	function(e)
		local surface_index = e.surface_index

		delete_all_from_surface(surface_index)
	end
)

tools.on_event(defines.events.on_pre_surface_deleted,
	---@param e EventData.on_pre_surface_deleted
	function(e)
		local surface_index = e.surface_index

		delete_all_from_surface(surface_index)
	end
)

--------------------------------------------

---@param device LuaEntity
---@param parameters UpdateDeviceParameters
function devicelib.update_parameters(device, parameters)
	---@type table<integer, UpdateDeviceParameters>
	local update_map = global.update_map
	if not update_map then
		update_map = {}
		global.update_map = update_map
	end
	update_map[device.unit_number] = parameters
end

--------------------------------------------

devicelib.rebuild_network = nodelib.rebuild_network
devicelib.entities_to_destroy = entities_to_destroy
devicelib.initialize_device = initialize_device

return devicelib
