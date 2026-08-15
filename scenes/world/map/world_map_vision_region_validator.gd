class_name WorldMapVisionRegionValidator
extends RefCounted


static func get_validation_error(type_key: String, value: Variant, grid_size: Vector2i) -> String:
	if not (value is Array):
		return "map_invalid"
	var regions: Array = value as Array
	if type_key != "vision_tower":
		return "" if regions.is_empty() else "map_invalid"
	if regions.is_empty() or regions.size() > VisionTower.MAX_REVEAL_REGIONS:
		return "map_invalid"
	var surface_candidate_count: int = 0
	for region_value: Variant in regions:
		if not (region_value is Dictionary):
			return "map_invalid"
		var region: Dictionary = region_value as Dictionary
		if not _is_integer_array(region.get("rect"), 4):
			return "map_invalid"
		if not _is_integer(region.get("min_elevation")) or not _is_integer(region.get("max_elevation")):
			return "map_invalid"
		var rect_values: Array = region.get("rect") as Array
		var bounds: Rect2i = Rect2i(
			int(rect_values[0]),
			int(rect_values[1]),
			int(rect_values[2]),
			int(rect_values[3])
		)
		var minimum_elevation: int = int(region.get("min_elevation", -1))
		var maximum_elevation: int = int(region.get("max_elevation", -1))
		if (
			bounds.size.x <= 0
			or bounds.size.y <= 0
			or bounds.position.x < 0
			or bounds.position.y < 0
			or bounds.end.x > grid_size.x
			or bounds.end.y > grid_size.y
			or minimum_elevation < WorldGridTopology.MIN_ELEVATION
			or maximum_elevation > WorldGridTopology.MAX_ELEVATION
			or minimum_elevation > maximum_elevation
		):
			return "map_invalid"
		surface_candidate_count += bounds.get_area() * (maximum_elevation - minimum_elevation + 1)
		if surface_candidate_count > WorldGridTopology.MAX_SURFACES:
			return "map_too_large"
	return ""


static func _is_integer_array(value: Variant, expected_size: int) -> bool:
	if not (value is Array) or (value as Array).size() != expected_size:
		return false
	for component: Variant in value as Array:
		if not _is_integer(component):
			return false
	return true


static func _is_integer(value: Variant) -> bool:
	return value is int or (value is float and is_equal_approx(value, roundf(value)))
