class_name NetworkReplicationStore
extends RefCounted

var object_states: Dictionary[String, int] = {}
var entity_ai_states: Dictionary[String, Dictionary] = {}
var entity_vitality_states: Dictionary[String, Dictionary] = {}
var world_spawn_records: Array[Dictionary] = []
var removed_world_items: Array[Dictionary] = []


func clear() -> void:
	object_states.clear()
	entity_ai_states.clear()
	entity_vitality_states.clear()
	world_spawn_records.clear()
	removed_world_items.clear()


func cache_object_state(object_id: String, object_state: int) -> void:
	if not object_id.is_empty():
		object_states[object_id] = object_state


func cache_entity_ai_state(entity_id: String, state: String, target_entity_id: String, reason: String) -> void:
	if entity_id.is_empty():
		return
	entity_ai_states[entity_id] = {
		"state": state,
		"target_entity_id": target_entity_id,
		"reason": reason,
	}


func cache_entity_vitality(entity_id: String, health: int, max_health: int, damage: int) -> void:
	if entity_id.is_empty() or max_health <= 0 or damage < 0:
		return
	entity_vitality_states[entity_id] = {
		"health": clampi(health, 0, max_health),
		"max_health": max_health,
		"damage": damage,
	}


func cache_world_spawn(record: Dictionary) -> void:
	var spawn_id: String = str(record.get("spawn_id", ""))
	if spawn_id.is_empty():
		return
	_remove_world_item_tombstone(spawn_id)
	for existing_record: Dictionary in world_spawn_records:
		if str(existing_record.get("spawn_id", "")) == spawn_id:
			return
	world_spawn_records.append(record.duplicate(true))


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
	return world_spawn_records.duplicate(true)


func get_removed_world_items() -> Array[Dictionary]:
	return removed_world_items.duplicate(true)


func _cache_world_item_removal(record: Dictionary) -> void:
	var item_id: String = str(record.get("id", ""))
	var kind: String = str(record.get("kind", ""))
	if item_id.is_empty() or (kind != "entity" and kind != "object"):
		return

	var was_dynamic_spawn: bool = _erase_world_spawn_record(item_id)
	object_states.erase(item_id)
	entity_ai_states.erase(item_id)
	entity_vitality_states.erase(item_id)
	if was_dynamic_spawn:
		return

	for existing_record: Dictionary in removed_world_items:
		if str(existing_record.get("id", "")) == item_id and str(existing_record.get("kind", "")) == kind:
			return
	removed_world_items.append({"kind": kind, "id": item_id})


func _erase_world_spawn_record(spawn_id: String) -> bool:
	for index: int in range(world_spawn_records.size() - 1, -1, -1):
		var record: Dictionary = world_spawn_records[index]
		if str(record.get("spawn_id", "")) == spawn_id:
			world_spawn_records.remove_at(index)
			return true
	return false


func _remove_world_item_tombstone(item_id: String) -> void:
	for index: int in range(removed_world_items.size() - 1, -1, -1):
		var record: Dictionary = removed_world_items[index]
		if str(record.get("id", "")) == item_id:
			removed_world_items.remove_at(index)
