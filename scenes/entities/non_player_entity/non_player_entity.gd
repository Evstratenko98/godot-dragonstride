class_name NonPlayerEntity
extends "res://scenes/entities/entity/entity.gd"

@onready var view: NonPlayerView = get_node_or_null("View") as NonPlayerView

var active_behavior_generation: int = 0
var provoked_turn_controller: NonPlayerProvokedTurnController = NonPlayerProvokedTurnController.new()


func _ready() -> void:
	super._ready()
	provoked_turn_controller.configure(self)
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


func die() -> void:
	var death_surface: Vector3i = current_surface
	_on_died()
	if runtime == null:
		queue_free()
		return
	if not runtime.remove_defeated_non_player(self):
		return

	spawn_death_drop(death_surface)


func spawn_death_drop(_death_surface: Vector3i) -> bool:
	return false


func behavior() -> void:
	_finish_behavior()


func run_provoked_behavior_if_active() -> bool:
	return await provoked_turn_controller.run_if_active()


func begin_behavior_generation(generation: int) -> void:
	active_behavior_generation = generation


func get_behavior_generation() -> int:
	return active_behavior_generation


func consider_character_triggers(_characters: Array[Node]) -> void:
	pass


func consider_character_trigger(_character: Node) -> void:
	pass


func consider_character_defeated(_character_entity_id: String) -> void:
	pass


func apply_remote_ai_state(_new_state: String, _new_target_entity_id: String, _reason: String) -> void:
	pass


func play_incoming_attack_guard(_duration: float) -> void:
	pass


func play_remote_move(from_surface: Vector3i, target_surface: Vector3i) -> void:
	if runtime == null:
		runtime = _find_runtime()

	if runtime == null or is_moving or is_attacking:
		return

	current_surface = from_surface
	global_position = runtime.surface_to_world(from_surface)
	if not runtime.reserve_entity_surface(self, from_surface, target_surface):
		return

	_move_to_surface(target_surface, false)


func play_remote_attack(target_surface: Vector3i, should_apply: bool = true) -> void:
	request_attack_surface(target_surface, should_apply, false)


func set_provoked_indicator_visible(is_visible: bool) -> void:
	if view != null:
		view.set_provoked_indicator_visible(is_visible)


func request_behavior_move(direction: Vector2i) -> bool:
	return request_move(direction)


func cancel_behavior() -> void:
	provoked_turn_controller.cancel()
	if is_moving:
		force_cancel_movement(current_surface)
	if is_attacking:
		force_finish_attack_presentation()
	active_behavior_generation = 0


func can_behavior_move(direction: Vector2i) -> bool:
	if direction == Vector2i.ZERO or runtime == null:
		return false

	var target_surface: Vector3i = runtime.get_surface_in_direction(current_surface, direction)
	return (
		target_surface != WorldGridTopology.INVALID_SURFACE
		and runtime.can_enter_surface(target_surface, self)
	)


func _on_move_direction_selected(direction: Vector2i) -> void:
	if view != null:
		view.face_direction(direction)


func _on_move_started(_target_surface: Vector3i) -> void:
	if view != null:
		view.play_walk()


func _on_move_stopped() -> void:
	if view != null:
		view.play_idle()
	if provoked_turn_controller.is_running_turn:
		return
	_finish_behavior()


func _on_attack_presentation_forced() -> void:
	if view != null:
		view.play_idle()
	if provoked_turn_controller.is_running_turn:
		return
	_finish_behavior()


func _finish_behavior() -> void:
	if runtime != null:
		runtime.notify_entity_action_finished_in_turn(self, active_behavior_generation)
