class_name ActionModeButton
extends Button

const BUTTON_SIZE := Vector2(24.0, 24.0)
const ICON_MAX_WIDTH := 17

var shortcut_label: Label = null
var cooldown_label: Label = null


func configure(action_mode: int, tooltip: String, shortcut_text: String) -> void:
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	icon = InventoryBarCursor.get_action_texture(action_mode)
	icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	expand_icon = false
	add_theme_constant_override("icon_max_width", ICON_MAX_WIDTH)
	tooltip_text = tooltip
	custom_minimum_size = BUTTON_SIZE
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	shortcut_label = _create_overlay_label(shortcut_text, 7, HORIZONTAL_ALIGNMENT_RIGHT)
	shortcut_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	shortcut_label.offset_left = -11.0
	shortcut_label.offset_right = -1.0
	shortcut_label.offset_bottom = 10.0
	cooldown_label = _create_overlay_label("", 11, HORIZONTAL_ALIGNMENT_CENTER)
	cooldown_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	InventoryBarStyle.apply_action_button(self, false)


func refresh_visual(is_selected: bool, is_available: bool, tooltip: String, cooldown_turns: int) -> void:
	disabled = not is_available
	tooltip_text = tooltip
	cooldown_label.text = str(cooldown_turns) if cooldown_turns > 0 else ""
	cooldown_label.visible = cooldown_turns > 0
	InventoryBarStyle.apply_action_button(self, is_selected)
	InventoryBarStyle.apply_shortcut_label(shortcut_label, is_selected)


func _create_overlay_label(label_text: String, font_size: int, alignment: int) -> Label:
	var label: Label = Label.new()
	label.text = label_text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.025, 0.9))
	label.add_theme_constant_override("outline_size", 1)
	add_child(label)
	return label
