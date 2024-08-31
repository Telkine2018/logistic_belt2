local migration = require("__flib__.migration")

local commons = require "scripts.commons"
local tools = require "scripts.tools"
local locallib = require "scripts.locallib"
local config = require "scripts.config"

local prefix = commons.prefix

local device_name = commons.device_name
local inserter_name = commons.inserter_name
local filter_name = commons.filter_name
local device_loader_name = commons.device_loader_name
local overflow_name = commons.overflow_name

local debug = tools.debug
local cdebug = tools.cdebug
local get_vars = tools.get_vars
local strip = tools.strip
local get_opposite_direction = tools.get_opposite_direction
local get_back = tools.get_back
local get_front = tools.get_front
local create_inserters = locallib.create_inserters
local clear_entities = locallib.clear_entities

local table_insert = table.insert

local trace_scan
local tracing = tools.tracing


local structurelib = {}

---@type Context
local context

---@param context Context
local function compute_node_count(context)
    context.node_count = table_size(context.nodes)
    context.node_per_tick = context.node_count / 60
    context.node_index = 0
end

---@param content table<string, any>
local function purge_content(content)
    if not content then return end

    local to_delete = {}
    for item, _ in pairs(content) do
        if not game.item_prototypes[item] then
            to_delete[item] = true
        end
    end
    for item, _ in pairs(to_delete) do
        content[item] = nil
    end
end


---@return Context
function structurelib.get_context()
    if context then
        return context
    end
    context = global.context
    if context then
        return context
    end
    context = {
        nodes = {},
        iopoints = {},
        clusters = {},
        node_count = 0,
        node_index = 0,
        node_per_tick = 0,
        current_node_id = nil
    }
    global.context = context
    return context
end

local get_context = structurelib.get_context

---@param iopoint IOPoint
local function disconnect_iopoint(iopoint)
    if iopoint.overflows then
        locallib.disconnect_overflow(iopoint)
    else
        local connection = iopoint.connection
        if connection then
            if iopoint.is_output then
                connection.outputs[iopoint.id] = nil
            else
                connection.inputs[iopoint.id] = nil
            end
        end
        local node = iopoint.node
        if node then
            node.inputs[iopoint.id] = nil
            node.outputs[iopoint.id] = nil

            if node.routings then
                local removed_items
                for key, routing_map in pairs(node.routings) do
                    routing_map[iopoint.id] = nil
                    if not next(routing_map) then
                        if not removed_items then
                            removed_items = { key }
                        else
                            table.insert(removed_items, key)
                        end
                    end
                end
                if removed_items then
                    for _, item in pairs(removed_items) do
                        node.routings[item] = nil
                    end
                    if not next(node.routings) then
                        node.routings = nil
                    end
                end
            end

            if iopoint.is_output then
                structurelib.rebuild_output_map(node)
            end
        end
        iopoint.node = nil
        iopoint.container = nil
        iopoint.inventory = nil
    end
end
structurelib.disconnect_iopoint = disconnect_iopoint

---@param node Node
local function rebuild_output_map(node)
    local map = {}
    for _, output in pairs(node.outputs) do
        if output.connection then
            for _, input in pairs(output.connection.inputs) do
                local outputs = map[input.node.id]
                if outputs then
                    table.insert(outputs, output)
                else
                    map[input.node.id] = { output }
                end
            end
        end
    end
    node.output_map = map
end
structurelib.rebuild_output_map = rebuild_output_map

---@param node Node
function structurelib.rebuild_output_map_for_parent(node)
    local set = {}
    if node.inputs then
        for _, iopoint in pairs(node.inputs) do
            local connection = iopoint.connection
            for _, output in pairs(connection.outputs) do
                if not set[output.node.id] then
                    set[output.node.id] = true
                    rebuild_output_map(output.node)
                end
            end
        end
    end
end

---@param container LuaEntity
---@return LuaInventory?
function structurelib.get_inventory(container)
    local inventory
    if container.type == "assembling-machine" then
        if container.name ~= "supply-depot" then
            inventory = container.get_inventory(defines.inventory.assembling_machine_output) --[[@as LuaInventory]]
        else
            local chest = (container.surface.find_entities_filtered { position = container.position, type = "container" })[1]
            if chest then
                inventory = chest.get_inventory(defines.inventory.chest) --[[@as LuaInventory]]
            end
        end
    else
        inventory = container.get_inventory(defines.inventory.chest) --[[@as LuaInventory]]
    end
    return inventory
end

---@param container LuaEntity
---@return Node
function structurelib.create_node(container)
    local context = get_context()
    local id = container.unit_number

    ---@type Node
    local node = {
        id = container.unit_number,
        container = container,
        inputs = {},
        outputs = {},
        contents = {},
        buffer_size = config.io_buffer_size
    }
    if container.type == "assembling-machine" then
        if container.name ~= "supply-depot" then
            node.inventory = container.get_inventory(defines.inventory.assembling_machine_output) --[[@as LuaInventory]]
        else
            local chest = (container.surface.find_entities_filtered { position = container.position, type = "container" })[1]
            if chest then
                id = chest.unit_number
                local existing = context.nodes[id]
                if existing then
                    return existing
                end
                node.container = chest
                node.id = id
                node.inventory = chest.get_inventory(defines.inventory.chest) --[[@as LuaInventory]]
            end
        end
    else
        node.inventory = container.get_inventory(defines.inventory.chest) --[[@as LuaInventory]]
    end
    ---@cast id -nil
    context.nodes[id] = node
    compute_node_count(context)
    return node
end

---@param node Node
---@return boolean
function structurelib.is_orphan(node)
    return ((not node.inputs or next(node.inputs) == nil) and (not node.outputs or next(node.outputs) == nil))
end

---@param node Node
---@param clean boolean?
function structurelib.reset_node(node, clean)
    -- remove node
    if structurelib.is_orphan(node) then
        structurelib.delete_node(node, node.id)
        return
    end

    if node.requested then
        for _, req in pairs(node.requested) do
            req.remaining = 0
        end
    end
    if node.provided then
        for _, provided in pairs(node.provided) do
            provided.provided = 0
        end
    end
    if node.inputs and clean then
        for _, input in pairs(node.inputs) do
            input.inventory.clear()
        end
    end
    node.routings = nil
    node.last_reset_tick = game.tick
    node.previous = nil
    node.previous_provided = nil
    node.saturated = false
    node.remaining = nil
end

local reset_node = structurelib.reset_node

---@param node Node
local function reset_network(node)
    if node.last_reset_tick == game.tick then return end

    local nodes = structurelib.get_connected_nodes(node)
    for _, n in pairs(nodes) do
        reset_node(n)
    end
end
structurelib.reset_network = reset_network

---@param node  Node
---@param id  integer
function structurelib.delete_node(node, id)
    if not node then return end
    for _, iopoint in pairs(node.inputs) do
        local connection = iopoint.connection
        connection.inputs[iopoint.id] = nil
        context.iopoints[iopoint.id] = nil

        for _, output in pairs(connection.outputs) do
            rebuild_output_map(output.node)
        end
    end

    for _, iopoint in pairs(node.outputs) do
        local connection = iopoint.connection
        connection.outputs[iopoint.id] = nil
        context.iopoints[iopoint.id] = nil
    end

    context.nodes[id] = nil
    context.current_node_id = nil
    compute_node_count(context)
    --debug("remove node => " .. tostring(id))
end

---@param entity LuaEntity
function structurelib.on_mined_container(entity)
    local context = get_context()
    local id = entity.unit_number
    local node = context.nodes[id]
    structurelib.delete_node(node, id)
end

---@param entity LuaEntity
function structurelib.on_mined_iopoint(entity)
    local context = get_context()
    local id = entity.unit_number

    local iopoint = context.iopoints[id]
    if not iopoint then return end

    disconnect_iopoint(iopoint)
    ---@cast id -nil
    context.iopoints[id] = nil
end

---@param node Node
---@param req RequestedItem
---@param amount integer
---@return Node?
---@return ProvidedItem?
---@return integer?
local function find_producer(node, req, amount)
    ---@type table<integer, boolean>
    local parsed_nodes = { [node.id] = true }
    ---@type Node[]
    local nodes_to_parse = { node }

    local item = req.item
    local index = 1
    local count = 1
    ---@type Node?
    local found_node
    ---@type ProvidedItem?
    local found_provided
    ---@type integer?
    local found_available
    ---@type number
    local found_provided_value

    node.previous_provided = 0
    while index <= count do
        local current = nodes_to_parse[index]
        local previous_provided = current.previous_provided
        index = index + 1
        if current.restrictions and not current.restrictions[item] then
            if not (current.provided and current.provided[item]) then
                goto skip_node
            end
        end
        if current.inputs then
            for _, input in pairs(current.inputs) do
                local connection = input.connection

                for _, output in pairs(connection.outputs) do
                    local test_node = output.node
                    local id = test_node.id

                    if not parsed_nodes[id] then
                        parsed_nodes[id] = true
                        test_node.previous = current
                        test_node.previous_provided = previous_provided

                        if test_node.provided and not test_node.saturated then
                            local provided_item = test_node.provided[item]
                            if provided_item then
                                local available = (test_node.contents[item] or 0) - provided_item.provided
                                if available >= amount then
                                    if found_provided and found_provided_value <= provided_item.provided + previous_provided then
                                        goto skip
                                    end
                                    found_node = test_node
                                    found_provided = provided_item
                                    found_available = available
                                    found_provided_value = provided_item.provided + previous_provided
                                end
                            end
                        end
                        table.insert(nodes_to_parse, test_node)
                        count = count + 1
                        ::skip::
                    end
                end
            end
        end
        ::skip_node::
    end
    return found_node, found_provided, found_available
end

---@param producer Node
---@param node Node
---@param item string
---@param amount integer
---@return boolean?
local function insert_routing(producer, node, item, amount)
    local rnode = producer
    while rnode ~= node do
        local previous = rnode.previous
        local outputs = rnode.output_map[previous.id]
        if not outputs then
            return nil
        end
        local output_count = table_size(outputs)
        local per_output = math.ceil(amount / output_count)
        local remaining = amount
        for _, output in pairs(outputs) do
            if per_output > remaining then
                per_output = remaining
            end
            if per_output == 0 then
                break
            end

            if not rnode.routings then
                rnode.routings = {}
            end

            local item_routes = rnode.routings[item]
            if not item_routes then
                item_routes = {}
                rnode.routings[item] = item_routes
            end

            ---@type Routing
            local routing = item_routes[output.id]
            if routing then
                routing.remaining = routing.remaining + per_output
            else
                routing = {
                    id = output.id,
                    item = item,
                    output = output,
                    remaining = per_output
                }
                item_routes[output.id] = routing
            end

            remaining = remaining - per_output

            if rnode ~= producer and rnode.requested then
                local intermediate = rnode.requested[item]
                if intermediate then
                    intermediate.remaining = intermediate.remaining + per_output
                end
            end

            if remaining == 0 then
                break
            end
        end
        rnode = previous
    end
    return true
end
structurelib.insert_routing = insert_routing

---@param node Node
local function process_node(node)
    local inventory = node.inventory
    ---@type table<string, integer>
    local contents
    local changed
    ---@type table<string, integer>
    local input_items

    if not inventory.valid then
        structurelib.delete_node(node, node.id)
        return
    end

    --- Compute input to node
    local remaining = node.remaining
    local requested = node.requested
    local to_inventory = {}

    if not remaining or node.disabled then
        if remaining then
            input_items = remaining
            changed = true
            node.remaining = nil
        else
            input_items = {}
        end
        for _, input in pairs(node.inputs) do
            if not input.inventory.is_empty() then
                local input_contents = input.inventory.get_contents()
                for name, count in pairs(input_contents) do
                    input_items[name] = (input_items[name] or 0) + count
                    --[[
                    if tracing then
                        debug("[" .. node.id .. "] input " .. name .. "=" .. count)
                    end
                    --]]
                end
                input.inventory.clear()
                changed = true
            end
        end
    else
        changed = true
        input_items = remaining
        node.remaining = nil
    end

    --- Update request
    if requested then
        for item, request in pairs(requested) do
            local count = input_items[item]
            if count then
                local remaining = request.remaining
                --[[
                if tracing then
                    debug("[" .. node.id .. "] In inventory " .. item .. "=" .. count .. ",requested=" .. remaining)
                end
                    --]]
                if count <= remaining then
                    to_inventory[item] = count
                    request.remaining = remaining - count
                    input_items[item] = nil
                else
                    to_inventory[item] = remaining
                    input_items[item] = count - remaining
                    request.remaining = 0
                end
            end
        end
    end

    contents = inventory.get_contents()

    -- do routing
    node.saturated = false
    if node.routings then
        local to_remove_items

        changed = true
        for item, routing_map in pairs(node.routings) do
            local item_count = (contents[item] or 0)
            local input_count = input_items[item] or 0
            local to_inventory_count = to_inventory[item] or 0
            local available = item_count + input_count + to_inventory_count

            if available > 0 then
                local remaining_available = available
                local to_remove_routings = nil

                local sum = 0
                for _, routing in pairs(routing_map) do
                    sum = sum + routing.remaining
                end

                -- Do routing
                local total_inserted = 0
                for id, routing in pairs(routing_map) do
                    local amount = math.ceil(routing.remaining / sum * available)
                    local inserted_amount = amount
                    if inserted_amount > routing.remaining then
                        inserted_amount = routing.remaining
                    end
                    if inserted_amount > remaining_available then
                        inserted_amount = remaining_available
                    end

                    local real_inserted = routing.output.inventory.insert { name = item, count = inserted_amount }
                    if real_inserted ~= inserted_amount then
                        node.saturated = true
                    end
                    routing.remaining = routing.remaining - real_inserted
                    if routing.remaining <= 0 then
                        if not to_remove_routings then
                            to_remove_routings = { id }
                        else
                            table_insert(to_remove_routings, id)
                        end
                    end
                    total_inserted = total_inserted + real_inserted
                    remaining_available = remaining_available - real_inserted
                    if remaining_available == 0 then
                        break
                    end
                end

                --[[
                if tracing then
                    debug("[" .. node.id .. "] Routing " .. item .. "=" .. sum .. ",available=" .. available .. ",total_inserted=" .. total_inserted)
                end
                    --]]

                if total_inserted < input_count then
                    input_items[item] = input_count - total_inserted
                else
                    input_items[item] = nil
                    to_inventory[item] = to_inventory_count - (total_inserted - input_count)
                end

                -- Remove completed routing
                if to_remove_routings then
                    for _, id in pairs(to_remove_routings) do
                        routing_map[id] = nil
                    end
                    if not next(routing_map) then
                        if not to_remove_items then
                            to_remove_items = { item }
                        else
                            table_insert(to_remove_items, item)
                        end
                    end
                end

                -- Remove from provided
                if node.provided then
                    local provided_req = node.provided[item]
                    if provided_req then
                        local new_provided = provided_req.provided - total_inserted
                        if new_provided < 0 then
                            new_provided = 0
                        end
                        provided_req.provided = new_provided
                    end
                end
            end
        end
        ::end_routing::
        if to_remove_items then
            for _, item in pairs(to_remove_items) do
                node.routings[item] = nil
            end
            if not next(node.routings) then
                node.routings = nil
            end
        end
    end

    -- process request
    if not node.disabled then
        if requested then
            for item, req in pairs(requested) do
                local count = (contents[item] or 0) + (to_inventory[item] or 0)
                local needed = req.count - count - req.remaining

                local delivery = req.delivery or config.default_delivery
                if needed >= delivery then
                    local to_deliver = needed

                    ::next_delivery::
                    do
                        needed = delivery

                        local producer, provided_item, available = find_producer(node, req, needed)
                        if producer then
                            ---@cast provided_item -nil
                            ---@cast available -nil

                            local amount           = math.min(needed, available)
                            provided_item.provided = provided_item.provided + amount
                            req.remaining          = req.remaining + amount

                            if not insert_routing(producer, node, req.item, amount) then
                                goto cancel
                            end

                            to_deliver = to_deliver - amount
                            if to_deliver > 0 then
                                goto next_delivery
                            end
                        end
                    end
                end
            end
            ::cancel::
        end
        if node.disabled_id then
            rendering.destroy(node.disabled_id)
            node.disabled_id = nil
        end
    else
        if not node.disabled_id then
            local container = node.container
            if container and container.valid then
                node.disabled_id = rendering.draw_sprite {
                    target = container,
                    surface = container.surface,
                    sprite = prefix .. "_stopped",
                    x_scale = 0.6, y_scale = 0.6, target_offset = { -0.5, 0.5 } }
            end
        end
    end
    if node.overflows then
        for _, output in pairs(node.overflows) do
            for name, amount in pairs(output.overflows) do
                local amount_c = contents[name]
                if amount_c and amount_c > amount then
                    local count = amount_c - amount
                    local real = output.inventory.insert { name = name, count = count }
                    if real > 0 then
                        contents[name] = contents[name] - real
                        input_items[name] = -real
                        changed = true
                    end
                    if real ~= count then
                        break
                    end
                end
            end
        end
    end

    if changed then
        remaining = nil
        for name, count in pairs(to_inventory) do
            if count > 0 then
                local inserted = inventory.insert { name = name, count = count }
                if inserted ~= count then
                    if not remaining then
                        remaining = {}
                    end
                    remaining[name] = count - inserted
                end
                contents[name] = (contents[name] or 0) + count
            elseif count < 0 then
                inventory.remove { name = name, count = -count }
                contents[name] = (contents[name] or 0) + count
                if contents[name] < 0 then
                    contents[name] = 0
                end
            end
        end
        if table_size(input_items) > 0 then
            if not node.routings then
                for name, count in pairs(input_items) do
                    if count < 0 then
                        inventory.remove { name = name, count = -count }
                    else
                        local inserted = inventory.insert { name = name, count = count }
                        if inserted ~= count then
                            if not remaining then
                                remaining = {}
                            end
                            remaining[name] = count - inserted
                        end
                    end
                end
            else
                for name, count in pairs(input_items) do
                    if not remaining then
                        remaining = {}
                    end
                    remaining[name] = (remaining[name] or 0) + count
                end
            end
        end
    end

    if remaining then
        if node.disabled then
            if not node.routings then
                for name, count in pairs(remaining) do
                    --[[
                    if tracing then
                        debug("[" .. node.id .. "] remaining " .. name .. "=" .. count)
                    end
                                        --]]

                    local inserted = inventory.insert { name = name, count = count }
                    if inserted < count then
                        node.container.surface.spill_item_stack(node.container.position, { name = name, count = count }, true, node.container.force)
                    end
                end
                remaining = nil
            end
            node.remaining = remaining
        else
            if not node.full_id then
                local container = node.container
                if container and container.valid then
                    node.full_id = rendering.draw_sprite {
                        target = container,
                        surface = container.surface,
                        sprite = prefix .. "_full",
                        x_scale = 0.6, y_scale = 0.6, target_offset = { 0.5, 0.5 }
                    }
                end
            end
            node.remaining = remaining
        end
    else
        if node.full_id then
            rendering.destroy(node.full_id)
            node.full_id = nil
        end
    end
    node.contents = contents
end

---@param e {tick:integer}
local function on_tick(e)
    ---@type Context
    if not context then
        context = get_context()
    end
    local node_index = context.node_index
    local node_per_tick = context.node_per_tick
    local id = context.current_node_id
    local current_node
    local nodes = context.nodes
    node_index = node_index + node_per_tick
    while node_index >= 1 do
        id, current_node = next(nodes, id)
        if current_node then
            process_node(current_node)
            node_index = node_index - 1
        end
    end
    context.current_node_id = id
    context.node_index = node_index
end

--tools.on_nth_tick(30, on_ntick)
tools.on_event(defines.events.on_tick, on_tick)


---@param entity LuaEntity
---@return Node?
function structurelib.get_node(entity)
    if not context then
        context = get_context()
    end
    local node = context.nodes[entity.unit_number]
    if node then return node end
    if entity.name ~= commons.router_name then return nil end
    local cluster = context.clusters[entity.link_id]
    if not cluster then return nil end
    return cluster.node
end

locallib.get_context = get_context


---@param node Node
---@return table<integer, Node>
function structurelib.get_connected_nodes(node)
    ---@type table<integer, Node>
    local nodes = {}
    local to_process = {}

    to_process[node.id] = node
    while (true) do
        ---@type Node
        local current
        _, current = next(to_process)
        if not current then
            return nodes
        end
        to_process[current.id] = nil
        nodes[current.id] = current
        if current.outputs then
            for _, iopoint in pairs(current.outputs) do
                if iopoint.connection.inputs then
                    for _, input in pairs(iopoint.connection.inputs) do
                        if not nodes[input.node.id] then
                            to_process[input.node.id] = input.node
                        end
                    end
                end
            end
        end
        if current.inputs then
            for _, iopoint in pairs(current.inputs) do
                if iopoint.connection.outputs then
                    for _, output in pairs(iopoint.connection.outputs) do
                        if not nodes[output.node.id] then
                            to_process[output.node.id] = output.node
                        end
                    end
                end
            end
        end
    end
end

---@param node Node
---@return integer
function structurelib.stop_network(node)
    local nodes = structurelib.get_connected_nodes(node)

    for _, n in pairs(nodes) do
        if not n.disabled then
            n.disabled = true
        end
    end
    return table_size(nodes)
end

---@param node Node
---@return integer
function structurelib.start_network(node)
    local nodes = structurelib.get_connected_nodes(node)

    for _, n in pairs(nodes) do
        if n.disabled then
            n.disabled = false
            structurelib.reset_node(n)
        end
    end
    return table_size(nodes)
end

local function general_migrations()
    local context = get_context()

    local to_delete = {}
    context.node_count = table_size(context.nodes)
    for _, node in pairs(context.nodes) do
        node.buffer_size = node.buffer_size or config.io_buffer_size
        for _, output in pairs(node.outputs) do
            output.inventory.set_bar(node.buffer_size)
        end
        for _, input in pairs(node.inputs) do
            input.inventory.set_bar(node.buffer_size)
        end

        if node.requested then
            for _, request in pairs(node.requested) do
                if not request.delivery then
                    request.delivery = math.ceil(request.count / 2)
                end
            end
        end
        if not node.container.valid then
            table.insert(to_delete, node)
        else
            purge_content(node.contents)
            purge_content(node.routings)
            purge_content(node.provided)
            purge_content(node.requested)
            purge_content(node.remaining)
            purge_content(node.restrictions)
            if node.overflows then
                for _, overflow in pairs(node.overflows) do
                    purge_content(overflow.overflows)
                end
            end
        end
    end
    for _, node in pairs(to_delete) do
        structurelib.delete_node(node, node.id)
    end

    compute_node_count(context)
    if not context.clusters then
        context.clusters = {}
    end
end


local function on_configuration_changed(data)
    general_migrations()
end

tools.on_configuration_changed(on_configuration_changed)
tools.on_init(function()
    get_context()
end)

return structurelib
