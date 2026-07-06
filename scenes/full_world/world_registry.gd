extends Node

var world = null
var occupied_cells: Dictionary = {}
var objects_by_id: Dictionary = {}
var entity_cells: Dictionary = {}
var reserved_entity_cells: Dictionary = {}
var entities_by_id: Dictionary = {}


func _ready() -> void:
	world = get_parent()


func collect_blockers() -> void:
	occupied_cells.clear()
	objects_by_id.clear()

	for blocker in get_tree().get_nodes_in_group("game_blocker"):
		if blocker is Node2D and world.is_ancestor_of(blocker):
			_register_object(blocker)
			var anchor_cell: Vector2i = world.world_to_cell(blocker.global_position)
			if blocker.has_method("get_occupied_cells"):
				for occupied_cell in blocker.get_occupied_cells(anchor_cell):
					occupied_cells[occupied_cell] = blocker
			else:
				occupied_cells[anchor_cell] = blocker


func clear_entities() -> void:
	entities_by_id.clear()
	entity_cells.clear()
	reserved_entity_cells.clear()


func register_entity(entity: Node) -> void:
	var id: String = world.get_entity_id(entity)
	if id.is_empty():
		return

	entities_by_id[id] = entity
	if entity.get("current_cell") != null:
		entity_cells[entity.get("current_cell")] = entity


func unregister_entity(entity: Node) -> void:
	var id: String = world.get_entity_id(entity)
	if not id.is_empty():
		entities_by_id.erase(id)

	_remove_entity_cell_refs(entity)


func reserve_entity_cell(entity: Node, _from_cell: Vector2i, target_cell: Vector2i) -> bool:
	if not can_enter_cell(target_cell, entity):
		return false

	_remove_entity_reservations(entity)
	reserved_entity_cells[target_cell] = entity

	return true


func complete_entity_move(entity: Node, from_cell: Vector2i, target_cell: Vector2i) -> void:
	if entity_cells.get(from_cell, null) == entity:
		entity_cells.erase(from_cell)

	if reserved_entity_cells.get(target_cell, null) == entity:
		reserved_entity_cells.erase(target_cell)

	entity_cells[target_cell] = entity


func respawn_entity(entity: Node, cell: Vector2i) -> void:
	_remove_entity_cell_refs(entity)
	if entity.get("current_cell") != null:
		entity.set("current_cell", cell)
	entity_cells[cell] = entity


func sync_entity_cell(entity: Node, cell: Vector2i) -> void:
	_remove_entity_cell_refs(entity)
	if entity.get("current_cell") != null:
		entity.set("current_cell", cell)
	entity_cells[cell] = entity


func get_entity_by_id(entity_id: String) -> Node:
	return entities_by_id.get(entity_id, null) as Node


func get_entity_at_cell(cell: Vector2i) -> Node:
	return entity_cells.get(cell, null) as Node


func get_object_at_cell(cell: Vector2i) -> Node:
	return occupied_cells.get(cell, null) as Node


func get_object_by_id(object_id: String) -> Node:
	return objects_by_id.get(object_id, null) as Node


func get_registered_objects() -> Array:
	return objects_by_id.values()


func can_enter_cell(cell: Vector2i, moving_entity: Node = null) -> bool:
	if not world.is_cell_inside(cell) or not world.is_cell_walkable(cell) or occupied_cells.has(cell):
		return false

	var entity_at_cell: Node = entity_cells.get(cell, null) as Node
	if entity_at_cell != null and entity_at_cell != moving_entity:
		return false

	var reserved_entity: Node = reserved_entity_cells.get(cell, null) as Node
	if reserved_entity != null and reserved_entity != moving_entity:
		return false

	return true


func is_cell_interactable(cell: Vector2i) -> bool:
	return world.is_cell_inside(cell) and (world.is_cell_walkable(cell) or occupied_cells.has(cell) or entity_cells.has(cell))


func get_cell_display_name(cell: Vector2i) -> String:
	var target_entity: Node = get_entity_at_cell(cell)
	if target_entity != null:
		return world.get_entity_display_name(target_entity)

	for layer_name in world.walkable_layer_names:
		var layer: Node = world.get_node_or_null(NodePath(layer_name))
		if layer is TileMapLayer and layer.get_cell_source_id(cell) != -1:
			return layer.name

	return "ground"


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
