class_name VisionRevealRegion
extends Resource

@export var bounds: Rect2i = Rect2i()
@export_range(WorldGridTopology.MIN_ELEVATION, WorldGridTopology.MAX_ELEVATION, 1) var minimum_elevation: int = WorldGridTopology.MIN_ELEVATION
@export_range(WorldGridTopology.MIN_ELEVATION, WorldGridTopology.MAX_ELEVATION, 1) var maximum_elevation: int = WorldGridTopology.MIN_ELEVATION


func configure(new_bounds: Rect2i, new_minimum_elevation: int, new_maximum_elevation: int) -> void:
	bounds = new_bounds
	minimum_elevation = new_minimum_elevation
	maximum_elevation = new_maximum_elevation


func is_valid_for_grid(grid_size: Vector2i) -> bool:
	return (
		bounds.size.x > 0
		and bounds.size.y > 0
		and bounds.position.x >= 0
		and bounds.position.y >= 0
		and bounds.end.x <= grid_size.x
		and bounds.end.y <= grid_size.y
		and minimum_elevation >= WorldGridTopology.MIN_ELEVATION
		and maximum_elevation <= WorldGridTopology.MAX_ELEVATION
		and minimum_elevation <= maximum_elevation
	)


func contains_surface(surface: Vector3i) -> bool:
	return (
		bounds.has_point(Vector2i(surface.x, surface.y))
		and surface.z >= minimum_elevation
		and surface.z <= maximum_elevation
	)
