class_name WorldRegistry
extends Node

signal occupancy_changed

enum RegistrationError {
	NONE,
	INVALID_ID,
	DUPLICATE_ID,
	OUTSIDE_GRID,
	NOT_WALKABLE,
	OBJECT_OCCUPIED,
	ENTITY_OCCUPIED,
	RESERVED,
}

var runtime: WorldRuntime = null
var level: WorldLevel = null
var occupied_surfaces: Dictionary[Vector3i, Node] = {}
var objects_by_id: Dictionary[String, Node] = {}
var entity_surfaces: Dictionary[Vector3i, Node] = {}
var reserved_entity_surfaces: Dictionary[Vector3i, Node] = {}
var entities_by_id: Dictionary[String, Node] = {}
var object_cells_by_instance_id: Dictionary[int, Array] = {}
var entity_surfaces_by_instance_id: Dictionary[int, Array] = {}
var reserved_cells_by_instance_id: Dictionary[int, Array] = {}
var reserved_ramp_edges: Dictionary[String, Node] = {}
var reserved_ramp_edge_by_instance_id: Dictionary[int, String] = {}


func configure_context(new_runtime: WorldRuntime, new_level: WorldLevel) -> void:
	runtime = new_runtime
	level = new_level


func collect_blockers() -> void:
	occupied_surfaces.clear()
	objects_by_id.clear()
	object_cells_by_instance_id.clear()
	for blocker_value: Variant in get_tree().get_nodes_in_group("game_blocker"):
		var blocker: Node2D = blocker_value as Node2D
		if blocker == null or not level.is_ancestor_of(blocker):
			continue
		var blocker_object: GridObject = blocker as GridObject
		var elevation: int = 0 if blocker_object == null else blocker_object.surface_height
		var anchor_surface: Vector3i = runtime.world_to_surface(blocker.global_position, elevation)
		var result: int = register_object(blocker, anchor_surface, false)
		if result != RegistrationError.NONE:
			push_warning("Level blocker registration failed with code %d" % result)


func register_object(
	blocker: Node,
	anchor_surface: Vector3i,
	should_require_walkable_surface: bool = true
) -> int:
	if blocker == null:
		return RegistrationError.INVALID_ID
	var object_id: String = _get_candidate_object_id(blocker)
	if object_id.is_empty():
		return RegistrationError.INVALID_ID
	if entities_by_id.has(object_id):
		return RegistrationError.DUPLICATE_ID
	var existing_object: Node = objects_by_id.get(object_id, null) as Node
	if existing_object != null:
		return RegistrationError.DUPLICATE_ID
	var cells: Array[Vector3i] = _get_node_occupied_surfaces(blocker, anchor_surface)
	var error: int = _get_cell_error(blocker, anchor_surface, false, should_require_walkable_surface)
	if error != RegistrationError.NONE:
		return error
	if _get_object_id(blocker).is_empty() and blocker.get("object_id") != null:
		blocker.set("object_id", object_id)
	objects_by_id[object_id] = blocker
	object_cells_by_instance_id[blocker.get_instance_id()] = cells.duplicate()
	for cell: Vector3i in cells:
		occupied_surfaces[cell] = blocker
	occupancy_changed.emit()
	return RegistrationError.NONE


func unregister_object(target_object: Node) -> void:
	if target_object == null:
		return
	var was_changed: bool = false
	var object_id: String = _get_object_id(target_object)
	if not object_id.is_empty() and objects_by_id.get(object_id, null) == target_object:
		objects_by_id.erase(object_id)
		was_changed = true
	var instance_id: int = target_object.get_instance_id()
	var cells: Array = object_cells_by_instance_id.get(instance_id, []) as Array
	for cell_value: Variant in cells:
		var cell: Vector3i = cell_value as Vector3i
		if occupied_surfaces.get(cell, null) == target_object:
			occupied_surfaces.erase(cell)
			was_changed = true
	object_cells_by_instance_id.erase(instance_id)
	if was_changed:
		occupancy_changed.emit()


func clear_entities() -> void:
	var was_changed: bool = not entities_by_id.is_empty() or not entity_surfaces.is_empty() or not reserved_entity_surfaces.is_empty()
	entities_by_id.clear()
	entity_surfaces.clear()
	reserved_entity_surfaces.clear()
	entity_surfaces_by_instance_id.clear()
	reserved_cells_by_instance_id.clear()
	reserved_ramp_edges.clear()
	reserved_ramp_edge_by_instance_id.clear()
	if was_changed:
		occupancy_changed.emit()


func register_entity(entity: Node) -> int:
	if entity == null:
		return RegistrationError.INVALID_ID
	var entity_id: String = runtime.get_entity_id(entity)
	if entity_id.is_empty():
		return RegistrationError.INVALID_ID
	if objects_by_id.has(entity_id):
		return RegistrationError.DUPLICATE_ID
	var existing_entity: Node = entities_by_id.get(entity_id, null) as Node
	if existing_entity != null:
		return RegistrationError.DUPLICATE_ID
	if entity.get("current_surface") == null:
		return RegistrationError.OUTSIDE_GRID
	var anchor_surface: Vector3i = entity.get("current_surface") as Vector3i
	var error: int = get_registration_error(entity, anchor_surface)
	if error != RegistrationError.NONE:
		return error
	entities_by_id[entity_id] = entity
	_add_entity_surfaces(entity, anchor_surface)
	occupancy_changed.emit()
	return RegistrationError.NONE


func unregister_entity(entity: Node) -> void:
	if entity == null:
		return
	var was_registered: bool = false
	var entity_id: String = runtime.get_entity_id(entity)
	if not entity_id.is_empty() and entities_by_id.get(entity_id, null) == entity:
		entities_by_id.erase(entity_id)
		was_registered = true
	_remove_entity_cell_refs(entity)
	if was_registered:
		occupancy_changed.emit()


func reserve_entity_surface(entity: Node, from_surface: Vector3i, target_surface: Vector3i) -> bool:
	if not can_enter_surface(target_surface, entity):
		return false
	_remove_entity_reservations(entity)
	if runtime.is_ramp_edge(from_surface, target_surface):
		var edge_key: String = _get_transition_edge_key(from_surface, target_surface)
		var edge_owner: Node = reserved_ramp_edges.get(edge_key, null) as Node
		if edge_owner != null and edge_owner != entity:
			return false
		reserved_ramp_edges[edge_key] = entity
		reserved_ramp_edge_by_instance_id[entity.get_instance_id()] = edge_key
	var cells: Array[Vector3i] = _get_node_occupied_surfaces(entity, target_surface)
	reserved_cells_by_instance_id[entity.get_instance_id()] = cells.duplicate()
	for cell: Vector3i in cells:
		reserved_entity_surfaces[cell] = entity
	occupancy_changed.emit()
	return true


func complete_entity_move(entity: Node, _from_surface: Vector3i, target_surface: Vector3i) -> int:
	if not can_enter_surface(target_surface, entity):
		return _get_cell_error(entity, target_surface)
	_remove_entity_cell_refs(entity)
	if entity.get("current_surface") != null:
		entity.set("current_surface", target_surface)
	_add_entity_surfaces(entity, target_surface)
	occupancy_changed.emit()
	return RegistrationError.NONE


func respawn_entity(entity: Node, cell: Vector3i) -> int:
	var entity_id: String = runtime.get_entity_id(entity)
	if entity_id.is_empty():
		return RegistrationError.INVALID_ID
	var existing_entity: Node = entities_by_id.get(entity_id, null) as Node
	if existing_entity != null and existing_entity != entity:
		return RegistrationError.DUPLICATE_ID
	var error: int = get_registration_error(entity, cell)
	if error != RegistrationError.NONE:
		return error
	_remove_entity_cell_refs(entity)
	if entity.get("current_surface") != null:
		entity.set("current_surface", cell)
	entities_by_id[entity_id] = entity
	_add_entity_surfaces(entity, cell)
	occupancy_changed.emit()
	return RegistrationError.NONE


func sync_entity_surface(entity: Node, cell: Vector3i) -> int:
	return respawn_entity(entity, cell)


func apply_entity_surface_batch(surfaces_by_entity_id: Dictionary[String, Vector3i]) -> int:
	var staged_cells: Dictionary[Vector3i, Node] = {}
	var staged_entities: Dictionary[String, Node] = {}
	for entity_id: String in surfaces_by_entity_id.keys():
		var entity: Node = entities_by_id.get(entity_id, null) as Node
		if entity == null:
			return RegistrationError.INVALID_ID
		var anchor_surface: Vector3i = surfaces_by_entity_id[entity_id]
		for cell: Vector3i in _get_node_occupied_surfaces(entity, anchor_surface):
			if not runtime.is_surface_inside(cell):
				return RegistrationError.OUTSIDE_GRID
			var typed_entity: Entity = entity as Entity
			if not runtime.is_surface_walkable_for_entity(cell, typed_entity):
				return RegistrationError.NOT_WALKABLE
			if occupied_surfaces.has(cell):
				return RegistrationError.OBJECT_OCCUPIED
			var reserved_entity: Node = reserved_entity_surfaces.get(cell, null) as Node
			if reserved_entity != null and reserved_entity != entity:
				return RegistrationError.RESERVED
			if staged_cells.has(cell):
				return RegistrationError.ENTITY_OCCUPIED
			staged_cells[cell] = entity
		staged_entities[entity_id] = entity

	for entity: Node in staged_entities.values():
		_remove_entity_cell_refs(entity)
	for entity_id: String in surfaces_by_entity_id.keys():
		var entity: Node = staged_entities[entity_id]
		var anchor_surface: Vector3i = surfaces_by_entity_id[entity_id]
		if entity.get("current_surface") != null:
			entity.set("current_surface", anchor_surface)
		_add_entity_surfaces(entity, anchor_surface)
	occupancy_changed.emit()
	return RegistrationError.NONE


func get_registration_error(node: Node, anchor_surface: Vector3i) -> int:
	if node == null:
		return RegistrationError.INVALID_ID
	return _get_cell_error(node, anchor_surface)


func get_entity_by_id(entity_id: String) -> Node:
	return entities_by_id.get(entity_id, null) as Node


func get_entity_at_surface(cell: Vector3i) -> Node:
	return entity_surfaces.get(cell, null) as Node


func is_entity_registered_at_surface(entity: Node, anchor_surface: Vector3i) -> bool:
	if entity == null:
		return false
	for cell: Vector3i in _get_node_occupied_surfaces(entity, anchor_surface):
		if entity_surfaces.get(cell, null) != entity:
			return false
	return true


func has_entity_surface_reservation(entity: Node, anchor_surface: Vector3i) -> bool:
	if entity == null:
		return false
	for cell: Vector3i in _get_node_occupied_surfaces(entity, anchor_surface):
		if reserved_entity_surfaces.get(cell, null) != entity:
			return false
	return true


func get_object_at_surface(cell: Vector3i) -> Node:
	return occupied_surfaces.get(cell, null) as Node


func get_object_by_id(object_id: String) -> Node:
	return objects_by_id.get(object_id, null) as Node


func get_registered_objects() -> Array:
	return objects_by_id.values()


func get_registered_entities() -> Array:
	return entities_by_id.values()


func get_placement_error(spawn_node: Node, anchor_surface: Vector3i) -> String:
	var error: int = get_registration_error(spawn_node, anchor_surface)
	return WorldPlacementErrorText.from_registration_error(error)


func can_enter_surface(cell: Vector3i, moving_entity: Node = null) -> bool:
	return _get_cell_error(moving_entity, cell) == RegistrationError.NONE


func can_character_enter_surface(cell: Vector3i, ignored_entity: Entity = null) -> bool:
	return _get_cell_error(ignored_entity, cell, true) == RegistrationError.NONE


func is_surface_interactable(cell: Vector3i) -> bool:
	return runtime.is_surface_inside(cell) and (
		runtime.is_surface_walkable_for_character(cell)
		or occupied_surfaces.has(cell)
		or entity_surfaces.has(cell)
	)


func get_surface_display_name(cell: Vector3i) -> String:
	var target_entity: Node = get_entity_at_surface(cell)
	if target_entity != null:
		return runtime.get_entity_display_name(target_entity)
	return runtime.grid.get_surface_display_name(cell)


func _get_cell_error(
	node: Node,
	anchor_surface: Vector3i,
	should_use_character_walkability: bool = false,
	should_require_walkable_surface: bool = true
) -> int:
	var typed_entity: Entity = node as Entity
	for cell: Vector3i in _get_node_occupied_surfaces(node, anchor_surface):
		if not runtime.is_surface_inside(cell):
			return RegistrationError.OUTSIDE_GRID
		if should_require_walkable_surface:
			var is_walkable: bool = false
			if should_use_character_walkability:
				is_walkable = runtime.is_surface_walkable_for_character(cell)
			elif typed_entity != null:
				is_walkable = runtime.is_surface_walkable_for_entity(cell, typed_entity)
			else:
				is_walkable = runtime.is_surface_walkable(cell)
			if not is_walkable:
				return RegistrationError.NOT_WALKABLE
		var target_object: Node = occupied_surfaces.get(cell, null) as Node
		if target_object != null and target_object != node:
			return RegistrationError.OBJECT_OCCUPIED
		var target_entity: Node = entity_surfaces.get(cell, null) as Node
		if target_entity != null and target_entity != node:
			return RegistrationError.ENTITY_OCCUPIED
		var reserved_entity: Node = reserved_entity_surfaces.get(cell, null) as Node
		if reserved_entity != null and reserved_entity != node:
			return RegistrationError.RESERVED
	return RegistrationError.NONE


func _get_candidate_object_id(blocker: Node) -> String:
	var object_id: String = _get_object_id(blocker)
	if object_id.is_empty():
		object_id = blocker.name
	return object_id


func _get_object_id(blocker: Node) -> String:
	if blocker == null or blocker.get("object_id") == null:
		return ""
	return str(blocker.get("object_id"))


func _remove_entity_cell_refs(entity: Node) -> void:
	_remove_entity_reservations(entity)
	var instance_id: int = entity.get_instance_id()
	var cells: Array = entity_surfaces_by_instance_id.get(instance_id, []) as Array
	for cell_value: Variant in cells:
		var cell: Vector3i = cell_value as Vector3i
		if entity_surfaces.get(cell, null) == entity:
			entity_surfaces.erase(cell)
	entity_surfaces_by_instance_id.erase(instance_id)


func _remove_entity_reservations(entity: Node) -> void:
	var instance_id: int = entity.get_instance_id()
	var cells: Array = reserved_cells_by_instance_id.get(instance_id, []) as Array
	for cell_value: Variant in cells:
		var cell: Vector3i = cell_value as Vector3i
		if reserved_entity_surfaces.get(cell, null) == entity:
			reserved_entity_surfaces.erase(cell)
	reserved_cells_by_instance_id.erase(instance_id)
	var edge_key: String = reserved_ramp_edge_by_instance_id.get(instance_id, "")
	if not edge_key.is_empty() and reserved_ramp_edges.get(edge_key, null) == entity:
		reserved_ramp_edges.erase(edge_key)
	reserved_ramp_edge_by_instance_id.erase(instance_id)


func _get_transition_edge_key(first: Vector3i, second: Vector3i) -> String:
	var first_key: String = "%d,%d,%d" % [first.x, first.y, first.z]
	var second_key: String = "%d,%d,%d" % [second.x, second.y, second.z]
	if first_key > second_key:
		var swap: String = first_key
		first_key = second_key
		second_key = swap
	return "%s|%s" % [first_key, second_key]


func _add_entity_surfaces(entity: Node, anchor_surface: Vector3i) -> void:
	var cells: Array[Vector3i] = _get_node_occupied_surfaces(entity, anchor_surface)
	entity_surfaces_by_instance_id[entity.get_instance_id()] = cells.duplicate()
	for cell: Vector3i in cells:
		entity_surfaces[cell] = entity


func _get_node_occupied_surfaces(node: Node, anchor_surface: Vector3i) -> Array[Vector3i]:
	if node is Entity:
		return (node as Entity).get_occupied_surfaces(anchor_surface)
	if node is GridObject:
		return (node as GridObject).get_occupied_surfaces(anchor_surface)
	return [anchor_surface]
