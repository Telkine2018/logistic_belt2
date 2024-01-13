local commons = require("scripts.commons")
local tools = require("scripts.tools")


local styles = data.raw["gui-style"].default

styles["count_label_bottom"] = {
    type = "label_style",
    parent = "count_label",
    height = 36,
    width = 36,
    vertical_align = "bottom",
    horizontal_align = "right",
    right_padding = 2
}
styles["count_label_top"] = {
    type = "label_style",
    parent = "count_label_bottom",
    vertical_align = "top",
}

styles["count_label_center"] = {
    type = "label_style",
    parent = "count_label_bottom",
    vertical_align = "center",
}

for _, color in pairs {
    "default", "grey", "red", "orange", "yellow", "green", "cyan", "blue",
    "purple", "pink"
} do
    styles[commons.prefix .. "_slot_button_" .. color] = {
        type = "button_style",
        parent = "flib_slot_button_" .. color,
        size = 40
    }
end


