local commons = require "scripts.commons"
local tools = require "scripts.tools"
local locallib = require "scripts.locallib"
local config = require "scripts.config"
local structurelib = require "scripts.structurelib"

local prefix = commons.prefix
local get_context = structurelib.get_context

local function print(msg)
    log(msg .. "\n")
end

local function dump()
    print("----------- DUMP ----------")
    local context = structurelib.get_context()

    ---@param iopoint IOPoint
    ---@return string
    local function iopoint_tostring(iopoint)
        return "id=" .. tostring(iopoint.id) ..
            ",container=" .. tostring(iopoint.container.unit_number) ..
            ",is_output=" .. tostring(iopoint.is_output) ..
            ",node=" .. tostring(iopoint.node.id) ..
            ",connection=" .. tostring(iopoint.connection.id) ..
            ",content=" .. tools.strip(iopoint.inventory.get_contents())
    end

    ---@type table<integer, Connection>
    local connections = {}
    print("#nodes=" .. tostring(table_size(context.nodes)))
    print("#iopoints=" .. tostring(table_size(context.iopoints)))
    for id, node in pairs(context.nodes) do
        print("------------------------")
        print("NODE[" .. id .. "] " .. tools.strip(node.container.position) .. ",disabled=" .. tostring(node.disabled))
        for inputid, input in pairs(node.inputs) do
            print("  INPUT[" .. inputid .. "]=> " .. iopoint_tostring(input))
            connections[input.connection.id] = input.connection
        end
        print("  ---")
        for outputid, output in pairs(node.outputs) do
            print("  OUTPUT[" .. outputid .. "]=> " .. iopoint_tostring(output))
            connections[output.connection.id] = output.connection
        end
        print("  ---")
        print(" contents=" .. tools.strip(node.inventory.get_contents()))

        if (node.routings) then
            print("  ---")
            for item, routings in pairs(node.routings) do
                for idrouting, routing in pairs(routings) do
                    print("    ROUTING " .. item .. "=>" .. tostring(idrouting) ..
                        "=>item=" .. routing.item .. ",id=" .. tostring(routing.id) ..
                        ",remaining=" .. tostring(routing.remaining) ..
                        ",output=" .. routing.output.id)
                end
            end
        end
        if node.provided then
            print("  ---")
            for item, provided in pairs(node.provided) do
                print("    PROVIDED[" .. item .. "] item=" .. provided.item ..
                    ",provided=" .. tostring(provided.provided))
            end
        end
        if node.requested then
            print("  ---")
            for item, requested in pairs(node.requested) do
                print("    REQUESTED[" .. item .. "]item=" .. requested.item ..
                    ",count=" .. tostring(requested.count) ..
                    ",remaining=" .. tostring(requested.remaining)
                )
            end
        end
        if node.output_map then
            print("  ---")
            for idoutput, iopoints in pairs(node.output_map) do
                for _, iopoint in pairs(iopoints) do
                    print("    OUTPUTMAP[" .. idoutput .. "] => " .. iopoint.id)
                end
            end
        end
    end

    print("------------------------")
    print("#connections=" .. tostring(table_size(connections)))
    for idconnection, connection in pairs(connections) do
        print("------------------------")
        print("CONNECTION[" .. idconnection .. "]")
        for _, input in pairs(connection.inputs) do
            print("    INPUT=>" .. input.id)
        end
        for _, output in pairs(connection.outputs) do
            print("    OUTPUT=>" .. output.id)
        end
    end
    print("----------- END DUMP ----------")
    game.print("Dump ok")
end

---@param force_index any
---@param disabled any
local function disable_all(force_index, disabled)
    local context = get_context()
    for _, node in pairs(context.nodes) do
        node.disabled = disabled
        if not disabled then
            structurelib.reset_node(node)
        end
    end
end

---@param entity LuaEntity
local function gps_to_text(entity)

    if not entity.valid then return end

    local position = entity.position
    return string.format("[gps=%s,%s,%s]", position["x"], position["y"],
                  entity.surface.name)
end

---@param player_index integer
local function list_overflow(player_index)
    local player = game.players[player_index]
    local force = player.force
    local context = get_context()
    player.clear_console()
    for _, node in pairs(context.nodes) do
        if node.container and node.container.valid and node.container.force == force then
            if node.remaining then
                local inventory = structurelib.get_inventory(node.container)
                local proto = node.container.prototype
                player.print({"", gps_to_text(node.container), ":" ,  proto.localised_name, 
                    (inventory and ("," .. tools.strip(inventory.get_contents())) or "" ) })
            end
        end
    end
end

---@param player_index integer
local function list_disconnected(player_index)
    local player = game.players[player_index]
    local force = player.force
    local context = get_context()

    ---@type LuaEntity[]
    local devices = global.monitored_devices
    if not devices then return end
    player.clear_console()
    for _, device in pairs(devices) do
        if device.valid and device.force == force then
            local proto = device.prototype
            player.print({"", gps_to_text(device), ":" ,  proto.localised_name,})
        end
    end
end


commands.add_command("logistic_belt2_dump", { "logistic_belt2_dump" },
    ---@param command CustomCommandData
    function(command)
        dump()
    end)

commands.add_command("logistic_belt2_enable", { "logistic_belt2_enable" },
    ---@param command CustomCommandData
    function(command)
        local player = game.players[command.player_index]
        disable_all(player.force_index, false)
    end)

commands.add_command("logistic_belt2_disable", { "logistic_belt2_disable" },
    ---@param command CustomCommandData
    function(command)
        local player = game.players[command.player_index]
        disable_all(player.force_index, true)
    end)

commands.add_command("logistic_belt2_overflows", { "logistic_belt2_overflows" },
---@param command CustomCommandData
function(command)
    list_overflow(command.player_index)
end)

commands.add_command("logistic_belt2_disconnected", { "logistic_belt2_disconnected" },
---@param command CustomCommandData
function(command)
    list_disconnected(command.player_index)
end)
