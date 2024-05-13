local commons = require("scripts.commons")

local prefix = commons.prefix
local png = commons.png

local declarations = {}

local sprite

local function add_sprite(name)
    sprite = {
        type = "sprite",
        name = prefix .. "_" .. name,
        filename = png("images/" .. name),
        width = 32,
        height = 32
    }
    table.insert(declarations, sprite)
end

add_sprite("reset_black")
add_sprite("reset_white")
add_sprite("inspect_black")
add_sprite("inspect_white")
add_sprite("purge_black")
add_sprite("purge_white")
add_sprite("stopped")
add_sprite("full")

data:extend(declarations)
