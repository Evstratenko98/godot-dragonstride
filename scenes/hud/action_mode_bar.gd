class_name ActionModeBar
extends VBoxContainer

const BUTTON_ROW_SEPARATION := 4
const COLUMN_SIZE := Vector2(52.0, 72.0)
const MODE_ORDER: Array[int] = [
	PlayerCharacter.ActionMode.MOVE,
	PlayerCharacter.ActionMode.ATTACK,
	PlayerCharacter.ActionMode.INTERACT,
	PlayerCharacter.ActionMode.SPECIAL_ABILITY,
]
const MODE_INPUT_ACTIONS: Array[StringName] = [
	&"select_move_mode",
	&"select_attack_mode",
	&"select_interaction_mode",
	&"select_special_ability",
]
const MODE_SHORTCUT_FALLBACKS: Array[String] = ["Q", "E", "R", "T"]
const MODE_TOOLTIPS: Array[String] = [
	"Перемещение",
	"Атака",
	"Взаимодействие",
	"Агр: спровоцировать соседнее существо",
]

var runtime: WorldRuntime = null
var bound_player: PlayerCharacter = null
var action_buttons: Dictionary[int, ActionModeButton] = {}
var is_spell_targeting: bool = false
var selected_spell_slot_index: int = -1
var is_character_selected: bool = false
var is_input_blocked: bool = false
var is_action_cursor_owner: bool = false


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	_build_buttons()
	if bound_player != null:
		_refresh_buttons(bound_player.action_mode)


func _exit_tree() -> void:
	if is_action_cursor_owner:
		InventoryBarCursor.clear_action_cursor()
	_disconnect_player_signals()
	_disconnect_runtime_signals()


func _unhandled_key_input(event: InputEvent) -> void:
	if not _can_handle_input():
		return
	for mode_index: int in range(MODE_ORDER.size()):
		if event.is_action_pressed(MODE_INPUT_ACTIONS[mode_index]):
			_select_action_mode(MODE_ORDER[mode_index])
			get_viewport().set_input_as_handled()
			return


func configure_runtime(new_runtime: WorldRuntime) -> void:
	_disconnect_runtime_signals()
	runtime = new_runtime
	_connect_runtime_signals()
	_refresh_if_bound()


func bind_character(player: PlayerCharacter) -> void:
	if player != bound_player:
		_disconnect_player_signals()
		bound_player = player
		_connect_player_signals()
	_refresh_if_bound()


func set_character_selected(should_be_selected: bool) -> void:
	is_character_selected = should_be_selected
	_refresh_if_bound()


func set_input_blocked(should_be_blocked: bool) -> void:
	is_input_blocked = should_be_blocked
	_refresh_if_bound()


func _build_buttons() -> void:
	var top_row: HBoxContainer = _create_button_row()
	var vertical_spacer: Control = Control.new()
	vertical_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vertical_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bottom_row: HBoxContainer = _create_button_row()
	add_child(top_row)
	add_child(vertical_spacer)
	add_child(bottom_row)
	for mode_index: int in range(MODE_ORDER.size()):
		var action_mode: int = MODE_ORDER[mode_index]
		var button: ActionModeButton = ActionModeButton.new()
		button.configure(action_mode, MODE_TOOLTIPS[mode_index], _get_shortcut_label(mode_index))
		button.pressed.connect(_select_action_mode.bind(action_mode))
		action_buttons[action_mode] = button
		if mode_index < 2:
			top_row.add_child(button)
		else:
			bottom_row.add_child(button)


func _create_button_row() -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", BUTTON_ROW_SEPARATION)
	return row


func _get_shortcut_label(mode_index: int) -> String:
	for input_event: InputEvent in InputMap.action_get_events(MODE_INPUT_ACTIONS[mode_index]):
		var key_event: InputEventKey = input_event as InputEventKey
		if key_event != null:
			var shortcut_text: String = key_event.as_text_physical_keycode()
			if shortcut_text.is_empty():
				shortcut_text = key_event.as_text_keycode()
			if not shortcut_text.is_empty():
				return shortcut_text
	return MODE_SHORTCUT_FALLBACKS[mode_index]


func _refresh_buttons(action_mode: int) -> void:
	for mode_index: int in range(MODE_ORDER.size()):
		var button_mode: int = MODE_ORDER[mode_index]
		var button: ActionModeButton = action_buttons.get(button_mode) as ActionModeButton
		var is_available: bool = _is_action_available(button_mode)
		var cooldown_turns: int = _get_cooldown(button_mode)
		var tooltip: String = MODE_TOOLTIPS[mode_index]
		if cooldown_turns > 0:
			tooltip = "%s — перезарядка: %d х." % [tooltip, cooldown_turns]
		elif not is_available:
			tooltip = "%s — недоступно" % tooltip
		button.refresh_visual(
			is_available and button_mode == action_mode and not is_spell_targeting,
			is_available,
			tooltip,
			cooldown_turns
		)
	_refresh_cursor(action_mode)


func _select_action_mode(action_mode: int) -> void:
	if bound_player == null or runtime == null or not _is_action_available(action_mode):
		return
	var should_cancel: bool = not is_spell_targeting and bound_player.action_mode == action_mode
	runtime.cancel_spell_targeting(bound_player)
	bound_player.set_action_mode(PlayerCharacter.ActionMode.NONE if should_cancel else action_mode)
	_refresh_buttons(bound_player.action_mode)


func _is_action_available(action_mode: int) -> bool:
	if not _has_available_character():
		return false
	if runtime == null or runtime.turn_manager == null:
		return action_mode != PlayerCharacter.ActionMode.SPECIAL_ABILITY
	var turns: WorldTurns = runtime.turn_manager
	if not turns.is_turn_mode_enabled():
		return action_mode != PlayerCharacter.ActionMode.SPECIAL_ABILITY
	if not turns.is_entity_active_in_turn(bound_player):
		return false
	match action_mode:
		PlayerCharacter.ActionMode.MOVE:
			return turns.get_steps_left(bound_player.entity_id) > 0
		PlayerCharacter.ActionMode.ATTACK:
			return turns.get_attacks_left(bound_player.entity_id) > 0
		PlayerCharacter.ActionMode.INTERACT:
			return turns.get_interactions_left(bound_player.entity_id) > 0
		PlayerCharacter.ActionMode.SPECIAL_ABILITY:
			return runtime.can_character_use_ability(bound_player)
	return false


func _get_cooldown(action_mode: int) -> int:
	if action_mode != PlayerCharacter.ActionMode.SPECIAL_ABILITY or runtime == null:
		return 0
	return runtime.get_character_ability_cooldown(bound_player)


func _refresh_cursor(action_mode: int) -> void:
	if not is_character_selected or is_input_blocked or bound_player == null:
		_clear_cursor_if_owned()
		return
	if _is_meteor_targeting():
		InventoryBarCursor.apply_meteor_targeting()
		is_action_cursor_owner = true
		return
	if action_mode == PlayerCharacter.ActionMode.NONE:
		_clear_cursor_if_owned()
		return
	InventoryBarCursor.apply(action_mode, _is_action_available(action_mode))
	is_action_cursor_owner = true


func _clear_cursor_if_owned() -> void:
	if is_action_cursor_owner:
		InventoryBarCursor.clear_action_cursor()
		is_action_cursor_owner = false


func _is_meteor_targeting() -> bool:
	return (
		is_spell_targeting
		and bound_player != null
		and selected_spell_slot_index >= 0
		and bound_player.character_inventory != null
		and bound_player.character_inventory.get_spell_id_at_slot(selected_spell_slot_index) == WorldSpells.SPELL_ID_METEOR
	)


func _can_handle_input() -> bool:
	return (
		_has_available_character()
		and not _is_console_open()
		and not _is_text_input_focused()
	)


func _has_available_character() -> bool:
	return (
		bound_player != null
		and is_character_selected
		and not is_input_blocked
		and bound_player.is_locally_owned
		and bound_player.is_selected_local_character
		and bound_player.can_receive_input
		and not bound_player.is_local_input_blocked
		and bound_player.health > 0
	)


func _connect_runtime_signals() -> void:
	if runtime == null:
		return
	if runtime.turn_manager != null and not runtime.turn_manager.turn_state_changed.is_connected(_on_state_changed):
		runtime.turn_manager.turn_state_changed.connect(_on_state_changed)
	if runtime.spells != null and not runtime.spells.targeting_changed.is_connected(_on_spell_targeting_changed):
		runtime.spells.targeting_changed.connect(_on_spell_targeting_changed)
	if runtime.abilities != null and not runtime.abilities.ability_state_changed.is_connected(_on_state_changed):
		runtime.abilities.ability_state_changed.connect(_on_state_changed)


func _disconnect_runtime_signals() -> void:
	if runtime == null:
		return
	if runtime.turn_manager != null and runtime.turn_manager.turn_state_changed.is_connected(_on_state_changed):
		runtime.turn_manager.turn_state_changed.disconnect(_on_state_changed)
	if runtime.spells != null and runtime.spells.targeting_changed.is_connected(_on_spell_targeting_changed):
		runtime.spells.targeting_changed.disconnect(_on_spell_targeting_changed)
	if runtime.abilities != null and runtime.abilities.ability_state_changed.is_connected(_on_state_changed):
		runtime.abilities.ability_state_changed.disconnect(_on_state_changed)


func _connect_player_signals() -> void:
	if bound_player == null:
		return
	if not bound_player.action_mode_changed.is_connected(_on_action_mode_changed):
		bound_player.action_mode_changed.connect(_on_action_mode_changed)
	if not bound_player.vitality_changed.is_connected(_on_vitality_changed):
		bound_player.vitality_changed.connect(_on_vitality_changed)


func _disconnect_player_signals() -> void:
	if bound_player == null or not is_instance_valid(bound_player):
		return
	if bound_player.action_mode_changed.is_connected(_on_action_mode_changed):
		bound_player.action_mode_changed.disconnect(_on_action_mode_changed)
	if bound_player.vitality_changed.is_connected(_on_vitality_changed):
		bound_player.vitality_changed.disconnect(_on_vitality_changed)


func _refresh_if_bound() -> void:
	if bound_player != null and is_node_ready():
		_refresh_buttons(bound_player.action_mode)


func _is_text_input_focused() -> bool:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit


func _is_console_open() -> bool:
	var console: Node = get_node_or_null("/root/Console")
	return console != null and console.has_method("is_visible") and console.is_visible()


func _on_action_mode_changed(action_mode: int) -> void:
	_refresh_buttons(action_mode)


func _on_vitality_changed(_current_health: int, _maximum_health: int) -> void:
	_refresh_if_bound()


func _on_spell_targeting_changed(next_is_targeting: bool, spell_slot_index: int) -> void:
	is_spell_targeting = next_is_targeting
	selected_spell_slot_index = spell_slot_index if next_is_targeting else -1
	_refresh_if_bound()


func _on_state_changed() -> void:
	if (
		bound_player != null
		and bound_player.action_mode == PlayerCharacter.ActionMode.SPECIAL_ABILITY
		and not _is_action_available(PlayerCharacter.ActionMode.SPECIAL_ABILITY)
	):
		bound_player.set_action_mode(PlayerCharacter.ActionMode.NONE)
		return
	_refresh_if_bound()
