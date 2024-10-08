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

local tracing = tools.tracing
local debug = tools.debug
local cdebug = tools.cdebug
local get_vars = tools.get_vars
local strip = tools.strip

--local debug_nodeids = { [1347116] = true, [1347193] = true, [1347149] = true }
local debug_nodeids = {}

local table_insert = table.insert

local trace_scan
local tracing = tools.tracing
local migration_done = false

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
        if not migration_done then
            structurelib.repair(context)
        end
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
    node.saturated = false
    node.remaining = nil
    node.dist_cache = nil
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

---@param pos MapPosition
---@param origin MapPosition
local function distance(pos, origin)
    local dx = pos.x - origin.x
    if dx < 0 then dx = -dx end
    local dy = pos.y - origin.y
    if dy < 0 then dy = -dy end
    return dx + dy
end

---@param node Node
---@param req RequestedItem
---@param amount integer
---@return Node?
---@return ProvidedItem?
---@return integer?
local function find_producer(node, req, amount)
    local tick = game.tick
    local item = req.item

    if req.last_provider_node then
        local structure_tick = context.structure_tick or 0
        if req.last_provider_tick >= structure_tick and tick < req.last_provider_tick + 600 then
            local test_node = context.nodes[req.last_provider_node]
            if test_node then
                local provided_item = test_node.provided[item]
                local available = (test_node.contents[item] or 0) - provided_item.provided
                if available >= amount then
                    local last_routings = req.last_routings
                    ---@cast last_routings -nil

                    local current = test_node
                    for _, nodeid in pairs(last_routings) do
                        local pnode = context.nodes[nodeid]
                        if not pnode then
                            goto skip
                        end
                        current.previous = pnode
                        current = pnode
                    end
                    return test_node, provided_item, available
                end
            end
        end
    end

    ::skip::

    local graph_tick = (context.graph_tick or 0) + 1
    context.graph_tick = graph_tick


    ---@type table<integer, boolean>
    local parsed_nodes = { [node.id] = true }
    ---@type Node[]
    local nodes_to_parse = { node }

    node.previous = nil
    node.previous_dist = 0

    local index = 1
    local count = 1
    ---@type Node?
    local found_node
    ---@type ProvidedItem?
    local found_provided
    ---@type integer?
    local found_available
    ---@type integer
    local found_priority
    ---@type number
    local found_dist

    while index <= count do
        local current = nodes_to_parse[index]
        index = index + 1
        if current.restrictions and not current.restrictions[item] then
            if not (current.provided and current.provided[item]) then
                goto skip_node
            end
        end
        local current_pos = current.container.position
        if current.inputs then
            for _, input in pairs(current.inputs) do
                if not input.error then
                    local connection = input.connection
                    for _, output in pairs(connection.outputs) do
                        if not output.error then
                            local test_node = output.node
                            local id = test_node.id
                            if not parsed_nodes[id] then
                                parsed_nodes[id] = true

                                local d
                                if test_node.dist_cache then
                                    d = test_node.dist_cache[current.id]
                                end
                                if not d then
                                    local test_node_pos = test_node.container.position
                                    d = distance(test_node_pos, current_pos)
                                    if not test_node.dist_cache then
                                        test_node.dist_cache = {}
                                    end
                                    d = d + current.previous_dist
                                    test_node.dist_cache[current.id] = d
                                end
                                if test_node.graph_tick == graph_tick then
                                    if test_node.previous_dist > d then
                                        test_node.previous = current
                                        test_node.dist_cache[current.id] = d
                                    else
                                        goto skip_node
                                    end
                                else
                                    test_node.graph_tick = graph_tick
                                    test_node.previous = current
                                    test_node.previous_dist = d
                                end

                                if not test_node.saturated then
                                    ---@type ProvidedItem
                                    local provided_item
                                    local priority = test_node.priority or 0
                                    if test_node.provided then
                                        provided_item = test_node.provided[item]
                                        if provided_item then
                                            local available = (test_node.contents[item] or 0) - provided_item.provided
                                            if available >= amount then
                                                local dist = test_node.previous_dist
                                                if found_priority then
                                                    if found_priority > priority then
                                                        goto skip
                                                    elseif found_priority == priority then
                                                        if dist >= found_dist then
                                                            goto skip
                                                        end
                                                    end
                                                end
                                                found_node = test_node
                                                found_provided = provided_item
                                                found_available = available
                                                found_priority = priority
                                                found_dist = dist
                                            end
                                        end
                                    end
                                    if not provided_item and test_node.auto_provide then
                                        local available = (test_node.contents[item] or 0)
                                        if available >= amount then
                                            provided_item = {
                                                item = item,
                                                provided = 0
                                            }
                                            local dist = test_node.previous_dist
                                            if found_priority then
                                                if found_priority > priority then
                                                    goto skip
                                                elseif found_priority == priority then
                                                    if dist >= found_dist then
                                                        goto skip
                                                    end
                                                end
                                            end
                                            if not test_node.provided then
                                                test_node.provided = { [item] = provided_item }
                                            else
                                                test_node.provided[item] = provided_item
                                            end
                                            found_node = test_node
                                            found_provided = provided_item
                                            found_available = available
                                            found_priority = priority
                                            found_dist = dist
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
            end
        end
        ::skip_node::
    end

    if config.use_cache then
        if found_node then
            req.last_provider_node = found_node.id
            req.last_provider_tick = tick
            local last_routings = {}

            local current = found_node.previous
            while (true) do
                table.insert(last_routings, current.id)
                if current == node then break end
                current = current.previous
            end

            req.last_routings = last_routings
        else
            req.last_provider_node = nil
            req.last_routings = nil
        end
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

            --[[             if debug_nodeids[rnode.id] then
                debug("(" .. rnode.id .. ") routings for request: " .. item .. "=" .. routing.remaining)
            end
 ]]
            remaining = remaining - per_output
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
local function do_clean(node)
    ---@type table<integer, boolean>
    local parsed_nodes   = {}
    local nodes_to_parse = { node }
    local index          = 1
    local count          = 1
    while index <= count do
        local current = nodes_to_parse[index]
        index = index + 1
        if current.inputs then
            for _, input in pairs(current.inputs) do
                if not input.error then
                    local connection = input.connection
                    for _, output in pairs(connection.outputs) do
                        if not output.error then
                            local test_node = output.node
                            local id = test_node.id
                            if not parsed_nodes[id] then
                                parsed_nodes[id] = true
                                if not test_node.cleaner then
                                    test_node.previous = current
                                    table.insert(nodes_to_parse, test_node)
                                    count = count + 1
                                    if node.contents then
                                        for name, count in pairs(test_node.contents) do
                                            if not (node.routings and node.routings[name]) and
                                                not (test_node.requested and test_node.requested[name]) and
                                                not (test_node.provided and test_node.provided[name])
                                            then
                                                insert_routing(test_node, node, name, count)
                                                return
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

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
                end
                input.inventory.clear()
                changed = true
            end
        end
        --[[         if debug_nodeids[node.id] then
            debug("(" .. node.id .. ") input_items=" .. tools.strip(input_items))
        end
 ]]
    else
        changed = true
        input_items = remaining
        node.remaining = nil
    end

    contents = inventory.get_contents()


    -- do routing
    node.saturated = false
    if node.routings then
        local to_remove_items
        changed = true
        for item, routing_map in pairs(node.routings) do
            local item_count = (contents[item] or 0)
            local provided_req = node.provided and node.provided[item]
            if provided_req then
                if provided_req.provided < item_count then
                    item_count = provided_req.provided
                end
            end

            local input_count = input_items[item] or 0
            local available = item_count + input_count

            if available > 0 then
                local remaining_available = available
                local to_remove_routings = nil

                local sum = 0
                for _, routing in pairs(routing_map) do
                    sum = sum + routing.remaining
                end

                --[[                 if debug_nodeids[node.id] then
                    debug("(" .. node.id .. ") routings before: " .. item .. "=" .. sum)
                end
 ]]
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
                    if routing.remaining == 0 then
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

                --[[                 if debug_nodeids[node.id] then
                    debug("(" .. node.id .. ") routing after: " .. item .. "=" .. total_inserted)
                end
 ]]
                input_items[item] = input_count - total_inserted

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

                        --[[                         if debug_nodeids[node.id] then
                            debug("(" .. node.id .. ") remove local routing")
                        end
 ]]
                    end
                end

                local provided_items = total_inserted - input_count

                -- Remove from provided
                if provided_req and provided_items > 0 then
                    local new_provided = provided_req.provided - provided_items
                    if new_provided < 0 then
                        new_provided = 0
                        --- invalid case
                    end
                    provided_req.provided = new_provided

                    --[[                     if debug_nodeids[node.id] then
                        debug("(" .. node.id .. ") remains provided=" .. tools.strip(node.provided))
                    end
 ]]
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

                --[[                 if debug_nodeids[node.id] then
                    debug("(" .. node.id .. ") remove global routing")
                end
 ]]
            end
        end
    end

    --- Update request
    local to_inventory = {}
    if requested then
        for item, request in pairs(requested) do
            local count = input_items[item]
            if count and count > 0 then
                local remaining = request.remaining
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

        --[[         if debug_nodeids[node.id] then
            debug("(" .. node.id .. ") to_inventory=" .. tools.strip(to_inventory))
        end
 ]]
    end

    -- process request
    if not node.disabled then
        if requested then
            for item, req in pairs(requested) do
                local count = to_inventory[item]
                if not count or count < 0 then
                    count = 0
                end
                count = (contents[item] or 0) + count
                local needed = req.count - count - req.remaining

                --[[                 if debug_nodeids[node.id] then
                    debug("(" .. node.id .. ") request prepare: req.count=" .. req.count ..
                        ",count=" .. count .. ", req.remaining=" .. req.remaining .. ",needed=" .. needed)
                end
 ]]
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

                            --[[                             if debug_nodeids[node.id] then
                                debug("(" .. node.id .. ") request=" .. tools.strip(req))
                            end
 ]]
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

        --[[         if debug_nodeids[node.id] then
            debug("(" .. node.id .. ") remains to_inventory=" .. tools.strip(to_inventory))
        end
 ]]
        for name, count in pairs(to_inventory) do
            if count > 0 then
                local inserted = inventory.insert { name = name, count = count }
                contents[name] = (contents[name] or 0) + inserted
                if inserted ~= count then
                    if not remaining then
                        remaining = {}
                    end
                    remaining[name] = count - inserted
                end
            elseif count < 0 then
                local removed = inventory.remove { name = name, count = -count }
                contents[name] = (contents[name] or 0) - removed
                if contents[name] < 0 then
                    contents[name] = 0
                end
            end
        end
        if table_size(input_items) > 0 then
            --[[             if debug_nodeids[node.id] then
                debug("(" .. node.id .. ") remains input_items=" .. tools.strip(input_items))
            end
 ]]
            for name, count in pairs(input_items) do
                if (not node.routings) or (not node.routings[name]) or count < 0 then
                    if count < 0 then
                        count = -count
                        local real = inventory.remove { name = name, count = count }
                        if real ~= count then
                            log("---> invalid remove: nodeid=" .. node.id .. ",item=" .. name .. "," .. count .. " => " .. real)
                        end
                    elseif count > 0 then
                        log("---> input remains: nodeid=" .. node.id .. ",item=" .. name .. "," .. count)
                        local inserted = inventory.insert { name = name, count = count }
                        if inserted ~= count then
                            if not remaining then
                                remaining = {}
                            end
                            remaining[name] = count - inserted
                        end
                    end
                elseif count > 0 then
                    if not remaining then
                        remaining = {}
                    end
                    remaining[name] = count
                end
            end
        end
    end

    if node.cleaner then
        node.cleaner_count = (node.cleaner_count or 0) + 1
        if node.cleaner_count > 1 then
            node.cleaner_count = nil
            do_clean(node)
        end
    end

    if remaining then
        if node.disabled then
            if not node.routings then
                for name, count in pairs(remaining) do
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
    if global.monitoring then
        return
    end

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

---@param context Context
function structurelib.repair(context)
    for _, iopoint in pairs(context.iopoints) do
        if iopoint.container and iopoint.container.valid then
            local containers = iopoint.device.surface.find_entities_filtered
                { position = iopoint.container.position, name = commons.chest_name, radius = 0.5 }
            for _, c in pairs(containers) do
                if c.unit_number ~= iopoint.container.unit_number then
                    c.destroy()
                end
            end
        end
    end

    compute_node_count(context)
    if not context.clusters then
        context.clusters = {}
    end
end

local function general_migrations()
    local context = global.context

    migration_done = true
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

    structurelib.repair(context)
end

local function on_configuration_changed(data)
    general_migrations()
end

tools.on_configuration_changed(on_configuration_changed)
tools.on_init(function()
    get_context()
end)

return structurelib
