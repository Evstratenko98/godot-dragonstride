class_name CharacterModel
extends Node

var character: PlayerCharacter = null


func _ready() -> void:
	character = get_parent() as PlayerCharacter


func _process(_delta: float) -> void:
	if character == null or not character.is_local_player:
		return

	var direction: Vector2i = Vector2i.ZERO
	var can_read_movement_input: bool = _can_read_movement_input()
	if can_read_movement_input:
		direction = get_input_direction()
		character.update_move_animation(direction != Vector2i.ZERO)
	elif not character.is_attacking:
		character.update_move_animation(false)

	if GameSession.is_multiplayer() and not character.is_attacking:
		character.send_network_state()

	if not can_read_movement_input or character.is_moving:
		return

	if direction != Vector2i.ZERO:
		character.request_move(direction)


func _unhandled_input(event: InputEvent) -> void:
	if character == null:
		return

	if not character.can_receive_input or character.runtime == null or _is_console_open():
		return

	if event.is_action_pressed("end_turn"):
		character.runtime.request_end_turn(character)
		get_viewport().set_input_as_handled()
		return

	if character.is_moving or character.is_attacking:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		character.request_attack_cell(character.runtime.world_to_cell(character.get_global_mouse_position()), true, true)


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
	return _can_read_movement_input() and get_input_direction() != Vector2i.ZERO


func try_continue_moving() -> bool:
	if not should_play_move_animation():
		return false

	var direction: Vector2i = get_input_direction()
	if direction == Vector2i.ZERO:
		return false

	character.request_move(direction)
	return character.is_moving


func _can_read_movement_input() -> bool:
	if not character.can_receive_input or character.is_attacking or _is_console_open():
		return false

	if character.runtime != null:
		return character.runtime.can_entity_move_in_turn(character)

	return true


func _is_console_open() -> bool:
	var console: Node = get_node_or_null("/root/Console")
	return console != null and console.has_method("is_visible") and console.is_visible()
