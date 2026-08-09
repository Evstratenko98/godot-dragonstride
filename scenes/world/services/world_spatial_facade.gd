class_name WorldSpatialFacade
extends RefCounted

var grid: WorldGrid = null
var registry: WorldRegistry = null
var selected_input_surface: Vector3i = WorldGridTopology.INVALID_SURFACE


func configure(new_grid: WorldGrid, new_registry: WorldRegistry) -> void:
	grid = new_grid
	registry = new_registry
	selected_input_surface = WorldGridTopology.INVALID_SURFACE


func has_surface(surface: Vector3i) -> bool:
	return grid != null and grid.has_surface(surface)


func is_surface_walkable(surface: Vector3i) -> bool:
	return grid != null and grid.is_surface_walkable(surface)


func is_surface_walkable_for_entity(surface: Vector3i, entity: Entity) -> bool:
	return grid != null and grid.is_surface_walkable_for_entity(surface, entity)


func is_surface_walkable_for_character(surface: Vector3i) -> bool:
	return grid != null and grid.is_surface_walkable_for_character(surface)


func is_surface_inside(surface: Vector3i) -> bool:
	return grid != null and grid.is_surface_inside(surface)


func get_surface_neighbors(surface: Vector3i) -> Array[Vector3i]:
	if grid == null:
		return []
	return grid.get_surface_neighbors(surface)


func get_surface_in_direction(surface: Vector3i, direction: Vector2i) -> Vector3i:
	return WorldGridTopology.INVALID_SURFACE if grid == null else grid.get_surface_in_direction(surface, direction)


func has_traversal_edge(from_surface: Vector3i, to_surface: Vector3i) -> bool:
	return grid != null and grid.has_traversal_edge(from_surface, to_surface)


func is_ramp_edge(from_surface: Vector3i, to_surface: Vector3i) -> bool:
	return grid != null and grid.is_ramp_edge(from_surface, to_surface)


func is_ramp_footprint_cell(cell: Vector2i) -> bool:
	return grid != null and grid.is_ramp_footprint_cell(cell)


func get_traversal_kind(from_surface: Vector3i, to_surface: Vector3i) -> int:
	return WorldRampConnection.TraversalKind.NORMAL if grid == null else grid.get_traversal_kind(from_surface, to_surface)


func get_traversal_input_direction(from_surface: Vector3i, to_surface: Vector3i) -> Vector2i:
	return Vector2i.ZERO if grid == null else grid.get_traversal_input_direction(from_surface, to_surface)


func get_surfaces_at(cell: Vector2i) -> Array[Vector3i]:
	if grid == null:
		return []
	return grid.get_surfaces_at(cell)


func get_all_surfaces() -> Array[Vector3i]:
	if grid == null:
		return []
	return grid.get_all_surfaces()


func resolve_surface_at_world(world_position: Vector2, preferred_elevation: int) -> Vector3i:
	if grid == null:
		return WorldGridTopology.INVALID_SURFACE
	var projected: Vector3i = grid.world_to_surface(world_position, preferred_elevation)
	var surfaces: Array[Vector3i] = grid.get_surfaces_at(Vector2i(projected.x, projected.y))
	if surfaces.is_empty():
		return projected
	for surface: Vector3i in surfaces:
		if surface.z == preferred_elevation:
			return surface
	return surfaces[surfaces.size() - 1]


func set_selected_input_surface(surface: Vector3i) -> void:
	selected_input_surface = surface if has_surface(surface) else WorldGridTopology.INVALID_SURFACE


func resolve_selected_surface_at_world(world_position: Vector2, preferred_elevation: int) -> Vector3i:
	if selected_input_surface != WorldGridTopology.INVALID_SURFACE:
		var projected: Vector3i = grid.world_to_surface(world_position, preferred_elevation)
		if Vector2i(projected.x, projected.y) == Vector2i(selected_input_surface.x, selected_input_surface.y):
			return selected_input_surface
	return resolve_surface_at_world(world_position, preferred_elevation)


func get_object_anchor_surface(target_object: GridObject) -> Vector3i:
	if target_object == null or grid == null:
		return WorldGridTopology.INVALID_SURFACE
	return grid.world_to_surface(target_object.global_position, target_object.surface_height)


func get_topology_hash() -> String:
	return "" if grid == null else grid.get_topology_hash()


func get_grid_size() -> Vector2i:
	return Vector2i.ZERO if grid == null else grid.get_grid_size()


func get_cell_size() -> int:
	return WorldGrid.CELL_SIZE if grid == null else grid.get_cell_size()


func get_grid_world_bounds() -> Rect2:
	return Rect2() if grid == null else grid.get_world_bounds()


func world_to_surface(world_position: Vector2, elevation: int = 0) -> Vector3i:
	return WorldGridTopology.INVALID_SURFACE if grid == null else grid.world_to_surface(world_position, elevation)


func surface_to_world(surface: Vector3i) -> Vector2:
	return Vector2.ZERO if grid == null else grid.surface_to_world(surface)


func get_entity_by_id(entity_id: String) -> Node:
	return null if registry == null else registry.get_entity_by_id(entity_id)


func get_entity_at_surface(surface: Vector3i) -> Node:
	return null if registry == null else registry.get_entity_at_surface(surface)


func get_object_at_surface(surface: Vector3i) -> Node:
	return null if registry == null else registry.get_object_at_surface(surface)


func get_object_by_id(object_id: String) -> Node:
	return null if registry == null else registry.get_object_by_id(object_id)


func get_registered_objects() -> Array:
	return [] if registry == null else registry.get_registered_objects()


func get_registered_entities() -> Array:
	return [] if registry == null else registry.get_registered_entities()
