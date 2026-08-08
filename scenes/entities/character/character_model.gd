class_name CharacterModel
extends Node

signal spell_target_selected(target_surface: Vector3i)

var character: PlayerCharacter = null
var console: Node = null


func _ready() -> void:
	character = get_parent() as PlayerCharacter
	console = get_node_or_null("/root/Console")


func _process(_delta: float) -> void:
	if character == null or not character.is_locally_owned:
		return
	var movement_input_direction: Vector2i = Vector2i.ZERO
	if _can_present_movement_input():
		movement_input_direction = get_input_direction()
	character.set_local_movement_input_state(movement_input_direction != Vector2i.ZERO)
	if character.is_executing_move_path:
		return

	var direction: Vector2i = Vector2i.ZERO
	var can_read_movement_input: bool = _can_read_movement_input()
	if can_read_movement_input:
		direction = get_input_direction()
		if not character.is_attacking:
			character.update_move_animation(direction != Vector2i.ZERO)
	elif not character.is_attacking:
		character.update_move_animation(false)

	if not can_read_movement_input or character.is_moving:
		return

	if direction != Vector2i.ZERO:
		_request_keyboard_move(direction)


func _unhandled_input(event: InputEvent) -> void:
	if character == null:
		return

	if not character.can_process_local_input() or character.runtime == null or _is_console_open():
		return

	if event.is_action_pressed("end_turn"):
		character.runtime.cancel_spell_targeting(character)
		character.runtime.request_end_turn(character)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var target_surface: Vector3i = character.runtime.resolve_selected_surface_at_world(
			character.get_global_mouse_position(),
			character.current_surface.z
		)
		var clicked_character: PlayerCharacter = character.runtime.get_entity_at_surface(target_surface) as PlayerCharacter
		if clicked_character != null and clicked_character.is_locally_owned:
			return
		if character.runtime.has_selected_spell(character):
			if character.runtime.is_surface_inside(target_surface):
				spell_target_selected.emit(target_surface)
			else:
				character.runtime.request_selected_spell_cast(character, target_surface)
			get_viewport().set_input_as_handled()
			return
		if character.action_mode == PlayerCharacter.ActionMode.NONE:
			return
		if character.action_mode == PlayerCharacter.ActionMode.MOVE:
			_request_mouse_move(target_surface)
		elif character.action_mode == PlayerCharacter.ActionMode.INTERACT:
			character.request_interaction_surface(target_surface)
		elif character.action_mode == PlayerCharacter.ActionMode.ATTACK:
			character.runtime.request_character_attack(character, target_surface)


func get_input_direction() -> Vector2i:
	if Input.is_action_pressed("move_right"):
		return Vector2i.RIGHT
	if Input.is_action_pressed("move_left"):
		return Vector2i.LEFT
	if Input.is_action_pressed("move_down"):
		return Vector2i.DOWN
	if Input.is_action_pressed("move_up"):
		return Vector2i.UP

	return Vector2i.ZERO


func should_play_move_animation() -> bool:
	return character != null and character.is_movement_input_held


func try_continue_moving() -> bool:
	if not should_play_move_animation():
		return false

	var direction: Vector2i = get_input_direction()
	if direction == Vector2i.ZERO:
		return false

	_request_keyboard_move(direction)
	return character.is_moving


func _request_keyboard_move(direction: Vector2i) -> void:
	if character.runtime == null or direction == Vector2i.ZERO:
		return
	var target_surface: Vector3i = character.runtime.get_surface_in_direction(
		character.current_surface,
		direction
	)
	if target_surface == WorldGridTopology.INVALID_SURFACE:
		return
	var requested_path: Array[Vector3i] = [target_surface]
	character.request_move_path(requested_path)


func _request_mouse_move(target_surface: Vector3i) -> void:
	if character.runtime == null or not character.runtime.can_entity_move_in_turn(character):
		return
	var requested_path: Array[Vector3i] = WorldGridPathfinder.find_path_to_surface(
		character.runtime,
		character,
		character.current_surface,
		target_surface,
		true
	)
	if not requested_path.is_empty():
		character.request_move_path(requested_path)


func _can_read_movement_input() -> bool:
	if (
		not character.can_process_local_input()
		or _is_console_open()
	):
		return false

	if character.runtime != null:
		return character.runtime.can_entity_move_in_turn(character)

	return true


func _can_present_movement_input() -> bool:
	if (
		character == null
		or not character.is_locally_owned
		or not character.is_selected_local_character
		or not character.can_receive_input
		or character.is_local_input_blocked
		or character.is_attacking
		or character.health <= 0
		or _is_console_open()
	):
		return false
	return character.runtime == null or character.runtime.can_entity_move_in_turn(character)


func _is_console_open() -> bool:
	return console != null and console.has_method("is_visible") and console.is_visible()
