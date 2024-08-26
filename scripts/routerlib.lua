local routerlib = {}

local commons = require "scripts.commons"
local tools = require "scripts.tools"
local locallib = require "scripts.locallib"
local structurelib = require "scripts.structurelib"
local config = require "scripts.config"

local prefix = commons.prefix
local router_name = commons.router_name

local debug = tools.debug
local cdebug = tools.cdebug
local get_vars = tools.get_vars
local strip = tools.strip

local get_context = structurelib.get_context

local changed_clusters = {}

local tracing = false

local router_max = settings.startup[prefix .. "-max-router-entity"].value

---@param position MapPosition
---@return string
local function get_key(position)
    return tostring(math.floor(position.x)) .. "/" .. math.floor(position.y)
end

local disp = {
    { direction = defines.direction.east,  x = 1,  y = 0 },
    { direction = defines.direction.west,  x = -1, y = 0 },
    { direction = defines.direction.south, x = 0,  y = 1 },
    { direction = defines.direction.north, x = 0,  y = -1 }
}

local function dump_nodes()
    if not tracing then return end
    local context = get_context()
    debug("---------------- Nodes ")
    for id, node in pairs(context.nodes) do
        debug("[" .. id .. "] " .. " node.id=" .. tostring(node.id) .. "," .. tools.strip(node.container.position)
            .. (node.container.type == "linked-container" and ",link_id=" .. tostring(node.container.link_id) or ""))
    end
    debug("---------------- End Nodes ")
end

--- Collect routers and devices in a cluster
---@param start_router LuaEntity
---@param exception LuaEntity?
---@return Router[]
---@return table<int, LuaEntity>
function routerlib.compute_cluster(start_router, exception)
    ---@type table<string, boolean>
    local map = {}
    ---@type table<string, LuaEntity>
    local to_process = {}
    local surface = start_router.surface
    local force = start_router.force
    ---@type Router[]
    local router_list = {}
    ---@type table<int, LuaEntity>
    local devices = {}

    to_process[start_router.unit_number] = start_router
    map[get_key(start_router.position)] = true

    while (true) do
        local _, router = next(to_process)
        if not router then break end

        to_process[router.unit_number] = nil
        table.insert(router_list, router)

        local position = router.position
        for _, d in ipairs(disp) do
            local test_pos = { x = position.x + d.x, y = position.y + d.y }
            local key = get_key(test_pos)
            if not map[key] then
                map[key] = true
                local routers = surface.find_entities_filtered {
                    name = router_name,
                    position = test_pos,
                    force = force }
                if #routers > 0 then
                    local found = routers[1]
                    if not exception or exception.unit_number ~= found.unit_number then
                        to_process[found.unit_number] = found
                    end
                else
                    local found_devices = surface.find_entities_filtered {
                        name = commons.device_name,
                        position = test_pos,
                        force = force }
                    if #found_devices > 0 then
                        local device = found_devices[1]
                        if device.direction == d.direction or device.direction == tools.opposite_directions[d.direction] then
                            devices[device.unit_number] = device
                        else
                            map[key] = false
                        end
                    end
                end
            end
        end
    end
    return router_list, devices
end

---@param router Router
---@return Node?     @ Removed node if cluster is destroyed
function routerlib.remove_from_cluster(router)
    local link_id = router.link_id
    local context = get_context()
    local cluster = context.clusters[link_id] --[[@as Cluster]]

    if tracing then
        debug("remove_from_cluster for link_id=" .. tostring(link_id) .. ",router=" .. tostring(router.unit_number))
    end

    if cluster then
        cluster.routers[router.unit_number] = nil

        local _, other = next(cluster.routers)
        if not other then
            if tracing then
                debug("remove_from_cluster delete cluster link_id=" .. tostring(cluster.link_id))
            end
            -- remove cluster
            local node = cluster.node
            context.clusters[link_id] = nil
            structurelib.delete_node(node, router.unit_number)
            changed_clusters[link_id] = nil
            cluster.node = nil
            cluster.masterid = nil
            cluster.deleted = true
            return node
        elseif router.unit_number == cluster.masterid then
            if tracing then
                debug("remove_from_cluster switch master link_id=" .. tostring(cluster.link_id) .. ", " ..
                    tostring(cluster.masterid) .. "=>" .. tostring(other.unit_number))
            end
            local node = context.nodes[cluster.masterid]
            if node then
                context.nodes[cluster.masterid] = nil
                cluster.masterid = other.unit_number
                context.nodes[cluster.masterid] = node
                context.current_node_id = nil
                node.container = other
                node.id = cluster.masterid
                node.inventory = other.get_inventory(defines.inventory.chest) --[[@as LuaInventory]]
                changed_clusters[link_id] = cluster
                structurelib.rebuild_output_map_for_parent(node)
            end
        end
    else
        if tracing then
            debug("no cluster for link_id=" .. tostring(link_id))
        end
    end
    return nil
end

---@param link_id integer
---@return Cluster
function routerlib.get_or_create_cluster(link_id)
    local context = get_context()
    local cluster = context.clusters[link_id]
    if cluster then return cluster end
    if tracing then
        debug("get_or_create_cluster link_id=" .. tostring(link_id))
    end
    cluster = { routers = {} }
    context.clusters[link_id] = cluster
    cluster.link_id = link_id
    changed_clusters[link_id] = cluster
    return cluster
end

local EMPTY_FILTERS = {}

---@param inv LuaInventory
---@return table<string, integer>
function routerlib.get_filters(inv)
    if inv.get_filter(1) == nil then
        return EMPTY_FILTERS
    end
    local filters = {}
    for i = 1, #inv do
        local item = inv.get_filter(i)
        if item then
            local count = filters[item]
            if count then
                filters[item] = count + 1
            else
                filters[item] = 1
            end
        else
            return filters
        end
    end
    return filters
end

---@param merge_filters table<string, integer>
---@param inv LuaInventory
function routerlib.merge_filters(merge_filters, inv)
    local filters = routerlib.get_filters(inv)
    for item, count in pairs(filters) do
        local org_count = merge_filters[item]
        if org_count then
            merge_filters[item] = math.max(count, org_count)
        else
            merge_filters[item] = count
        end
    end
end

---@param inv LuaInventory
---@param filters table<string, integer>
---@return integer
function routerlib.apply_filters(inv, filters)
    local index = 1
    local size = #inv
    for item, count in pairs(filters) do
        for i = 1, count do
            if index > size then goto end_loop end
            inv.set_filter(index, item)
            index = index + 1
        end
    end
    ::end_loop::
    return index
end

---@param entity LuaEntity
---@param routers table<integer, Router>
---@param link_id integer
---@param filters table<string, integer>?
---@return Cluster
function routerlib.set_routers_in_cluster(entity, routers, link_id, filters)
    local base_inv = nil
    local done = {}
    local cluster = routerlib.get_or_create_cluster(link_id)
    local merge_filters = {}
    if filters then
        merge_filters = filters
    end

    local requested, provided, restrictions
    for _, router in pairs(routers) do
        local org_link_id = router.link_id
        if org_link_id ~= link_id then
            local oldnode = routerlib.remove_from_cluster(router)
            if oldnode then
                requested = oldnode.requested or requested
                provided = oldnode.provided or provided
                restrictions = oldnode.restrictions or restrictions
            end
            cluster.routers[router.unit_number] = router
            changed_clusters[link_id] = cluster
            if org_link_id ~= 0 then
                if not done[org_link_id] then
                    local inv = router.get_inventory(defines.inventory.chest)
                    ---@cast inv -nil
                    local contents = inv.get_contents()
                    routerlib.merge_filters(merge_filters, inv)
                    if base_inv == nil then
                        router.link_id = link_id
                        base_inv = entity.get_inventory(defines.inventory.chest)
                        ---@cast base_inv -nil
                        routerlib.merge_filters(merge_filters, base_inv)
                        base_inv.set_bar()
                        for i = 1, #inv do
                            base_inv.set_filter(i, nil);
                        end
                    end
                    for name, count in pairs(contents) do
                        base_inv.insert({ name = name, count = count })
                    end
                    done[org_link_id] = true

                    inv = entity.force.get_linked_inventory(router.name, org_link_id)
                    ---@cast inv -nil

                    inv.clear()
                end
            end
            router.link_id = link_id
        end
    end

    if next(merge_filters) then
        if not base_inv then
            base_inv = entity.force.get_linked_inventory(entity.name, link_id)
            ---@cast base_inv -nil
            routerlib.merge_filters(merge_filters, base_inv)
            base_inv.set_bar()
        end

        local contents = base_inv.get_contents()
        base_inv.clear()

        local index = routerlib.apply_filters(base_inv, merge_filters)
        for name, count in pairs(contents) do
            base_inv.insert({ name = name, count = count })
        end
        if index > 1 and index < #base_inv then
            base_inv.set_bar(index)
        else
            base_inv.set_bar()
        end
    end
    local node = routerlib.create_node(cluster)
    node.requested = node.requested or requested
    node.provided = node.provided or provided
    node.restrictions = node.restrictions or restrictions
    return cluster
end

function routerlib.reconnect_changes()
    for _, cluster in pairs(changed_clusters) do
        if cluster.devices then
            for _, device in pairs(cluster.devices) do
                locallib.add_monitored_device(device)
            end
        end
    end
    changed_clusters = {}
end

---@param cluster Cluster
---@param router LuaEntity?
---@return Node
function routerlib.create_node(cluster, router)
    if not cluster.node and not cluster.deleted then
        if not router then
            _, router = next(cluster.routers)
            if not router then
                return {}
            end
        end
        if tracing then
            debug("create node for link_id=" .. tostring(cluster.link_id))
        end
        local node = structurelib.create_node(router)
        local masterid = router.unit_number
        cluster.node = node
        cluster.masterid = masterid
    end
    return cluster.node
end

---@param entity LuaEntity
---@param tags Tags
function routerlib.on_build(entity, tags)
    entity.link_id = 0

    ---@type table<string, integer>
    local filters
    if tags then
        if tags.filters then
            filters = game.json_to_table(tags.filters --[[@as string]]) --[[@as table<string, integer>]]
        end
    end

    changed_clusters = {}

    local routers, devices = routerlib.compute_cluster(entity)
    if table_size(routers) > router_max then
        entity.destroy()
        return
    end
    local cluster
    if #routers == 1 then
        local link_id = tools.get_id()
        cluster = routerlib.get_or_create_cluster(link_id)

        entity.link_id = link_id
        cluster.routers[entity.unit_number] = entity
        cluster.devices = devices
        changed_clusters[link_id] = cluster
    else
        cluster = routerlib.set_routers_in_cluster(entity, routers, routers[2].link_id, filters)
        cluster.devices = devices
    end

    if filters then
        local inv = entity.get_inventory(defines.inventory.chest)
        ---@cast inv -nil
        local index = routerlib.apply_filters(inv, filters)
        if index > 1 then
            inv.set_bar(index)
        else
            inv.set_bar()
        end
    end

    local node = routerlib.create_node(cluster, entity)
    if tags then
        if tags.requested then
            node.requested = tags.requested --[[@as table<string, RequestedItem> ]]
        end
        if tags.provided then
            node.provided = tags.provided --[[@as table<string, ProvidedItem> ]]
        end
        if tags.restrictions then
            node.restrictions = tags.restrictions --[[@as table<string, boolean> ]]
        end
    end
    routerlib.reconnect_changes()
end

---@param ev EventData.on_player_mined_entity
function routerlib.on_mined(ev)
    local entity = ev.entity
    local position = entity.position
    local surface = entity.surface
    local force = entity.force
    local processed = {}
    ---@type integer?
    local current_id = entity.link_id
    changed_clusters = {}

    if tracing then
        debug("=> on_mined -----------------------------" .. strip(entity.position))
    end
    dump_nodes()

    if routerlib.remove_from_cluster(entity) then
        local inv = entity.get_inventory(defines.inventory.chest)
        ---@cast inv -nil
        local contents = inv.get_contents()

        local force = entity.force --[[@as LuaForce]]
        if ev.player_index and config.place_items_in_inventory then
            local player = game.players[ev.player_index]
            local player_inv = player.get_main_inventory()
            if player_inv then
                for name, count in pairs(contents) do
                    local count1 = player_inv.insert { name = name, count = count }
                    if count1 < count and config.spill_items_on_ground then
                        entity.surface.spill_item_stack(entity.position, { name = name, count = count - count1 }, true, force)
                    end
                end
            end
        else
            if config.spill_items_on_ground then
                for name, count in pairs(contents) do
                    entity.surface.spill_item_stack(entity.position, { name = name, count = count }, true, force)
                end
            end
        end
        return
    end

    for _, d in ipairs(disp) do
        local test_pos = { x = position.x + d.x, y = position.y + d.y }
        local key = get_key(test_pos)

        local routers = surface.find_entities_filtered { name = commons.router_name, position = test_pos,
            force = force }
        if #routers > 0 then
            local root = routers[1]

            if not processed[root.unit_number] then
                local router_list, devices = routerlib.compute_cluster(root, entity)

                for _, r in pairs(router_list) do
                    processed[r.unit_number] = r
                end
                if not current_id then
                    current_id = tools.get_id()
                end
                local cluster = routerlib.set_routers_in_cluster(root, router_list, current_id)
                changed_clusters[current_id] = cluster
                cluster.devices = devices
                current_id = nil
                routerlib.create_node(cluster)
            end
        end
    end
    routerlib.reconnect_changes()
    dump_nodes()
end

--tools.set_tracing(true)

return routerlib
