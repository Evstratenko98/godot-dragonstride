class_name PlayerCharacter
extends "res://scenes/entities/entity/entity.gd"

signal action_mode_changed(action_mode: ActionMode)
signal movement_input_state_requested(character: PlayerCharacter, is_held: bool)

enum ActionMode {
	MOVE,
	ATTACK,
	INTERACT,
}

const DEFAULT_WARRIOR_COLOR := "Blue"
const WARRIOR_NAMES_BY_COLOR: Dictionary[String, String] = {
	"Purple": "Patrick",
	"Blue": "Arnoldo",
	"Yellow": "Huan",
	"Red": "Dick",
}

@onready var view: CharacterView = get_node("View") as CharacterView
@onready var model: CharacterModel = get_node("Model") as CharacterModel
@onready var character_inventory: CharacterInventory = get_node("CharacterInventory") as CharacterInventory

var facing_left: bool = false
var steam_id: int = 0
var owner_player_id: String = ""
var squad_slot: int = 0
var is_locally_owned: bool = true
var is_selected_local_character: bool = false
var can_receive_input: bool = true
var is_local_input_blocked: bool = false
var is_executing_move_path: bool = false
var is_movement_input_held: bool = false
var action_mode: ActionMode = ActionMode.MOVE
var warrior_color: String = DEFAULT_WARRIOR_COLOR


func _ready() -> void:
	super._ready()
	var character_view: CharacterView = _get_view()
	if character_view != null:
		character_view.play_idle()
	_sync_facing_from_view()


func setup_multiplayer_player(player_info: Dictionary) -> void:
	steam_id = int(player_info.get("steam_id", 0))
	owner_player_id = str(player_info.get("player_id", ""))
	squad_slot = int(player_info.get("squad_slot", 0))
	is_locally_owned = bool(player_info.get("is_local", true))
	can_receive_input = is_locally_owned


func start(
	start_position: Vector2,
	receive_input: bool = true,
	new_entity_id: String = "",
	new_entity_name: String = ""
) -> void:
	can_receive_input = receive_input
	is_executing_move_path = false
	is_movement_input_held = false
	action_mode = ActionMode.MOVE
	start_entity(start_position, new_entity_id, new_entity_name, EntityType.CHARACTER)
	character_inventory.configure_owner(entity_id)
	var character_view: CharacterView = _get_view()
	if character_view != null:
		character_view.set_display_name(get_display_name())


func configure_warrior_profile(color_name: String, display_name: String = "") -> void:
	warrior_color = color_name if WARRIOR_NAMES_BY_COLOR.has(color_name) else DEFAULT_WARRIOR_COLOR
	entity_name = display_name if not display_name.is_empty() else str(WARRIOR_NAMES_BY_COLOR.get(warrior_color, WARRIOR_NAMES_BY_COLOR[DEFAULT_WARRIOR_COLOR]))
	var character_view: CharacterView = _get_view()
	if character_view != null:
		character_view.set_warrior_color(warrior_color)
		character_view.set_display_name(entity_name)


func set_action_mode(new_action_mode: ActionMode) -> void:
	if action_mode == new_action_mode:
		return

	action_mode = new_action_mode
	action_mode_changed.emit(action_mode)


func set_local_input_blocked(should_block: bool) -> void:
	is_local_input_blocked = should_block
	if should_block:
		set_local_movement_input_state(false)


func set_selected_local_character(should_be_selected: bool) -> void:
	is_selected_local_character = should_be_selected
	if not should_be_selected:
		set_local_movement_input_state(false)


func set_local_movement_input_state(is_held: bool) -> void:
	if not is_locally_owned or is_movement_input_held == is_held:
		return
	apply_movement_input_state(is_held)
	movement_input_state_requested.emit(self, is_held)


func apply_movement_input_state(is_held: bool) -> void:
	is_movement_input_held = is_held
	if is_held:
		if health > 0 and not is_attacking:
			update_move_animation(true)
		return
	if not is_moving and not is_executing_move_path:
		update_move_animation(false)


func can_process_local_input() -> bool:
	return (
		is_locally_owned
		and is_selected_local_character
		and can_receive_input
		and not is_local_input_blocked
		and not is_executing_move_path
	)


func get_max_movement_steps_per_turn() -> int:
	return WorldSquadTurnBudget.MAX_STEPS_PER_MEMBER


func request_interaction_cell(target_cell: Vector2i) -> bool:
	if runtime == null or health <= 0:
		return false

	current_cell = runtime.world_to_cell(global_position)
	if not can_attack_cell(target_cell):
		return false

	runtime.request_character_interaction(self, target_cell)
	return true


func request_move_path(requested_path: Array[Vector2i]) -> bool:
	if runtime == null or requested_path.is_empty():
		return false
	return runtime.request_character_move_path(self, requested_path)


func execute_authoritative_move_path(path: Array[Vector2i]) -> bool:
	return await _play_move_path(path, true)


func play_remote_move_path(path: Array[Vector2i]) -> bool:
	return await _play_move_path(path, false)


func play_remote_attack(target_cell: Vector2i, should_apply: bool = true) -> void:
	if runtime == null:
		runtime = _find_runtime()

	if runtime == null or is_attacking or health <= 0:
		return

	current_cell = runtime.world_to_cell(global_position)
	var direction: Vector2i = _get_attack_direction_to_cell(target_cell)
	if direction == Vector2i.ZERO:
		return
	_attack_cell(target_cell, direction, should_apply, false)


func get_expected_attack_duration(target_cell: Vector2i) -> float:
	var character_view: CharacterView = _get_view()
	if character_view == null:
		return 0.0
	var direction: Vector2i = _get_attack_direction_to_cell(target_cell)
	if direction == Vector2i.RIGHT or direction == Vector2i.LEFT:
		return character_view.get_animation_length(&"attack_right")
	if direction == Vector2i.DOWN:
		return character_view.get_animation_length(&"attack_down")
	if direction == Vector2i.UP:
		return character_view.get_animation_length(&"attack_up")
	return 0.0


func update_move_animation(should_walk: bool) -> void:
	var character_view: CharacterView = _get_view()
	if character_view == null:
		return

	if should_walk:
		character_view.play_walk()
	else:
		character_view.play_idle()


func die() -> void:
	set_local_movement_input_state(false)
	if runtime != null:
		runtime.notify_character_defeated(self)
	respawn()


func respawn() -> bool:
	if not super.respawn():
		return false
	var character_view: CharacterView = _get_view()
	if character_view != null:
		character_view.play_idle()
	is_movement_input_held = false
	update_move_animation(false)
	_sync_facing_from_view()
	return true


func _on_move_direction_selected(direction: Vector2i) -> void:
	var character_view: CharacterView = _get_view()
	if character_view != null:
		character_view.face_direction(direction)
	_sync_facing_from_view()


func _play_move_path(path: Array[Vector2i], should_consume_steps: bool) -> bool:
	if (
		runtime == null
		or path.is_empty()
		or is_moving
		or is_attacking
		or health <= 0
		or runtime.is_entity_casting(self)
	):
		return false
	if should_consume_steps and not runtime.can_entity_move_in_turn(self):
		return false

	var start_cell: Vector2i = runtime.world_to_cell(global_position)
	var move_path_generation: int = get_action_generation()
	current_cell = start_cell
	is_executing_move_path = true
	for path_index: int in range(path.size()):
		var target_cell: Vector2i = path[path_index]
		var from_cell: Vector2i = current_cell
		var direction: Vector2i = target_cell - from_cell
		if absi(direction.x) + absi(direction.y) != 1:
			force_cancel_movement(start_cell)
			_finish_move_path()
			return false
		if not runtime.reserve_entity_cell(self, from_cell, target_cell):
			force_cancel_movement(start_cell)
			_finish_move_path()
			return false

		var movement_step_cost: int = 0
		if should_consume_steps and path_index == path.size() - 1:
			movement_step_cost = path.size()
		_on_move_direction_selected(direction)
		_move_to_cell(target_cell, false, movement_step_cost)
		var move_deadline_msec: int = Time.get_ticks_msec() + int((move_time + 2.0) * 1000.0)
		while is_inside_tree() and is_moving and Time.get_ticks_msec() < move_deadline_msec:
			await get_tree().process_frame
		if not is_inside_tree():
			_finish_move_path()
			return false
		if get_action_generation() != move_path_generation:
			_finish_move_path()
			return false
		if is_moving:
			force_cancel_movement(start_cell)
			_finish_move_path()
			return false

	_finish_move_path()
	return true


func _on_move_started(_target_cell: Vector2i) -> void:
	update_move_animation(true)


func _try_continue_moving() -> bool:
	var character_model: CharacterModel = _get_model()
	if character_model == null:
		return false

	return character_model.try_continue_moving()


func _on_move_stopped() -> void:
	if is_executing_move_path:
		return
	update_move_animation(is_movement_input_held)


func _finish_move_path() -> void:
	is_executing_move_path = false
	if is_inside_tree():
		update_move_animation(is_movement_input_held)


func _attack_cell(target_cell: Vector2i, direction: Vector2i, should_apply: bool, should_broadcast: bool) -> void:
	if direction == Vector2i.RIGHT:
		_attack(&"attack_right", false, true, target_cell, should_apply, should_broadcast)
	elif direction == Vector2i.LEFT:
		_attack(&"attack_right", true, true, target_cell, should_apply, should_broadcast)
	elif direction == Vector2i.DOWN:
		_attack(&"attack_down", false, false, target_cell, should_apply, should_broadcast)
	elif direction == Vector2i.UP:
		_attack(&"attack_up", false, false, target_cell, should_apply, should_broadcast)


func _attack(
	animation_name: StringName,
	attack_facing_left: bool,
	update_horizontal_facing: bool,
	target_cell: Vector2i,
	should_apply: bool,
	should_broadcast: bool
) -> void:
	is_attacking = true
	attack_target_cell = target_cell
	var attack_generation: int = get_action_generation()
	var character_view: CharacterView = _get_view()
	if character_view == null:
		is_attacking = false
		return

	if should_apply:
		_apply_attack_to_world(should_broadcast)
	_play_target_incoming_attack_guard(target_cell, character_view.get_animation_length(animation_name))

	await character_view.play_attack(animation_name, attack_facing_left, update_horizontal_facing)
	if attack_generation != get_action_generation():
		return

	is_attacking = false
	if runtime != null:
		runtime.notify_entity_action_finished_in_turn(self)
	attack_finished.emit(target_cell)
	character_view.play_idle()
	_sync_facing_from_view()


func _sync_facing_from_view() -> void:
	var character_view: CharacterView = _get_view()
	if character_view != null:
		facing_left = character_view.get_facing_left()


func _on_attack_presentation_forced() -> void:
	var character_view: CharacterView = _get_view()
	if character_view != null:
		character_view.play_idle()
	_sync_facing_from_view()


func _get_view() -> CharacterView:
	if view == null:
		view = get_node_or_null("View") as CharacterView

	return view


func _get_model() -> CharacterModel:
	if model == null:
		model = get_node_or_null("Model") as CharacterModel

	return model
