class_name PlayerCharacter
extends "res://scenes/entities/entity/entity.gd"

signal action_mode_changed(action_mode: ActionMode)

enum ActionMode {
	ATTACK,
	INTERACT,
}

@onready var view: CharacterView = get_node("View") as CharacterView
@onready var model: CharacterModel = get_node("Model") as CharacterModel
@onready var character_inventory: CharacterInventory = get_node("CharacterInventory") as CharacterInventory

var facing_left: bool = false
var steam_id: int = 0
var is_local_player: bool = true
var can_receive_input: bool = true
var action_mode: ActionMode = ActionMode.ATTACK


func _ready() -> void:
	super._ready()
	var character_view: CharacterView = _get_view()
	if character_view != null:
		character_view.play_idle()
	_sync_facing_from_view()


func setup_multiplayer_player(player_info: Dictionary) -> void:
	steam_id = int(player_info.get("steam_id", 0))
	is_local_player = bool(player_info.get("is_local", true))
	can_receive_input = is_local_player


func start(
	start_position: Vector2,
	receive_input: bool = true,
	new_entity_id: String = "",
	new_entity_name: String = ""
) -> void:
	can_receive_input = receive_input
	is_local_player = receive_input
	action_mode = ActionMode.ATTACK
	start_entity(start_position, new_entity_id, new_entity_name, EntityType.CHARACTER)
	character_inventory.configure_owner(entity_id)


func set_warrior_color(color_name: String) -> void:
	var character_view: CharacterView = _get_view()
	if character_view != null:
		character_view.set_warrior_color(color_name)


func set_action_mode(new_action_mode: ActionMode) -> void:
	if action_mode == new_action_mode:
		return

	action_mode = new_action_mode
	action_mode_changed.emit(action_mode)


func request_interaction_cell(target_cell: Vector2i) -> bool:
	if runtime == null or health <= 0:
		return false

	current_cell = runtime.world_to_cell(global_position)
	if not can_attack_cell(target_cell):
		return false

	runtime.request_character_interaction(self, target_cell)
	return true


func request_move(direction: Vector2i) -> bool:
	if runtime == null or direction == Vector2i.ZERO:
		return false
	return runtime.request_character_move(self, direction)


func execute_authoritative_move(direction: Vector2i) -> bool:
	return super.execute_move(direction, false)


func play_remote_move(from_cell: Vector2i, target_cell: Vector2i) -> bool:
	if runtime == null or is_moving or is_attacking:
		return false
	current_cell = from_cell
	global_position = runtime.cell_to_world(from_cell)
	if not runtime.reserve_entity_cell(self, from_cell, target_cell):
		return false
	_move_to_cell(target_cell, false)
	return true


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
	if runtime != null:
		runtime.notify_character_defeated(self)
	respawn()


func respawn() -> void:
	super.respawn()
	var character_view: CharacterView = _get_view()
	if character_view != null:
		character_view.play_idle()
	update_move_animation(false)
	_sync_facing_from_view()


func _on_move_direction_selected(direction: Vector2i) -> void:
	var character_view: CharacterView = _get_view()
	if character_view != null:
		character_view.face_direction(direction)
	_sync_facing_from_view()


func _try_continue_moving() -> bool:
	var character_model: CharacterModel = _get_model()
	if character_model == null:
		return false

	return character_model.try_continue_moving()


func _on_move_stopped() -> void:
	var character_model: CharacterModel = _get_model()
	update_move_animation(character_model != null and character_model.should_play_move_animation())


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
