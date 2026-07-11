class_name NonPlayerEntity
extends "res://scenes/entities/entity/entity.gd"

@onready var view: NonPlayerView = get_node_or_null("View") as NonPlayerView


func _ready() -> void:
	super._ready()
	if view != null:
		view.play_idle()


func start_non_player_entity(
	start_position: Vector2,
	new_entity_id: String = "",
	new_entity_name: String = "",
	new_entity_type: EntityType = EntityType.NPC
) -> void:
	start_entity(start_position, new_entity_id, new_entity_name, new_entity_type)
	if view != null:
		view.play_idle()


func start(
	start_position: Vector2,
	new_entity_id: String = "",
	new_entity_name: String = ""
) -> void:
	start_non_player_entity(start_position, new_entity_id, new_entity_name)


func behavior() -> void:
	_finish_behavior()


func consider_character_triggers(_characters: Array[Node]) -> void:
	pass


func consider_character_trigger(_character: Node) -> void:
	pass


func apply_remote_ai_state(_new_state: String, _new_target_entity_id: String, _reason: String) -> void:
	pass


func play_incoming_attack_guard(_duration: float) -> void:
	pass


func play_remote_move(from_cell: Vector2i, target_cell: Vector2i) -> void:
	if runtime == null:
		runtime = _find_runtime()

	if runtime == null or is_moving or is_attacking:
		return

	current_cell = from_cell
	global_position = runtime.cell_to_world(from_cell)
	if not runtime.reserve_entity_cell(self, from_cell, target_cell):
		return

	_move_to_cell(target_cell, false)


func play_remote_attack(target_cell: Vector2i, should_apply: bool = true) -> void:
	request_attack_cell(target_cell, should_apply, false)


func request_behavior_move(direction: Vector2i) -> bool:
	return request_move(direction)


func can_behavior_move(direction: Vector2i) -> bool:
	if direction == Vector2i.ZERO or runtime == null:
		return false

	current_cell = runtime.world_to_cell(global_position)
	return runtime.can_enter_cell(current_cell + direction, self)


func _on_move_direction_selected(direction: Vector2i) -> void:
	if view != null:
		view.face_direction(direction)


func _on_move_started(_target_cell: Vector2i) -> void:
	if view != null:
		view.play_walk()


func _on_move_stopped() -> void:
	if view != null:
		view.play_idle()
	_finish_behavior()


func _finish_behavior() -> void:
	if runtime != null:
		runtime.notify_entity_action_finished_in_turn(self)
