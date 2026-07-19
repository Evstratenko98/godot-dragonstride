class_name InventoryBar
extends HBoxContainer

const SLOT_SIZE := Vector2(38.0, 38.0)
const SLOT_SEPARATION := 5
const ATTACK_MODE_ACTION := &"select_attack_mode"
const INTERACTION_MODE_ACTION := &"select_interaction_mode"
const ATTACK_CURSOR_HOTSPOT := Vector2(3.0, 3.0)
const INTERACTION_CURSOR_HOTSPOT := Vector2(18.0, 20.0)
const INACTIVE_ACTION_CURSOR_HOTSPOT := Vector2(15.0, 4.0)
const ATTACK_CURSOR_TEXTURE: Texture2D = preload("res://art/pointers/tool_sword_a.svg")
const INTERACTION_CURSOR_TEXTURE: Texture2D = preload("res://art/pointers/hand_open.svg")
const INACTIVE_ACTION_CURSOR_TEXTURE: Texture2D = preload("res://art/pointers/hand_small_point_n.svg")

var runtime: WorldRuntime = null
var character_inventory: CharacterInventory = null
var bound_player: PlayerCharacter = null
var item_slots: Array[InventorySlotControl] = []
var spell_slots: Array[InventorySlotControl] = []
var action_buttons: Array[Button] = []
var selected_spell_slot_index: int = -1


func _ready() -> void:
	add_theme_constant_override("separation", SLOT_SEPARATION)
	_build_bar()
	_apply_action_cursor(PlayerCharacter.ActionMode.ATTACK)


func _exit_tree() -> void:
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
	_disconnect_turn_signal()
	if bound_player != null and bound_player.action_mode_changed.is_connected(_on_player_action_mode_changed):
		bound_player.action_mode_changed.disconnect(_on_player_action_mode_changed)
	if character_inventory != null and character_inventory.inventory_changed.is_connected(_refresh_items):
		character_inventory.inventory_changed.disconnect(_refresh_items)
	if runtime == null or runtime.spells == null:
		return
	if runtime.spells.targeting_changed.is_connected(_on_spell_targeting_changed):
		runtime.spells.targeting_changed.disconnect(_on_spell_targeting_changed)
	if runtime.spells.spell_usage_changed.is_connected(_on_spell_usage_changed):
		runtime.spells.spell_usage_changed.disconnect(_on_spell_usage_changed)


func _unhandled_key_input(event: InputEvent) -> void:
	if (
		bound_player == null
		or not bound_player.can_process_local_input()
		or _is_console_open()
		or _is_text_input_focused()
	):
		return

	if event.is_action_pressed(ATTACK_MODE_ACTION):
		_select_action_mode(PlayerCharacter.ActionMode.ATTACK)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(INTERACTION_MODE_ACTION):
		_select_action_mode(PlayerCharacter.ActionMode.INTERACT)
		get_viewport().set_input_as_handled()


func configure_runtime(new_runtime: WorldRuntime) -> void:
	_disconnect_turn_signal()
	runtime = new_runtime
	if runtime != null and runtime.turn_manager != null:
		if not runtime.turn_manager.turn_state_changed.is_connected(_on_turn_state_changed):
			runtime.turn_manager.turn_state_changed.connect(_on_turn_state_changed)
	_connect_spell_signals()


func bind_character(player: PlayerCharacter) -> void:
	if player == null:
		return
	_connect_spell_signals()
	if player == bound_player:
		_refresh_action_buttons(player.action_mode)
		_refresh_spell_states()
		return
	if bound_player != null and bound_player.action_mode_changed.is_connected(_on_player_action_mode_changed):
		bound_player.action_mode_changed.disconnect(_on_player_action_mode_changed)
	if character_inventory != null and character_inventory.inventory_changed.is_connected(_refresh_items):
		character_inventory.inventory_changed.disconnect(_refresh_items)

	bound_player = player
	character_inventory = player.character_inventory
	if not character_inventory.inventory_changed.is_connected(_refresh_items):
		character_inventory.inventory_changed.connect(_refresh_items)
	if not bound_player.action_mode_changed.is_connected(_on_player_action_mode_changed):
		bound_player.action_mode_changed.connect(_on_player_action_mode_changed)
	selected_spell_slot_index = runtime.get_selected_spell_slot_index(bound_player)
	_refresh_items()
	_refresh_action_buttons(bound_player.action_mode)


func request_move(inventory_kind: String, source_slot_index: int, target_slot_index: int) -> void:
	if (
		runtime == null
		or bound_player == null
		or not bound_player.can_process_local_input()
		or source_slot_index == target_slot_index
	):
		return

	runtime.request_inventory_move(inventory_kind, source_slot_index, target_slot_index)


func request_delete(inventory_kind: String, source_slot_index: int) -> void:
	if runtime == null or bound_player == null or not bound_player.can_process_local_input():
		return

	runtime.request_inventory_delete(inventory_kind, source_slot_index)


func request_use(inventory_kind: String, slot_index: int) -> void:
	if runtime == null or bound_player == null or not bound_player.can_process_local_input():
		return

	if inventory_kind == CharacterInventory.INVENTORY_KIND_SPELL:
		runtime.toggle_spell_targeting(bound_player, slot_index)
		return

	runtime.request_inventory_use(slot_index)


func _build_bar() -> void:
	for slot_index: int in range(CharacterInventory.ITEM_SLOT_COUNT):
		var item_slot: InventorySlotControl = InventorySlotControl.new()
		item_slot.configure(self, CharacterInventory.INVENTORY_KIND_ITEM, slot_index)
		item_slots.append(item_slot)
		add_child.call_deferred(item_slot)

	var attack_button: Button = _create_action_button(
		ATTACK_CURSOR_TEXTURE,
		"Attack (Q)",
		PlayerCharacter.ActionMode.ATTACK
	)
	var interaction_button: Button = _create_action_button(
		INTERACTION_CURSOR_TEXTURE,
		"Interact (E)",
		PlayerCharacter.ActionMode.INTERACT
	)
	action_buttons.append(attack_button)
	action_buttons.append(interaction_button)
	add_child.call_deferred(attack_button)
	add_child.call_deferred(interaction_button)

	for spell_index: int in range(CharacterInventory.SPELL_SLOT_COUNT):
		var spell_slot: InventorySlotControl = InventorySlotControl.new()
		spell_slot.configure(self, CharacterInventory.INVENTORY_KIND_SPELL, spell_index)
		spell_slots.append(spell_slot)
		add_child.call_deferred(spell_slot)


func _refresh_items() -> void:
	if character_inventory == null:
		return

	for slot_index: int in range(item_slots.size()):
		item_slots[slot_index].set_inventory_item(
			character_inventory.get_item_at_slot(CharacterInventory.INVENTORY_KIND_ITEM, slot_index)
		)
	for slot_index: int in range(spell_slots.size()):
		spell_slots[slot_index].set_inventory_item(
			character_inventory.get_item_at_slot(CharacterInventory.INVENTORY_KIND_SPELL, slot_index)
		)

	if selected_spell_slot_index >= 0:
		var selected_spell_id: String = character_inventory.get_spell_id_at_slot(selected_spell_slot_index)
		if selected_spell_id.is_empty():
			runtime.cancel_spell_targeting(bound_player)
	_refresh_spell_states()


func _refresh_spell_states() -> void:
	if runtime == null or character_inventory == null or bound_player == null:
		return

	var should_show_usage: bool = runtime.is_turn_mode_enabled()
	for slot_index: int in range(spell_slots.size()):
		var spell_id: String = character_inventory.get_spell_id_at_slot(slot_index)
		var total_uses: int = 0 if spell_id.is_empty() else 1
		var remaining_uses: int = runtime.get_remaining_spell_slot_uses(bound_player, slot_index)
		spell_slots[slot_index].set_spell_state(
			slot_index == selected_spell_slot_index,
			remaining_uses,
			total_uses,
			should_show_usage
		)


func _create_action_button(
	icon_texture: Texture2D,
	button_tooltip_text: String,
	action_mode: int
) -> Button:
	var action_button: Button = Button.new()
	action_button.icon = icon_texture
	action_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action_button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	action_button.expand_icon = false
	action_button.tooltip_text = button_tooltip_text
	action_button.custom_minimum_size = SLOT_SIZE
	action_button.focus_mode = Control.FOCUS_NONE
	action_button.mouse_filter = Control.MOUSE_FILTER_STOP
	action_button.pressed.connect(_on_action_button_pressed.bind(action_mode))
	_apply_action_button_style(action_button, false)
	return action_button


func _refresh_action_buttons(action_mode: int) -> void:
	var attack_is_available: bool = _is_action_available(PlayerCharacter.ActionMode.ATTACK)
	var interaction_is_available: bool = _is_action_available(PlayerCharacter.ActionMode.INTERACT)
	var next_action_mode: int = action_mode
	if action_mode == PlayerCharacter.ActionMode.ATTACK and not attack_is_available and interaction_is_available:
		next_action_mode = PlayerCharacter.ActionMode.INTERACT
	elif action_mode == PlayerCharacter.ActionMode.INTERACT and not interaction_is_available and attack_is_available:
		next_action_mode = PlayerCharacter.ActionMode.ATTACK

	if bound_player != null and bound_player.action_mode != next_action_mode:
		bound_player.set_action_mode(next_action_mode)
		return

	for button_index: int in range(action_buttons.size()):
		var is_available: bool = attack_is_available if button_index == PlayerCharacter.ActionMode.ATTACK else interaction_is_available
		var is_selected: bool = is_available and button_index == next_action_mode and selected_spell_slot_index < 0
		var available_tooltip: String = "Attack (Q)" if button_index == PlayerCharacter.ActionMode.ATTACK else "Interact (E)"
		action_buttons[button_index].disabled = not is_available
		action_buttons[button_index].tooltip_text = available_tooltip if is_available else "Действие недоступно в текущем ходу"
		_apply_action_button_style(action_buttons[button_index], is_selected)
	_apply_action_cursor(next_action_mode, attack_is_available or interaction_is_available)


func _apply_action_button_style(action_button: Button, is_selected: bool) -> void:
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


func _on_action_button_pressed(action_mode: int) -> void:
	_select_action_mode(action_mode)


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
	_refresh_action_buttons(bound_player.action_mode)


func _apply_action_cursor(action_mode: int, has_available_action: bool = true) -> void:
	if not has_available_action:
		Input.set_custom_mouse_cursor(
			INACTIVE_ACTION_CURSOR_TEXTURE,
			Input.CURSOR_ARROW,
			INACTIVE_ACTION_CURSOR_HOTSPOT
		)
		return
	if action_mode == PlayerCharacter.ActionMode.INTERACT:
		Input.set_custom_mouse_cursor(
			INTERACTION_CURSOR_TEXTURE,
			Input.CURSOR_ARROW,
			INTERACTION_CURSOR_HOTSPOT
		)
		return

	Input.set_custom_mouse_cursor(
		ATTACK_CURSOR_TEXTURE,
		Input.CURSOR_ARROW,
		ATTACK_CURSOR_HOTSPOT
	)


func _is_action_available(action_mode: int) -> bool:
	if runtime == null or runtime.turn_manager == null or bound_player == null:
		return true
	var turn_manager: WorldTurns = runtime.turn_manager
	if not turn_manager.is_turn_mode_enabled():
		return true
	if not turn_manager.is_entity_active_in_turn(bound_player):
		return false
	if action_mode == PlayerCharacter.ActionMode.ATTACK:
		return turn_manager.get_attacks_left() > 0
	return turn_manager.get_interactions_left() > 0


func _is_text_input_focused() -> bool:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit


func _is_console_open() -> bool:
	var console: Node = get_node_or_null("/root/Console")
	return console != null and console.has_method("is_visible") and console.is_visible()


func _on_player_action_mode_changed(action_mode: int) -> void:
	_refresh_action_buttons(action_mode)


func _on_spell_targeting_changed(is_targeting: bool, spell_slot_index: int) -> void:
	selected_spell_slot_index = spell_slot_index if is_targeting else -1
	if bound_player != null:
		_refresh_action_buttons(bound_player.action_mode)
	_refresh_spell_states()


func _on_spell_usage_changed() -> void:
	_refresh_spell_states()


func _on_turn_state_changed() -> void:
	if bound_player != null:
		_refresh_action_buttons(bound_player.action_mode)
	_refresh_spell_states()


func _connect_spell_signals() -> void:
	if runtime == null or runtime.spells == null:
		return
	if not runtime.spells.targeting_changed.is_connected(_on_spell_targeting_changed):
		runtime.spells.targeting_changed.connect(_on_spell_targeting_changed)
	if not runtime.spells.spell_usage_changed.is_connected(_on_spell_usage_changed):
		runtime.spells.spell_usage_changed.connect(_on_spell_usage_changed)


func _disconnect_turn_signal() -> void:
	if runtime == null or runtime.turn_manager == null:
		return
	if runtime.turn_manager.turn_state_changed.is_connected(_on_turn_state_changed):
		runtime.turn_manager.turn_state_changed.disconnect(_on_turn_state_changed)
