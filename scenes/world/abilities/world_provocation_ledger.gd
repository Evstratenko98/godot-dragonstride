class_name WorldProvocationLedger
extends RefCounted

var provoker_by_target_entity_id: Dictionary[String, String] = {}


func clear() -> void:
	provoker_by_target_entity_id.clear()


func provoke(target_entity_id: String, provoker_entity_id: String) -> void:
	provoker_by_target_entity_id[target_entity_id] = provoker_entity_id


func get_provoker_entity_id(target_entity_id: String) -> String:
	return str(provoker_by_target_entity_id.get(target_entity_id, ""))


func has_provocation(target_entity_id: String) -> bool:
	return provoker_by_target_entity_id.has(target_entity_id)


func remove_entity(entity_id: String) -> void:
	provoker_by_target_entity_id.erase(entity_id)
	for target_entity_id: String in provoker_by_target_entity_id.keys():
		if provoker_by_target_entity_id[target_entity_id] == entity_id:
			provoker_by_target_entity_id.erase(target_entity_id)


func remove_target(target_entity_id: String) -> void:
	provoker_by_target_entity_id.erase(target_entity_id)


func get_target_entity_ids() -> Array[String]:
	var target_entity_ids: Array[String] = []
	for target_entity_id: String in provoker_by_target_entity_id.keys():
		target_entity_ids.append(target_entity_id)
	return target_entity_ids


func create_snapshot() -> Dictionary:
	return {"provoker_by_target_entity_id": provoker_by_target_entity_id.duplicate()}


func apply_snapshot(snapshot: Dictionary) -> void:
	provoker_by_target_entity_id.clear()
	var values: Dictionary = snapshot.get("provoker_by_target_entity_id", {}) as Dictionary
	for target_id_value: Variant in values.keys():
		provoker_by_target_entity_id[str(target_id_value)] = str(values[target_id_value])


func is_valid_snapshot(
	snapshot: Dictionary,
	valid_target_entity_ids: Array[String],
	valid_provoker_entity_ids: Array[String]
) -> bool:
	var values_variant: Variant = snapshot.get("provoker_by_target_entity_id", {})
	if not (values_variant is Dictionary):
		return false
	var values: Dictionary = values_variant as Dictionary
	if values.size() > NetworkProtocol.MAX_WORLD_RECORDS:
		return false
	for target_id_value: Variant in values.keys():
		var target_entity_id: String = str(target_id_value)
		var provoker_entity_id: String = str(values[target_id_value])
		if (
			not NetworkProtocol.is_valid_identifier(target_entity_id)
			or not NetworkProtocol.is_valid_identifier(provoker_entity_id)
			or target_entity_id not in valid_target_entity_ids
			or provoker_entity_id not in valid_provoker_entity_ids
		):
			return false
	return true
