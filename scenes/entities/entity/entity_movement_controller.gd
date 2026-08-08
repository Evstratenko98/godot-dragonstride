class_name EntityMovementController
extends RefCounted

var entity: Entity = null
var runtime: WorldRuntime = null
var current_surface: Vector3i = Vector3i.ZERO
var spawn_surface: Vector3i = Vector3i.ZERO
var is_moving: bool = false
var movement_tween: Tween = null
var action_generation: int = 0


func configure(owner: Entity, world_runtime: WorldRuntime) -> void:
	entity = owner
	runtime = world_runtime


func reset_at_surface(surface: Vector3i) -> void:
	action_generation += 1
	_kill_tween()
	is_moving = false
	current_surface = surface
	if entity != null and runtime != null:
		entity.global_position = runtime.surface_to_world(surface)
		entity.z_index = surface.z * 20 + 10


func cancel_to_surface(surface: Vector3i) -> void:
	reset_at_surface(surface)
	if entity == null:
		return
	if runtime != null:
		runtime.sync_entity_surface(entity, surface)
	entity._on_move_stopped()


func move_to_surface(
	target_surface: Vector3i,
	should_broadcast: bool,
	movement_step_cost: int
) -> void:
	if entity == null or runtime == null or is_moving:
		return
	is_moving = true
	var from_surface: Vector3i = current_surface
	var target_position: Vector2 = runtime.surface_to_world(target_surface)
	var move_generation: int = action_generation
	movement_tween = entity.create_tween()
	movement_tween.set_trans(Tween.TRANS_LINEAR)
	movement_tween.set_ease(Tween.EASE_IN)
	var duration: float = entity.move_time
	var is_ramp_transition: bool = runtime.is_ramp_edge(from_surface, target_surface)
	if is_ramp_transition:
		duration *= 2.0
		# The ramp terrain is rendered in the upper terrain band. Keep the moving
		# entity in the corresponding entity band for the whole diagonal tween.
		entity.z_index = maxi(from_surface.z, target_surface.z) * 20 + 10
	movement_tween.tween_property(entity, "global_position", target_position, duration)
	entity._on_move_started(target_surface)
	runtime.handle_entity_move_started(entity, from_surface, target_surface, should_broadcast)
	entity.movement_started.emit(from_surface, target_surface)
	movement_tween.finished.connect(func() -> void:
		if move_generation != action_generation:
			return
		movement_tween = null
		entity.global_position = target_position
		entity.z_index = target_surface.z * 20 + 10
		current_surface = target_surface
		is_moving = false
		runtime.handle_entity_move_completed(entity, from_surface, target_surface, movement_step_cost)
		entity.movement_finished.emit(from_surface, target_surface)
		entity._on_move_finished(target_surface)
		if entity._try_continue_moving():
			return
		entity._on_move_stopped()
	)


func _kill_tween() -> void:
	if movement_tween != null and movement_tween.is_valid():
		movement_tween.kill()
	movement_tween = null
