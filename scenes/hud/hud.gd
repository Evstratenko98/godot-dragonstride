class_name GameHud
extends CanvasLayer

signal end_game

const METEOR_CONFIRMATION_TITLE := "Подтверждение заклинания"
const METEOR_CONFIRMATION_TEXT := "Вы действительно хотите использовать заклинание метеорита?"

enum ModalContext {
	NONE,
	LEVEL_WELCOME,
	METEOR_CONFIRMATION,
}

@onready var inventory_bar: InventoryBar = get_node("InventoryBar") as InventoryBar
@onready var local_squad_panel: LocalSquadPanel = get_node("LocalSquadPanel") as LocalSquadPanel
@onready var turn_status_panel: TurnStatusPanel = get_node("TurnStatusPanel") as TurnStatusPanel
@onready var player_roster_panel: PlayerRosterPanel = get_node("PlayerRosterPanel") as PlayerRosterPanel
@onready var end_turn_button: Button = get_node("EndTurnButton") as Button
@onready var modal_dialog: GameModalDialog = get_node("ModalDialog") as GameModalDialog
@onready var chest_loot_dialog: ChestLootDialog = get_node("ChestLootDialog") as ChestLootDialog
@onready var cursor_controller: HudCursorController = get_node("CursorController") as HudCursorController
@onready var pause_menu: GamePauseMenu = get_node("GamePauseMenu") as GamePauseMenu

var runtime: WorldRuntime = null
var bound_player: PlayerCharacter = null
var modal_context: ModalContext = ModalContext.NONE
var pending_spell_target_surface: Vector3i = Vector3i.ZERO
var inventory_bar_default_z_index: int = 0
var inventory_bar_default_child_index: int = 0


func _ready() -> void:
	cursor_controller.configure(self)
	inventory_bar_default_z_index = inventory_bar.z_index
	inventory_bar_default_child_index = inventory_bar.get_index()
	inventory_bar.configure_loot_dialog(chest_loot_dialog)
	if not modal_dialog.open_state_changed.is_connected(_on_modal_open_state_changed):
		modal_dialog.open_state_changed.connect(_on_modal_open_state_changed)
	if not modal_dialog.resolved.is_connected(_on_modal_resolved):
		modal_dialog.resolved.connect(_on_modal_resolved)
	if not chest_loot_dialog.open_state_changed.is_connected(_on_chest_loot_open_state_changed):
		chest_loot_dialog.open_state_changed.connect(_on_chest_loot_open_state_changed)


func _exit_tree() -> void:
	_disconnect_bound_player_signal()
	_disconnect_spell_targeting_signal()
	_disconnect_turn_signal()
	_disconnect_selection_signal()
	inventory_bar.set_loot_modal_mode(false)
	inventory_bar.z_index = inventory_bar_default_z_index
	_set_local_squad_input_blocked(false)
	if runtime != null:
		runtime.set_local_camera_input_blocked(false)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or event.is_echo():
		return
	if pause_menu.is_open():
		pause_menu.handle_cancel()
		get_viewport().set_input_as_handled()
		return
	if _is_gameplay_modal_open() or _is_console_open() or _is_text_input_focused():
		return
	pause_menu.open(GameCamera.MODE_FOLLOW if runtime == null else runtime.get_local_camera_mode())
	get_viewport().set_input_as_handled()


func configure_runtime(new_runtime: WorldRuntime) -> void:
	_disconnect_spell_targeting_signal()
	_disconnect_turn_signal()
	_disconnect_selection_signal()
	runtime = new_runtime
	chest_loot_dialog.configure_runtime(runtime)
	if runtime == null:
		_refresh_end_turn_button()
		return
	inventory_bar.configure_runtime(runtime)
	turn_status_panel.configure_runtime(runtime)
	player_roster_panel.configure_runtime(runtime)
	_connect_spell_targeting_signal()
	_connect_turn_signal()
	_connect_selection_signal()
	_refresh_end_turn_button()


func bind_session() -> void:
	if runtime == null:
		return
	var local_player: PlayerCharacter = runtime.get_selected_local_character()
	_bind_local_player(local_player)
	local_squad_panel.bind_squad(runtime, runtime.get_local_squad_members())
	local_squad_panel.set_selected_character(local_player)
	if local_player != null:
		inventory_bar.bind_character(local_player)
	chest_loot_dialog.bind_character(local_player)
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
	return _is_gameplay_modal_open() or pause_menu.is_open()


func _on_end_turn_button_pressed() -> void:
	if (
		runtime == null
		or runtime.turn_manager == null
		or not runtime.turn_manager.can_end_turn(_get_local_turn_representative())
	):
		return

	if bound_player != null:
		runtime.cancel_spell_targeting(bound_player)
	runtime.request_end_turn(_get_local_turn_representative())


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


func _connect_selection_signal() -> void:
	if runtime != null and not runtime.selected_local_character_changed.is_connected(_on_selected_local_character_changed):
		runtime.selected_local_character_changed.connect(_on_selected_local_character_changed)


func _disconnect_selection_signal() -> void:
	if runtime != null and runtime.selected_local_character_changed.is_connected(_on_selected_local_character_changed):
		runtime.selected_local_character_changed.disconnect(_on_selected_local_character_changed)


func _refresh_end_turn_button() -> void:
	if end_turn_button == null:
		return

	var turn_manager: WorldTurns = null if runtime == null else runtime.turn_manager
	var is_turn_mode_enabled: bool = turn_manager != null and turn_manager.is_turn_mode_enabled()
	end_turn_button.visible = is_turn_mode_enabled
	end_turn_button.disabled = (
		not is_turn_mode_enabled
		or pause_menu.is_open()
		or not turn_manager.can_end_turn(_get_local_turn_representative())
	)


func _get_local_turn_representative() -> PlayerCharacter:
	if bound_player != null and is_instance_valid(bound_player):
		return bound_player
	if runtime == null:
		return null
	var members: Array[PlayerCharacter] = runtime.get_local_squad_members()
	return null if members.is_empty() else members[0]


func _apply_modal_input_block() -> void:
	var should_block: bool = is_modal_open()
	_set_local_squad_input_blocked(should_block)
	_refresh_end_turn_button()


func _set_local_squad_input_blocked(should_be_blocked: bool) -> void:
	if runtime == null:
		local_squad_panel.set_input_blocked(should_be_blocked)
		return
	for member: PlayerCharacter in runtime.get_local_squad_members():
		member.set_local_input_blocked(should_be_blocked)
	local_squad_panel.set_input_blocked(should_be_blocked)


func _is_gameplay_modal_open() -> bool:
	return modal_dialog.is_open() or chest_loot_dialog.is_open()


func _is_text_input_focused() -> bool:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit


func _is_console_open() -> bool:
	var console: Node = get_node_or_null("/root/Console")
	return console != null and console.has_method("is_visible") and console.is_visible()


func _on_selected_local_character_changed(character: PlayerCharacter) -> void:
	_bind_local_player(character)
	local_squad_panel.set_selected_character(character)
	inventory_bar.bind_character(character)
	chest_loot_dialog.bind_character(character)


func _on_player_spell_target_selected(target_surface: Vector3i) -> void:
	if (
		runtime == null
		or bound_player == null
		or not is_instance_valid(bound_player)
		or is_modal_open()
	):
		return

	var selected_slot_index: int = runtime.get_selected_spell_slot_index(bound_player)
	if selected_slot_index < 0:
		return
	var spell_id: String = bound_player.character_inventory.get_spell_id_at_slot(selected_slot_index)
	if spell_id != WorldSpells.SPELL_ID_METEOR:
		runtime.request_selected_spell_cast(bound_player, target_surface)
		return

	pending_spell_target_surface = target_surface
	if not modal_dialog.show_confirmation(METEOR_CONFIRMATION_TITLE, METEOR_CONFIRMATION_TEXT):
		pending_spell_target_surface = Vector3i.ZERO
		return
	modal_context = ModalContext.METEOR_CONFIRMATION


func _on_modal_open_state_changed(_is_open: bool) -> void:
	_apply_modal_input_block()


func _on_chest_loot_open_state_changed(is_open: bool) -> void:
	inventory_bar.set_loot_modal_mode(is_open)
	_set_loot_inventory_layer(is_open)
	_apply_modal_input_block()


func _on_pause_menu_camera_mode_requested(camera_mode: String) -> void:
	if runtime != null:
		runtime.set_local_camera_mode(camera_mode)


func _on_pause_menu_exit_game_requested() -> void:
	end_game.emit()


func _on_pause_menu_open_state_changed(is_open: bool) -> void:
	if runtime != null:
		runtime.set_local_camera_input_blocked(is_open)
	_apply_modal_input_block()


func _set_loot_inventory_layer(is_open: bool) -> void:
	if is_open:
		move_child(inventory_bar, get_child_count() - 1)
		inventory_bar.z_index = chest_loot_dialog.z_index + 1
		return

	move_child(inventory_bar, inventory_bar_default_child_index)
	inventory_bar.z_index = inventory_bar_default_z_index


func _on_modal_resolved(result: GameModalDialog.Result) -> void:
	var resolved_context: ModalContext = modal_context
	modal_context = ModalContext.NONE
	if resolved_context != ModalContext.METEOR_CONFIRMATION:
		pending_spell_target_surface = Vector3i.ZERO
		return

	var target_surface: Vector3i = pending_spell_target_surface
	pending_spell_target_surface = Vector3i.ZERO
	if runtime == null or bound_player == null or not is_instance_valid(bound_player):
		return
	if result == GameModalDialog.Result.CONFIRMED:
		runtime.request_selected_spell_cast(bound_player, target_surface)
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
