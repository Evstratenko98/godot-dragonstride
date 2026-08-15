class_name WorldVisibilitySurfaceCatalog
extends RefCounted

var surface_order: Array[Vector3i] = []
var display_surfaces: Array[Vector3i] = []
var display_surface_by_cell: Dictionary[Vector2i, Vector3i] = {}
var surface_index_by_surface: Dictionary[Vector3i, int] = {}


func configure(runtime: WorldRuntime) -> void:
	clear()
	if runtime == null:
		return
	surface_order = runtime.get_all_surfaces()
	var known_surfaces: Dictionary[Vector3i, bool] = {}
	for surface: Vector3i in surface_order:
		known_surfaces[surface] = true
	var grid_size: Vector2i = runtime.get_grid_size()
	for y: int in range(grid_size.y):
		for x: int in range(grid_size.x):
			var base_surface: Vector3i = Vector3i(x, y, WorldGridTopology.MIN_ELEVATION)
			if not known_surfaces.has(base_surface):
				known_surfaces[base_surface] = true
				surface_order.append(base_surface)
	surface_order.sort_custom(func(first: Vector3i, second: Vector3i) -> bool:
		if first.y != second.y:
			return first.y < second.y
		if first.x != second.x:
			return first.x < second.x
		return first.z < second.z
	)
	if surface_order.size() > WorldGridTopology.MAX_SURFACES:
		push_error("Visibility surface limit exceeded: %d" % surface_order.size())
		clear()
		return
	for index: int in range(surface_order.size()):
		var surface: Vector3i = surface_order[index]
		surface_index_by_surface[surface] = index
		var cell: Vector2i = Vector2i(surface.x, surface.y)
		var current_display_surface: Vector3i = display_surface_by_cell.get(
			cell,
			WorldGridTopology.INVALID_SURFACE
		)
		if current_display_surface == WorldGridTopology.INVALID_SURFACE or surface.z > current_display_surface.z:
			display_surface_by_cell[cell] = surface
	for surface: Vector3i in display_surface_by_cell.values():
		display_surfaces.append(surface)
	display_surfaces.sort_custom(func(first: Vector3i, second: Vector3i) -> bool:
		return first.y < second.y if first.y != second.y else first.x < second.x
	)


func clear() -> void:
	surface_order.clear()
	display_surfaces.clear()
	display_surface_by_cell.clear()
	surface_index_by_surface.clear()
