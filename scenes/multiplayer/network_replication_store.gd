class_name NetworkReplicationStore
extends RefCounted

var object_states: Dictionary[String, int] = {}
var entity_ai_states: Dictionary[String, Dictionary] = {}
var entity_vitality_states: Dictionary[String, Dictionary] = {}
var world_spawn_records_by_id: Dictionary[String, Dictionary] = {}
var removed_world_items_by_key: Dictionary[String, Dictionary] = {}


func clear() -> void:
	object_states.clear()
	entity_ai_states.clear()
	entity_vitality_states.clear()
	world_spawn_records_by_id.clear()
	removed_world_items_by_key.clear()


func cache_object_state(object_id: String, object_state: int) -> void:
	if (
		NetworkProtocol.is_valid_identifier(object_id)
		and object_state in [0, 1]
		and (object_states.has(object_id) or object_states.size() < NetworkProtocol.MAX_WORLD_RECORDS)
	):
		object_states[object_id] = object_state


func cache_entity_ai_state(entity_id: String, state: String, target_entity_id: String, reason: String) -> void:
	if not NetworkProtocol.is_valid_identifier(entity_id):
		return
	if not entity_ai_states.has(entity_id) and entity_ai_states.size() >= NetworkProtocol.MAX_WORLD_RECORDS:
		return
	entity_ai_states[entity_id] = {
		"state": state.left(NetworkProtocol.MAX_IDENTIFIER_LENGTH),
		"target_entity_id": target_entity_id.left(NetworkProtocol.MAX_IDENTIFIER_LENGTH),
		"reason": reason.left(NetworkProtocol.MAX_IDENTIFIER_LENGTH),
	}


func cache_entity_vitality(entity_id: String, health: int, max_health: int, damage: int) -> void:
	if (
		not NetworkProtocol.is_valid_identifier(entity_id)
		or max_health <= 0
		or max_health > NetworkProtocol.MAX_GAMEPLAY_VALUE
		or damage < 0
		or damage > NetworkProtocol.MAX_GAMEPLAY_VALUE
	):
		return
	if not entity_vitality_states.has(entity_id) and entity_vitality_states.size() >= NetworkProtocol.MAX_WORLD_RECORDS:
		return
	entity_vitality_states[entity_id] = {
		"health": clampi(health, 0, max_health),
		"max_health": max_health,
		"damage": damage,
	}


func cache_world_spawn(record: Dictionary) -> void:
	var spawn_id: String = str(record.get("spawn_id", ""))
	if not NetworkProtocol.is_valid_identifier(spawn_id):
		return
	if not world_spawn_records_by_id.has(spawn_id) and world_spawn_records_by_id.size() >= NetworkProtocol.MAX_WORLD_RECORDS:
		return
	_remove_world_item_tombstone(spawn_id)
	world_spawn_records_by_id[spawn_id] = record.duplicate(true)


func cache_world_spawns(records: Array[Dictionary]) -> void:
	for record: Dictionary in records:
		cache_world_spawn(record)


func cache_world_item_removals(records: Array[Dictionary]) -> void:
	for record: Dictionary in records:
		_cache_world_item_removal(record)


func get_object_states() -> Dictionary:
	return object_states.duplicate()


func get_entity_ai_states() -> Dictionary:
	return entity_ai_states.duplicate(true)


func get_entity_vitality_states() -> Dictionary:
	return entity_vitality_states.duplicate(true)


func get_world_spawn_records() -> Array[Dictionary]:
	var spawn_ids: Array[String] = []
	for spawn_id: String in world_spawn_records_by_id.keys():
		spawn_ids.append(spawn_id)
	spawn_ids.sort()
	var records: Array[Dictionary] = []
	for spawn_id: String in spawn_ids:
		records.append(world_spawn_records_by_id[spawn_id].duplicate(true))
	return records


func get_removed_world_items() -> Array[Dictionary]:
	var removal_keys: Array[String] = []
	for removal_key: String in removed_world_items_by_key.keys():
		removal_keys.append(removal_key)
	removal_keys.sort()
	var records: Array[Dictionary] = []
	for removal_key: String in removal_keys:
		records.append(removed_world_items_by_key[removal_key].duplicate(true))
	return records


func replace_from_world_snapshot(world_state: Dictionary) -> void:
	clear()
	var spawn_records: Array[Dictionary] = []
	for record_value: Variant in world_state.get("dynamic_spawns", []):
		if record_value is Dictionary:
			spawn_records.append(record_value as Dictionary)
	cache_world_spawns(spawn_records)
	var removal_records: Array[Dictionary] = []
	for record_value: Variant in world_state.get("removed_items", []):
		if record_value is Dictionary:
			removal_records.append(record_value as Dictionary)
	cache_world_item_removals(removal_records)
	for record_value: Variant in world_state.get("objects", []):
		if record_value is Dictionary:
			var record: Dictionary = record_value as Dictionary
			cache_object_state(
				str(record.get("object_id", "")),
				int(record.get("object_state", 0))
			)
	for record_value: Variant in world_state.get("entities", []):
		if record_value is Dictionary:
			var record: Dictionary = record_value as Dictionary
			cache_entity_vitality(
				str(record.get("entity_id", "")),
				int(record.get("health", 0)),
				int(record.get("max_health", 1)),
				int(record.get("damage", 0))
			)
	var ai_states_value: Variant = world_state.get("ai_states", {})
	if ai_states_value is Dictionary:
		var ai_states: Dictionary = ai_states_value as Dictionary
		for entity_id_value: Variant in ai_states.keys():
			var state: Dictionary = ai_states.get(entity_id_value, {}) as Dictionary
			cache_entity_ai_state(
				str(entity_id_value),
				str(state.get("state", "")),
				str(state.get("target_entity_id", "")),
				str(state.get("reason", ""))
			)


func _cache_world_item_removal(record: Dictionary) -> void:
	var item_id: String = str(record.get("id", ""))
	var kind: String = str(record.get("kind", ""))
	if not NetworkProtocol.is_valid_identifier(item_id) or (kind != "entity" and kind != "object"):
		return
	var was_dynamic_spawn: bool = world_spawn_records_by_id.erase(item_id)
	object_states.erase(item_id)
	entity_ai_states.erase(item_id)
	entity_vitality_states.erase(item_id)
	if was_dynamic_spawn:
		return
	var removal_key: String = "%s:%s" % [kind, item_id]
	if not removed_world_items_by_key.has(removal_key) and removed_world_items_by_key.size() >= NetworkProtocol.MAX_WORLD_RECORDS:
		return
	removed_world_items_by_key[removal_key] = {"kind": kind, "id": item_id}


func _remove_world_item_tombstone(item_id: String) -> void:
	removed_world_items_by_key.erase("entity:%s" % item_id)
	removed_world_items_by_key.erase("object:%s" % item_id)
