class_name WorldGridPathfinder
extends RefCounted

const ORTHOGONAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i.RIGHT,
	Vector2i.LEFT,
	Vector2i.DOWN,
	Vector2i.UP,
]
const REACHABILITY_DIRECTIONS: Array[Vector2i] = [
	Vector2i.LEFT,
	Vector2i.RIGHT,
	Vector2i.UP,
	Vector2i.DOWN,
]


static func get_adjacent_walkable_cells(runtime: WorldRuntime, target_cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if runtime == null:
		return cells
	for direction: Vector2i in ORTHOGONAL_DIRECTIONS:
		var candidate_cell: Vector2i = target_cell + direction
		if runtime.is_cell_inside(candidate_cell) and runtime.is_cell_walkable(candidate_cell):
			cells.append(candidate_cell)
	return cells


static func get_reachable_cells_for_entity(
	runtime: WorldRuntime,
	entity: Entity,
	max_steps: int
) -> Array[Vector2i]:
	var reachable_cells: Array[Vector2i] = []
	if runtime == null or entity == null or max_steps <= 0:
		return reachable_cells

	var start_cell: Vector2i = runtime.world_to_cell(entity.global_position)
	var grid_size: Vector2i = runtime.get_grid_size()
	var maximum_distance: int = mini(max_steps, grid_size.x * grid_size.y)
	var frontier: Array[Vector2i] = [start_cell]
	var distances: Dictionary[Vector2i, int] = {start_cell: 0}
	var frontier_index: int = 0
	while frontier_index < frontier.size():
		var current_cell: Vector2i = frontier[frontier_index]
		frontier_index += 1
		var current_distance: int = distances[current_cell]
		if current_distance >= maximum_distance:
			continue

		for direction: Vector2i in REACHABILITY_DIRECTIONS:
			var next_cell: Vector2i = current_cell + direction
			if distances.has(next_cell) or not runtime.can_enter_cell(next_cell, entity):
				continue
			distances[next_cell] = current_distance + 1
			frontier.append(next_cell)
			reachable_cells.append(next_cell)

	return reachable_cells


static func find_path_to_any(
	runtime: WorldRuntime,
	moving_entity: Entity,
	start_cell: Vector2i,
	goal_cells: Array[Vector2i],
	should_respect_occupancy: bool
) -> Array[Vector2i]:
	var empty_path: Array[Vector2i] = []
	if runtime == null or moving_entity == null or goal_cells.is_empty():
		return empty_path
	var goals: Dictionary[Vector2i, bool] = {}
	for goal_cell: Vector2i in goal_cells:
		goals[goal_cell] = true
	if goals.has(start_cell):
		return empty_path

	var frontier: Array[Vector2i] = [start_cell]
	var came_from: Dictionary[Vector2i, Vector2i] = {start_cell: start_cell}
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_front()
		for direction: Vector2i in ORTHOGONAL_DIRECTIONS:
			var next_cell: Vector2i = cell + direction
			if came_from.has(next_cell):
				continue
			if not _can_enter(runtime, moving_entity, next_cell, should_respect_occupancy):
				continue
			came_from[next_cell] = cell
			if goals.has(next_cell):
				return _reconstruct_path(came_from, start_cell, next_cell)
			frontier.append(next_cell)
	return empty_path


static func _can_enter(
	runtime: WorldRuntime,
	moving_entity: Entity,
	cell: Vector2i,
	should_respect_occupancy: bool
) -> bool:
	if not runtime.is_cell_inside(cell) or not runtime.is_cell_walkable(cell):
		return false
	if runtime.get_object_at_cell(cell) != null:
		return false
	return not should_respect_occupancy or runtime.can_enter_cell(cell, moving_entity)


static func _reconstruct_path(
	came_from: Dictionary[Vector2i, Vector2i],
	start_cell: Vector2i,
	end_cell: Vector2i
) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var cell: Vector2i = end_cell
	while cell != start_cell:
		path.push_front(cell)
		cell = came_from[cell]
	return path
