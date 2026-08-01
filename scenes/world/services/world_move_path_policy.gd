class_name WorldMovePathPolicy
extends RefCounted

const REQUESTED_PATH_KEY := "requested_path"
const REQUESTED_TARGET_CELL_KEY := "requested_target_cell"
const AUTHORITATIVE_PATH_KEY := "path"


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

	var start_cell: Vector2i = runtime.world_to_cell(player.global_position)
	var target_cell_value: Variant = action.payload.get(REQUESTED_TARGET_CELL_KEY)
	if action.payload.has(REQUESTED_PATH_KEY):
		var requested_path: Array[Vector2i] = read_cells(action.payload, REQUESTED_PATH_KEY)
		if requested_path.is_empty():
			return WorldActionStream.REJECTION_INVALID_ACTION
		target_cell_value = requested_path[requested_path.size() - 1]
		action.payload.erase(REQUESTED_PATH_KEY)
	if not (target_cell_value is Vector2i):
		return WorldActionStream.REJECTION_INVALID_ACTION
	var target_cell: Vector2i = target_cell_value as Vector2i
	action.payload[REQUESTED_TARGET_CELL_KEY] = target_cell
	var shortest_path: Array[Vector2i] = WorldGridPathfinder.find_path_to_cell(
		runtime,
		player,
		start_cell,
		target_cell,
		true
	)
	if shortest_path.is_empty():
		return WorldActionStream.REJECTION_INVALID_ACTION

	var executable_step_count: int = shortest_path.size()
	if turns != null and turns.is_turn_mode_enabled():
		executable_step_count = mini(executable_step_count, turns.get_steps_left())
	if executable_step_count <= 0:
		return WorldActionStream.REJECTION_INVALID_ACTION

	var authoritative_path: Array[Vector2i] = []
	for path_index: int in range(executable_step_count):
		authoritative_path.append(shortest_path[path_index])
	action.payload[AUTHORITATIVE_PATH_KEY] = authoritative_path
	return ""


static func read_cells(payload: Dictionary, path_key: String) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var path_value: Variant = payload.get(path_key, [])
	if not (path_value is Array):
		return path
	for cell_value: Variant in (path_value as Array):
		if not (cell_value is Vector2i):
			path.clear()
			return path
		path.append(cell_value as Vector2i)
	return path
