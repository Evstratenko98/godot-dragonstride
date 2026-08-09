class_name GameModalStyle
extends RefCounted

const PANEL_COLOR := Color(0.035, 0.045, 0.065, 0.97)
const BORDER_COLOR := Color(0.92, 0.70, 0.20, 0.96)
const TEXT_COLOR := Color(0.94, 0.96, 1.0, 1.0)
const MUTED_TEXT_COLOR := Color(0.76, 0.79, 0.84, 1.0)
const BUTTON_COLOR := Color(0.08, 0.09, 0.12, 0.98)
const BUTTON_HOVER_COLOR := Color(0.18, 0.15, 0.08, 0.98)
const BUTTON_PRESSED_COLOR := Color(0.27, 0.21, 0.08, 0.98)


static func create_panel_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	style.shadow_size = 14
	return style


static func apply_button_style(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _create_button_style(BUTTON_COLOR))
	button.add_theme_stylebox_override("hover", _create_button_style(BUTTON_HOVER_COLOR))
	button.add_theme_stylebox_override("focus", _create_button_style(BUTTON_HOVER_COLOR))
	button.add_theme_stylebox_override("pressed", _create_button_style(BUTTON_PRESSED_COLOR))
	button.add_theme_color_override("font_color", TEXT_COLOR)
	button.add_theme_color_override("font_hover_color", TEXT_COLOR)
	button.add_theme_color_override("font_focus_color", TEXT_COLOR)
	button.add_theme_color_override("font_pressed_color", TEXT_COLOR)


static func _create_button_style(background_color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = BORDER_COLOR
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(8.0)
	return style
