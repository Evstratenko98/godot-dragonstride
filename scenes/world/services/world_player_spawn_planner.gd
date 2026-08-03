class_name WorldPlayerSpawnPlanner
extends RefCounted

const INVALID_SPAWN_CELL := Vector2i(-1, -1)
const MULTIPLAYER_WARRIOR_COLORS: Array[String] = ["Blue", "Purple", "Red", "Yellow"]


static func get_default_spawn_cell(
	runtime: WorldRuntime,
	spawn_cells: Array[Vector2i],
	index: int
) -> Vector2i:
	if index < spawn_cells.size():
		return spawn_cells[index]
	var grid_size: Vector2i = runtime.get_grid_size()
	for y: int in range(grid_size.y):
		for x: int in range(grid_size.x):
			var cell: Vector2i = Vector2i(x, y)
			if runtime.is_cell_walkable_for_character(cell):
				return cell
	return Vector2i(1, 1)


static func find_available_cell(
	runtime: WorldRuntime,
	preferred_cell: Vector2i,
	has_preferred_cell: bool,
	assigned_cells: Dictionary[Vector2i, bool],
	ignored_player: PlayerCharacter = null
) -> Vector2i:
	if has_preferred_cell and _is_available(runtime, preferred_cell, assigned_cells, ignored_player):
		return preferred_cell
	var best_cell: Vector2i = INVALID_SPAWN_CELL
	var best_distance: int = 0
	var grid_size: Vector2i = runtime.get_grid_size()
	for y: int in range(grid_size.y):
		for x: int in range(grid_size.x):
			var cell: Vector2i = Vector2i(x, y)
			if not _is_available(runtime, cell, assigned_cells, ignored_player):
				continue
			if not has_preferred_cell:
				return cell
			var distance: int = absi(cell.x - preferred_cell.x) + absi(cell.y - preferred_cell.y)
			if best_cell == INVALID_SPAWN_CELL or distance < best_distance:
				best_cell = cell
				best_distance = distance
	return best_cell


static func get_warrior_color(player_index: int) -> String:
	if player_index >= 0 and player_index < MULTIPLAYER_WARRIOR_COLORS.size():
		return MULTIPLAYER_WARRIOR_COLORS[player_index]
	return MULTIPLAYER_WARRIOR_COLORS[0]


static func get_player_node_name(player_info: Dictionary) -> String:
	var player_id: String = str(player_info.get("player_id", "player"))
	var squad_slot: int = int(player_info.get("squad_slot", 0))
	return "%s_Follower_%d" % [player_id.to_pascal_case(), squad_slot + 1]


static func _is_available(
	runtime: WorldRuntime,
	cell: Vector2i,
	assigned_cells: Dictionary[Vector2i, bool],
	ignored_player: PlayerCharacter
) -> bool:
	return not assigned_cells.has(cell) and runtime.can_character_enter_cell(cell, ignored_player)
