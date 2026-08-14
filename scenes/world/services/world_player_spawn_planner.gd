class_name WorldPlayerSpawnPlanner
extends RefCounted

const INVALID_SPAWN_SURFACE: Vector3i = Vector3i(-1, -1, -1)
const MULTIPLAYER_APPEARANCES: Array[String] = ["Blue", "Purple", "Red", "Yellow"]


static func get_default_spawn_surface(
	runtime: WorldRuntime,
	spawn_surfaces: Array[Vector3i],
	index: int
) -> Vector3i:
	if index >= 0 and index < spawn_surfaces.size():
		return spawn_surfaces[index]
	return find_available_surface(runtime, INVALID_SPAWN_SURFACE, false, {})


static func find_available_surface(
	runtime: WorldRuntime,
	preferred_surface: Vector3i,
	has_preferred_surface: bool,
	assigned_surfaces: Dictionary[Vector3i, bool],
	ignored_player: PlayerCharacter = null
) -> Vector3i:
	if (
		has_preferred_surface
		and _is_available(runtime, preferred_surface, assigned_surfaces, ignored_player)
	):
		return preferred_surface
	var best_surface: Vector3i = INVALID_SPAWN_SURFACE
	var best_distance: int = 0
	var grid_size: Vector2i = runtime.get_grid_size()
	for elevation: int in range(WorldGridTopology.MIN_ELEVATION, WorldGridTopology.MAX_ELEVATION + 1):
		for y: int in range(grid_size.y):
			for x: int in range(grid_size.x):
				var surface: Vector3i = Vector3i(x, y, elevation)
				if not _is_available(runtime, surface, assigned_surfaces, ignored_player):
					continue
				if not has_preferred_surface:
					return surface
				var distance: int = (
					absi(surface.x - preferred_surface.x)
					+ absi(surface.y - preferred_surface.y)
					+ absi(surface.z - preferred_surface.z)
				)
				if best_surface == INVALID_SPAWN_SURFACE or distance < best_distance:
					best_surface = surface
					best_distance = distance
	return best_surface


static func get_character_appearance(player_index: int) -> String:
	if player_index >= 0 and player_index < MULTIPLAYER_APPEARANCES.size():
		return MULTIPLAYER_APPEARANCES[player_index]
	return MULTIPLAYER_APPEARANCES[0]


static func get_player_node_name(player_info: Dictionary) -> String:
	var player_id: String = str(player_info.get("player_id", "player"))
	var squad_slot: int = int(player_info.get("squad_slot", 0))
	return "%s_Follower_%d" % [player_id.to_pascal_case(), squad_slot + 1]


static func _is_available(
	runtime: WorldRuntime,
	surface: Vector3i,
	assigned_surfaces: Dictionary[Vector3i, bool],
	ignored_player: PlayerCharacter
) -> bool:
	return (
		not assigned_surfaces.has(surface)
		and runtime.has_surface(surface)
		and runtime.can_character_enter_surface(surface, ignored_player)
	)
