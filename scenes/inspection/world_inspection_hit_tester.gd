class_name WorldInspectionHitTester
extends RefCounted


static func find_target(
	runtime: WorldRuntime,
	world_position: Vector2,
	fallback_surface: Vector3i
) -> Node:
	if runtime == null:
		return null

	var best_target: Node = null
	var best_z_index: int = -2147483648
	var best_y_position: float = -INF
	var best_tree_order: int = -1
	var candidates: Array[Node] = []
	for entity_value: Variant in runtime.get_registered_entities():
		var entity: Entity = entity_value as Entity
		if entity != null:
			candidates.append(entity)
	for object_value: Variant in runtime.get_registered_objects():
		var grid_object: GridObject = object_value as GridObject
		if grid_object != null:
			candidates.append(grid_object)

	for candidate: Node in candidates:
		var inspectable: WorldInspectable = WorldInspectable.from_target(candidate)
		if not _is_visible_candidate(candidate, inspectable, runtime):
			continue
		var sprite: Sprite2D = inspectable.preview_sprite
		var local_position: Vector2 = sprite.to_local(world_position)
		if not sprite.get_rect().has_point(local_position) or not sprite.is_pixel_opaque(local_position):
			continue
		var candidate_z_index: int = _get_effective_z_index(candidate, sprite)
		var candidate_y_position: float = sprite.global_position.y
		var candidate_tree_order: int = candidate.get_index()
		if _is_drawn_after(
			candidate_z_index,
			candidate_y_position,
			candidate_tree_order,
			best_z_index,
			best_y_position,
			best_tree_order
		):
			best_target = candidate
			best_z_index = candidate_z_index
			best_y_position = candidate_y_position
			best_tree_order = candidate_tree_order

	if best_target != null:
		return best_target
	return _get_surface_target(runtime, fallback_surface)


static func _is_visible_candidate(
	target: Node,
	inspectable: WorldInspectable,
	runtime: WorldRuntime
) -> bool:
	if inspectable == null or inspectable.preview_sprite == null:
		return false
	var target_canvas_item: CanvasItem = target as CanvasItem
	if (
		target_canvas_item == null
		or not target_canvas_item.is_visible_in_tree()
		or not inspectable.preview_sprite.is_visible_in_tree()
	):
		return false
	if runtime.visibility == null:
		return true
	var entity: Entity = target as Entity
	if entity != null:
		return runtime.visibility.is_surface_visible_for_local_player(entity.current_surface)
	var grid_object: GridObject = target as GridObject
	return (
		grid_object != null
		and runtime.visibility.get_object_visibility_mode(
			runtime.visibility.get_local_player_id(),
			grid_object
		) == WorldVisibility.VisibilityMode.VISIBLE
	)


static func _get_surface_target(runtime: WorldRuntime, surface: Vector3i) -> Node:
	if surface == WorldGridTopology.INVALID_SURFACE or not runtime.is_surface_inside(surface):
		return null
	var entity: Entity = runtime.get_entity_at_surface(surface) as Entity
	var entity_inspectable: WorldInspectable = WorldInspectable.from_target(entity)
	if _is_visible_candidate(entity, entity_inspectable, runtime):
		return entity
	var grid_object: GridObject = runtime.get_object_at_surface(surface) as GridObject
	var object_inspectable: WorldInspectable = WorldInspectable.from_target(grid_object)
	if _is_visible_candidate(grid_object, object_inspectable, runtime):
		return grid_object
	return null


static func _get_effective_z_index(target: Node, sprite: Sprite2D) -> int:
	var target_canvas_item: CanvasItem = target as CanvasItem
	var target_z_index: int = 0 if target_canvas_item == null else target_canvas_item.z_index
	return target_z_index + sprite.z_index if sprite.z_as_relative else sprite.z_index


static func _is_drawn_after(
	z_index: int,
	y_position: float,
	tree_order: int,
	current_z_index: int,
	current_y_position: float,
	current_tree_order: int
) -> bool:
	if z_index != current_z_index:
		return z_index > current_z_index
	if not is_equal_approx(y_position, current_y_position):
		return y_position > current_y_position
	return tree_order > current_tree_order
