class_name MenuPresentation
extends Node

const CURSOR_TEXTURE: Texture2D = preload("res://art/pointers/hand_small_point_n.svg")
const CURSOR_HOTSPOT := Vector2(15.0, 4.0)
const TEXT_COLOR := Color(0.94, 0.96, 1.0, 1.0)
const MUTED_TEXT_COLOR := Color(0.58, 0.63, 0.72, 1.0)
const ACCENT_COLOR := Color(1.0, 0.82, 0.20, 1.0)
const BORDER_COLOR := Color(0.27, 0.31, 0.38, 0.95)
const PANEL_COLOR := Color(0.055, 0.065, 0.085, 0.96)


func _ready() -> void:
	var screen: Control = get_parent() as Control
	if screen != null:
		screen.theme = _create_theme()
	_apply_menu_cursor()


func _exit_tree() -> void:
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_POINTING_HAND)


func _apply_menu_cursor() -> void:
	Input.set_custom_mouse_cursor(CURSOR_TEXTURE, Input.CURSOR_ARROW, CURSOR_HOTSPOT)
	Input.set_custom_mouse_cursor(CURSOR_TEXTURE, Input.CURSOR_POINTING_HAND, CURSOR_HOTSPOT)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _create_theme() -> Theme:
	var menu_theme: Theme = Theme.new()
	menu_theme.set_color("font_color", "Label", TEXT_COLOR)
	menu_theme.set_color("font_shadow_color", "Label", Color(0.0, 0.0, 0.0, 0.55))
	menu_theme.set_constant("shadow_offset_x", "Label", 1)
	menu_theme.set_constant("shadow_offset_y", "Label", 2)
	menu_theme.set_font_size("font_size", "Label", 16)
	menu_theme.set_font_size("font_size", "Button", 16)
	menu_theme.set_font_size("font_size", "OptionButton", 15)
	menu_theme.set_color("font_color", "Button", TEXT_COLOR)
	menu_theme.set_color("font_hover_color", "Button", Color.WHITE)
	menu_theme.set_color("font_pressed_color", "Button", ACCENT_COLOR)
	menu_theme.set_color("font_disabled_color", "Button", MUTED_TEXT_COLOR.darkened(0.25))
	menu_theme.set_color("font_color", "OptionButton", TEXT_COLOR)
	menu_theme.set_color("font_hover_color", "OptionButton", Color.WHITE)
	menu_theme.set_color("font_pressed_color", "OptionButton", ACCENT_COLOR)
	menu_theme.set_stylebox("normal", "Button", _create_button_style(Color(0.075, 0.09, 0.12, 0.98), BORDER_COLOR))
	menu_theme.set_stylebox("hover", "Button", _create_button_style(Color(0.11, 0.14, 0.19, 1.0), ACCENT_COLOR))
	menu_theme.set_stylebox("pressed", "Button", _create_button_style(Color(0.045, 0.055, 0.075, 1.0), ACCENT_COLOR.darkened(0.18)))
	menu_theme.set_stylebox("focus", "Button", _create_button_style(Color(0.0, 0.0, 0.0, 0.0), ACCENT_COLOR))
	menu_theme.set_stylebox("disabled", "Button", _create_button_style(Color(0.045, 0.05, 0.065, 0.82), BORDER_COLOR.darkened(0.25)))
	menu_theme.set_stylebox("normal", "OptionButton", _create_button_style(Color(0.075, 0.09, 0.12, 0.98), BORDER_COLOR))
	menu_theme.set_stylebox("hover", "OptionButton", _create_button_style(Color(0.11, 0.14, 0.19, 1.0), ACCENT_COLOR))
	menu_theme.set_stylebox("pressed", "OptionButton", _create_button_style(Color(0.045, 0.055, 0.075, 1.0), ACCENT_COLOR.darkened(0.18)))
	menu_theme.set_stylebox("focus", "OptionButton", _create_button_style(Color(0.0, 0.0, 0.0, 0.0), ACCENT_COLOR))
	menu_theme.set_stylebox("panel", "PanelContainer", _create_panel_style())
	menu_theme.set_type_variation("CompactMenuPanel", "PanelContainer")
	menu_theme.set_stylebox("panel", "CompactMenuPanel", _create_compact_panel_style())
	menu_theme.set_type_variation("PrimaryMenuButton", "Button")
	menu_theme.set_color("font_color", "PrimaryMenuButton", ACCENT_COLOR)
	menu_theme.set_color("font_hover_color", "PrimaryMenuButton", Color(0.055, 0.065, 0.085, 1.0))
	menu_theme.set_color("font_pressed_color", "PrimaryMenuButton", Color(0.055, 0.065, 0.085, 1.0))
	menu_theme.set_stylebox("normal", "PrimaryMenuButton", _create_button_style(Color(0.12, 0.11, 0.065, 0.98), ACCENT_COLOR.darkened(0.14)))
	menu_theme.set_stylebox("hover", "PrimaryMenuButton", _create_button_style(ACCENT_COLOR, ACCENT_COLOR))
	menu_theme.set_stylebox("pressed", "PrimaryMenuButton", _create_button_style(ACCENT_COLOR.darkened(0.18), ACCENT_COLOR.darkened(0.2)))
	menu_theme.set_stylebox("focus", "PrimaryMenuButton", _create_button_style(Color(0.0, 0.0, 0.0, 0.0), ACCENT_COLOR))
	menu_theme.set_type_variation("DangerMenuButton", "Button")
	menu_theme.set_color("font_hover_color", "DangerMenuButton", Color.WHITE)
	menu_theme.set_stylebox("normal", "DangerMenuButton", _create_button_style(Color(0.09, 0.065, 0.075, 0.98), Color(0.48, 0.22, 0.25, 0.9)))
	menu_theme.set_stylebox("hover", "DangerMenuButton", _create_button_style(Color(0.32, 0.09, 0.11, 1.0), Color(0.92, 0.32, 0.36, 1.0)))
	menu_theme.set_stylebox("pressed", "DangerMenuButton", _create_button_style(Color(0.22, 0.055, 0.07, 1.0), Color(0.76, 0.24, 0.28, 1.0)))
	menu_theme.set_stylebox("focus", "DangerMenuButton", _create_button_style(Color(0.0, 0.0, 0.0, 0.0), Color(0.92, 0.32, 0.36, 1.0)))
	menu_theme.set_color("font_color", "PopupMenu", TEXT_COLOR)
	menu_theme.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	menu_theme.set_stylebox("panel", "PopupMenu", _create_button_style(PANEL_COLOR, BORDER_COLOR))
	menu_theme.set_stylebox("hover", "PopupMenu", _create_button_style(Color(0.11, 0.14, 0.19, 1.0), ACCENT_COLOR))
	return menu_theme


func _create_button_style(background_color: Color, outline_color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = outline_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 18.0
	style.content_margin_top = 12.0
	style.content_margin_right = 18.0
	style.content_margin_bottom = 12.0
	return style


func _create_panel_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.38)
	style.shadow_size = 12
	style.content_margin_left = 28.0
	style.content_margin_top = 26.0
	style.content_margin_right = 28.0
	style.content_margin_bottom = 26.0
	return style


func _create_compact_panel_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.075, 0.09, 0.12, 0.9)
	style.border_color = Color(0.22, 0.26, 0.33, 0.92)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14.0
	style.content_margin_top = 10.0
	style.content_margin_right = 14.0
	style.content_margin_bottom = 10.0
	return style
