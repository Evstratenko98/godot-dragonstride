class_name WorldMovePathPolicy
extends RefCounted

const REQUESTED_PATH_KEY: String = "requested_path"
const REQUESTED_TARGET_SURFACE_KEY: String = "requested_target_surface"
const AUTHORITATIVE_PATH_KEY: String = "path"


static func prepare_authoritative_path(
	runtime: WorldRuntime,
	turns: WorldTurns,
	player: PlayerCharacter,
	action: WorldActionRecord
) -> String:
	if runtime == null or player == null or action == null:
		return WorldActionStream.REJECTION_INVALID_ACTION
	if not runtime.can_entity_move_in_turn(player):
		return WorldActionStream.REJECTION_INVALID_ACTION
	var target_value: Variant = action.payload.get(REQUESTED_TARGET_SURFACE_KEY)
	if action.payload.has(REQUESTED_PATH_KEY):
		var requested_path: Array[Vector3i] = read_surfaces(action.payload, REQUESTED_PATH_KEY)
		if requested_path.is_empty():
			return WorldActionStream.REJECTION_INVALID_ACTION
		target_value = requested_path[requested_path.size() - 1]
		action.payload.erase(REQUESTED_PATH_KEY)
	if not (target_value is Vector3i):
		return WorldActionStream.REJECTION_INVALID_ACTION
	var target_surface: Vector3i = target_value as Vector3i
	if not runtime.is_surface_inside(target_surface):
		return WorldActionStream.REJECTION_INVALID_ACTION
	action.payload[REQUESTED_TARGET_SURFACE_KEY] = target_surface
	var shortest_path: Array[Vector3i] = WorldGridPathfinder.find_path_to_surface(
		runtime,
		player,
		player.current_surface,
		target_surface,
		true
	)
	if shortest_path.is_empty():
		return WorldActionStream.REJECTION_INVALID_ACTION
	var executable_step_count: int = shortest_path.size()
	if runtime.visibility != null and runtime.visibility.fog_enabled:
		for path_index: int in range(shortest_path.size()):
			if runtime.visibility.get_visibility_mode(player.owner_player_id, shortest_path[path_index]) == WorldVisibility.VisibilityMode.HIDDEN:
				executable_step_count = path_index + 1
				break
	if turns != null and turns.is_turn_mode_enabled():
		if executable_step_count > turns.get_steps_left(player.entity_id):
			return WorldActionStream.REJECTION_INVALID_ACTION
	if executable_step_count <= 0:
		return WorldActionStream.REJECTION_INVALID_ACTION
	var authoritative_path: Array[Vector3i] = []
	for path_index: int in range(executable_step_count):
		authoritative_path.append(shortest_path[path_index])
	action.payload[AUTHORITATIVE_PATH_KEY] = authoritative_path
	return ""


static func read_surfaces(payload: Dictionary, path_key: String) -> Array[Vector3i]:
	var path: Array[Vector3i] = []
	var path_value: Variant = payload.get(path_key, [])
	if not (path_value is Array):
		return path
	for surface_value: Variant in path_value as Array:
		if not (surface_value is Vector3i):
			path.clear()
			return path
		var surface: Vector3i = surface_value as Vector3i
		if surface.z < WorldGridTopology.MIN_ELEVATION or surface.z > WorldGridTopology.MAX_ELEVATION:
			path.clear()
			return path
		path.append(surface)
	return path
