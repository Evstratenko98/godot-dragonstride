class_name EntityFootprint
extends RefCounted


static func get_occupied_surfaces(
	anchor_surface: Vector3i,
	occupied_offsets: Array[Vector2i]
) -> Array[Vector3i]:
	var surfaces: Array[Vector3i] = []
	if occupied_offsets.is_empty():
		surfaces.append(anchor_surface)
		return surfaces
	for offset: Vector2i in occupied_offsets:
		var occupied_surface: Vector3i = Vector3i(
			anchor_surface.x + offset.x,
			anchor_surface.y + offset.y,
			anchor_surface.z
		)
		if not surfaces.has(occupied_surface):
			surfaces.append(occupied_surface)
	return surfaces


static func get_adjacent_direction(
	current_surface: Vector3i,
	target_surface: Vector3i,
	occupied_offsets: Array[Vector2i]
) -> Vector2i:
	if current_surface.z != target_surface.z:
		return Vector2i.ZERO
	for occupied_surface: Vector3i in get_occupied_surfaces(current_surface, occupied_offsets):
		var direction: Vector2i = Vector2i(
			target_surface.x - occupied_surface.x,
			target_surface.y - occupied_surface.y
		)
		if direction in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			return direction
	return Vector2i.ZERO
