class_name ActionModeBar
extends VBoxContainer

const BUTTON_SIZE := Vector2(24.0, 24.0)
const BUTTON_ICON_MAX_WIDTH := 17
const BUTTON_SEPARATION := 0
const COLUMN_SIZE := Vector2(24.0, 72.0)
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
const MODE_SHORTCUT_FALLBACKS: Array[String] = ["Q", "E", "R"]
const MODE_TOOLTIPS: Array[String] = ["Пойти", "Атаковать", "Схватить"]

var runtime: WorldRuntime = null
var bound_player: PlayerCharacter = null
var action_buttons: Dictionary[int, Button] = {}
var shortcut_labels: Dictionary[int, Label] = {}
var is_spell_targeting: bool = false
var selected_spell_slot_index: int = -1
var is_character_selected: bool = false
var is_input_blocked: bool = false
var is_action_cursor_owner: bool = false


func _ready() -> void:
	add_theme_constant_override("separation", BUTTON_SEPARATION)
	_build_buttons()
	if bound_player != null:
		_refresh_buttons(bound_player.action_mode)


func _exit_tree() -> void:
	if is_action_cursor_owner:
		InventoryBarCursor.clear_action_cursor()
	_disconnect_player_signals()
	_disconnect_runtime_signals()


func _unhandled_key_input(event: InputEvent) -> void:
	if (
		bound_player == null
		or not is_character_selected
		or is_input_blocked
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
	_disconnect_player_signals()
	bound_player = player
	_connect_player_signals()
	if bound_player != null and is_node_ready():
		_refresh_buttons(bound_player.action_mode)


func set_character_selected(should_be_selected: bool) -> void:
	if is_character_selected == should_be_selected:
		return
	is_character_selected = should_be_selected
	if bound_player != null and is_node_ready():
		_refresh_buttons(bound_player.action_mode)


func set_input_blocked(should_be_blocked: bool) -> void:
	if is_input_blocked == should_be_blocked:
		return
	is_input_blocked = should_be_blocked
	if bound_player != null and is_node_ready():
		_refresh_buttons(bound_player.action_mode)


func _build_buttons() -> void:
	for mode_index: int in range(MODE_ORDER.size()):
		var action_mode: int = MODE_ORDER[mode_index]
		var action_button: Button = _create_action_button(action_mode, MODE_TOOLTIPS[mode_index])
		action_buttons[action_mode] = action_button
		add_child.call_deferred(action_button)


func _create_action_button(action_mode: int, tooltip: String) -> Button:
	var action_button: Button = Button.new()
	action_button.icon = InventoryBarCursor.get_action_texture(action_mode)
	action_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action_button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	action_button.expand_icon = false
	action_button.add_theme_constant_override("icon_max_width", BUTTON_ICON_MAX_WIDTH)
	action_button.tooltip_text = tooltip
	action_button.custom_minimum_size = BUTTON_SIZE
	action_button.focus_mode = Control.FOCUS_NONE
	action_button.mouse_filter = Control.MOUSE_FILTER_STOP
	action_button.pressed.connect(_on_action_button_pressed.bind(action_mode))
	shortcut_labels[action_mode] = _add_shortcut_label(
		action_button,
		_get_shortcut_label(action_mode)
	)
	InventoryBarStyle.apply_action_button(action_button, false)
	return action_button


func _add_shortcut_label(action_button: Button, shortcut_text: String) -> Label:
	var shortcut_label: Label = Label.new()
	shortcut_label.text = shortcut_text
	shortcut_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shortcut_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	shortcut_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	shortcut_label.add_theme_font_size_override("font_size", 7)
	shortcut_label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.025, 0.9))
	shortcut_label.add_theme_constant_override("outline_size", 1)
	InventoryBarStyle.apply_shortcut_label(shortcut_label, false)
	action_button.add_child(shortcut_label)
	shortcut_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	shortcut_label.offset_left = -11.0
	shortcut_label.offset_top = 0.0
	shortcut_label.offset_right = -1.0
	shortcut_label.offset_bottom = 10.0
	return shortcut_label


func _get_shortcut_label(action_mode: int) -> String:
	var mode_index: int = MODE_ORDER.find(action_mode)
	if mode_index < 0:
		return ""
	var input_events: Array[InputEvent] = InputMap.action_get_events(MODE_INPUT_ACTIONS[mode_index])
	for input_event: InputEvent in input_events:
		var key_event: InputEventKey = input_event as InputEventKey
		if key_event == null:
			continue
		var shortcut_text: String = key_event.as_text_physical_keycode()
		if shortcut_text.is_empty():
			shortcut_text = key_event.as_text_keycode()
		if not shortcut_text.is_empty():
			return shortcut_text
	return MODE_SHORTCUT_FALLBACKS[mode_index]


func _refresh_buttons(action_mode: int) -> void:
	if action_buttons.is_empty():
		return

	for mode_index: int in range(MODE_ORDER.size()):
		var button_mode: int = MODE_ORDER[mode_index]
		var button: Button = action_buttons.get(button_mode) as Button
		var is_available: bool = _is_action_available(button_mode)
		var is_selected: bool = is_available and button_mode == action_mode and not is_spell_targeting
		var shortcut_label: Label = shortcut_labels.get(button_mode) as Label
		button.disabled = not is_available
		button.tooltip_text = MODE_TOOLTIPS[mode_index] if is_available else "%s — недоступно" % MODE_TOOLTIPS[mode_index]
		InventoryBarStyle.apply_action_button(button, is_selected)
		InventoryBarStyle.apply_shortcut_label(shortcut_label, is_selected)

	_refresh_cursor(action_mode)


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
	if (
		bound_player == null
		or not is_character_selected
		or is_input_blocked
		or not bound_player.can_process_local_input()
	):
		return false
	if runtime == null or runtime.turn_manager == null:
		return true
	var turn_manager: WorldTurns = runtime.turn_manager
	if not turn_manager.is_turn_mode_enabled():
		return true
	if not turn_manager.is_entity_active_in_turn(bound_player):
		return false
	if action_mode == PlayerCharacter.ActionMode.MOVE:
		return turn_manager.get_steps_left(bound_player.entity_id) > 0
	if action_mode == PlayerCharacter.ActionMode.ATTACK:
		return turn_manager.get_attacks_left(bound_player.entity_id) > 0
	return turn_manager.get_interactions_left(bound_player.entity_id) > 0


func _refresh_cursor(action_mode: int) -> void:
	if not is_character_selected or is_input_blocked or bound_player == null:
		if is_action_cursor_owner:
			InventoryBarCursor.clear_action_cursor()
			is_action_cursor_owner = false
		return
	if _is_meteor_targeting():
		InventoryBarCursor.apply_meteor_targeting()
		is_action_cursor_owner = true
		return
	InventoryBarCursor.apply(action_mode, _is_action_available(action_mode))
	is_action_cursor_owner = true


func _is_meteor_targeting() -> bool:
	if (
		not is_spell_targeting
		or bound_player == null
		or selected_spell_slot_index < 0
		or bound_player.character_inventory == null
	):
		return false
	var spell_id: String = bound_player.character_inventory.get_spell_id_at_slot(
		selected_spell_slot_index
	)
	return spell_id == WorldSpells.SPELL_ID_METEOR


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


func _connect_player_signals() -> void:
	if bound_player == null:
		return
	if not bound_player.action_mode_changed.is_connected(_on_player_action_mode_changed):
		bound_player.action_mode_changed.connect(_on_player_action_mode_changed)
	if not bound_player.movement_started.is_connected(_on_player_activity_changed):
		bound_player.movement_started.connect(_on_player_activity_changed)
	if not bound_player.movement_finished.is_connected(_on_player_activity_changed):
		bound_player.movement_finished.connect(_on_player_activity_changed)
	if not bound_player.attack_finished.is_connected(_on_player_attack_finished):
		bound_player.attack_finished.connect(_on_player_attack_finished)
	if not bound_player.vitality_changed.is_connected(_on_player_vitality_changed):
		bound_player.vitality_changed.connect(_on_player_vitality_changed)


func _disconnect_player_signals() -> void:
	if bound_player == null or not is_instance_valid(bound_player):
		return
	if bound_player.action_mode_changed.is_connected(_on_player_action_mode_changed):
		bound_player.action_mode_changed.disconnect(_on_player_action_mode_changed)
	if bound_player.movement_started.is_connected(_on_player_activity_changed):
		bound_player.movement_started.disconnect(_on_player_activity_changed)
	if bound_player.movement_finished.is_connected(_on_player_activity_changed):
		bound_player.movement_finished.disconnect(_on_player_activity_changed)
	if bound_player.attack_finished.is_connected(_on_player_attack_finished):
		bound_player.attack_finished.disconnect(_on_player_attack_finished)
	if bound_player.vitality_changed.is_connected(_on_player_vitality_changed):
		bound_player.vitality_changed.disconnect(_on_player_vitality_changed)


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


func _on_player_activity_changed(_from_cell: Vector2i, _target_cell: Vector2i) -> void:
	if bound_player != null:
		_refresh_buttons.call_deferred(bound_player.action_mode)


func _on_player_attack_finished(_target_cell: Vector2i) -> void:
	if bound_player != null:
		_refresh_buttons(bound_player.action_mode)


func _on_player_vitality_changed(_current_health: int, _maximum_health: int) -> void:
	if bound_player != null:
		_refresh_buttons(bound_player.action_mode)


func _on_spell_targeting_changed(next_is_targeting: bool, spell_slot_index: int) -> void:
	is_spell_targeting = next_is_targeting
	selected_spell_slot_index = spell_slot_index if next_is_targeting else -1
	if bound_player != null:
		_refresh_buttons(bound_player.action_mode)


func _on_turn_state_changed() -> void:
	if bound_player != null:
		_refresh_buttons(bound_player.action_mode)
