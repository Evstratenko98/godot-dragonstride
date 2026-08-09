class_name GamePauseMenu
extends Control

signal resume_requested
signal camera_mode_requested(camera_mode: String)
signal fog_of_war_requested(is_enabled: bool)
signal exit_game_requested
signal open_state_changed(is_open: bool)

enum MenuView {
	ROOT,
	SETTINGS,
}

@onready var root_menu: VBoxContainer = get_node("Center/Panel/Margin/RootMenu") as VBoxContainer
@onready var settings_menu: VBoxContainer = get_node("Center/Panel/Margin/SettingsMenu") as VBoxContainer
@onready var camera_mode_select: OptionButton = get_node(
	"Center/Panel/Margin/SettingsMenu/CameraModeRow/CameraModeSelect"
) as OptionButton
@onready var fog_of_war_toggle: CheckButton = get_node(
	"Center/Panel/Margin/SettingsMenu/FogOfWarRow/FogOfWarToggle"
) as CheckButton

var current_view: MenuView = MenuView.ROOT
var authoritative_fog_enabled: bool = true
var can_edit_fog: bool = false


func _ready() -> void:
	camera_mode_select.add_item("Свободный режим")
	camera_mode_select.set_item_metadata(0, GameCamera.MODE_FREE)
	camera_mode_select.add_item("Следовать за командой")
	camera_mode_select.set_item_metadata(1, GameCamera.MODE_FOLLOW)
	_set_view(MenuView.ROOT)
	hide()


func open(camera_mode: String, fog_enabled: bool, allow_fog_edit: bool) -> void:
	_select_camera_mode(camera_mode)
	set_fog_of_war_state(fog_enabled, allow_fog_edit)
	_set_view(MenuView.ROOT)
	show()
	open_state_changed.emit(true)


func close() -> void:
	if not visible:
		return
	hide()
	open_state_changed.emit(false)


func is_open() -> bool:
	return visible


func get_current_view() -> MenuView:
	return current_view


func set_fog_of_war_state(is_enabled: bool, allow_edit: bool) -> void:
	authoritative_fog_enabled = is_enabled
	can_edit_fog = allow_edit
	if fog_of_war_toggle == null:
		return
	fog_of_war_toggle.set_pressed_no_signal(authoritative_fog_enabled)
	fog_of_war_toggle.disabled = not can_edit_fog


func handle_cancel() -> void:
	if current_view == MenuView.SETTINGS:
		_set_view(MenuView.ROOT)
		return
	_resume_game()


func _set_view(next_view: MenuView) -> void:
	current_view = next_view
	root_menu.visible = current_view == MenuView.ROOT
	settings_menu.visible = current_view == MenuView.SETTINGS


func _select_camera_mode(camera_mode: String) -> void:
	for item_index: int in range(camera_mode_select.item_count):
		if str(camera_mode_select.get_item_metadata(item_index)) == camera_mode:
			camera_mode_select.select(item_index)
			return
	camera_mode_select.select(1)


func _resume_game() -> void:
	close()
	resume_requested.emit()


func _on_continue_button_pressed() -> void:
	_resume_game()


func _on_settings_button_pressed() -> void:
	_set_view(MenuView.SETTINGS)


func _on_exit_button_pressed() -> void:
	exit_game_requested.emit()


func _on_camera_mode_select_item_selected(item_index: int) -> void:
	var camera_mode: String = str(camera_mode_select.get_item_metadata(item_index))
	camera_mode_requested.emit(camera_mode)


func _on_fog_of_war_toggle_toggled(is_enabled: bool) -> void:
	if not can_edit_fog:
		fog_of_war_toggle.set_pressed_no_signal(authoritative_fog_enabled)
		return
	fog_of_war_requested.emit(is_enabled)
	fog_of_war_toggle.set_pressed_no_signal(authoritative_fog_enabled)


func _on_back_button_pressed() -> void:
	_set_view(MenuView.ROOT)
