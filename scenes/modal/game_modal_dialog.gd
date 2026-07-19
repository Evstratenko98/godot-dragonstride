class_name GameModalDialog
extends Control

signal open_state_changed(is_open: bool)
signal resolved(result: Result)

enum Mode {
	INFORMATION,
	CONFIRMATION,
}

enum Result {
	DISMISSED,
	CONFIRMED,
	DECLINED,
}

const PANEL_COLOR := Color(0.035, 0.045, 0.065, 0.97)
const BORDER_COLOR := Color(0.92, 0.70, 0.20, 0.96)
const TEXT_COLOR := Color(0.94, 0.96, 1.0, 1.0)
const MUTED_TEXT_COLOR := Color(0.76, 0.79, 0.84, 1.0)
const BUTTON_COLOR := Color(0.08, 0.09, 0.12, 0.98)
const BUTTON_HOVER_COLOR := Color(0.18, 0.15, 0.08, 0.98)
const BUTTON_PRESSED_COLOR := Color(0.27, 0.21, 0.08, 0.98)

@onready var panel: PanelContainer = get_node("Backdrop/CenterContainer/Panel") as PanelContainer
@onready var title_label: Label = get_node(
	"Backdrop/CenterContainer/Panel/MarginContainer/Content/Header/TitleLabel"
) as Label
@onready var close_button: Button = get_node(
	"Backdrop/CenterContainer/Panel/MarginContainer/Content/Header/CloseButton"
) as Button
@onready var body_label: Label = get_node(
	"Backdrop/CenterContainer/Panel/MarginContainer/Content/BodyLabel"
) as Label
@onready var actions: HBoxContainer = get_node(
	"Backdrop/CenterContainer/Panel/MarginContainer/Content/Actions"
) as HBoxContainer
@onready var yes_button: Button = get_node(
	"Backdrop/CenterContainer/Panel/MarginContainer/Content/Actions/YesButton"
) as Button
@onready var no_button: Button = get_node(
	"Backdrop/CenterContainer/Panel/MarginContainer/Content/Actions/NoButton"
) as Button

var modal_mode: Mode = Mode.INFORMATION
var is_modal_open: bool = false


func _ready() -> void:
	_apply_style()
	visible = false
	set_process_unhandled_input(false)


func _unhandled_input(_event: InputEvent) -> void:
	if not is_modal_open:
		return

	get_viewport().set_input_as_handled()


func show_information(title_text: String, body_text: String) -> bool:
	return _show_modal(Mode.INFORMATION, title_text, body_text)


func show_confirmation(title_text: String, body_text: String) -> bool:
	return _show_modal(Mode.CONFIRMATION, title_text, body_text)


func is_open() -> bool:
	return is_modal_open


func cancel() -> void:
	if not is_modal_open:
		return

	var result: Result = Result.DECLINED if modal_mode == Mode.CONFIRMATION else Result.DISMISSED
	_resolve(result)


func _show_modal(mode: Mode, title_text: String, body_text: String) -> bool:
	if is_modal_open:
		return false

	modal_mode = mode
	title_label.text = title_text
	body_label.text = body_text
	close_button.visible = modal_mode == Mode.INFORMATION
	actions.visible = modal_mode == Mode.CONFIRMATION
	is_modal_open = true
	visible = true
	set_process_unhandled_input(true)
	open_state_changed.emit(true)
	call_deferred("_focus_primary_control")
	return true


func _resolve(result: Result) -> void:
	if not is_modal_open:
		return

	is_modal_open = false
	visible = false
	set_process_unhandled_input(false)
	_release_modal_focus()
	open_state_changed.emit(false)
	resolved.emit(result)


func _focus_primary_control() -> void:
	if not is_modal_open or not is_inside_tree():
		return

	if modal_mode == Mode.INFORMATION:
		close_button.grab_focus()
	else:
		no_button.grab_focus()


func _release_modal_focus() -> void:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if focus_owner != null and is_ancestor_of(focus_owner):
		focus_owner.release_focus()


func _apply_style() -> void:
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = PANEL_COLOR
	panel_style.border_color = BORDER_COLOR
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	panel_style.shadow_size = 14
	panel.add_theme_stylebox_override("panel", panel_style)

	title_label.add_theme_color_override("font_color", TEXT_COLOR)
	body_label.add_theme_color_override("font_color", MUTED_TEXT_COLOR)
	_apply_button_style(close_button)
	_apply_button_style(yes_button)
	_apply_button_style(no_button)


func _apply_button_style(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _create_button_style(BUTTON_COLOR))
	button.add_theme_stylebox_override("hover", _create_button_style(BUTTON_HOVER_COLOR))
	button.add_theme_stylebox_override("focus", _create_button_style(BUTTON_HOVER_COLOR))
	button.add_theme_stylebox_override("pressed", _create_button_style(BUTTON_PRESSED_COLOR))
	button.add_theme_color_override("font_color", TEXT_COLOR)
	button.add_theme_color_override("font_hover_color", TEXT_COLOR)
	button.add_theme_color_override("font_focus_color", TEXT_COLOR)
	button.add_theme_color_override("font_pressed_color", TEXT_COLOR)


func _create_button_style(background_color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = BORDER_COLOR
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(8.0)
	return style


func _on_close_button_pressed() -> void:
	_resolve(Result.DISMISSED)


func _on_yes_button_pressed() -> void:
	_resolve(Result.CONFIRMED)


func _on_no_button_pressed() -> void:
	_resolve(Result.DECLINED)
