class_name WorldGridPathfinder
extends RefCounted

const ORTHOGONAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i.RIGHT,
	Vector2i.LEFT,
	Vector2i.DOWN,
	Vector2i.UP,
]


static func get_adjacent_walkable_surfaces(
	runtime: WorldRuntime,
	target_surface: Vector3i
) -> Array[Vector3i]:
	var surfaces: Array[Vector3i] = []
	if runtime == null:
		return surfaces
	for direction: Vector2i in ORTHOGONAL_DIRECTIONS:
		var candidate: Vector3i = Vector3i(
			target_surface.x + direction.x,
			target_surface.y + direction.y,
			target_surface.z
		)
		if runtime.is_surface_inside(candidate) and runtime.is_surface_walkable(candidate):
			surfaces.append(candidate)
	return surfaces


static func get_reachable_surfaces_for_entity(
	runtime: WorldRuntime,
	entity: Entity,
	max_steps: int
) -> Array[Vector3i]:
	var reachable: Array[Vector3i] = []
	if runtime == null or entity == null or max_steps <= 0:
		return reachable
	var start: Vector3i = entity.current_surface
	var known_map_player_id: String = ""
	var local_player: PlayerCharacter = entity as PlayerCharacter
	if local_player != null and local_player.is_locally_owned:
		known_map_player_id = local_player.owner_player_id
	var maximum_distance: int = mini(max_steps, WorldGridTopology.MAX_SURFACES)
	var frontier: Array[Vector3i] = [start]
	var distances: Dictionary[Vector3i, int] = {start: 0}
	var frontier_index: int = 0
	while frontier_index < frontier.size():
		var current: Vector3i = frontier[frontier_index]
		frontier_index += 1
		var current_distance: int = distances[current]
		if current_distance >= maximum_distance:
			continue
		for next_surface: Vector3i in runtime.get_surface_neighbors(current):
			if distances.has(next_surface) or not _can_enter(runtime, entity, next_surface, true, known_map_player_id):
				continue
			distances[next_surface] = current_distance + 1
			frontier.append(next_surface)
			reachable.append(next_surface)
	return reachable


static func find_path_to_any(
	runtime: WorldRuntime,
	moving_entity: Entity,
	start_surface: Vector3i,
	goal_surfaces: Array[Vector3i],
	should_respect_occupancy: bool,
	known_map_player_id: String = ""
) -> Array[Vector3i]:
	var empty_path: Array[Vector3i] = []
	if runtime == null or moving_entity == null or goal_surfaces.is_empty():
		return empty_path
	var goals: Dictionary[Vector3i, bool] = {}
	for goal_surface: Vector3i in goal_surfaces:
		goals[goal_surface] = true
	if goals.has(start_surface):
		return empty_path
	var frontier: Array[Vector3i] = [start_surface]
	var came_from: Dictionary[Vector3i, Vector3i] = {start_surface: start_surface}
	var frontier_index: int = 0
	while frontier_index < frontier.size() and frontier_index < WorldGridTopology.MAX_SURFACES:
		var surface: Vector3i = frontier[frontier_index]
		frontier_index += 1
		for next_surface: Vector3i in runtime.get_surface_neighbors(surface):
			if came_from.has(next_surface):
				continue
			if not _can_enter(runtime, moving_entity, next_surface, should_respect_occupancy, known_map_player_id):
				continue
			came_from[next_surface] = surface
			if goals.has(next_surface):
				return _reconstruct_path(came_from, start_surface, next_surface)
			frontier.append(next_surface)
	return empty_path


static func find_path_to_surface(
	runtime: WorldRuntime,
	moving_entity: Entity,
	start_surface: Vector3i,
	target_surface: Vector3i,
	should_respect_occupancy: bool = true,
	known_map_player_id: String = ""
) -> Array[Vector3i]:
	return find_path_to_any(
		runtime,
		moving_entity,
		start_surface,
		[target_surface],
		should_respect_occupancy,
		known_map_player_id
	)


static func _can_enter(
	runtime: WorldRuntime,
	moving_entity: Entity,
	surface: Vector3i,
	should_respect_occupancy: bool,
	known_map_player_id: String = ""
) -> bool:
	if not runtime.is_surface_inside(surface):
		return false
	if not runtime.is_surface_walkable_for_entity(surface, moving_entity):
		return false
	if not known_map_player_id.is_empty() and runtime.visibility != null:
		if runtime.visibility.is_surface_blocked_on_known_map(known_map_player_id, surface):
			return false
		var visibility_mode: WorldVisibility.VisibilityMode = runtime.visibility.get_visibility_mode(known_map_player_id, surface)
		if visibility_mode == WorldVisibility.VisibilityMode.HIDDEN:
			return false
		if visibility_mode == WorldVisibility.VisibilityMode.EXPLORED:
			return true
	elif runtime.get_object_at_surface(surface) != null:
		return false
	return not should_respect_occupancy or runtime.can_enter_surface(surface, moving_entity)


static func _reconstruct_path(
	came_from: Dictionary[Vector3i, Vector3i],
	start_surface: Vector3i,
	end_surface: Vector3i
) -> Array[Vector3i]:
	var path: Array[Vector3i] = []
	var surface: Vector3i = end_surface
	while surface != start_surface:
		path.append(surface)
		surface = came_from[surface]
	path.reverse()
	return path
