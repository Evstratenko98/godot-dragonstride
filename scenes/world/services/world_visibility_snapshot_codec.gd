class_name WorldVisibilitySnapshotCodec
extends RefCounted

const KEY_ENABLED: String = "fog_enabled"
const KEY_TOPOLOGY_HASH: String = "topology_hash"
const KEY_EXPLORED: String = "explored_by_player"
const KEY_TOWERS: String = "tower_owners"
const KEY_MEMORIES: String = "object_memories_by_player"
const MAX_RESOURCE_PATH_LENGTH: int = 256
const MAX_OBJECT_FOOTPRINT_SURFACES: int = 64


static func create_snapshot(visibility: WorldVisibility) -> Dictionary:
	var explored_records: Dictionary[String, PackedByteArray] = {}
	var memory_records: Dictionary[String, Dictionary] = {}
	for player_id: String in visibility.get_valid_player_ids().keys():
		explored_records[player_id] = _encode_surface_set(
			visibility.surface_index_by_surface,
			visibility.explored_by_player.get(player_id, {}) as Dictionary,
			visibility.surface_order.size()
		)
		memory_records[player_id] = (visibility.object_memories_by_player.get(player_id, {}) as Dictionary).duplicate(true)
	var tower_records: Array[Dictionary] = []
	for object_value: Variant in visibility.runtime.get_registered_objects():
		var tower: VisionTower = object_value as VisionTower
		if tower != null and not tower.object_id.is_empty():
			tower_records.append({"object_id": tower.object_id, "owner_player_id": tower.owner_player_id})
	return {
		KEY_ENABLED: visibility.fog_enabled,
		KEY_TOPOLOGY_HASH: visibility.runtime.get_topology_hash(),
		KEY_EXPLORED: explored_records,
		KEY_TOWERS: tower_records,
		KEY_MEMORIES: memory_records,
	}


static func is_valid_snapshot(
	visibility: WorldVisibility,
	snapshot: Dictionary,
	additional_tower_ids: Dictionary[String, bool] = {},
	should_require_exact_tower_count: bool = true
) -> bool:
	if (
		not (snapshot.get(KEY_ENABLED) is bool)
		or str(snapshot.get(KEY_TOPOLOGY_HASH, "")) != visibility.runtime.get_topology_hash()
		or not (snapshot.get(KEY_EXPLORED) is Dictionary)
		or not (snapshot.get(KEY_TOWERS) is Array)
		or not (snapshot.get(KEY_MEMORIES) is Dictionary)
	):
		return false
	var valid_player_ids: Dictionary[String, bool] = visibility.get_valid_player_ids()
	var required_byte_count: int = ceili(float(visibility.surface_order.size()) / 8.0)
	var explored_records: Dictionary = snapshot[KEY_EXPLORED] as Dictionary
	if explored_records.size() != valid_player_ids.size() or explored_records.size() > NetworkProtocol.MAX_ROSTER_SIZE:
		return false
	for player_id_value: Variant in explored_records.keys():
		var player_id: String = str(player_id_value)
		if not valid_player_ids.has(player_id):
			return false
		var bytes_value: Variant = explored_records[player_id_value]
		if not (bytes_value is PackedByteArray) or (bytes_value as PackedByteArray).size() != required_byte_count:
			return false
		if visibility.surface_order.size() % 8 != 0 and required_byte_count > 0:
			var valid_last_byte_mask: int = (1 << (visibility.surface_order.size() % 8)) - 1
			if ((bytes_value as PackedByteArray)[required_byte_count - 1] & ~valid_last_byte_mask) != 0:
				return false
	var towers: Array = snapshot[KEY_TOWERS] as Array
	if towers.size() > NetworkProtocol.MAX_WORLD_RECORDS:
		return false
	var registered_tower_count: int = 0
	for object_value: Variant in visibility.runtime.get_registered_objects():
		if object_value is VisionTower:
			registered_tower_count += 1
	if should_require_exact_tower_count and towers.size() != registered_tower_count + additional_tower_ids.size():
		return false
	var seen_tower_ids: Dictionary[String, bool] = {}
	for record_value: Variant in towers:
		if not (record_value is Dictionary):
			return false
		var record: Dictionary = record_value as Dictionary
		var object_id: String = str(record.get("object_id", ""))
		if (
			not NetworkProtocol.is_valid_identifier(object_id)
			or seen_tower_ids.has(object_id)
			or (not (visibility.runtime.get_object_by_id(object_id) is VisionTower) and not additional_tower_ids.has(object_id))
			or not NetworkProtocol.is_valid_optional_identifier(str(record.get("owner_player_id", "")))
			or (not str(record.get("owner_player_id", "")).is_empty() and not valid_player_ids.has(str(record.get("owner_player_id", ""))))
		):
			return false
		seen_tower_ids[object_id] = true
	return _are_memories_valid(snapshot[KEY_MEMORIES] as Dictionary, valid_player_ids)


static func apply_snapshot(visibility: WorldVisibility, snapshot: Dictionary) -> bool:
	if not is_valid_snapshot(visibility, snapshot):
		return false
	var next_explored: Dictionary[String, Dictionary] = {}
	var explored_records: Dictionary = snapshot[KEY_EXPLORED] as Dictionary
	for player_id_value: Variant in explored_records.keys():
		var player_id: String = str(player_id_value)
		next_explored[player_id] = _decode_surface_set(
			visibility.surface_order,
			explored_records[player_id_value] as PackedByteArray
		)
	visibility.explored_by_player = next_explored
	visibility.object_memories_by_player = (snapshot[KEY_MEMORIES] as Dictionary).duplicate(true)
	visibility.fog_enabled = bool(snapshot[KEY_ENABLED])
	GameSession.set_match_setting(GameSession.MATCH_SETTING_FOG_OF_WAR, visibility.fog_enabled)
	for record_value: Variant in snapshot[KEY_TOWERS] as Array:
		var record: Dictionary = record_value as Dictionary
		var tower: VisionTower = visibility.runtime.get_object_by_id(str(record.get("object_id", ""))) as VisionTower
		if tower != null:
			tower.apply_owner_player_id(str(record.get("owner_player_id", "")))
	visibility._recompute_visibility()
	visibility.fog_enabled_changed.emit(visibility.fog_enabled)
	return true


static func _encode_surface_set(index_by_surface: Dictionary[Vector3i, int], values: Dictionary, count: int) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(ceili(float(count) / 8.0))
	for surface_value: Variant in values.keys():
		if not (surface_value is Vector3i) or not index_by_surface.has(surface_value as Vector3i):
			continue
		var index: int = index_by_surface[surface_value as Vector3i]
		var byte_index: int = index >> 3
		bytes[byte_index] = bytes[byte_index] | (1 << (index % 8))
	return bytes


static func _decode_surface_set(surface_order: Array[Vector3i], bytes: PackedByteArray) -> Dictionary[Vector3i, bool]:
	var result: Dictionary[Vector3i, bool] = {}
	for index: int in range(surface_order.size()):
		if (bytes[index >> 3] & (1 << (index % 8))) != 0:
			result[surface_order[index]] = true
	return result


static func _are_memories_valid(memories: Dictionary, valid_player_ids: Dictionary[String, bool]) -> bool:
	if memories.size() != valid_player_ids.size() or memories.size() > NetworkProtocol.MAX_ROSTER_SIZE:
		return false
	for player_id_value: Variant in memories.keys():
		var player_id: String = str(player_id_value)
		var records_value: Variant = memories[player_id_value]
		if not valid_player_ids.has(player_id) or not (records_value is Dictionary):
			return false
		var records: Dictionary = records_value as Dictionary
		if records.size() > NetworkProtocol.MAX_WORLD_RECORDS:
			return false
		for object_id_value: Variant in records.keys():
			var record_value: Variant = records[object_id_value]
			if not NetworkProtocol.is_valid_identifier(str(object_id_value)) or not (record_value is Dictionary):
				return false
			var record: Dictionary = record_value as Dictionary
			var owner_player_id: String = str(record.get("owner_player_id", ""))
			var texture_path: String = str(record.get("texture_path", ""))
			var occupied_surfaces_value: Variant = record.get("occupied_surfaces", [])
			if (
				not (record.get("surface") is Vector3i)
				or not NetworkProtocol.is_valid_surface_value(record["surface"] as Vector3i)
				or int(record.get("object_state", -1)) not in [0, 1, 2]
				or not NetworkProtocol.is_valid_optional_identifier(owner_player_id)
				or (not owner_player_id.is_empty() and not valid_player_ids.has(owner_player_id))
				or texture_path.length() > MAX_RESOURCE_PATH_LENGTH
				or (not texture_path.is_empty() and not texture_path.begins_with("res://"))
				or not (record.get("sprite_position") is Vector2)
				or not (record.get("sprite_scale") is Vector2)
				or not (record.get("sprite_offset") is Vector2)
				or not (record.get("sprite_modulate") is Color)
				or not (record.get("sprite_centered") is bool)
				or not (occupied_surfaces_value is Array)
				or (occupied_surfaces_value as Array).is_empty()
				or (occupied_surfaces_value as Array).size() > MAX_OBJECT_FOOTPRINT_SURFACES
			):
				return false
			for occupied_surface_value: Variant in occupied_surfaces_value as Array:
				if not (occupied_surface_value is Vector3i) or not NetworkProtocol.is_valid_surface_value(occupied_surface_value as Vector3i):
					return false
	return true
