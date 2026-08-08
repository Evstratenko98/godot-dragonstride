class_name WorldGrid
extends Node

const CELL_SIZE: int = 64

@export var grid_size: Vector2i = Vector2i(19, 19)
@export var walkable_layer_names: PackedStringArray = ["Ground"]
@export var character_walkable_layer_names: PackedStringArray = ["Hay", "Bridge"]

var level: WorldLevel = null
var topology: WorldGridTopology = WorldGridTopology.new()
var topology_error: String = ""


func configure_context(_runtime: WorldRuntime, new_level: WorldLevel) -> void:
	level = new_level
	_compile_topology()


func configure(
	new_grid_size: Vector2i,
	new_walkable_layer_names: PackedStringArray,
	new_character_walkable_layer_names: PackedStringArray
) -> void:
	grid_size = new_grid_size
	walkable_layer_names = new_walkable_layer_names
	character_walkable_layer_names = new_character_walkable_layer_names
	_compile_topology()


func has_surface(surface: Vector3i) -> bool:
	return topology.has_surface(surface)


func is_surface_walkable(surface: Vector3i) -> bool:
	return topology.is_walkable_for_entity(surface, null)


func is_surface_walkable_for_entity(surface: Vector3i, entity: Entity) -> bool:
	return topology.is_walkable_for_entity(surface, entity)


func is_surface_walkable_for_character(surface: Vector3i) -> bool:
	return topology.is_walkable_for_character(surface)


func is_surface_inside(surface: Vector3i) -> bool:
	return (
		surface.z >= WorldGridTopology.MIN_ELEVATION
		and surface.z <= WorldGridTopology.MAX_ELEVATION
		and surface.x >= 0
		and surface.y >= 0
		and surface.x < grid_size.x
		and surface.y < grid_size.y
	)


func get_surface_neighbors(surface: Vector3i) -> Array[Vector3i]:
	return topology.get_neighbors(surface)


func get_surface_in_direction(surface: Vector3i, direction: Vector2i) -> Vector3i:
	return topology.get_surface_in_direction(surface, direction)


func has_traversal_edge(from_surface: Vector3i, to_surface: Vector3i) -> bool:
	return topology.has_edge(from_surface, to_surface)


func is_ramp_edge(from_surface: Vector3i, to_surface: Vector3i) -> bool:
	return topology.is_ramp_edge(from_surface, to_surface)


func get_traversal_kind(from_surface: Vector3i, to_surface: Vector3i) -> int:
	return topology.get_traversal_kind(from_surface, to_surface)


func get_traversal_input_direction(from_surface: Vector3i, to_surface: Vector3i) -> Vector2i:
	return topology.get_input_direction_for_edge(from_surface, to_surface)


func get_surfaces_at(cell: Vector2i) -> Array[Vector3i]:
	return topology.get_surfaces_at(cell)


func get_topology_hash() -> String:
	return topology.get_hash()


func get_surface_display_name(surface: Vector3i) -> String:
	return topology.get_display_name(surface)


func get_topology_error() -> String:
	return topology_error


func get_grid_size() -> Vector2i:
	return grid_size


func get_cell_size() -> int:
	return CELL_SIZE


func get_world_bounds() -> Rect2:
	if level == null or grid_size.x <= 0 or grid_size.y <= 0:
		return Rect2()
	var local_size: Vector2 = Vector2(grid_size) * float(CELL_SIZE)
	var top_left: Vector2 = level.to_global(Vector2.ZERO)
	var top_right: Vector2 = level.to_global(Vector2(local_size.x, 0.0))
	var bottom_left: Vector2 = level.to_global(Vector2(0.0, local_size.y))
	var bottom_right: Vector2 = level.to_global(local_size)
	var minimum_position: Vector2 = Vector2(
		minf(minf(top_left.x, top_right.x), minf(bottom_left.x, bottom_right.x)),
		minf(minf(top_left.y, top_right.y), minf(bottom_left.y, bottom_right.y))
	)
	var maximum_position: Vector2 = Vector2(
		maxf(maxf(top_left.x, top_right.x), maxf(bottom_left.x, bottom_right.x)),
		maxf(maxf(top_left.y, top_right.y), maxf(bottom_left.y, bottom_right.y))
	)
	return Rect2(minimum_position, maximum_position - minimum_position)


func world_to_surface(world_position: Vector2, elevation: int = 0) -> Vector3i:
	var local_position: Vector2 = level.to_local(world_position)
	return Vector3i(
		floori(local_position.x / CELL_SIZE),
		floori(local_position.y / CELL_SIZE),
		elevation
	)


func surface_to_world(surface: Vector3i) -> Vector2:
	var local_position: Vector2 = Vector2(surface.x, surface.y) * CELL_SIZE
	local_position += Vector2(CELL_SIZE, CELL_SIZE) * 0.5
	return level.to_global(local_position)


func get_surface_center(world_position: Vector2, elevation: int = 0) -> Vector2:
	return surface_to_world(world_to_surface(world_position, elevation))


func get_adjacent_surface_center(
	world_position: Vector2,
	direction: Vector2i,
	elevation: int = 0
) -> Vector2:
	var surface: Vector3i = world_to_surface(world_position, elevation)
	var target: Vector3i = get_surface_in_direction(surface, direction)
	if target == WorldGridTopology.INVALID_SURFACE:
		return surface_to_world(surface)
	return surface_to_world(target)


func _compile_topology() -> void:
	topology_error = ""
	if level == null:
		topology.clear()
		return
	topology_error = topology.compile(level, level.get_terrain_topology_root())
	if not topology_error.is_empty():
		push_error("World topology validation failed: %s" % topology_error)
