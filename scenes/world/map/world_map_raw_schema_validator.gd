class_name WorldMapRawSchemaValidator
extends RefCounted


static func is_valid(value: Dictionary) -> bool:
	if (
		not _is_integer(value.get("schema_version"))
		or not (value.get("level_id") is String)
		or not (value.get("generator_id") is String)
		or not _is_integer(value.get("generator_version"))
		or not _is_integer(value.get("seed"))
		or not _is_integer_array(value.get("grid_size"), 2)
		or not _is_dictionary_array(value.get("layers"))
		or not _is_dictionary_array(value.get("surface_layers"))
		or not _is_dictionary_array(value.get("ramps"))
		or not _is_array(value.get("player_spawn_surfaces"))
		or not _is_dictionary_array(value.get("static_entities"))
		or not _is_dictionary_array(value.get("static_objects"))
	):
		return false
	for record: Dictionary in value.get("layers") as Array:
		if not _is_valid_layer(record):
			return false
	for record: Dictionary in value.get("surface_layers") as Array:
		if not _is_valid_surface_layer(record):
			return false
	for record: Dictionary in value.get("ramps") as Array:
		if not _is_valid_ramp(record):
			return false
	for spawn_value: Variant in value.get("player_spawn_surfaces") as Array:
		if not _is_integer_array(spawn_value, 3):
			return false
	for key: String in ["static_entities", "static_objects"]:
		for record: Dictionary in value.get(key) as Array:
			if not _is_valid_placement(record):
				return false
	return true


static func _is_valid_layer(record: Dictionary) -> bool:
	return (
		record.get("name") is String
		and record.get("tile_set_key") is String
		and record.get("parent") is String
		and record.get("placement") is String
		and record.get("visible") is bool
		and _is_integer(record.get("z_index"))
		and _is_array(record.get("cells"))
	)


static func _is_valid_surface_layer(record: Dictionary) -> bool:
	return (
		record.get("node_name") is String
		and record.get("source_layer") is String
		and _is_integer(record.get("elevation"))
		and _is_array(record.get("explicit_cells"))
		and _is_array(record.get("excluded_cells"))
		and record.get("character_only") is bool
		and record.get("display_name") is String
	)


static func _is_valid_ramp(record: Dictionary) -> bool:
	return (
		record.get("node_name") is String
		and record.get("connection_id") is String
		and _is_integer_array(record.get("low_surface"), 3)
		and _is_integer_array(record.get("high_surface"), 3)
		and _is_integer_array(record.get("low_input_direction"), 2)
		and _is_integer_array(record.get("high_input_direction"), 2)
		and _is_array(record.get("visual_footprint"))
		and _is_array(record.get("blocked_lower_cells"))
		and _is_integer(record.get("traversal_kind"))
	)


static func _is_valid_placement(record: Dictionary) -> bool:
	if not (
		record.get("type_key") is String
		and record.get("id") is String
		and record.get("node_name") is String
		and _is_number_array(record.get("position"), 2)
		and _is_number_array(record.get("scale"), 2)
		and _is_integer(record.get("surface_height"))
		and _is_dictionary_array(record.get("vision_regions"))
	):
		return false
	for region: Dictionary in record.get("vision_regions") as Array:
		if not _is_valid_vision_region(region):
			return false
	return true


static func _is_valid_vision_region(record: Dictionary) -> bool:
	return (
		_is_integer_array(record.get("rect"), 4)
		and _is_integer(record.get("min_elevation"))
		and _is_integer(record.get("max_elevation"))
	)


static func _is_dictionary_array(value: Variant) -> bool:
	if not (value is Array):
		return false
	for item: Variant in value as Array:
		if not (item is Dictionary):
			return false
	return true


static func _is_integer_array(value: Variant, expected_size: int) -> bool:
	if not _is_number_array(value, expected_size):
		return false
	for item: Variant in value as Array:
		if not _is_integer(item):
			return false
	return true


static func _is_number_array(value: Variant, expected_size: int) -> bool:
	if not (value is Array) or (value as Array).size() != expected_size:
		return false
	for item: Variant in value as Array:
		if not (item is int) and not (item is float):
			return false
	return true


static func _is_array(value: Variant) -> bool:
	return value is Array


static func _is_integer(value: Variant) -> bool:
	return value is int or (value is float and is_equal_approx(value, roundf(value)))
