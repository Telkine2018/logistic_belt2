local commons = require "scripts.commons"
local tools = require "scripts.tools"
local structurelib = require "scripts.structurelib"
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
local get_context = structurelib.get_context

local trace_scan


local nodelib = {}

---@param node Node
---@return table<string, integer>
function nodelib.get_stock(node)
    ---@type table<integer, boolean>
    local parsed_nodes = { [node.id] = true }
    ---@type Node[]
    local nodes_to_parse = { node }
    local index = 1

    local contents = {}
    while index <= #nodes_to_parse do
        local current = nodes_to_parse[index]
        index = index + 1
        if current.inputs then
            for _, input in pairs(current.inputs) do
                local connection = input.connection
                for _, output in pairs(connection.outputs) do
                    local test_node = output.node
                    local id = test_node.id
                    if not parsed_nodes[id] then
                        parsed_nodes[test_node.id] = true
                        table.insert(nodes_to_parse, test_node)
                        if test_node.provided and test_node.contents then
                            for name, count in pairs(test_node.contents) do
                                if test_node.provided[name] then
                                    contents[name] = (contents[name] or 0) + count
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return contents
end

---@param node Node
---@param all boolean?
---@param include_source boolean?
---@return table<string, integer>
function nodelib.get_requests(node, all, include_source)
    ---@type table<integer, boolean>
    local parsed_nodes = { [node.id] = true }
    ---@type Node[]
    local nodes_to_parse = { node }
    local index = 1

    local contents = {}
    while index <= #nodes_to_parse do
        local current = nodes_to_parse[index]
        index = index + 1
        if current.requested then
            for item, request in pairs(current.requested) do
                if all then
                    if node ~= current or include_source then
                        contents[item] = (contents[item] or 0) + request.count
                    end
                else
                    local stock = (current.contents and current.contents[item]) or 0
                    local missing = request.count - request.remaining - stock
                    if missing > 0 then
                        contents[item] = (contents[item] or 0) + (request.count - stock - request.remaining)
                    end
                end
            end
        end
        if current.outputs then
            for _, output in pairs(current.outputs) do
                local connection = output.connection
                for _, input in pairs(connection.inputs) do
                    local test_node = input.node
                    local id = test_node.id
                    if not parsed_nodes[id] then
                        parsed_nodes[test_node.id] = true
                        table.insert(nodes_to_parse, test_node)
                    end
                end
            end
        end
    end
    return contents
end

---@param node Node
function nodelib.purge(node)
    ---@type table<integer, boolean>
    local parsed_nodes = { [node.id] = true }
    ---@type Node[]
    local nodes_to_parse = { node }
    local index = 1

    local contents = node.contents
    if node.requested then
        for _, request in pairs(node.requested) do
            local count = contents[request.item]
            if count then
                count = count - request.count
                if count <= 0 then
                    contents[request.item] = nil
                else
                    contents[request.item] = count
                end
            end
        end
    end
    if node.provided then
        for item, _ in pairs(node.provided) do
            contents[item] = nil
        end
    end

    while index <= #nodes_to_parse do
        local current = nodes_to_parse[index]
        if not next(contents) then
            break
        end
        index = index + 1
        if current ~= node then
            if current.requested then
                for item, request in pairs(current.requested) do
                    local count = contents[item]
                    if count then
                        local stack_size = game.item_prototypes[item].stack_size
                        local slot_count = 0
                        local inv = current.inventory
                        local free
                        if inv.is_filtered() then
                            for i = 1, #inv do
                                if inv.get_filter(i) == item then
                                    slot_count = slot_count + 1
                                end
                            end
                            free = slot_count * stack_size - inv.get_item_count(item) - request.remaining
                        else
                            slot_count = inv.count_empty_stacks(false, false) - request.remaining
                            free = slot_count * stack_size
                        end
                        if free > 0 then
                            local amount = math.min(free, count)
                            local remaing = count - amount
                            if remaing == 0 then
                                contents[item] = nil
                            else
                                contents[item] = remaing
                            end
                            local n = current
                            n.previous = nil
                            while n ~= node do
                                n.next.previous = n
                                n = n.next
                            end
                            structurelib.insert_routing(node, current, item, amount)
                        end
                    end
                end
            end
        end
        if current.outputs then
            for _, output in pairs(current.outputs) do
                local connection = output.connection
                for _, input in pairs(connection.inputs) do
                    local test_node = input.node
                    local id = test_node.id
                    if not parsed_nodes[id] then
                        parsed_nodes[test_node.id] = true
                        table.insert(nodes_to_parse, test_node)
                        test_node.next = current
                    end
                end
            end
        end
    end
    return contents
end

---@param node Node
---@param item string
---@param count integer
---@param delivery integer?
---@param old_requests table<string, RequestedItem>
function nodelib.add_request(node, item, count, delivery, old_requests)
    ---@type RequestedItem
    local existing = (old_requests and old_requests[item])

    if not node.requested then
        node.requested = {}
    end
    if existing then
        node.requested[item] = existing
        existing.count = count
        existing.delivery = delivery
    else
        node.requested[item] = {
            count = count,
            item = item,
            delivery = delivery,
            remaining = 0
        }
    end
end

---@param device LuaEntity
---@return table<integer, LoaderInfo>?		@ scanned loader
---@return table<integer, LuaEntity>?		@ scanned belt
---@return table<string, integer>?			@ item on belt network
---@return boolean?
local function scan_network(device)
    local position = get_front(device.direction, device.position)
    local entities = device.surface.find_entities_filtered { position = position, type = locallib.belt_types }

    if #entities == 0 then return end

    local belt = entities[1]

    if tools.tracing then
        debug("device: " .. strip(device.position))
    end

    ---@type table<integer, LuaEntity>
    local to_scan = { [belt.unit_number] = belt }
    ---@type table<integer, LuaEntity>
    local scanned = {}
    ---@type table<integer, LoaderInfo>
    local loaders = {}

    ---@param b LuaEntity
    ---@param output boolean?
    ---@return boolean
    local function add_to_scan(b, output)
        if b.name == device_loader_name then
            if tools.tracing then
                debug("Scan loader: " .. strip(b.position) .. ",direction=" .. b.direction)
            end
            loaders[b.unit_number] = { loader = b, output = output }
            return false
        end
        if not scanned[b.unit_number] then
            to_scan[b.unit_number] = b
        end
        return true
    end

    ---@type table<string, integer>
    local content = {}
    while true do
        local id, belt = next(to_scan)
        if id == nil then
            break
        end
        to_scan[id] = nil
        scanned[id] = belt
        local neightbours = belt.belt_neighbours
        local has_input = false
        local has_output = false

        cdebug(trace_scan, "Scan: " ..
            belt.name ..
            ",pos=" ..
            strip(belt.position) ..
            ",direction=" .. belt.direction .. ",#inputs=" .. #neightbours.inputs .. ",#outputs" .. #neightbours.outputs)

        if neightbours.inputs and #neightbours.inputs == 0 then
            local back_pos = get_back(belt.direction, belt.position);
            local loaderlist = belt.surface.find_entities_filtered { name = device_loader_name, position = back_pos }
            if #loaderlist == 1 then
                add_to_scan(loaderlist[1], false)
                loaderlist[1].loader_type = "output"
            end
        else
            for _, child in ipairs(neightbours.inputs) do
                if add_to_scan(child, false) then
                    has_input = true
                end
            end
        end

        if #neightbours.outputs == 0 then
            local front_pos = get_front(belt.direction, belt.position);
            local loaderlist = belt.surface.find_entities_filtered { name = device_loader_name, position = front_pos }
            if #loaderlist == 1 then
                add_to_scan(loaderlist[1], true)
                loaderlist[1].loader_type = "input"
            end
        else
            for _, child in ipairs(neightbours.outputs) do
                if add_to_scan(child, true) then
                    has_output = true
                end
            end
        end
        if belt.type == "underground-belt" then
            neightbours = belt.neighbours
            if neightbours then
                add_to_scan(neightbours)
                if has_input then
                    has_output = true
                elseif has_output then
                    has_input = true
                end
            end
        elseif belt.type == "linked-belt" then
            local n = belt.linked_belt_neighbour
            if n then
                add_to_scan(n)
            end
        end

        if belt.name == "entity-ghost" then
            return nil, nil, nil, true
        end

        local t_count = belt.get_max_transport_line_index()
        for i = 1, t_count do
            local t = belt.get_transport_line(i)
            if t then
                local t_content = t.get_contents()
                for item, count in pairs(t_content) do
                    content[item] = (content[item] or 0) - count
                end
            end
        end
    end

    return loaders, scanned, content, false
end

---@param loaders table<integer, LoaderInfo>		@ scanned loader
---@param player LuaPlayer?
---@return DeviceInfo[]?
local function build_device_list(loaders, player)
    ---@type DeviceInfo[]
    local devices = {}
    local has_input = false
    local has_output = false
    for _, l in pairs(loaders) do
        local loader = l.loader
        local position = loader.position

        if tools.tracing then
            debug("==> End: " .. loader.name .. ",pos=" .. strip(position))
        end

        local device_list = loader.surface.find_entities_filtered { position = position, name = { device_name, overflow_name } }
        if #device_list > 0 then
            local device = device_list[1]
            local search_pos = get_front(device.direction, device.position)
            if tools.tracing then
                debug("SearchPOS:" .. strip(search_pos))
                debug("Device: " ..
                    device.name ..
                    ",pos=" .. strip(device.position) .. ",direction=" .. device.direction .. ",output=" .. tostring(l.output))
            end

            local belts = loader.surface.find_entities_filtered { type = locallib.belt_types, position = search_pos }
            if #belts == 0 then
                if tools.tracing then
                    debug("Cannot find belt")
                end
                return nil
            end

            local belt = belts[1]
            table.insert(devices, {
                device = device,
                output = l.output,
                direction = device.direction,
                belt = belt,
                loader = loader,
            })

            if l.output then
                has_output = true
            else
                has_input = true
            end
        end
    end

    if not has_input then
        if tools.tracing then
            debug("missing input")
        end
        if player then
            player.print({ "message.missing_input" })
        end
        return nil
    end

    if not has_output then
        if tools.tracing then
            debug("missing output")
        end
        if player then
            player.print({ "message.missing_output" })
        end
        return nil
    end

    return devices
end

---@param master LuaEntity
---@param player LuaPlayer?
---@return boolean
---@return boolean?
---@return integer[]?
function nodelib.rebuild_network(master, player)
    local loaders, _, _, is_ghost = scan_network(master)
    if not loaders then return false, is_ghost end

    local devices = build_device_list(loaders, player)
    if not devices then return false end

    nodelib.build_network(devices)
    local ids = {}
    for _, d in pairs(devices) do
        table.insert(ids, d.device.unit_number)
    end
    return true, is_ghost, ids
end

---@param surface LuaSurface
---@param position MapPosition
---@return LuaEntity?
local function find_container(surface, position)
    local containers = surface.find_entities_filtered {
        position = position,
        type = locallib.container_types,
        radius = 5
    }
    local found
    for _, container in pairs(containers) do
        local w, h = container.tile_width / 2, container.tile_height / 2
        local cpos = container.position
        if position.x > cpos.x - w and position.x < cpos.x + w and position.y > cpos.y - h and position.y < cpos.y + h then
            if not found or found.type == "assembling-machine" then
                found = container
            end
        end
    end
    return found
end

---Move from container to belt
---@param iopoint IOPoint
---@param loader LuaEntity
---@param inserter_count integer
---@return LuaEntity?
local function create_output_objects(iopoint, loader, inserter_count)
    local device = iopoint.device
    local surface = device.surface
    loader.loader_type = "output"
    iopoint.is_output = true

    local container_position = get_back(device.direction, device.position)
    local container = find_container(surface, container_position)
    if not container then
        return nil
    end

    local inserters = surface.find_entities_filtered { position = device.position, name = inserter_name }
    if #inserters ~= 2 * inserter_count then
        if #inserters > 0 then
            for _, inserter in pairs(inserters) do
                inserter.destroy()
            end
            iopoint.inserters = nil
        end
        local positions = locallib.output_positions2
        inserters = create_inserters(device, get_opposite_direction(device.direction), positions[1], inserter_count, inserter_name)
    end

    iopoint.inserters = inserters
    return container
end
nodelib.create_output_objects = create_output_objects

---Move from belt to container
---@param iopoint IOPoint
---@param loader LuaEntity
---@param inserter_count integer
---@return LuaEntity?
local function create_input_object(iopoint, loader, inserter_count)
    local device = iopoint.device
    local surface = device.surface

    loader.loader_type = "input"

    local output_position = get_back(device.direction, device.position)

    local container = find_container(surface, output_position)
    if not container then
        return nil
    end
    local inserters = surface.find_entities_filtered { position = device.position, name = inserter_name }
    if #inserters ~= 2 * inserter_count then
        if #inserters > 0 then
            for _, inserter in pairs(inserters) do
                inserter.destroy()
            end
            iopoint.inserters = nil
        end
        local positions = locallib.input_positions2[1]
        inserters = create_inserters(device, device.direction, positions, inserter_count, inserter_name)
    end

    iopoint.inserters = inserters
    return container
end
nodelib.create_input_object = create_input_object

---@param iopoint IOPoint
local function create_internal_container(iopoint)
    if not iopoint.container then
        local device = iopoint.device
        local surface = device.surface
        local existings = surface.find_entities_filtered { position = device.position,
            name = commons.chest_name, radius = 0.5 }
        if #existings >= 1 then
            iopoint.container = existings[1]
        else
            iopoint.container = surface.create_entity(
                { position = device.position, name = commons.chest_name, force = device.force, create_build_effect_smoke = false }) --[[@as LuaEntity]]
        end
        iopoint.inventory = iopoint.container.get_inventory(defines.inventory.chest) --[[@as LuaInventory]]
        iopoint.inventory.set_bar(config.io_buffer_size)
    end

    if iopoint.is_output then
        for _, inserter in pairs(iopoint.inserters) do
            inserter.pickup_target = iopoint.container
        end
    else
        for _, inserter in pairs(iopoint.inserters) do
            inserter.drop_target = iopoint.container
        end
    end
end
nodelib.create_internal_container = create_internal_container

---@param devices DeviceInfo[]
function nodelib.build_network(devices)
    local context = get_context()

    ---@type Connection
    local connection = {
        outputs = {},
        inputs = {},
        id = tools.get_id()
    }

    ---@type table<integer, Node>
    local node_to_rebuild = {}

    for _, device_info in ipairs(devices) do
        local device = device_info.device
        local iopoint_id = device_info.device.unit_number
        local loader = device_info.loader

        ---@cast iopoint_id -nil

        local iopoint = context.iopoints[iopoint_id]
        if iopoint then
            structurelib.disconnect_iopoint(iopoint)
        else
            iopoint = {
                id = iopoint_id,
                device = device,
            }
            context.iopoints[iopoint_id] = iopoint
        end

        local inserter_count = locallib.get_inserter_count(device_info.belt)

        ---@type LuaEntity?
        local container

        loader.active = false
        if device_info.output then -- move from belt to container
            container = create_input_object(iopoint, loader, inserter_count)
            if not container then
                context.iopoints[iopoint_id] = nil
                goto _next
            end
            connection.inputs[iopoint_id] = iopoint
        else --- Move from container to belt
            container = create_output_objects(iopoint, loader, inserter_count)
            if not container then
                context.iopoints[iopoint_id] = nil
                goto _next
            end
            connection.outputs[iopoint_id] = iopoint
        end

        create_internal_container(iopoint)
        do
            local node = structurelib.get_node(container)
            if not node then
                node = structurelib.create_node(container)
            end
            iopoint.node = node
            iopoint.connection = connection
            node_to_rebuild[node.id] = node
            if iopoint.is_output then
                node.outputs[iopoint_id] = iopoint
            else
                node.inputs[iopoint_id] = iopoint
            end
            if node.buffer_size then
                iopoint.inventory.set_bar(node.buffer_size)
            end
        end
        ::_next::
    end

    for _, node in pairs(node_to_rebuild) do
        structurelib.reset_network(node)
        structurelib.rebuild_output_map(node)
    end
end

return nodelib
