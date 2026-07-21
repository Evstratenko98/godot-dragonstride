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
	var candidates: Array[Vector2i] = []
	var grid_size: Vector2i = runtime.get_grid_size()
	for y: int in range(grid_size.y):
		for x: int in range(grid_size.x):
			var cell: Vector2i = Vector2i(x, y)
			if _is_available(runtime, cell, assigned_cells, ignored_player):
				candidates.append(cell)
	if has_preferred_cell:
		candidates.sort_custom(func(first: Vector2i, second: Vector2i) -> bool:
			var first_distance: int = absi(first.x - preferred_cell.x) + absi(first.y - preferred_cell.y)
			var second_distance: int = absi(second.x - preferred_cell.x) + absi(second.y - preferred_cell.y)
			if first_distance != second_distance:
				return first_distance < second_distance
			if first.y != second.y:
				return first.y < second.y
			return first.x < second.x
		)
	return INVALID_SPAWN_CELL if candidates.is_empty() else candidates[0]


static func get_warrior_color(player_index: int) -> String:
	if player_index >= 0 and player_index < MULTIPLAYER_WARRIOR_COLORS.size():
		return MULTIPLAYER_WARRIOR_COLORS[player_index]
	return MULTIPLAYER_WARRIOR_COLORS[0]


static func get_player_node_name(player_info: Dictionary) -> String:
	var steam_id: int = int(player_info.get("steam_id", 0))
	return "Character" if steam_id == 0 else "Character_%s" % steam_id


static func _is_available(
	runtime: WorldRuntime,
	cell: Vector2i,
	assigned_cells: Dictionary[Vector2i, bool],
	ignored_player: PlayerCharacter
) -> bool:
	return not assigned_cells.has(cell) and runtime.can_character_enter_cell(cell, ignored_player)
