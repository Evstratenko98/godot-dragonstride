class_name InventoryBarStyle
extends RefCounted


static func apply_action_button(action_button: Button, is_selected: bool) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.32, 0.24, 0.06, 0.78) if is_selected else Color(0.06, 0.06, 0.08, 0.70)
	style.border_color = Color(1.0, 0.78, 0.18, 0.92) if is_selected else Color(0.3, 0.3, 0.35, 0.82)
	style.set_border_width_all(2 if is_selected else 1)
	style.set_corner_radius_all(3)
	var disabled_style: StyleBoxFlat = StyleBoxFlat.new()
	disabled_style.bg_color = Color(0.05, 0.05, 0.06, 0.50)
	disabled_style.border_color = Color(0.22, 0.22, 0.25, 0.65)
	disabled_style.set_border_width_all(1)
	disabled_style.set_corner_radius_all(3)
	action_button.add_theme_stylebox_override("normal", style)
	action_button.add_theme_stylebox_override("hover", style)
	action_button.add_theme_stylebox_override("pressed", style)
	action_button.add_theme_stylebox_override("disabled", disabled_style)
	action_button.add_theme_color_override(
		"font_color",
		Color(1.0, 0.93, 0.68, 1.0) if is_selected else Color(0.7, 0.7, 0.75, 1.0)
	)
	action_button.add_theme_color_override("icon_disabled_color", Color(0.42, 0.42, 0.45, 0.72))
