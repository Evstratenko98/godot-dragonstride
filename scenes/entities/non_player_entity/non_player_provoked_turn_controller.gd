class_name NonPlayerProvokedTurnController
extends RefCounted

var entity: NonPlayerEntity = null
var is_running_turn: bool = false


func configure(owner: NonPlayerEntity) -> void:
	entity = owner


func run_if_active() -> bool:
	if (
		entity == null
		or entity.runtime == null
		or entity.runtime.abilities == null
		or not entity.runtime.abilities.has_active_provocation(entity)
	):
		return false
	is_running_turn = true
	var behavior_generation: int = entity.get_behavior_generation()
	var provoker: PlayerCharacter = entity.runtime.abilities.get_provoker(entity)
	if not _is_valid_provoker(provoker):
		_end_turn()
		return true
	if _try_attack(provoker):
		return true
	var goal_surfaces: Array[Vector3i] = WorldGridPathfinder.get_adjacent_walkable_surfaces(
		entity.runtime,
		provoker.current_surface
	)
	var path: Array[Vector3i] = WorldGridPathfinder.find_path_to_any(
		entity.runtime,
		entity,
		entity.current_surface,
		goal_surfaces,
		true
	)
	if path.is_empty():
		_end_turn()
		return true
	var steps_to_take: int = mini(entity.get_max_movement_steps_per_turn(), path.size())
	for path_index: int in range(steps_to_take):
		if not _is_valid_provoker(provoker):
			_end_turn()
			return true
		var next_surface: Vector3i = path[path_index]
		var direction: Vector2i = entity.runtime.get_traversal_input_direction(
			entity.current_surface,
			next_surface
		)
		if not entity.request_behavior_move(direction):
			_end_turn()
			return true
		await _wait_until_ready()
		if behavior_generation != entity.get_behavior_generation() or not is_running_turn:
			return true
		if _try_attack(provoker):
			return true
	_end_turn()
	return true


func cancel() -> void:
	is_running_turn = false


func _try_attack(provoker: PlayerCharacter) -> bool:
	if not _is_valid_provoker(provoker) or not entity.can_attack_surface(provoker.current_surface):
		return false
	is_running_turn = false
	if entity.request_attack_surface(provoker.current_surface, true, true):
		return true
	entity._finish_behavior()
	return true


func _is_valid_provoker(provoker: PlayerCharacter) -> bool:
	return provoker != null and is_instance_valid(provoker) and provoker.health > 0 and provoker.visible


func _wait_until_ready() -> void:
	if entity == null or not entity.is_inside_tree():
		return
	var scene_tree: SceneTree = entity.get_tree()
	while entity.is_moving or entity.is_attacking:
		await scene_tree.process_frame
		if not entity.is_inside_tree():
			return


func _end_turn() -> void:
	is_running_turn = false
	if entity != null:
		entity._finish_behavior()
