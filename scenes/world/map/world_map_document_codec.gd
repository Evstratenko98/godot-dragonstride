class_name WorldMapDocumentCodec
extends RefCounted

const MAX_GRID_SIDE: int = 128


static func encode(document: WorldMapDocument) -> PackedByteArray:
	if not get_validation_error(document).is_empty():
		return PackedByteArray()
	return JSON.stringify(document.to_dictionary()).to_utf8_buffer()


static func decode(payload: PackedByteArray) -> WorldMapDecodeResult:
	if payload.is_empty():
		return WorldMapDecodeResult.failure("map_invalid")
	if payload.size() > NetworkProtocol.MAX_LEVEL_MAP_BYTES:
		return WorldMapDecodeResult.failure("map_too_large")
	var parsed_value: Variant = JSON.parse_string(payload.get_string_from_utf8())
	if not (parsed_value is Dictionary):
		return WorldMapDecodeResult.failure("map_invalid")
	if not WorldMapRawSchemaValidator.is_valid(parsed_value as Dictionary):
		return WorldMapDecodeResult.failure("map_invalid")
	var document: WorldMapDocument = _from_dictionary(parsed_value as Dictionary)
	var validation_error: String = get_validation_error(document)
	if not validation_error.is_empty():
		return WorldMapDecodeResult.failure(validation_error)
	return WorldMapDecodeResult.success(document)


static func get_validation_error(document: WorldMapDocument) -> String:
	if document == null:
		return "map_invalid"
	if (
		document.schema_version != NetworkProtocol.MAP_SCHEMA_VERSION
		or not NetworkProtocol.is_valid_identifier(document.level_id)
		or not NetworkProtocol.is_valid_identifier(document.generator_id)
		or document.generator_version <= 0
		or document.grid_size.x <= 0
		or document.grid_size.y <= 0
		or document.grid_size.x > MAX_GRID_SIDE
		or document.grid_size.y > MAX_GRID_SIDE
	):
		return "map_invalid"
	var layer_error: String = _validate_layers(document.layers)
	if not layer_error.is_empty():
		return layer_error
	var topology_error: String = _validate_topology(document)
	if not topology_error.is_empty():
		return topology_error
	return _validate_placements(document)


static func get_sha256(payload: PackedByteArray) -> String:
	var hashing_context: HashingContext = HashingContext.new()
	if hashing_context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if hashing_context.update(payload) != OK:
		return ""
	return hashing_context.finish().hex_encode()


static func _from_dictionary(value: Dictionary) -> WorldMapDocument:
	var document: WorldMapDocument = WorldMapDocument.new()
	document.schema_version = int(value.get("schema_version", 0))
	document.level_id = str(value.get("level_id", ""))
	document.generator_id = str(value.get("generator_id", ""))
	document.generator_version = int(value.get("generator_version", 0))
	document.seed = int(value.get("seed", 0))
	document.grid_size = _read_vector2i(value.get("grid_size"))
	document.layers = _read_dictionary_array(value.get("layers"))
	document.surface_layers = _read_dictionary_array(value.get("surface_layers"))
	document.ramps = _read_dictionary_array(value.get("ramps"))
	document.static_entities = _read_dictionary_array(value.get("static_entities"))
	document.static_objects = _read_dictionary_array(value.get("static_objects"))
	var spawn_values: Variant = value.get("player_spawn_surfaces")
	if spawn_values is Array:
		for spawn_value: Variant in spawn_values as Array:
			document.player_spawn_surfaces.append(_read_vector3i(spawn_value))
	return document


static func _validate_layers(layers: Array[Dictionary]) -> String:
	if layers.is_empty() or layers.size() > NetworkProtocol.MAX_LEVEL_MAP_LAYERS:
		return "map_invalid"
	var names: Dictionary[String, bool] = {}
	var total_cells: int = 0
	for layer: Dictionary in layers:
		var layer_name: String = str(layer.get("name", ""))
		var tile_set_key: String = str(layer.get("tile_set_key", ""))
		var parent_kind: String = str(layer.get("parent", ""))
		var placement: String = str(layer.get("placement", ""))
		var cells_value: Variant = layer.get("cells")
		if (
			not NetworkProtocol.is_valid_identifier(layer_name)
			or names.has(layer_name)
			or not WorldMapTileSetCatalog.has_key(tile_set_key)
			or parent_kind not in ["level", "topology"]
			or placement not in ["semantic", "terrain", "overlay"]
			or absi(int(layer.get("z_index", 0))) > 4096
			or not (cells_value is Array)
			or (cells_value as Array).size() > NetworkProtocol.MAX_LEVEL_MAP_TILE_RECORDS
		):
			return "map_invalid"
		names[layer_name] = true
		total_cells += (cells_value as Array).size()
		if total_cells > NetworkProtocol.MAX_LEVEL_MAP_TILE_RECORDS:
			return "map_too_large"
		var occupied_cells: Dictionary[Vector2i, bool] = {}
		for cell_value: Variant in cells_value as Array:
			if not _is_valid_cell(cell_value, tile_set_key):
				return "map_invalid"
			var cell: Array = cell_value as Array
			var coordinates: Vector2i = Vector2i(int(cell[0]), int(cell[1]))
			if occupied_cells.has(coordinates):
				return "map_invalid"
			occupied_cells[coordinates] = true
	return ""


static func _validate_topology(document: WorldMapDocument) -> String:
	if (
		document.surface_layers.is_empty()
		or document.surface_layers.size() > NetworkProtocol.MAX_LEVEL_MAP_LAYERS
		or document.ramps.size() > WorldGridTopology.MAX_RAMPS
		or document.player_spawn_surfaces.size() > NetworkProtocol.MAX_PLAYER_CHARACTERS
	):
		return "map_invalid"
	var layer_cell_counts: Dictionary[String, int] = {}
	var semantic_layer_names: Dictionary[String, bool] = {}
	for layer: Dictionary in document.layers:
		var layer_name: String = str(layer.get("name", ""))
		layer_cell_counts[layer_name] = (layer.get("cells", []) as Array).size()
		if str(layer.get("parent", "")) == "topology" and str(layer.get("placement", "")) == "semantic":
			semantic_layer_names[layer_name] = true
			for cell_value: Variant in layer.get("cells") as Array:
				var cell: Array = cell_value as Array
				if int(cell[0]) < 0 or int(cell[1]) < 0 or int(cell[0]) >= document.grid_size.x or int(cell[1]) >= document.grid_size.y:
					return "map_invalid"
	var topology_node_names: Dictionary[String, bool] = {}
	var surface_candidate_count: int = 0
	for surface_layer: Dictionary in document.surface_layers:
		var node_name: String = str(surface_layer.get("node_name", ""))
		var source_layer: String = str(surface_layer.get("source_layer", ""))
		var elevation: int = int(surface_layer.get("elevation", -1))
		var explicit_cells: Variant = surface_layer.get("explicit_cells")
		var excluded_cells: Variant = surface_layer.get("excluded_cells")
		if (
			not _is_valid_grid_cell_array(explicit_cells, document.grid_size)
			or not _is_valid_grid_cell_array(excluded_cells, document.grid_size)
		):
			return "map_invalid"
		if (
			not NetworkProtocol.is_valid_identifier(node_name)
			or topology_node_names.has(node_name)
			or (source_layer.is_empty() and (explicit_cells as Array).is_empty())
			or (not source_layer.is_empty() and not semantic_layer_names.has(source_layer))
			or elevation < WorldGridTopology.MIN_ELEVATION
			or elevation > WorldGridTopology.MAX_ELEVATION
		):
			return "map_invalid"
		topology_node_names[node_name] = true
		surface_candidate_count += (explicit_cells as Array).size()
		if not source_layer.is_empty():
			surface_candidate_count += int(layer_cell_counts[source_layer])
		if surface_candidate_count > WorldGridTopology.MAX_SURFACES:
			return "map_too_large"
	var connection_ids: Dictionary[String, bool] = {}
	for ramp: Dictionary in document.ramps:
		var node_name: String = str(ramp.get("node_name", ""))
		var connection_id: String = str(ramp.get("connection_id", ""))
		if (
			not NetworkProtocol.is_valid_identifier(node_name)
			or topology_node_names.has(node_name)
			or not NetworkProtocol.is_valid_identifier(connection_id)
			or connection_ids.has(connection_id)
			or int(ramp.get("traversal_kind", -1)) not in WorldRampConnection.TraversalKind.values()
			or not _is_valid_grid_surface(ramp.get("low_surface"), document.grid_size)
			or not _is_valid_grid_surface(ramp.get("high_surface"), document.grid_size)
			or not _is_cardinal_direction(ramp.get("low_input_direction"))
			or not _is_cardinal_direction(ramp.get("high_input_direction"))
			or not _is_valid_grid_cell_array(ramp.get("visual_footprint"), document.grid_size)
			or not _is_valid_grid_cell_array(ramp.get("blocked_lower_cells"), document.grid_size)
		):
			return "map_invalid"
		topology_node_names[node_name] = true
		connection_ids[connection_id] = true
	for spawn_surface: Vector3i in document.player_spawn_surfaces:
		if not _is_surface_inside_grid(spawn_surface, document.grid_size):
			return "map_invalid"
	return ""


static func _validate_placements(document: WorldMapDocument) -> String:
	if document.static_entities.size() + document.static_objects.size() > NetworkProtocol.MAX_LEVEL_MAP_PLACEMENTS:
		return "map_too_large"
	var ids: Dictionary[String, bool] = {}
	var node_names: Dictionary[String, bool] = {}
	for record: Dictionary in document.static_entities:
		var error: String = _validate_placement(record, WorldSpawnCatalog.KIND_ENTITY, ids, node_names)
		if not error.is_empty():
			return error
	for record: Dictionary in document.static_objects:
		var error: String = _validate_placement(record, WorldSpawnCatalog.KIND_OBJECT, ids, node_names)
		if not error.is_empty():
			return error
	return ""


static func _validate_placement(
	record: Dictionary,
	expected_kind: String,
	ids: Dictionary[String, bool],
	node_names: Dictionary[String, bool]
) -> String:
	var item_id: String = str(record.get("id", ""))
	var node_name: String = str(record.get("node_name", ""))
	var type_key: String = str(record.get("type_key", ""))
	if (
		not NetworkProtocol.is_valid_identifier(item_id)
		or ids.has(item_id)
		or not NetworkProtocol.is_valid_identifier(node_name)
		or node_names.has(node_name)
		or not WorldSpawnCatalog.has_type(type_key)
		or WorldSpawnCatalog.get_kind(type_key) != expected_kind
		or not _is_vector_array(record.get("position"), 2)
		or not _is_vector_array(record.get("scale"), 2)
	):
		return "map_invalid"
	var position: Array = record.get("position") as Array
	var scale: Array = record.get("scale") as Array
	if (
		absf(float(position[0])) > NetworkProtocol.MAX_GAMEPLAY_VALUE
		or absf(float(position[1])) > NetworkProtocol.MAX_GAMEPLAY_VALUE
		or float(scale[0]) <= 0.0
		or float(scale[1]) <= 0.0
		or float(scale[0]) > NetworkProtocol.MAX_GAMEPLAY_VALUE
		or float(scale[1]) > NetworkProtocol.MAX_GAMEPLAY_VALUE
	):
		return "map_invalid"
	var surface_height: int = int(record.get("surface_height", 0))
	if surface_height < WorldGridTopology.MIN_ELEVATION or surface_height > WorldGridTopology.MAX_ELEVATION:
		return "map_invalid"
	ids[item_id] = true
	node_names[node_name] = true
	return ""


static func _is_valid_cell(value: Variant, tile_set_key: String) -> bool:
	if not (value is Array) or (value as Array).size() != 6:
		return false
	var cell: Array = value as Array
	for component: Variant in cell:
		if not _is_integer_number(component):
			return false
	return (
		absi(int(cell[0])) <= NetworkProtocol.MAX_ABSOLUTE_GRID_COORDINATE
		and absi(int(cell[1])) <= NetworkProtocol.MAX_ABSOLUTE_GRID_COORDINATE
		and WorldMapTileSetCatalog.is_valid_tile(
			tile_set_key,
			int(cell[2]),
			Vector2i(int(cell[3]), int(cell[4])),
			int(cell[5])
		)
	)


static func _is_valid_vector2i_array(value: Variant) -> bool:
	if not (value is Array) or (value as Array).size() > WorldGridTopology.MAX_SURFACES:
		return false
	for item: Variant in value as Array:
		if not _is_integer_vector_array(item, 2):
			return false
	return true


static func _is_valid_grid_cell_array(value: Variant, grid_size: Vector2i) -> bool:
	if not _is_valid_vector2i_array(value):
		return false
	for item: Variant in value as Array:
		var cell: Vector2i = _read_vector2i(item)
		if cell.x < 0 or cell.y < 0 or cell.x >= grid_size.x or cell.y >= grid_size.y:
			return false
	return true


static func _is_valid_grid_surface(value: Variant, grid_size: Vector2i) -> bool:
	return _is_integer_vector_array(value, 3) and _is_surface_inside_grid(_read_vector3i(value), grid_size)


static func _is_surface_inside_grid(surface: Vector3i, grid_size: Vector2i) -> bool:
	return (
		NetworkProtocol.is_valid_surface_value(surface)
		and surface.x >= 0
		and surface.y >= 0
		and surface.x < grid_size.x
		and surface.y < grid_size.y
	)


static func _is_cardinal_direction(value: Variant) -> bool:
	if not _is_integer_vector_array(value, 2):
		return false
	var direction: Vector2i = _read_vector2i(value)
	return absi(direction.x) + absi(direction.y) == 1


static func _is_vector_array(value: Variant, expected_size: int) -> bool:
	if not (value is Array) or (value as Array).size() != expected_size:
		return false
	for component: Variant in value as Array:
		if not _is_integer_number(component) and not (component is float):
			return false
	return true


static func _is_integer_vector_array(value: Variant, expected_size: int) -> bool:
	if not (value is Array) or (value as Array).size() != expected_size:
		return false
	for component: Variant in value as Array:
		if not _is_integer_number(component):
			return false
	return true


static func _is_integer_number(value: Variant) -> bool:
	return value is int or (value is float and is_equal_approx(value, roundf(value)))


static func _read_dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (value is Array):
		return result
	for item: Variant in value as Array:
		if item is Dictionary:
			result.append((item as Dictionary).duplicate(true))
	return result


static func _read_vector2i(value: Variant) -> Vector2i:
	if not _is_integer_vector_array(value, 2):
		return Vector2i.ZERO
	var components: Array = value as Array
	return Vector2i(int(components[0]), int(components[1]))


static func _read_vector3i(value: Variant) -> Vector3i:
	if not _is_integer_vector_array(value, 3):
		return Vector3i(-1, -1, -1)
	var components: Array = value as Array
	return Vector3i(int(components[0]), int(components[1]), int(components[2]))
