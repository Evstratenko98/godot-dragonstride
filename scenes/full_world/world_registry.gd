class_name WorldRegistry
extends Node

var runtime: WorldRuntime = null
var level: WorldLevel = null
var occupied_cells: Dictionary = {}
var objects_by_id: Dictionary = {}
var entity_cells: Dictionary = {}
var reserved_entity_cells: Dictionary = {}
var entities_by_id: Dictionary = {}


func _ready() -> void:
	level = get_parent() as WorldLevel
	if level != null:
		runtime = level.get_runtime()


func configure_context(new_runtime: WorldRuntime, new_level: WorldLevel) -> void:
	runtime = new_runtime
	level = new_level


func collect_blockers() -> void:
	occupied_cells.clear()
	objects_by_id.clear()

	for blocker in get_tree().get_nodes_in_group("game_blocker"):
		if blocker is Node2D and level.is_ancestor_of(blocker):
			var anchor_cell: Vector2i = runtime.world_to_cell(blocker.global_position)
			register_object(blocker, anchor_cell)


func register_object(blocker: Node, anchor_cell: Vector2i) -> void:
	_register_object(blocker)
	for occupied_cell in _get_node_occupied_cells(blocker, anchor_cell):
		occupied_cells[occupied_cell] = blocker


func clear_entities() -> void:
	entities_by_id.clear()
	entity_cells.clear()
	reserved_entity_cells.clear()


func register_entity(entity: Node) -> void:
	var id: String = runtime.get_entity_id(entity)
	if id.is_empty():
		return

	entities_by_id[id] = entity
	if entity.get("current_cell") != null:
		_add_entity_cells(entity, entity.get("current_cell"))


func unregister_entity(entity: Node) -> void:
	var id: String = runtime.get_entity_id(entity)
	if not id.is_empty():
		entities_by_id.erase(id)

	_remove_entity_cell_refs(entity)


func reserve_entity_cell(entity: Node, _from_cell: Vector2i, target_cell: Vector2i) -> bool:
	if not can_enter_cell(target_cell, entity):
		return false

	_remove_entity_reservations(entity)
	for cell in _get_node_occupied_cells(entity, target_cell):
		reserved_entity_cells[cell] = entity

	return true


func complete_entity_move(entity: Node, _from_cell: Vector2i, target_cell: Vector2i) -> void:
	_remove_entity_cell_refs(entity)
	if entity is Entity:
		(entity as Entity).current_cell = target_cell
	_add_entity_cells(entity, target_cell)


func respawn_entity(entity: Node, cell: Vector2i) -> void:
	_remove_entity_cell_refs(entity)
	if entity.get("current_cell") != null:
		entity.set("current_cell", cell)
	_add_entity_cells(entity, cell)


func sync_entity_cell(entity: Node, cell: Vector2i) -> void:
	_remove_entity_cell_refs(entity)
	if entity.get("current_cell") != null:
		entity.set("current_cell", cell)
	_add_entity_cells(entity, cell)


func get_entity_by_id(entity_id: String) -> Node:
	return entities_by_id.get(entity_id, null) as Node


func get_entity_at_cell(cell: Vector2i) -> Node:
	return entity_cells.get(cell, null) as Node


func is_entity_registered_at_cell(entity: Node, anchor_cell: Vector2i) -> bool:
	if entity == null:
		return false

	for cell in _get_node_occupied_cells(entity, anchor_cell):
		if entity_cells.get(cell, null) != entity:
			return false

	return true


func has_entity_cell_reservation(entity: Node, anchor_cell: Vector2i) -> bool:
	if entity == null:
		return false

	for cell in _get_node_occupied_cells(entity, anchor_cell):
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
	for occupied_cell in _get_node_occupied_cells(spawn_node, anchor_cell):
		if not runtime.is_cell_inside(occupied_cell):
			return "Cell %s is outside the grid." % str(occupied_cell)

		if not runtime.is_cell_walkable(occupied_cell):
			return "Cell %s is not walkable." % str(occupied_cell)

		var target_object: Node = occupied_cells.get(occupied_cell, null) as Node
		if target_object != null:
			return "Cell %s is occupied by %s." % [str(occupied_cell), target_object.name]

		var target_entity: Node = entity_cells.get(occupied_cell, null) as Node
		if target_entity != null:
			return "Cell %s is occupied by %s." % [str(occupied_cell), runtime.get_entity_display_name(target_entity)]

		var reserved_entity: Node = reserved_entity_cells.get(occupied_cell, null) as Node
		if reserved_entity != null:
			return "Cell %s is reserved by %s." % [str(occupied_cell), runtime.get_entity_display_name(reserved_entity)]

	return ""


func can_enter_cell(cell: Vector2i, moving_entity: Node = null) -> bool:
	var typed_entity: Entity = moving_entity as Entity
	for occupied_cell in _get_node_occupied_cells(moving_entity, cell):
		if (
			not runtime.is_cell_inside(occupied_cell)
			or not runtime.is_cell_walkable_for_entity(occupied_cell, typed_entity)
			or occupied_cells.has(occupied_cell)
		):
			return false

		var entity_at_cell: Node = entity_cells.get(occupied_cell, null) as Node
		if entity_at_cell != null and entity_at_cell != moving_entity:
			return false

		var reserved_entity: Node = reserved_entity_cells.get(occupied_cell, null) as Node
		if reserved_entity != null and reserved_entity != moving_entity:
			return false

	return true


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

	var character_layer_name: String = _get_layer_name_at_cell(cell, level.character_walkable_layer_names)
	if not character_layer_name.is_empty():
		return character_layer_name

	var walkable_layer_name: String = _get_layer_name_at_cell(cell, level.walkable_layer_names)
	if not walkable_layer_name.is_empty():
		return walkable_layer_name

	return "ground"


func _get_layer_name_at_cell(cell: Vector2i, layer_names: PackedStringArray) -> String:
	for layer_name in layer_names:
		var layer: Node = level.get_node_or_null(NodePath(layer_name))
		if layer is TileMapLayer and layer.get_cell_source_id(cell) != -1:
			return str(layer.name)

	return ""


func _register_object(blocker: Node) -> void:
	var object_id: String = ""
	if blocker.get("object_id") != null:
		object_id = str(blocker.get("object_id"))

	if object_id.is_empty():
		object_id = blocker.name
		if blocker.get("object_id") != null:
			blocker.set("object_id", object_id)

	objects_by_id[object_id] = blocker


func _remove_entity_cell_refs(entity: Node) -> void:
	_remove_entity_reservations(entity)

	for cell in entity_cells.keys():
		if entity_cells[cell] == entity:
			entity_cells.erase(cell)


func _remove_entity_reservations(entity: Node) -> void:
	for cell in reserved_entity_cells.keys():
		if reserved_entity_cells[cell] == entity:
			reserved_entity_cells.erase(cell)


func _add_entity_cells(entity: Node, anchor_cell: Vector2i) -> void:
	for cell in _get_node_occupied_cells(entity, anchor_cell):
		entity_cells[cell] = entity


func _get_node_occupied_cells(node: Node, anchor_cell: Vector2i) -> Array[Vector2i]:
	if node is Entity:
		return (node as Entity).get_occupied_cells(anchor_cell)

	if node is GridObject:
		return (node as GridObject).get_occupied_cells(anchor_cell)

	var cells: Array[Vector2i] = [anchor_cell]
	return cells
