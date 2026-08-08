class_name WorldSpawnBatchOperator
extends RefCounted

var spawner: WorldSpawner = null


func configure(owner: WorldSpawner) -> void:
	spawner = owner


func fill(type_key: String, requester_peer_id: int) -> void:
	if not WorldSpawnCatalog.DEFINITIONS.has(type_key):
		spawner._report_spawn_error("Unknown create type: %s." % type_key, requester_peer_id, "unknown_type")
		return
	var created_records: Array[Dictionary] = []
	var grid_size: Vector2i = spawner.runtime.get_grid_size()
	for elevation: int in range(WorldGridTopology.MIN_ELEVATION, WorldGridTopology.MAX_ELEVATION + 1):
		for y: int in range(grid_size.y):
			for x: int in range(grid_size.x):
				var surface: Vector3i = Vector3i(x, y, elevation)
				if not spawner.runtime.is_surface_walkable(surface):
					continue
				var record: Dictionary = spawner._try_fill_surface(type_key, surface)
				if not record.is_empty():
					created_records.append(record)
	if GameSession.is_multiplayer() and not created_records.is_empty():
		NetworkManager.world.broadcast_world_spawns(created_records)
	ConsoleOutput.print_console("Created %d %s instance(s) on available cells." % [created_records.size(), type_key], spawner.runtime)


func clear(type_key: String, requester_peer_id: int) -> void:
	if not type_key.is_empty() and not WorldSpawnCatalog.DEFINITIONS.has(type_key):
		spawner._report_spawn_error("Unknown clear type: %s." % type_key, requester_peer_id, "invalid_clear_type")
		return
	var removal_records: Array[Dictionary] = []
	for entity_variant: Variant in spawner.runtime.get_registered_entities():
		var entity: NonPlayerEntity = entity_variant as NonPlayerEntity
		if entity != null and spawner._matches_catalog_type(entity, type_key):
			var entity_removal: Dictionary = spawner._remove_world_item(entity)
			if not entity_removal.is_empty():
				removal_records.append(entity_removal)
	for object_variant: Variant in spawner.runtime.get_registered_objects():
		var target_object: GridObject = object_variant as GridObject
		if target_object != null and spawner._matches_catalog_type(target_object, type_key):
			var object_removal: Dictionary = spawner._remove_world_item(target_object)
			if not object_removal.is_empty():
				removal_records.append(object_removal)
	if GameSession.is_multiplayer() and not removal_records.is_empty():
		NetworkManager.world.broadcast_world_items_removed(removal_records, spawner.runtime.get_current_action_sequence_id())
	var cleared_type: String = type_key if not type_key.is_empty() else "all world items"
	ConsoleOutput.print_console("Removed %d %s instance(s)." % [removal_records.size(), cleared_type], spawner.runtime)
