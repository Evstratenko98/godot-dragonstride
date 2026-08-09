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
	panel.add_theme_stylebox_override("panel", GameModalStyle.create_panel_style())
	title_label.add_theme_color_override("font_color", GameModalStyle.TEXT_COLOR)
	body_label.add_theme_color_override("font_color", GameModalStyle.MUTED_TEXT_COLOR)
	GameModalStyle.apply_button_style(close_button)
	GameModalStyle.apply_button_style(yes_button)
	GameModalStyle.apply_button_style(no_button)


func _on_close_button_pressed() -> void:
	_resolve(Result.DISMISSED)


func _on_yes_button_pressed() -> void:
	_resolve(Result.CONFIRMED)


func _on_no_button_pressed() -> void:
	_resolve(Result.DECLINED)
