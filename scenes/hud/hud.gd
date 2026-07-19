class_name GameHud
extends CanvasLayer

signal end_game

const POINTING_HAND_CURSOR_TEXTURE: Texture2D = preload("res://art/pointers/hand_small_point_n.svg")
const POINTING_HAND_CURSOR_HOTSPOT := Vector2(15.0, 4.0)
const METEOR_CONFIRMATION_TITLE := "Подтверждение заклинания"
const METEOR_CONFIRMATION_TEXT := "Вы действительно хотите использовать заклинание метеорита?"

enum ModalContext {
	NONE,
	LEVEL_WELCOME,
	METEOR_CONFIRMATION,
}

@onready var inventory_bar: InventoryBar = get_node("InventoryBar") as InventoryBar
@onready var local_player_card: PlayerStatusCard = get_node("LocalPlayerCard") as PlayerStatusCard
@onready var turn_status_panel: TurnStatusPanel = get_node("TurnStatusPanel") as TurnStatusPanel
@onready var player_roster_panel: PlayerRosterPanel = get_node("PlayerRosterPanel") as PlayerRosterPanel
@onready var end_turn_button: Button = get_node("EndTurnButton") as Button
@onready var modal_dialog: GameModalDialog = get_node("ModalDialog") as GameModalDialog

var runtime: WorldRuntime = null
var bound_player: PlayerCharacter = null
var modal_context: ModalContext = ModalContext.NONE
var pending_spell_target_cell: Vector2i = Vector2i.ZERO


func _ready() -> void:
	Input.set_custom_mouse_cursor(
		POINTING_HAND_CURSOR_TEXTURE,
		Input.CURSOR_POINTING_HAND,
		POINTING_HAND_CURSOR_HOTSPOT
	)
	Input.set_custom_mouse_cursor(
		POINTING_HAND_CURSOR_TEXTURE,
		Input.CURSOR_DRAG,
		POINTING_HAND_CURSOR_HOTSPOT
	)
	Input.set_custom_mouse_cursor(
		POINTING_HAND_CURSOR_TEXTURE,
		Input.CURSOR_CAN_DROP,
		POINTING_HAND_CURSOR_HOTSPOT
	)
	Input.set_custom_mouse_cursor(
		POINTING_HAND_CURSOR_TEXTURE,
		Input.CURSOR_FORBIDDEN,
		POINTING_HAND_CURSOR_HOTSPOT
	)
	_configure_interactive_cursor(self)
	if not get_tree().node_added.is_connected(_on_scene_tree_node_added):
		get_tree().node_added.connect(_on_scene_tree_node_added)
	if not modal_dialog.open_state_changed.is_connected(_on_modal_open_state_changed):
		modal_dialog.open_state_changed.connect(_on_modal_open_state_changed)
	if not modal_dialog.resolved.is_connected(_on_modal_resolved):
		modal_dialog.resolved.connect(_on_modal_resolved)


func _exit_tree() -> void:
	_disconnect_bound_player_signal()
	_disconnect_spell_targeting_signal()
	_disconnect_turn_signal()
	if bound_player != null and is_instance_valid(bound_player):
		bound_player.set_local_input_blocked(false)
	if get_tree().node_added.is_connected(_on_scene_tree_node_added):
		get_tree().node_added.disconnect(_on_scene_tree_node_added)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_POINTING_HAND)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_DRAG)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_CAN_DROP)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_FORBIDDEN)


func configure_runtime(new_runtime: WorldRuntime) -> void:
	_disconnect_spell_targeting_signal()
	_disconnect_turn_signal()
	runtime = new_runtime
	if runtime == null:
		_refresh_end_turn_button()
		return
	inventory_bar.configure_runtime(runtime)
	turn_status_panel.configure_runtime(runtime)
	player_roster_panel.configure_runtime(runtime)
	_connect_spell_targeting_signal()
	_connect_turn_signal()
	_refresh_end_turn_button()


func bind_session() -> void:
	if runtime == null:
		return
	var local_player: PlayerCharacter = runtime.get_local_player()
	_bind_local_player(local_player)
	local_player_card.bind_player(local_player, "", true)
	if local_player != null:
		inventory_bar.bind_character(local_player)
	turn_status_panel.bind_session()
	player_roster_panel.bind_session()
	_refresh_end_turn_button()


func show_level_welcome(title_text: String, body_text: String) -> bool:
	if title_text.is_empty() or body_text.is_empty():
		return false
	if not modal_dialog.show_information(title_text, body_text):
		return false

	modal_context = ModalContext.LEVEL_WELCOME
	return true


func is_modal_open() -> bool:
	return modal_dialog.is_open()


func _configure_interactive_cursor(node: Node) -> void:
	var control: Control = node as Control
	if control is BaseButton or control is InventorySlotControl:
		control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for child: Node in node.get_children():
		_configure_interactive_cursor(child)


func _on_end_game_button_pressed() -> void:
	if modal_dialog.is_open():
		return
	end_game.emit()


func _on_end_turn_button_pressed() -> void:
	if (
		runtime == null
		or runtime.turn_manager == null
		or bound_player == null
		or not bound_player.can_process_local_input()
		or not runtime.turn_manager.can_end_turn(bound_player)
	):
		return

	runtime.cancel_spell_targeting(bound_player)
	runtime.request_end_turn(bound_player)


func _on_scene_tree_node_added(node: Node) -> void:
	if is_ancestor_of(node):
		_configure_interactive_cursor(node)


func _bind_local_player(player: PlayerCharacter) -> void:
	if bound_player == player:
		_apply_modal_input_block()
		_refresh_end_turn_button()
		return

	if modal_context == ModalContext.METEOR_CONFIRMATION and modal_dialog.is_open():
		modal_dialog.cancel()
	_disconnect_bound_player_signal()
	if bound_player != null and is_instance_valid(bound_player):
		bound_player.set_local_input_blocked(false)
	bound_player = player
	if bound_player != null:
		var character_model: CharacterModel = bound_player.model
		if character_model != null:
			if not character_model.spell_target_selected.is_connected(_on_player_spell_target_selected):
				character_model.spell_target_selected.connect(_on_player_spell_target_selected)
	_apply_modal_input_block()
	_refresh_end_turn_button()


func _disconnect_bound_player_signal() -> void:
	if bound_player == null or not is_instance_valid(bound_player):
		return
	var character_model: CharacterModel = bound_player.model
	if character_model == null:
		return
	if character_model.spell_target_selected.is_connected(_on_player_spell_target_selected):
		character_model.spell_target_selected.disconnect(_on_player_spell_target_selected)


func _connect_spell_targeting_signal() -> void:
	if runtime == null or runtime.spells == null:
		return
	if not runtime.spells.targeting_changed.is_connected(_on_spell_targeting_changed):
		runtime.spells.targeting_changed.connect(_on_spell_targeting_changed)


func _disconnect_spell_targeting_signal() -> void:
	if runtime == null or runtime.spells == null:
		return
	if runtime.spells.targeting_changed.is_connected(_on_spell_targeting_changed):
		runtime.spells.targeting_changed.disconnect(_on_spell_targeting_changed)


func _connect_turn_signal() -> void:
	if runtime == null or runtime.turn_manager == null:
		return
	if not runtime.turn_manager.turn_state_changed.is_connected(_on_turn_state_changed):
		runtime.turn_manager.turn_state_changed.connect(_on_turn_state_changed)


func _disconnect_turn_signal() -> void:
	if runtime == null or runtime.turn_manager == null:
		return
	if runtime.turn_manager.turn_state_changed.is_connected(_on_turn_state_changed):
		runtime.turn_manager.turn_state_changed.disconnect(_on_turn_state_changed)


func _refresh_end_turn_button() -> void:
	if end_turn_button == null:
		return

	var turn_manager: WorldTurns = null if runtime == null else runtime.turn_manager
	var is_turn_mode_enabled: bool = turn_manager != null and turn_manager.is_turn_mode_enabled()
	end_turn_button.visible = is_turn_mode_enabled
	end_turn_button.disabled = (
		not is_turn_mode_enabled
		or bound_player == null
		or not turn_manager.can_end_turn(bound_player)
	)


func _apply_modal_input_block() -> void:
	if bound_player == null or not is_instance_valid(bound_player):
		return
	bound_player.set_local_input_blocked(modal_dialog.is_open())


func _on_player_spell_target_selected(target_cell: Vector2i) -> void:
	if (
		runtime == null
		or bound_player == null
		or not is_instance_valid(bound_player)
		or modal_dialog.is_open()
	):
		return

	var selected_slot_index: int = runtime.get_selected_spell_slot_index(bound_player)
	if selected_slot_index < 0:
		return
	var spell_id: String = bound_player.character_inventory.get_spell_id_at_slot(selected_slot_index)
	if spell_id != WorldSpells.SPELL_ID_METEOR:
		runtime.request_selected_spell_cast(bound_player, target_cell)
		return

	pending_spell_target_cell = target_cell
	if not modal_dialog.show_confirmation(METEOR_CONFIRMATION_TITLE, METEOR_CONFIRMATION_TEXT):
		pending_spell_target_cell = Vector2i.ZERO
		return
	modal_context = ModalContext.METEOR_CONFIRMATION


func _on_modal_open_state_changed(_is_open: bool) -> void:
	_apply_modal_input_block()


func _on_modal_resolved(result: GameModalDialog.Result) -> void:
	var resolved_context: ModalContext = modal_context
	modal_context = ModalContext.NONE
	if resolved_context != ModalContext.METEOR_CONFIRMATION:
		pending_spell_target_cell = Vector2i.ZERO
		return

	var target_cell: Vector2i = pending_spell_target_cell
	pending_spell_target_cell = Vector2i.ZERO
	if runtime == null or bound_player == null or not is_instance_valid(bound_player):
		return
	if result == GameModalDialog.Result.CONFIRMED:
		runtime.request_selected_spell_cast(bound_player, target_cell)
	else:
		runtime.cancel_spell_targeting(bound_player)


func _on_spell_targeting_changed(is_targeting: bool, _spell_slot_index: int) -> void:
	if (
		is_targeting
		or modal_context != ModalContext.METEOR_CONFIRMATION
		or not modal_dialog.is_open()
	):
		return

	modal_dialog.cancel()


func _on_turn_state_changed() -> void:
	_refresh_end_turn_button()
