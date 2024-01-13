local commons = require "scripts.commons"
local tools = require "scripts.tools"
local locallib = require "scripts.locallib"
local config = require "scripts.config"
local structurelib = require "scripts.structurelib"
local nodelib= require "scripts.nodelib"

local prefix = commons.prefix

local debug = tools.debug
local cdebug = tools.cdebug
local get_vars = tools.get_vars
local strip = tools.strip
local get_opposite_direction = tools.get_opposite_direction

local get_back = tools.get_back
local create_inserters = locallib.create_inserters
local clear_entities = locallib.clear_entities

local table_insert = table.insert

---@param name string
local function np(name)
    return prefix .. "_overflow." .. name
end

local overflowlib = {}

---@param iopoint IOPoint
---@param loader LuaEntity?
---@return boolean
local function try_connect(iopoint, loader)
    local entity = iopoint.device
    local speed = locallib.get_belt_speed(entity)
    if not speed then
        return false
    end
    local inserter_count = locallib.get_inserter_count_from_speed(speed)

    if not loader then
        local loaders = entity.surface.find_entities_filtered { name = commons.overflow_loader_name, position = entity.position }
        if #loaders ~= 1 then return false end
        loader = loaders[1]
    end

    local container = nodelib.create_output_objects(iopoint, loader, inserter_count)
    if not container then
        return false
    end

    nodelib.create_internal_container(iopoint)
    local node = structurelib.get_node(container)
    if not node then
        node = structurelib.create_node(container)
    end
    iopoint.node = node

    if not node.overflows then
        node.overflows = { [iopoint.id] = iopoint }
    else
        node.overflows[iopoint.id] = iopoint
    end
    return true
end
overflowlib.try_connect = try_connect

---@param entity LuaEntity
---@param tags Tags
function overflowlib.on_built_entity(entity, tags)
    entity.active = false
    entity.rotatable = false
    if not locallib.adjust_direction(entity) then
        entity.rotatable = false
    end
    local loader = locallib.create_loader(entity, commons.overflow_loader_name)
    loader.active = false

    --- Register
    local iopoint_id = entity.unit_number
    ---@type IOPoint
    local iopoint = {
        id = iopoint_id,
        device = entity,
        overflows = {}
    }
    if tags and tags.overflows then
        iopoint.overflows = tags.overflows --[[@as table<string, integer>]]
    end
    
    local context = structurelib.get_context()
    context.iopoints[iopoint_id] = iopoint

    if not try_connect(iopoint, loader) then
        locallib.add_monitored_device(iopoint.device)
    end
end

---@param entity LuaEntity
function overflowlib.on_mined(entity)
    tools.close_ui(entity.unit_number, locallib.close_ui)

    local context = structurelib.get_context()
    local id = entity.unit_number
    local iopoint = context.iopoints[id]
    if not iopoint then goto __end__ end
    context.iopoints[id] = nil
    locallib.disconnect_overflow(iopoint)

    ::__end__::
    clear_entities(entity, locallib.entities_to_destroy)
end

---@param overflow_table LuaGuiElement
---@param item string?
---@param count integer?
local function add_overflow_field(overflow_table, item, count)
    local item_field = overflow_table.add {
        type = "choose-elem-button",
        elem_type = "item",
        tooltip = { np("overflow_item_tooltip") }
    }
    if item then
        item_field.elem_value = item
    end
    tools.set_name_handler(item_field, np("overflow_item"))

    local count_field = overflow_table.add {
        type = "textfield",
        tooltip = { np("overflow_count_tooltip") },
        numeric = true,
        allow_negative = false
    }
    if count then
        count_field.text = tostring(count)
    end
    tools.set_name_handler(count_field, np("overflow_count"))

    count_field.style.width = 80
    return item_field, count_field
end

---@param event EventData.on_gui_opened
local function on_gui_open_overflow_panel(event)
    local player = game.players[event.player_index]

    local entity = event.entity
    if not entity or not entity.valid or entity.name ~= commons.overflow_name then
        return
    end
    locallib.close_ui(player)

    local vars    = get_vars(player)
    player.opened = nil

    local context = structurelib.get_context()
    local iopoint = context.iopoints[entity.unit_number]
    if not iopoint then return end

    vars.selected_iopoint = iopoint

    local frame   = player.gui.left.add {
        type = "frame",
        name = commons.overflow_panel_name,
        direction = "vertical"
    }
    locallib.add_title(frame, np("title"))

    local inner_frame = frame.add {
        type = "frame",
        direction = "vertical",
        style = "inside_shallow_frame_with_padding"
    }

    inner_frame.add { type = "label", caption = { np("items") } }
    local overflow_table = inner_frame.add { type = "table", column_count = 4, style_mods = { margin = 10 }, name = np("overflow_table") }

    for item, count in pairs(iopoint.overflows) do
        add_overflow_field(overflow_table, item, count)
    end
    add_overflow_field(overflow_table)

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

tools.on_gui_click(np("save"), 
---@param e EventData.on_gui_click
function(e)
    local player = game.players[e.player_index]
    overflowlib.save(player)
    locallib.close_ui(player)
end)

tools.on_event(defines.events.on_gui_confirmed, 
---@param e EventData.on_gui_confirmed
function(e)
    local player = game.players[e.player_index]
    if player.gui.left[commons.overflow_panel_name] then
        overflowlib.save(player)
        locallib.close_ui(player)
    end
end)

tools.on_event(defines.events.on_gui_opened, on_gui_open_overflow_panel)

---@param e EventData.on_gui_elem_changed
local function on_overflow_item_changed(e)
    local player = game.players[e.player_index]
    if not e.element or not e.element.valid then return end

    local panel = player.gui.left[commons.overflow_panel_name]
    if not panel then return end

    local f_overflow_table = tools.get_child(panel, np("overflow_table"))
    if not f_overflow_table then return end

    local children = f_overflow_table.children
    local count = #children

    if e.element.elem_value then
        local index = tools.index_of(children, e.element)
        children[index + 1].text = tostring(game.item_prototypes[e.element.elem_value].stack_size)
    end
    if e.element == children[count - 1] then
        if e.element.elem_value then
            add_overflow_field(f_overflow_table)
        end
    else
        if not e.element.elem_value then
            local index = tools.index_of(children, e.element)
            e.element.destroy()
            children[index + 1].destroy()
        end
    end
end
tools.on_named_event(np("overflow_item"), defines.events.on_gui_elem_changed, on_overflow_item_changed)


---@param player LuaPlayer
function overflowlib.save(player)
	local vars = get_vars(player)

	---@type IOPoint
	local iopoint = vars.selected_iopoint
	if not iopoint or not iopoint.container or not iopoint.container.valid then return end

	local frame = player.gui.left[commons.overflow_panel_name]
	if not frame then return end

	local request_table = tools.get_child(frame, np("overflow_table"))
	if request_table ~= nil then
		---@type table<string, integer>
		local overflows = {}

		local children = request_table.children
		local index = 1
		while index <= #children do
			local f_item = children[index]
			local f_count = children[index + 1]
			local item = f_item.elem_value
			local tcount = f_count.text
			local count = tonumber(tcount)

			if count and item then
                overflows[item] = count
			end
			index = index + 2
		end
        iopoint.overflows = overflows
	end
end

return overflowlib
