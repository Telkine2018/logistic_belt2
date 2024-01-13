local commons = require("scripts.commons")

local prefix = commons.prefix
local png = commons.png

local declarations = {}

local sprite

sprite = {
    type = "sprite",
    name = prefix .. "_reset_black",
    filename = png("images/reset_black"),
    width = 32,
    height = 32
}
table.insert(declarations, sprite)

sprite = {
    type = "sprite",
    name = prefix .. "_reset_white",
    filename = png("images/reset_white"),
    width = 32,
    height = 32
}
table.insert(declarations, sprite)

sprite = {
    type = "sprite",
    name = prefix .. "_inspect_black",
    filename = png("images/inspect_black"),
    width = 32,
    height = 32
}
table.insert(declarations, sprite)

sprite = {
    type = "sprite",
    name = prefix .. "_inspect_white",
    filename = png("images/inspect_white"),
    width = 32,
    height = 32
}
table.insert(declarations, sprite)

sprite = {
    type = "sprite",
    name = prefix .. "_purge_black",
    filename = png("images/purge_black"),
    width = 32,
    height = 32
}
table.insert(declarations, sprite)

sprite = {
    type = "sprite",
    name = prefix .. "_purge_white",
    filename = png("images/purge_white"),
    width = 32,
    height = 32
}
table.insert(declarations, sprite)

sprite = {
    type = "sprite",
    name = prefix .. "_stopped",
    filename = png("images/stopped"),
    width = 32,
    height = 32
}
table.insert(declarations, sprite)

data:extend(declarations)
