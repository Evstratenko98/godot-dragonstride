extends Node

const CELL_SIZE := 64

@export var grid_size: Vector2i = Vector2i(18, 18)
@export var walkable_layer_names: PackedStringArray = ["Ground"]

var world: Node2D = null


func _ready() -> void:
	world = get_parent() as Node2D


func configure(new_grid_size: Vector2i, new_walkable_layer_names: PackedStringArray) -> void:
	grid_size = new_grid_size
	walkable_layer_names = new_walkable_layer_names


func is_cell_walkable(cell: Vector2i) -> bool:
	for layer_name in walkable_layer_names:
		var layer: Node = world.get_node_or_null(NodePath(layer_name))
		if layer is TileMapLayer and layer.get_cell_source_id(cell) != -1:
			return true

	return false


func is_cell_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y


func get_grid_size() -> Vector2i:
	return grid_size


func get_cell_size() -> int:
	return CELL_SIZE


func world_to_cell(world_position: Vector2) -> Vector2i:
	var local_position: Vector2 = world.to_local(world_position)
	return Vector2i(floori(local_position.x / CELL_SIZE), floori(local_position.y / CELL_SIZE))


func cell_to_world(cell: Vector2i) -> Vector2:
	var local_position: Vector2 = Vector2(cell) * CELL_SIZE + Vector2(CELL_SIZE, CELL_SIZE) * 0.5
	return world.to_global(local_position)


func get_cell_center(world_position: Vector2) -> Vector2:
	return cell_to_world(world_to_cell(world_position))


func get_adjacent_cell_center(world_position: Vector2, direction: Vector2i) -> Vector2:
	return cell_to_world(world_to_cell(world_position) + direction)
