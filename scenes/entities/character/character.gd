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
	if runtime == null or not can_act():
		return false

	current_cell = runtime.world_to_cell(global_position)
	if not can_attack_cell(target_cell):
		return false

	runtime.request_character_interaction(self, target_cell)
	return true


func apply_remote_state(
	remote_position: Vector2,
	animation: String,
	moving: bool,
	remote_facing_left: bool,
	should_sync_cell: bool = true
) -> void:
	if is_attacking:
		return

	global_position = remote_position
	is_moving = moving
	facing_left = remote_facing_left
	var character_view: CharacterView = _get_view()
	if character_view != null:
		character_view.apply_remote_visual_state(animation, remote_facing_left)

	if runtime != null and should_sync_cell:
		current_cell = runtime.world_to_cell(global_position)
		if not moving:
			runtime.sync_entity_cell(self, current_cell)


func play_remote_attack(target_cell: Vector2i, should_apply: bool = true) -> void:
	if runtime == null:
		runtime = _find_runtime()

	if runtime == null or is_attacking:
		return

	current_cell = runtime.world_to_cell(global_position)
	request_attack_cell(target_cell, should_apply, false)


func update_move_animation(should_walk: bool) -> void:
	var character_view: CharacterView = _get_view()
	if character_view == null:
		return

	if should_walk:
		character_view.play_walk()
	else:
		character_view.play_idle()


func send_network_state() -> void:
	_sync_facing_from_view()
	var character_view: CharacterView = _get_view()
	var current_animation: StringName = &""
	if character_view != null:
		current_animation = character_view.get_current_animation()

	NetworkManager.send_character_state(
		steam_id,
		global_position,
		str(current_animation),
		is_moving,
		facing_left
	)


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

	_play_target_incoming_attack_guard(target_cell, character_view.get_animation_length(animation_name))
	if should_apply:
		_apply_attack_to_world(should_broadcast)

	await character_view.play_attack(animation_name, attack_facing_left, update_horizontal_facing)
	if attack_generation != get_action_generation():
		return

	is_attacking = false
	if runtime != null:
		runtime.notify_entity_action_finished_in_turn(self)
	character_view.play_idle()
	_sync_facing_from_view()


func _sync_facing_from_view() -> void:
	var character_view: CharacterView = _get_view()
	if character_view != null:
		facing_left = character_view.get_facing_left()


func _get_view() -> CharacterView:
	if view == null:
		view = get_node_or_null("View") as CharacterView

	return view


func _get_model() -> CharacterModel:
	if model == null:
		model = get_node_or_null("Model") as CharacterModel

	return model
