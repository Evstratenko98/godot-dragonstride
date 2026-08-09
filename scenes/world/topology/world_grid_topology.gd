class_name WorldGridTopology
extends RefCounted

const MIN_ELEVATION: int = 0
const MAX_ELEVATION: int = 15
const MAX_SURFACES: int = 8192
const MAX_RAMPS: int = 1024
const INVALID_SURFACE: Vector3i = Vector3i(-1, -1, -1)
const ORTHOGONAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i.RIGHT,
	Vector2i.LEFT,
	Vector2i.DOWN,
	Vector2i.UP,
]

var surfaces: Dictionary[Vector3i, int] = {}
var display_names: Dictionary[Vector3i, String] = {}
var neighbors: Dictionary[Vector3i, Array] = {}
var ramps_by_edge: Dictionary[String, WorldRampConnection] = {}
var ramp_footprint_owners: Dictionary[Vector2i, String] = {}
var surfaces_by_cell: Dictionary[Vector2i, Array] = {}
var topology_hash: String = ""


func compile(level: WorldLevel, topology_root: Node) -> String:
	clear()
	if level == null or topology_root == null:
		return "missing_topology"
	var ramp_count: int = 0
	for child: Node in topology_root.get_children():
		if child is WorldSurfaceLayer:
			var error: String = _add_surface_layer(level, child as WorldSurfaceLayer)
			if not error.is_empty():
				clear()
				return error
		elif child is WorldRampConnection:
			ramp_count += 1
			if ramp_count > MAX_RAMPS:
				clear()
				return "too_many_ramps"
	_build_normal_neighbors()
	for child: Node in topology_root.get_children():
		if child is WorldRampConnection:
			var error: String = _add_ramp(child as WorldRampConnection)
			if not error.is_empty():
				clear()
				return error
	topology_hash = _calculate_hash()
	return ""


func clear() -> void:
	surfaces.clear()
	display_names.clear()
	neighbors.clear()
	ramps_by_edge.clear()
	ramp_footprint_owners.clear()
	surfaces_by_cell.clear()
	topology_hash = ""


func has_surface(surface: Vector3i) -> bool:
	return surfaces.has(surface)


func is_walkable_for_entity(surface: Vector3i, entity: Entity) -> bool:
	if not surfaces.has(surface):
		return false
	var mask: int = surfaces[surface]
	return mask == 0 or (entity != null and entity.entity_type == Entity.EntityType.CHARACTER)


func is_walkable_for_character(surface: Vector3i) -> bool:
	return surfaces.has(surface)


func get_neighbors(surface: Vector3i) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for value: Variant in neighbors.get(surface, []):
		if value is Vector3i:
			result.append(value as Vector3i)
	return result


func get_surface_in_direction(surface: Vector3i, direction: Vector2i) -> Vector3i:
	if direction == Vector2i.ZERO:
		return INVALID_SURFACE
	var same_height: Vector3i = Vector3i(surface.x + direction.x, surface.y + direction.y, surface.z)
	if has_edge(surface, same_height):
		return same_height
	for candidate: Vector3i in get_neighbors(surface):
		var ramp: WorldRampConnection = get_ramp(surface, candidate)
		if ramp != null and ramp.get_input_direction(surface) == direction:
			return candidate
	return INVALID_SURFACE


func get_surfaces_at(cell: Vector2i) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for value: Variant in surfaces_by_cell.get(cell, []):
		if value is Vector3i:
			result.append(value as Vector3i)
	result.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return a.z < b.z)
	return result


func get_all_surfaces() -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for surface: Vector3i in surfaces.keys():
		result.append(surface)
	result.sort_custom(func(first: Vector3i, second: Vector3i) -> bool:
		if first.x != second.x:
			return first.x < second.x
		if first.y != second.y:
			return first.y < second.y
		return first.z < second.z
	)
	return result


func has_edge(from_surface: Vector3i, to_surface: Vector3i) -> bool:
	return get_neighbors(from_surface).has(to_surface)


func is_ramp_edge(from_surface: Vector3i, to_surface: Vector3i) -> bool:
	return get_traversal_kind(from_surface, to_surface) == WorldRampConnection.TraversalKind.RAMP


func is_ramp_footprint_cell(cell: Vector2i) -> bool:
	return ramp_footprint_owners.has(cell)


func get_traversal_kind(from_surface: Vector3i, to_surface: Vector3i) -> int:
	var ramp: WorldRampConnection = get_ramp(from_surface, to_surface)
	if ramp != null:
		return ramp.traversal_kind
	return WorldRampConnection.TraversalKind.NORMAL


func get_ramp(from_surface: Vector3i, to_surface: Vector3i) -> WorldRampConnection:
	return ramps_by_edge.get(_edge_key(from_surface, to_surface), null) as WorldRampConnection


func get_input_direction_for_edge(from_surface: Vector3i, to_surface: Vector3i) -> Vector2i:
	var ramp: WorldRampConnection = get_ramp(from_surface, to_surface)
	if ramp != null:
		return ramp.get_input_direction(from_surface)
	if not has_edge(from_surface, to_surface) or from_surface.z != to_surface.z:
		return Vector2i.ZERO
	return Vector2i(to_surface.x - from_surface.x, to_surface.y - from_surface.y)


func get_display_name(surface: Vector3i) -> String:
	return display_names.get(surface, "ground")


func get_hash() -> String:
	return topology_hash


func _add_surface_layer(level: WorldLevel, layer: WorldSurfaceLayer) -> String:
	if layer.elevation < MIN_ELEVATION or layer.elevation > MAX_ELEVATION:
		return "invalid_elevation"
	for surface: Vector3i in layer.collect_surfaces(level):
		if surfaces.size() >= MAX_SURFACES and not surfaces.has(surface):
			return "too_many_surfaces"
		var cell: Vector2i = Vector2i(surface.x, surface.y)
		if cell.x < 0 or cell.y < 0 or cell.x >= level.get_grid_size().x or cell.y >= level.get_grid_size().y:
			return "surface_outside_grid"
		var walkability_mask: int = 1 if layer.character_only else 0
		if surfaces.has(surface):
			surfaces[surface] = mini(surfaces[surface], walkability_mask)
		else:
			surfaces[surface] = walkability_mask
			display_names[surface] = layer.display_name
			var column: Array = surfaces_by_cell.get(cell, []) as Array
			column.append(surface)
			surfaces_by_cell[cell] = column
		neighbors[surface] = []
	return ""


func _build_normal_neighbors() -> void:
	for surface: Vector3i in surfaces.keys():
		for direction: Vector2i in ORTHOGONAL_DIRECTIONS:
			var candidate: Vector3i = Vector3i(surface.x + direction.x, surface.y + direction.y, surface.z)
			if surfaces.has(candidate):
				_add_neighbor(surface, candidate)


func _add_ramp(ramp: WorldRampConnection) -> String:
	if ramp.connection_id.is_empty():
		return "missing_ramp_id"
	if not surfaces.has(ramp.low_surface) or not surfaces.has(ramp.high_surface):
		return "missing_ramp_endpoint"
	if ramp.low_surface.z >= ramp.high_surface.z:
		return "invalid_ramp_height"
	if ramp.low_input_direction == Vector2i.ZERO or ramp.high_input_direction == Vector2i.ZERO:
		return "missing_ramp_direction"
	var forward_key: String = _edge_key(ramp.low_surface, ramp.high_surface)
	var reverse_key: String = _edge_key(ramp.high_surface, ramp.low_surface)
	if ramps_by_edge.has(forward_key) or ramps_by_edge.has(reverse_key):
		return "duplicate_ramp_edge"
	if ramp.visual_footprint.is_empty() or ramp.visual_footprint.size() > 8:
		return "invalid_ramp_footprint"
	for blocked_cell: Vector2i in ramp.blocked_lower_cells:
		if not ramp.visual_footprint.has(blocked_cell):
			return "blocked_cell_outside_ramp_footprint"
		if surfaces.has(Vector3i(blocked_cell.x, blocked_cell.y, MIN_ELEVATION)):
			return "blocked_ramp_surface_present"
	for footprint_cell: Vector2i in ramp.visual_footprint:
		if ramp_footprint_owners.has(footprint_cell):
			return "conflicting_ramp_footprint"
		if (
			not ramp.blocked_lower_cells.has(footprint_cell)
			and not surfaces.has(Vector3i(footprint_cell.x, footprint_cell.y, MIN_ELEVATION))
		):
			return "missing_ramp_passable_surface"
		ramp_footprint_owners[footprint_cell] = ramp.connection_id
	ramps_by_edge[forward_key] = ramp
	ramps_by_edge[reverse_key] = ramp
	_add_neighbor(ramp.low_surface, ramp.high_surface)
	_add_neighbor(ramp.high_surface, ramp.low_surface)
	return ""


func _add_neighbor(from_surface: Vector3i, to_surface: Vector3i) -> void:
	var values: Array = neighbors.get(from_surface, []) as Array
	if not values.has(to_surface):
		values.append(to_surface)
	neighbors[from_surface] = values


func _edge_key(from_surface: Vector3i, to_surface: Vector3i) -> String:
	return "%d,%d,%d>%d,%d,%d" % [
		from_surface.x,
		from_surface.y,
		from_surface.z,
		to_surface.x,
		to_surface.y,
		to_surface.z,
	]


func _calculate_hash() -> String:
	var records: PackedStringArray = []
	for surface: Vector3i in surfaces.keys():
		records.append("s:%d,%d,%d:%d" % [surface.x, surface.y, surface.z, surfaces[surface]])
	for edge_key: String in ramps_by_edge.keys():
		var ramp: WorldRampConnection = ramps_by_edge[edge_key] as WorldRampConnection
		records.append("r:%s:%d:%d,%d:%d,%d" % [
			edge_key,
			int(ramp.traversal_kind),
			ramp.low_input_direction.x,
			ramp.low_input_direction.y,
			ramp.high_input_direction.x,
			ramp.high_input_direction.y,
		])
	records.sort()
	return ("|".join(records)).sha256_text()
