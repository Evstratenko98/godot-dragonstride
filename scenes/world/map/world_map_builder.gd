class_name WorldMapBuilder
extends Node

signal progress_changed(completed_units: int, total_units: int)

const TILE_BATCH_SIZE: int = 2048
const PLACEMENT_BATCH_SIZE: int = 64

var completed_units: int = 0
var total_units: int = 0
var build_deadline_msec: int = 0


func build(
	level: WorldLevel,
	document: WorldMapDocument,
	document_hash: String,
	deadline_msec: int
) -> String:
	if level == null or document == null or level.get_child_count() != 0:
		return "map_build_failed"
	var validation_error: String = WorldMapDocumentCodec.get_validation_error(document)
	if not validation_error.is_empty():
		return validation_error

	completed_units = 0
	total_units = get_build_unit_count(document)
	build_deadline_msec = deadline_msec
	progress_changed.emit(completed_units, total_units)
	var topology_root: Node = Node.new()
	topology_root.name = "TerrainTopology"
	level.add_child(topology_root)

	var build_error: String = await _build_layers(level, topology_root, document.layers, "semantic")
	if not build_error.is_empty():
		_clear_level(level)
		return build_error
	build_error = await _build_surface_layers(topology_root, document.surface_layers)
	if build_error.is_empty():
		build_error = await _build_ramps(topology_root, document.ramps)
	if not build_error.is_empty():
		_clear_level(level)
		return build_error
	build_error = await _build_layers(level, topology_root, document.layers, "terrain")
	if not build_error.is_empty():
		_clear_level(level)
		return build_error
	if _deadline_expired():
		_clear_level(level)
		return "map_sync_timeout"

	var world_entities_root: Node2D = Node2D.new()
	world_entities_root.name = "WorldEntities"
	world_entities_root.y_sort_enabled = true
	level.add_child(world_entities_root)
	build_error = await _build_placements(world_entities_root, document.static_entities, true)
	if build_error.is_empty():
		build_error = await _build_placements(world_entities_root, document.static_objects, false)
	if not build_error.is_empty():
		_clear_level(level)
		return build_error

	var spawned_objects_root: Node2D = Node2D.new()
	spawned_objects_root.name = "SpawnedObjects"
	level.add_child(spawned_objects_root)
	build_error = await _build_layers(level, topology_root, document.layers, "overlay")
	if not build_error.is_empty():
		_clear_level(level)
		return build_error

	level.commit_map_document(document, document_hash)
	progress_changed.emit(total_units, total_units)
	return ""


func get_build_unit_count(document: WorldMapDocument) -> int:
	var unit_count: int = document.surface_layers.size() + document.ramps.size()
	unit_count += document.static_entities.size() + document.static_objects.size()
	for layer: Dictionary in document.layers:
		var cells: Array = layer.get("cells", []) as Array
		unit_count += cells.size()
	return maxi(unit_count, 1)


func _build_layers(
	level: WorldLevel,
	topology_root: Node,
	layers: Array[Dictionary],
	placement: String
) -> String:
	for layer_record: Dictionary in layers:
		if _deadline_expired():
			return "map_sync_timeout"
		if str(layer_record.get("placement", "")) != placement:
			continue
		var cells: Array = layer_record.get("cells", []) as Array
		var tile_set: TileSet = WorldMapTileSetCatalog.create_tile_set(
			str(layer_record.get("tile_set_key", "")),
			cells
		)
		if tile_set == null:
			return "map_build_failed"
		var layer: TileMapLayer = TileMapLayer.new()
		layer.name = str(layer_record.get("name", ""))
		layer.visible = bool(layer_record.get("visible", true))
		layer.z_index = int(layer_record.get("z_index", 0))
		layer.tile_set = tile_set
		var parent_kind: String = str(layer_record.get("parent", ""))
		if parent_kind == "topology":
			topology_root.add_child(layer)
		elif parent_kind == "level":
			level.add_child(layer)
		else:
			return "map_build_failed"
		var batch_count: int = 0
		for cell_value: Variant in cells:
			var cell: Array = cell_value as Array
			layer.set_cell(
				Vector2i(int(cell[0]), int(cell[1])),
				int(cell[2]),
				Vector2i(int(cell[3]), int(cell[4])),
				int(cell[5])
			)
			completed_units += 1
			batch_count += 1
			if batch_count >= TILE_BATCH_SIZE:
				if _deadline_expired():
					return "map_sync_timeout"
				progress_changed.emit(completed_units, total_units)
				batch_count = 0
				await get_tree().process_frame
		progress_changed.emit(completed_units, total_units)
	return ""


func _build_surface_layers(topology_root: Node, records: Array[Dictionary]) -> String:
	var batch_count: int = 0
	for record: Dictionary in records:
		if _deadline_expired():
			return "map_sync_timeout"
		var surface_layer: WorldSurfaceLayer = WorldSurfaceLayer.new()
		surface_layer.name = str(record.get("node_name", ""))
		surface_layer.elevation = int(record.get("elevation", 0))
		var source_layer: String = str(record.get("source_layer", ""))
		if not source_layer.is_empty():
			surface_layer.source_layer_path = NodePath("TerrainTopology/%s" % source_layer)
		surface_layer.explicit_cells = _read_vector2i_array(record.get("explicit_cells"))
		surface_layer.excluded_cells = _read_vector2i_array(record.get("excluded_cells"))
		surface_layer.character_only = bool(record.get("character_only", false))
		surface_layer.display_name = str(record.get("display_name", "ground"))
		topology_root.add_child(surface_layer)
		completed_units += 1
		batch_count += 1
		if batch_count >= PLACEMENT_BATCH_SIZE:
			progress_changed.emit(completed_units, total_units)
			batch_count = 0
			await get_tree().process_frame
	progress_changed.emit(completed_units, total_units)
	return ""


func _build_ramps(topology_root: Node, records: Array[Dictionary]) -> String:
	var batch_count: int = 0
	for record: Dictionary in records:
		if _deadline_expired():
			return "map_sync_timeout"
		var ramp: WorldRampConnection = WorldRampConnection.new()
		ramp.name = str(record.get("node_name", ""))
		ramp.connection_id = str(record.get("connection_id", ""))
		ramp.low_surface = _read_vector3i(record.get("low_surface"))
		ramp.high_surface = _read_vector3i(record.get("high_surface"))
		ramp.low_input_direction = _read_vector2i(record.get("low_input_direction"))
		ramp.high_input_direction = _read_vector2i(record.get("high_input_direction"))
		ramp.visual_footprint = _read_vector2i_array(record.get("visual_footprint"))
		ramp.blocked_lower_cells = _read_vector2i_array(record.get("blocked_lower_cells"))
		ramp.traversal_kind = int(record.get("traversal_kind", WorldRampConnection.TraversalKind.RAMP)) as WorldRampConnection.TraversalKind
		topology_root.add_child(ramp)
		completed_units += 1
		batch_count += 1
		if batch_count >= PLACEMENT_BATCH_SIZE:
			progress_changed.emit(completed_units, total_units)
			batch_count = 0
			await get_tree().process_frame
	progress_changed.emit(completed_units, total_units)
	return ""


func _build_placements(root: Node2D, records: Array[Dictionary], should_be_entity: bool) -> String:
	var batch_count: int = 0
	for record: Dictionary in records:
		if _deadline_expired():
			return "map_sync_timeout"
		var scene: PackedScene = WorldSpawnCatalog.get_scene(str(record.get("type_key", "")))
		if scene == null:
			return "map_build_failed"
		var instance: Node = scene.instantiate()
		var node_2d: Node2D = instance as Node2D
		if node_2d == null:
			instance.free()
			return "map_build_failed"
		instance.name = str(record.get("node_name", ""))
		node_2d.position = _read_vector2(record.get("position"))
		node_2d.scale = _read_vector2(record.get("scale"))
		if should_be_entity:
			var entity: Entity = instance as Entity
			if entity == null:
				instance.free()
				return "map_build_failed"
			entity.entity_id = str(record.get("id", ""))
			entity.surface_height = int(record.get("surface_height", 0))
		else:
			var grid_object: GridObject = instance as GridObject
			if grid_object == null:
				instance.free()
				return "map_build_failed"
			grid_object.object_id = str(record.get("id", ""))
			grid_object.surface_height = int(record.get("surface_height", 0))
		root.add_child(instance)
		completed_units += 1
		batch_count += 1
		if batch_count >= PLACEMENT_BATCH_SIZE:
			progress_changed.emit(completed_units, total_units)
			batch_count = 0
			await get_tree().process_frame
	progress_changed.emit(completed_units, total_units)
	return ""


func _clear_level(level: WorldLevel) -> void:
	for child: Node in level.get_children():
		level.remove_child(child)
		child.free()


func _deadline_expired() -> bool:
	return build_deadline_msec > 0 and Time.get_ticks_msec() >= build_deadline_msec


func _read_vector2(value: Variant) -> Vector2:
	var components: Array = value as Array
	return Vector2(float(components[0]), float(components[1]))


func _read_vector2i(value: Variant) -> Vector2i:
	var components: Array = value as Array
	return Vector2i(int(components[0]), int(components[1]))


func _read_vector3i(value: Variant) -> Vector3i:
	var components: Array = value as Array
	return Vector3i(int(components[0]), int(components[1]), int(components[2]))


func _read_vector2i_array(value: Variant) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for item: Variant in value as Array:
		result.append(_read_vector2i(item))
	return result
