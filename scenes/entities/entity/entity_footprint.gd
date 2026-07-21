class_name EntityFootprint
extends RefCounted


static func get_occupied_cells(anchor_cell: Vector2i, occupied_offsets: Array[Vector2i]) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if occupied_offsets.is_empty():
		cells.append(anchor_cell)
		return cells
	for offset: Vector2i in occupied_offsets:
		var occupied_cell: Vector2i = anchor_cell + offset
		if not cells.has(occupied_cell):
			cells.append(occupied_cell)
	return cells


static func get_adjacent_direction(
	current_cell: Vector2i,
	target_cell: Vector2i,
	occupied_offsets: Array[Vector2i]
) -> Vector2i:
	for occupied_cell: Vector2i in get_occupied_cells(current_cell, occupied_offsets):
		var direction: Vector2i = target_cell - occupied_cell
		if direction in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			return direction
	return Vector2i.ZERO
