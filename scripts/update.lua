
local commons = require "scripts.commons"
local tools = require "scripts.tools"
local sushilib = require "scripts.sushilib"
local devicelib = require "scripts.devicelib"
local structurelib = require "scripts.structurelib"
local devicegui = require "scripts.devicegui"

local prefix = commons.prefix

local debug = tools.debug
local get_vars = tools.get_vars
local strip = tools.strip


local old_prefix = ""


---@class UpdateDeviceRequest
---@field item string
---@field count integer

---@class UpdateDeviceParameters
---@field is_overflow boolean
---@field request_table UpdateDeviceRequest[]


local function remote_install()
    remote.add_interface("logistic_belt2_update", {

        ---@param sushi LuaEntity
        ---@param parameters Parameters
        update_sushi = function(sushi, parameters)
            sushilib.update_parameters(sushi, parameters)
        end,

        ---@param device LuaEntity
        ---@param parameters UpdateDeviceParameters
        update_device = function(device, parameters)
            devicelib.update_parameters(device, parameters)
        end,

        ---@param overflow LuaEntity
        ---@param parameters UpdateDeviceParameters
        update_overflow = function(overflow, parameters)
            devicelib.update_parameters(overflow, parameters)
        end
    })

    remote.add_interface("logistic_belt2_filtering", {


        set_restrictions =
        ---@param entity LuaEntity
        ---@param item_set table<string, boolean>²
        ---@param player_index integer
            function(entity, item_set, player_index)
                local context = structurelib.get_context()

                local node = structurelib.get_node(entity)
                if not node then return end

                node.restrictions = item_set

                local player = game.players[player_index]
                if player.opened == entity then
                    devicegui.open(player, entity)
                end
            end
    })
end

tools.on_load(function()
    remote_install()
end)

tools.on_init(function()
    remote_install()
end)
