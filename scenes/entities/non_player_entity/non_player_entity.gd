class_name NonPlayerEntity
extends "res://scenes/entities/entity/entity.gd"

@onready var view = get_node_or_null("View")


func _ready() -> void:
	super._ready()
	if view != null and view.has_method("play_idle"):
		view.play_idle()


func start_non_player_entity(
	start_position: Vector2,
	new_entity_id := "",
	new_entity_name := "",
	new_entity_type: EntityType = EntityType.NPC
) -> void:
	start_entity(start_position, new_entity_id, new_entity_name, new_entity_type)
	if view != null and view.has_method("play_idle"):
		view.play_idle()


func behavior() -> void:
	_finish_behavior()


func play_remote_move(from_cell: Vector2i, target_cell: Vector2i) -> void:
	if world == null:
		world = _find_world()

	if world == null or is_moving or is_attacking:
		return

	current_cell = from_cell
	global_position = world.cell_to_world(from_cell)
	if world.has_method("reserve_entity_cell") and not world.reserve_entity_cell(self, from_cell, target_cell):
		return

	_move_to_cell(target_cell, false)


func request_behavior_move(direction: Vector2i) -> bool:
	return request_move(direction)


func can_behavior_move(direction: Vector2i) -> bool:
	if direction == Vector2i.ZERO or world == null:
		return false

	current_cell = world.world_to_cell(global_position)
	return world.can_enter_cell(current_cell + direction, self)


func _on_move_direction_selected(direction: Vector2i) -> void:
	if view != null and view.has_method("face_direction"):
		view.face_direction(direction)


func _on_move_started(_target_cell: Vector2i) -> void:
	if view != null and view.has_method("play_walk"):
		view.play_walk()


func _on_move_stopped() -> void:
	if view != null and view.has_method("play_idle"):
		view.play_idle()
	_finish_behavior()


func _finish_behavior() -> void:
	if world != null and world.has_method("notify_entity_action_finished_in_turn"):
		world.notify_entity_action_finished_in_turn(self)
