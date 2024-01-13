local util = require("__core__/lualib/util")
local commons = require("scripts.commons")
local tools = require("scripts.tools")

local structurelib = require("scripts.structurelib")
local locallib = require("scripts.locallib")
local nodelib = require("scripts.nodelib")

local inspectlib = {}

local prefix = commons.prefix
local debug = tools.debug
local cdebug = tools.cdebug
local get_vars = tools.get_vars
local strip = tools.strip

---@param name string
---@return string
local function np(name)
    return prefix .. "-inspect." .. name
end

local inspect_name = np("inspector")

---@param player LuaPlayer
local function get_frame(player)
    local frame = player.gui.left[inspect_name]
    local signal_table
    if not frame then
        frame = player.gui.left.add { type = "frame", name = inspect_name, direction = "vertical" }

        local titleflow = frame.add { type = "flow", name = "titleflow" }
        titleflow.add {
            type = "label",
            caption = { np("title") },
            style = "frame_title",
            ignored_by_interaction = true,
            name = "label"
        }

        local empty = titleflow.add {
            type = "empty-widget",
        }
        empty.style.horizontally_stretchable = true

        titleflow.add {
            type = "sprite-button",
            name = np("close"),
            style = "frame_action_button",
            mouse_button_filter = { "left" },
            sprite = "utility/close_white",
            hovered_sprite = "utility/close_black"
        }

        local inner_frame = frame.add {
            type = "frame",
            direction = "vertical",
            style = "inside_shallow_frame_with_padding",
            name = "inner_frame"
        }
        return inner_frame
    else
        frame.inner_frame.clear()
    end
    return frame.inner_frame
end

local button_style = commons.prefix .. "_slot_button_default"

---@param item_table {item:string}[]
local function sort_item_table(item_table)
    local order_map = {}
    local function get_order(item)
        local order = order_map[item]
        if order then return order end

        local proto = game.item_prototypes[item]
        order = proto.group.order .. "  " .. proto.subgroup.order .. "  " .. proto.order
        order_map[item] = order
        return order
    end
    table.sort(item_table, function(e1, e2)
        local order1 = get_order(e1.item)
        local order2 = get_order(e2.item)
        return order1 < order2
    end)
end

---@param map table<string, any>
local function sort_contents(map)
    local result = {}
    for item, value in pairs(map) do
        table.insert(result, {
            item = item,
            value = value
        })
    end
    sort_item_table(result)
    return result
end

---@param frame LuaGuiElement
---@param contents table<string, integer>
local function show_content(frame, contents)
    local list = sort_contents(contents)
    local signal_table = frame.add { type = "table", column_count = 10 }
    signal_table.style.cell_padding = 0
    for _, e in pairs(list) do
        local button = signal_table.add {
            type      = "choose-elem-button",
            elem_type = "item",
            item      = e.item
        }
        button.locked = true
        button.style.margin = 0
        button.style = button_style

        button.add {
            type = "label",
            name = "label1",
            style = "count_label_bottom",
            ignored_by_interaction = true,
            caption = util.format_number(e.value, true)
        }
    end
end

---@param position MapPosition
---@return string
local function position_to_string(position)
    return "position=[" .. position.x .. "," .. position.y .. "]"
end

---@param frame LuaGuiElement
---@param node Node
local function show_requests(frame, node)
    local result = {}
    for item, request in pairs(node.requested) do
        table.insert(result, {
            item = item,
            request = request
        })
    end
    sort_item_table(result)

    ---@type LuaGuiElement
    local signal_table
    for _, value in pairs(result) do
        local item = value.item
        local request = value.request

        if not signal_table then
            frame.add { type = "line" }
            frame.add { type = "label", caption = { np("requests") } }
            signal_table = frame.add { type = "table", column_count = 10 }
            signal_table.style.padding = 0
        end

        local button = signal_table.add {
            type      = "choose-elem-button",
            elem_type = "item",
            item      = item
        }
        button.style = button_style
        button.style.margin = 0

        button.add {
            type = "label",
            name = "label1",
            style = "count_label_bottom",
            ignored_by_interaction = true,
            caption = util.format_number(request.remaining, true)
        }
        button.add {
            type = "label",
            name = "label2",
            style = "count_label_top",
            ignored_by_interaction = true,
            caption = util.format_number(request.count, true)
        }
    end
end

---@param player LuaPlayer
---@param entity LuaEntity
function inspectlib.show(player, entity)
    if not (entity and entity.valid) then
        inspectlib.close(player)
        return
    end

    local inner_frame = get_frame(player)
    local function print(msg)
        inner_frame.add { type = "label", caption = msg }
    end

    local context = structurelib.get_context()
    if locallib.container_type_map[entity.type] then
        local node = structurelib.get_node(entity)
        if not node then
            print("Node not found")
            return
        end
        local msg = { "", "Node(" .. node.id .. ") " }
        if node.disabled then
            table.insert(msg, "[img=" .. prefix .. "_stopped]")
        end
        inner_frame.parent.titleflow.label.caption = msg

        if node.remaining then
            inner_frame.add { type = "line" }
            inner_frame.add { type = "label", caption = { np("overflow_items") } }
            show_content(inner_frame, node.remaining)
        end

        local all_requests = nodelib.get_requests(node)
        if next(all_requests) then
            inner_frame.add { type = "line" }
            inner_frame.add { type = "label", caption = {np("unsatisfied_requests")} }
            show_content(inner_frame, all_requests)
        end

        local stock = nodelib.get_stock(node)
        if next(stock) then
            inner_frame.add { type = "line" }
            inner_frame.add { type = "label", caption = { np("stock") } }
            show_content(inner_frame, stock)
        end

        if node.routings and next(node.routings) then
            inner_frame.add { type = "line" }
            inner_frame.add { type = "label", caption = { np("routing") } }
            local contents = {}
            for item, map_route in pairs(node.routings) do
                for _, routing in pairs(map_route) do
                    contents[item] = (contents[item] or 0) + routing.remaining
                end
            end
            show_content(inner_frame, contents)
        end

        if node.requested and next(node.requested) then
            show_requests(inner_frame, node)
        end

        if node.provided and next(node.provided) then
            inner_frame.add { type = "line" }
            inner_frame.add { type = "label", caption = { np("provides") } }

            local contents = {}
            for item, provided in pairs(node.provided) do
                contents[item] = provided.provided
            end
            show_content(inner_frame, contents)
        end

        if node.inputs then
            local input_content = {}
            for _, input in pairs(node.inputs) do
                local contents = input.inventory.get_contents()
                for item, count in pairs(contents) do
                    input_content[item] = (input_content[item] or 0) + count
                end
            end
            if next(input_content) then
                inner_frame.add { type = "line" }
                inner_frame.add { type = "label", caption = { np("input") } }
                show_content(inner_frame, input_content)
            end
        end

        if node.outputs then
            local output_content = {}
            for _, output in pairs(node.outputs) do
                local contents = output.inventory.get_contents()
                for item, count in pairs(contents) do
                    output_content[item] = (output_content[item] or 0) + count
                end
            end
            if next(output_content) then
                inner_frame.add { type = "line" }
                inner_frame.add { type = "label", caption = { np("output") } }
                show_content(inner_frame, output_content)
            end
        end
    else
        inspectlib.close(player)
    end

    tools.get_vars(player).inspectlib_selected = entity
end

function inspectlib.close(player)
    tools.get_vars(player).inspectlib_selected = nil
    local frame = player.gui.left[inspect_name]
    if frame then
        frame.destroy()
    end
end

tools.on_gui_click(np("close"),
    ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]
        inspectlib.close(player)
        get_vars(player).inspectlib_keep = nil
    end
)

function inspectlib.refresh()
    for _, player in pairs(game.players) do
        local entity = tools.get_vars(player).inspectlib_selected
        if entity then
            inspectlib.show(player, entity)
        end
    end
end

script.on_nth_tick(20, inspectlib.refresh)


---@param player LuaPlayer
---@param entity LuaEntity
function inspectlib.toogle_keep(player, entity)
    local keep = not get_vars(player).inspectlib_keep
    get_vars(player).inspectlib_keep = keep

    if keep then
        inspectlib.show(player, entity)
    else
        inspectlib.close(player)
    end
end

---@param player LuaPlayer
---@param entity LuaEntity
function inspectlib.update(player, entity)
    local keep = get_vars(player).inspectlib_keep
    if not keep then return end
    inspectlib.show(player, entity)
end

tools.on_event(defines.events.on_selected_entity_changed,

    ---@param e EventData.on_selected_entity_changed
    function(e)
        local player = game.players[e.player_index]
        local keep = get_vars(player).inspectlib_keep
        if keep then return end
        inspectlib.show(player, player.selected)
    end)

return inspectlib
