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
var occupied_cells: Dictionary[Vector2i, Node] = {}
var objects_by_id: Dictionary[String, Node] = {}
var entity_cells: Dictionary[Vector2i, Node] = {}
var reserved_entity_cells: Dictionary[Vector2i, Node] = {}
var entities_by_id: Dictionary[String, Node] = {}
var object_cells_by_instance_id: Dictionary[int, Array] = {}
var entity_cells_by_instance_id: Dictionary[int, Array] = {}
var reserved_cells_by_instance_id: Dictionary[int, Array] = {}


func configure_context(new_runtime: WorldRuntime, new_level: WorldLevel) -> void:
	runtime = new_runtime
	level = new_level


func collect_blockers() -> void:
	occupied_cells.clear()
	objects_by_id.clear()
	object_cells_by_instance_id.clear()
	for blocker_value: Variant in get_tree().get_nodes_in_group("game_blocker"):
		var blocker: Node2D = blocker_value as Node2D
		if blocker == null or not level.is_ancestor_of(blocker):
			continue
		var anchor_cell: Vector2i = runtime.world_to_cell(blocker.global_position)
		var result: int = register_object(blocker, anchor_cell)
		if result != RegistrationError.NONE:
			push_warning("Level blocker registration failed with code %d" % result)


func register_object(blocker: Node, anchor_cell: Vector2i) -> int:
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
	var cells: Array[Vector2i] = _get_node_occupied_cells(blocker, anchor_cell)
	var error: int = get_registration_error(blocker, anchor_cell)
	if error != RegistrationError.NONE:
		return error
	if _get_object_id(blocker).is_empty() and blocker.get("object_id") != null:
		blocker.set("object_id", object_id)
	objects_by_id[object_id] = blocker
	object_cells_by_instance_id[blocker.get_instance_id()] = cells.duplicate()
	for cell: Vector2i in cells:
		occupied_cells[cell] = blocker
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
		var cell: Vector2i = cell_value as Vector2i
		if occupied_cells.get(cell, null) == target_object:
			occupied_cells.erase(cell)
			was_changed = true
	object_cells_by_instance_id.erase(instance_id)
	if was_changed:
		occupancy_changed.emit()


func clear_entities() -> void:
	var was_changed: bool = not entities_by_id.is_empty() or not entity_cells.is_empty() or not reserved_entity_cells.is_empty()
	entities_by_id.clear()
	entity_cells.clear()
	reserved_entity_cells.clear()
	entity_cells_by_instance_id.clear()
	reserved_cells_by_instance_id.clear()
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
	if entity.get("current_cell") == null:
		return RegistrationError.OUTSIDE_GRID
	var anchor_cell: Vector2i = entity.get("current_cell") as Vector2i
	var error: int = get_registration_error(entity, anchor_cell)
	if error != RegistrationError.NONE:
		return error
	entities_by_id[entity_id] = entity
	_add_entity_cells(entity, anchor_cell)
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


func reserve_entity_cell(entity: Node, _from_cell: Vector2i, target_cell: Vector2i) -> bool:
	if not can_enter_cell(target_cell, entity):
		return false
	_remove_entity_reservations(entity)
	var cells: Array[Vector2i] = _get_node_occupied_cells(entity, target_cell)
	reserved_cells_by_instance_id[entity.get_instance_id()] = cells.duplicate()
	for cell: Vector2i in cells:
		reserved_entity_cells[cell] = entity
	occupancy_changed.emit()
	return true


func complete_entity_move(entity: Node, _from_cell: Vector2i, target_cell: Vector2i) -> int:
	if not can_enter_cell(target_cell, entity):
		return _get_cell_error(entity, target_cell)
	_remove_entity_cell_refs(entity)
	if entity.get("current_cell") != null:
		entity.set("current_cell", target_cell)
	_add_entity_cells(entity, target_cell)
	occupancy_changed.emit()
	return RegistrationError.NONE


func respawn_entity(entity: Node, cell: Vector2i) -> int:
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
	if entity.get("current_cell") != null:
		entity.set("current_cell", cell)
	entities_by_id[entity_id] = entity
	_add_entity_cells(entity, cell)
	occupancy_changed.emit()
	return RegistrationError.NONE


func sync_entity_cell(entity: Node, cell: Vector2i) -> int:
	return respawn_entity(entity, cell)


func apply_entity_cell_batch(cells_by_entity_id: Dictionary[String, Vector2i]) -> int:
	var staged_cells: Dictionary[Vector2i, Node] = {}
	var staged_entities: Dictionary[String, Node] = {}
	for entity_id: String in cells_by_entity_id.keys():
		var entity: Node = entities_by_id.get(entity_id, null) as Node
		if entity == null:
			return RegistrationError.INVALID_ID
		var anchor_cell: Vector2i = cells_by_entity_id[entity_id]
		for cell: Vector2i in _get_node_occupied_cells(entity, anchor_cell):
			if not runtime.is_cell_inside(cell):
				return RegistrationError.OUTSIDE_GRID
			var typed_entity: Entity = entity as Entity
			if not runtime.is_cell_walkable_for_entity(cell, typed_entity):
				return RegistrationError.NOT_WALKABLE
			if occupied_cells.has(cell):
				return RegistrationError.OBJECT_OCCUPIED
			var reserved_entity: Node = reserved_entity_cells.get(cell, null) as Node
			if reserved_entity != null and reserved_entity != entity:
				return RegistrationError.RESERVED
			if staged_cells.has(cell):
				return RegistrationError.ENTITY_OCCUPIED
			staged_cells[cell] = entity
		staged_entities[entity_id] = entity

	for entity: Node in staged_entities.values():
		_remove_entity_cell_refs(entity)
	for entity_id: String in cells_by_entity_id.keys():
		var entity: Node = staged_entities[entity_id]
		var anchor_cell: Vector2i = cells_by_entity_id[entity_id]
		if entity.get("current_cell") != null:
			entity.set("current_cell", anchor_cell)
		_add_entity_cells(entity, anchor_cell)
	occupancy_changed.emit()
	return RegistrationError.NONE


func get_registration_error(node: Node, anchor_cell: Vector2i) -> int:
	if node == null:
		return RegistrationError.INVALID_ID
	return _get_cell_error(node, anchor_cell)


func get_entity_by_id(entity_id: String) -> Node:
	return entities_by_id.get(entity_id, null) as Node


func get_entity_at_cell(cell: Vector2i) -> Node:
	return entity_cells.get(cell, null) as Node


func is_entity_registered_at_cell(entity: Node, anchor_cell: Vector2i) -> bool:
	if entity == null:
		return false
	for cell: Vector2i in _get_node_occupied_cells(entity, anchor_cell):
		if entity_cells.get(cell, null) != entity:
			return false
	return true


func has_entity_cell_reservation(entity: Node, anchor_cell: Vector2i) -> bool:
	if entity == null:
		return false
	for cell: Vector2i in _get_node_occupied_cells(entity, anchor_cell):
		if reserved_entity_cells.get(cell, null) != entity:
			return false
	return true


func get_object_at_cell(cell: Vector2i) -> Node:
	return occupied_cells.get(cell, null) as Node


func get_object_by_id(object_id: String) -> Node:
	return objects_by_id.get(object_id, null) as Node


func get_registered_objects() -> Array:
	return objects_by_id.values()


func get_registered_entities() -> Array:
	return entities_by_id.values()


func get_placement_error(spawn_node: Node, anchor_cell: Vector2i) -> String:
	var error: int = get_registration_error(spawn_node, anchor_cell)
	match error:
		RegistrationError.NONE:
			return ""
		RegistrationError.OUTSIDE_GRID:
			return "Spawn is outside the grid."
		RegistrationError.NOT_WALKABLE:
			return "Spawn is not walkable."
		RegistrationError.OBJECT_OCCUPIED:
			return "Spawn is occupied by an object."
		RegistrationError.ENTITY_OCCUPIED:
			return "Spawn is occupied by an entity."
		RegistrationError.RESERVED:
			return "Spawn is reserved."
		RegistrationError.DUPLICATE_ID:
			return "Spawn identifier is already registered."
		_:
			return "Spawn identifier is invalid."


func can_enter_cell(cell: Vector2i, moving_entity: Node = null) -> bool:
	return _get_cell_error(moving_entity, cell) == RegistrationError.NONE


func can_character_enter_cell(cell: Vector2i, ignored_entity: Entity = null) -> bool:
	return _get_cell_error(ignored_entity, cell, true) == RegistrationError.NONE


func is_cell_interactable(cell: Vector2i) -> bool:
	return runtime.is_cell_inside(cell) and (
		runtime.is_cell_walkable_for_character(cell)
		or occupied_cells.has(cell)
		or entity_cells.has(cell)
	)


func get_cell_display_name(cell: Vector2i) -> String:
	var target_entity: Node = get_entity_at_cell(cell)
	if target_entity != null:
		return runtime.get_entity_display_name(target_entity)
	var character_layer_name: String = _get_layer_name_at_cell(cell, level.get_character_walkable_layer_names())
	if not character_layer_name.is_empty():
		return character_layer_name
	var walkable_layer_name: String = _get_layer_name_at_cell(cell, level.get_walkable_layer_names())
	if not walkable_layer_name.is_empty():
		return walkable_layer_name
	return "ground"


func _get_cell_error(
	node: Node,
	anchor_cell: Vector2i,
	should_use_character_walkability: bool = false
) -> int:
	var typed_entity: Entity = node as Entity
	for cell: Vector2i in _get_node_occupied_cells(node, anchor_cell):
		if not runtime.is_cell_inside(cell):
			return RegistrationError.OUTSIDE_GRID
		var is_walkable: bool = false
		if should_use_character_walkability:
			is_walkable = runtime.is_cell_walkable_for_character(cell)
		elif typed_entity != null:
			is_walkable = runtime.is_cell_walkable_for_entity(cell, typed_entity)
		else:
			is_walkable = runtime.is_cell_walkable(cell)
		if not is_walkable:
			return RegistrationError.NOT_WALKABLE
		var target_object: Node = occupied_cells.get(cell, null) as Node
		if target_object != null and target_object != node:
			return RegistrationError.OBJECT_OCCUPIED
		var target_entity: Node = entity_cells.get(cell, null) as Node
		if target_entity != null and target_entity != node:
			return RegistrationError.ENTITY_OCCUPIED
		var reserved_entity: Node = reserved_entity_cells.get(cell, null) as Node
		if reserved_entity != null and reserved_entity != node:
			return RegistrationError.RESERVED
	return RegistrationError.NONE


func _get_layer_name_at_cell(cell: Vector2i, layer_names: PackedStringArray) -> String:
	for layer_name: String in layer_names:
		var layer: Node = level.get_node_or_null(NodePath(layer_name))
		if layer is TileMapLayer and layer.get_cell_source_id(cell) != -1:
			return str(layer.name)
	return ""


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
	var cells: Array = entity_cells_by_instance_id.get(instance_id, []) as Array
	for cell_value: Variant in cells:
		var cell: Vector2i = cell_value as Vector2i
		if entity_cells.get(cell, null) == entity:
			entity_cells.erase(cell)
	entity_cells_by_instance_id.erase(instance_id)


func _remove_entity_reservations(entity: Node) -> void:
	var instance_id: int = entity.get_instance_id()
	var cells: Array = reserved_cells_by_instance_id.get(instance_id, []) as Array
	for cell_value: Variant in cells:
		var cell: Vector2i = cell_value as Vector2i
		if reserved_entity_cells.get(cell, null) == entity:
			reserved_entity_cells.erase(cell)
	reserved_cells_by_instance_id.erase(instance_id)


func _add_entity_cells(entity: Node, anchor_cell: Vector2i) -> void:
	var cells: Array[Vector2i] = _get_node_occupied_cells(entity, anchor_cell)
	entity_cells_by_instance_id[entity.get_instance_id()] = cells.duplicate()
	for cell: Vector2i in cells:
		entity_cells[cell] = entity


func _get_node_occupied_cells(node: Node, anchor_cell: Vector2i) -> Array[Vector2i]:
	if node is Entity:
		return (node as Entity).get_occupied_cells(anchor_cell)
	if node is GridObject:
		return (node as GridObject).get_occupied_cells(anchor_cell)
	return [anchor_cell]
