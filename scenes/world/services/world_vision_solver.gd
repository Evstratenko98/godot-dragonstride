class_name WorldVisionSolver
extends RefCounted

const MAX_VISION_RADIUS: int = 32

var grid: WorldGrid = null
var offsets_by_radius: Dictionary[int, Array] = {}
var relative_rays: Dictionary[String, Array] = {}


func configure(new_grid: WorldGrid) -> void:
	grid = new_grid
	offsets_by_radius.clear()
	relative_rays.clear()


func calculate_visible_surfaces(
	origin: Vector3i,
	radius: int,
	blocker_cells: Dictionary[Vector2i, bool],
	ignore_object_blockers: bool = false
) -> Dictionary[Vector3i, bool]:
	var result: Dictionary[Vector3i, bool] = {}
	if grid == null or not grid.has_surface(origin):
		return result
	var bounded_radius: int = clampi(radius, 0, MAX_VISION_RADIUS)
	for offset_value: Variant in _get_offsets(bounded_radius):
		var offset: Vector2i = offset_value as Vector2i
		var cell: Vector2i = Vector2i(origin.x + offset.x, origin.y + offset.y)
		var targets: Array[Vector3i] = grid.get_surfaces_at(cell)
		var base_surface: Vector3i = Vector3i(cell.x, cell.y, WorldGridTopology.MIN_ELEVATION)
		if targets.is_empty() and grid.is_surface_inside(base_surface):
			targets.append(base_surface)
		for target: Vector3i in targets:
			if target.z > origin.z:
				continue
			if _has_line_of_sight(origin, target, blocker_cells, ignore_object_blockers):
				result[target] = true
	return result


func _get_offsets(radius: int) -> Array:
	if offsets_by_radius.has(radius):
		return offsets_by_radius[radius]
	var offsets: Array[Vector2i] = []
	var radius_squared: int = radius * radius
	for y: int in range(-radius, radius + 1):
		for x: int in range(-radius, radius + 1):
			if x * x + y * y <= radius_squared:
				offsets.append(Vector2i(x, y))
	offsets_by_radius[radius] = offsets
	return offsets


func _has_line_of_sight(
	origin: Vector3i,
	target: Vector3i,
	blocker_cells: Dictionary[Vector2i, bool],
	ignore_object_blockers: bool
) -> bool:
	var relative_target: Vector2i = Vector2i(target.x - origin.x, target.y - origin.y)
	for relative_value: Variant in _get_relative_ray(relative_target):
		var relative_cell: Vector2i = relative_value as Vector2i
		var cell: Vector2i = Vector2i(origin.x + relative_cell.x, origin.y + relative_cell.y)
		if not ignore_object_blockers and blocker_cells.has(cell):
			return false
		for intermediate_surface: Vector3i in grid.get_surfaces_at(cell):
			if intermediate_surface.z > origin.z:
				return false
	return true


func _get_relative_ray(target: Vector2i) -> Array:
	var cache_key: String = "%d,%d" % [target.x, target.y]
	if relative_rays.has(cache_key):
		return relative_rays[cache_key]
	var cells: Array[Vector2i] = []
	var nx: int = absi(target.x)
	var ny: int = absi(target.y)
	var sign_x: int = signi(target.x)
	var sign_y: int = signi(target.y)
	var x: int = 0
	var y: int = 0
	var ix: int = 0
	var iy: int = 0
	while ix < nx or iy < ny:
		var horizontal_progress: int = (1 + 2 * ix) * ny
		var vertical_progress: int = (1 + 2 * iy) * nx
		if horizontal_progress == vertical_progress:
			var horizontal_cell: Vector2i = Vector2i(x + sign_x, y)
			var vertical_cell: Vector2i = Vector2i(x, y + sign_y)
			if horizontal_cell != target:
				cells.append(horizontal_cell)
			if vertical_cell != target:
				cells.append(vertical_cell)
			x = horizontal_cell.x
			y = vertical_cell.y
			ix += 1
			iy += 1
		elif horizontal_progress < vertical_progress:
			x += sign_x
			ix += 1
		else:
			y += sign_y
			iy += 1
		if (ix < nx or iy < ny) and (cells.is_empty() or cells[cells.size() - 1] != Vector2i(x, y)):
			cells.append(Vector2i(x, y))
	relative_rays[cache_key] = cells
	return cells
