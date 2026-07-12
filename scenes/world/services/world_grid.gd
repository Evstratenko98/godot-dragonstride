class_name WorldGrid
extends Node

const CELL_SIZE := 64

@export var grid_size: Vector2i = Vector2i(19, 19)
@export var walkable_layer_names: PackedStringArray = ["Ground"]
@export var character_walkable_layer_names: PackedStringArray = ["Hay", "Bridge"]

var level: WorldLevel = null


func configure_context(_runtime: WorldRuntime, new_level: WorldLevel) -> void:
	level = new_level


func configure(
	new_grid_size: Vector2i,
	new_walkable_layer_names: PackedStringArray,
	new_character_walkable_layer_names: PackedStringArray
) -> void:
	grid_size = new_grid_size
	walkable_layer_names = new_walkable_layer_names
	character_walkable_layer_names = new_character_walkable_layer_names


func is_cell_walkable(cell: Vector2i) -> bool:
	return _is_cell_in_layers(cell, walkable_layer_names)


func is_cell_walkable_for_entity(cell: Vector2i, entity: Entity) -> bool:
	if is_cell_walkable(cell):
		return true

	return (
		entity != null
		and entity.entity_type == Entity.EntityType.CHARACTER
		and is_cell_walkable_for_character(cell)
	)


func is_cell_walkable_for_character(cell: Vector2i) -> bool:
	return is_cell_walkable(cell) or _is_cell_in_layers(cell, character_walkable_layer_names)


func is_cell_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y


func get_grid_size() -> Vector2i:
	return grid_size


func get_cell_size() -> int:
	return CELL_SIZE


func world_to_cell(world_position: Vector2) -> Vector2i:
	var local_position: Vector2 = _get_level().to_local(world_position)
	return Vector2i(floori(local_position.x / CELL_SIZE), floori(local_position.y / CELL_SIZE))


func cell_to_world(cell: Vector2i) -> Vector2:
	var local_position: Vector2 = Vector2(cell) * CELL_SIZE + Vector2(CELL_SIZE, CELL_SIZE) * 0.5
	return _get_level().to_global(local_position)


func get_cell_center(world_position: Vector2) -> Vector2:
	return cell_to_world(world_to_cell(world_position))


func get_adjacent_cell_center(world_position: Vector2, direction: Vector2i) -> Vector2:
	return cell_to_world(world_to_cell(world_position) + direction)


func _is_cell_in_layers(cell: Vector2i, layer_names: PackedStringArray) -> bool:
	for layer_name in layer_names:
		var layer: Node = _get_level().get_node_or_null(NodePath(layer_name))
		if layer is TileMapLayer and layer.get_cell_source_id(cell) != -1:
			return true

	return false


func _get_level() -> WorldLevel:
	return level
