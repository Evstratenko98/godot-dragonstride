class_name ActionModeBar
extends HBoxContainer

const BUTTON_SIZE := Vector2(38.0, 38.0)
const BUTTON_SEPARATION := 5
const HOTKEY_HINT_COLOR := Color(0.7, 0.7, 0.75, 1.0)
const MODE_ORDER: Array[int] = [
	PlayerCharacter.ActionMode.MOVE,
	PlayerCharacter.ActionMode.ATTACK,
	PlayerCharacter.ActionMode.INTERACT,
]
const MODE_INPUT_ACTIONS: Array[StringName] = [
	&"select_move_mode",
	&"select_attack_mode",
	&"select_interaction_mode",
]
const MODE_HOTKEY_TEXTS: Array[String] = ["q", "e", "r"]
const MODE_TOOLTIPS: Array[String] = ["Move (Q)", "Attack (E)", "Interact (R)"]

var runtime: WorldRuntime = null
var bound_player: PlayerCharacter = null
var action_buttons: Dictionary[int, Button] = {}
var is_spell_targeting: bool = false


func _ready() -> void:
	add_theme_constant_override("separation", BUTTON_SEPARATION)
	_build_buttons()
	if bound_player != null:
		_refresh_buttons(bound_player.action_mode)
	else:
		InventoryBarCursor.apply(PlayerCharacter.ActionMode.ATTACK)


func _exit_tree() -> void:
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
	_disconnect_player_signal()
	_disconnect_runtime_signals()


func _unhandled_key_input(event: InputEvent) -> void:
	if (
		bound_player == null
		or not bound_player.can_process_local_input()
		or _is_console_open()
		or _is_text_input_focused()
	):
		return

	for mode_index: int in range(MODE_ORDER.size()):
		if not event.is_action_pressed(MODE_INPUT_ACTIONS[mode_index]):
			continue
		_select_action_mode(MODE_ORDER[mode_index])
		get_viewport().set_input_as_handled()
		return


func configure_runtime(new_runtime: WorldRuntime) -> void:
	_disconnect_runtime_signals()
	runtime = new_runtime
	_connect_runtime_signals()
	if bound_player != null and is_node_ready():
		_refresh_buttons(bound_player.action_mode)


func bind_character(player: PlayerCharacter) -> void:
	if player == bound_player:
		if bound_player != null and is_node_ready():
			_refresh_buttons(bound_player.action_mode)
		return
	_disconnect_player_signal()
	bound_player = player
	if bound_player != null and not bound_player.action_mode_changed.is_connected(_on_player_action_mode_changed):
		bound_player.action_mode_changed.connect(_on_player_action_mode_changed)
	if bound_player != null and is_node_ready():
		_refresh_buttons(bound_player.action_mode)


func _build_buttons() -> void:
	for mode_index: int in range(MODE_ORDER.size()):
		var action_mode: int = MODE_ORDER[mode_index]
		var action_button: Button = _create_action_button(
			action_mode,
			MODE_TOOLTIPS[mode_index],
			MODE_HOTKEY_TEXTS[mode_index]
		)
		action_buttons[action_mode] = action_button
		add_child.call_deferred(action_button)


func _create_action_button(action_mode: int, tooltip: String, hotkey_text: String) -> Button:
	var action_button: Button = Button.new()
	action_button.icon = InventoryBarCursor.get_action_texture(action_mode)
	action_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action_button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	action_button.expand_icon = false
	action_button.tooltip_text = tooltip
	action_button.custom_minimum_size = BUTTON_SIZE
	action_button.focus_mode = Control.FOCUS_NONE
	action_button.mouse_filter = Control.MOUSE_FILTER_STOP
	action_button.pressed.connect(_on_action_button_pressed.bind(action_mode))
	action_button.add_child.call_deferred(_create_shortcut_label(hotkey_text))
	InventoryBarStyle.apply_action_button(action_button, false)
	return action_button


func _create_shortcut_label(shortcut_text: String) -> Label:
	var shortcut_label: Label = Label.new()
	shortcut_label.text = shortcut_text
	shortcut_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shortcut_label.offset_right = -3.0
	shortcut_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	shortcut_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	shortcut_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shortcut_label.add_theme_font_size_override("font_size", 9)
	shortcut_label.add_theme_color_override("font_color", HOTKEY_HINT_COLOR)
	return shortcut_label


func _refresh_buttons(action_mode: int) -> void:
	if action_buttons.is_empty():
		return
	var next_action_mode: int = action_mode
	if not _is_action_available(next_action_mode):
		next_action_mode = _find_first_available_mode()

	if bound_player != null and next_action_mode >= 0 and bound_player.action_mode != next_action_mode:
		bound_player.set_action_mode(next_action_mode)
		return

	for mode_index: int in range(MODE_ORDER.size()):
		var button_mode: int = MODE_ORDER[mode_index]
		var button: Button = action_buttons.get(button_mode) as Button
		var is_available: bool = _is_action_available(button_mode)
		var is_selected: bool = is_available and button_mode == next_action_mode and not is_spell_targeting
		button.disabled = not is_available
		button.tooltip_text = MODE_TOOLTIPS[mode_index] if is_available else "Action unavailable in current turn"
		InventoryBarStyle.apply_action_button(button, is_selected)

	InventoryBarCursor.apply(next_action_mode, next_action_mode >= 0)


func _find_first_available_mode() -> int:
	for action_mode: int in MODE_ORDER:
		if _is_action_available(action_mode):
			return action_mode
	return -1


func _select_action_mode(action_mode: int) -> void:
	if (
		bound_player == null
		or not bound_player.can_process_local_input()
		or runtime == null
		or not _is_action_available(action_mode)
	):
		return

	runtime.cancel_spell_targeting(bound_player)
	bound_player.set_action_mode(action_mode)
	_refresh_buttons(bound_player.action_mode)


func _is_action_available(action_mode: int) -> bool:
	if runtime == null or runtime.turn_manager == null or bound_player == null:
		return true
	var turn_manager: WorldTurns = runtime.turn_manager
	if not turn_manager.is_turn_mode_enabled():
		return true
	if not turn_manager.is_entity_active_in_turn(bound_player):
		return false
	if action_mode == PlayerCharacter.ActionMode.MOVE:
		return turn_manager.get_steps_left() > 0
	if action_mode == PlayerCharacter.ActionMode.ATTACK:
		return turn_manager.get_attacks_left() > 0
	return turn_manager.get_interactions_left() > 0


func _connect_runtime_signals() -> void:
	if runtime == null:
		return
	if runtime.turn_manager != null and not runtime.turn_manager.turn_state_changed.is_connected(_on_turn_state_changed):
		runtime.turn_manager.turn_state_changed.connect(_on_turn_state_changed)
	if runtime.spells != null and not runtime.spells.targeting_changed.is_connected(_on_spell_targeting_changed):
		runtime.spells.targeting_changed.connect(_on_spell_targeting_changed)


func _disconnect_runtime_signals() -> void:
	if runtime == null:
		return
	if runtime.turn_manager != null and runtime.turn_manager.turn_state_changed.is_connected(_on_turn_state_changed):
		runtime.turn_manager.turn_state_changed.disconnect(_on_turn_state_changed)
	if runtime.spells != null and runtime.spells.targeting_changed.is_connected(_on_spell_targeting_changed):
		runtime.spells.targeting_changed.disconnect(_on_spell_targeting_changed)


func _disconnect_player_signal() -> void:
	if (
		bound_player != null
		and is_instance_valid(bound_player)
		and bound_player.action_mode_changed.is_connected(_on_player_action_mode_changed)
	):
		bound_player.action_mode_changed.disconnect(_on_player_action_mode_changed)


func _is_text_input_focused() -> bool:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit


func _is_console_open() -> bool:
	var console: Node = get_node_or_null("/root/Console")
	return console != null and console.has_method("is_visible") and console.is_visible()


func _on_action_button_pressed(action_mode: int) -> void:
	_select_action_mode(action_mode)


func _on_player_action_mode_changed(action_mode: int) -> void:
	_refresh_buttons(action_mode)


func _on_spell_targeting_changed(next_is_targeting: bool, _spell_slot_index: int) -> void:
	is_spell_targeting = next_is_targeting
	if bound_player != null:
		_refresh_buttons(bound_player.action_mode)


func _on_turn_state_changed() -> void:
	if bound_player != null:
		_refresh_buttons(bound_player.action_mode)
