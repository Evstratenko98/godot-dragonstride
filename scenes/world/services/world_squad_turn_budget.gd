class_name WorldSquadTurnBudget
extends RefCounted

const MAX_STEPS_PER_MEMBER := 10
const MAX_ATTACKS_PER_MEMBER := 1
const MAX_INTERACTIONS_PER_MEMBER := 1

var steps_left_by_entity_id: Dictionary[String, int] = {}
var attacks_left_by_entity_id: Dictionary[String, int] = {}
var interactions_left_by_entity_id: Dictionary[String, int] = {}


func reset() -> void:
	steps_left_by_entity_id.clear()
	attacks_left_by_entity_id.clear()
	interactions_left_by_entity_id.clear()


func begin_turn(available_entity_ids: Array[String]) -> void:
	reset()
	for entity_id: String in available_entity_ids:
		steps_left_by_entity_id[entity_id] = MAX_STEPS_PER_MEMBER
		attacks_left_by_entity_id[entity_id] = MAX_ATTACKS_PER_MEMBER
		interactions_left_by_entity_id[entity_id] = MAX_INTERACTIONS_PER_MEMBER


func can_move(entity_id: String) -> bool:
	return not entity_id.is_empty() and get_steps_left(entity_id) > 0


func can_attack(entity_id: String) -> bool:
	return int(attacks_left_by_entity_id.get(entity_id, 0)) > 0


func can_interact(entity_id: String) -> bool:
	return int(interactions_left_by_entity_id.get(entity_id, 0)) > 0


func consume_steps(entity_id: String, step_count: int) -> bool:
	var steps_left: int = get_steps_left(entity_id)
	if step_count <= 0 or step_count > steps_left:
		return false
	steps_left_by_entity_id[entity_id] = steps_left - step_count
	return true


func consume_attack(entity_id: String) -> bool:
	if not can_attack(entity_id):
		return false
	attacks_left_by_entity_id[entity_id] = int(attacks_left_by_entity_id[entity_id]) - 1
	return true


func consume_interaction(entity_id: String) -> bool:
	if not can_interact(entity_id):
		return false
	interactions_left_by_entity_id[entity_id] = int(interactions_left_by_entity_id[entity_id]) - 1
	return true


func get_attacks_left(entity_id: String) -> int:
	return int(attacks_left_by_entity_id.get(entity_id, 0))


func get_steps_left(entity_id: String) -> int:
	return int(steps_left_by_entity_id.get(entity_id, 0))


func get_interactions_left(entity_id: String) -> int:
	return int(interactions_left_by_entity_id.get(entity_id, 0))


func create_snapshot() -> Dictionary:
	return {
		"steps_left_by_entity_id": steps_left_by_entity_id.duplicate(),
		"attacks_left_by_entity_id": attacks_left_by_entity_id.duplicate(),
		"interactions_left_by_entity_id": interactions_left_by_entity_id.duplicate(),
	}


func apply_snapshot(snapshot: Dictionary) -> void:
	steps_left_by_entity_id.clear()
	attacks_left_by_entity_id.clear()
	interactions_left_by_entity_id.clear()
	var steps_value: Dictionary = snapshot.get("steps_left_by_entity_id", {}) as Dictionary
	for entity_id_value: Variant in steps_value.keys():
		steps_left_by_entity_id[str(entity_id_value)] = int(steps_value[entity_id_value])
	var attacks_value: Dictionary = snapshot.get("attacks_left_by_entity_id", {}) as Dictionary
	for entity_id_value: Variant in attacks_value.keys():
		attacks_left_by_entity_id[str(entity_id_value)] = int(attacks_value[entity_id_value])
	var interactions_value: Dictionary = snapshot.get("interactions_left_by_entity_id", {}) as Dictionary
	for entity_id_value: Variant in interactions_value.keys():
		interactions_left_by_entity_id[str(entity_id_value)] = int(interactions_value[entity_id_value])


func is_valid_snapshot(snapshot: Dictionary, valid_entity_ids: Array[String]) -> bool:
	var steps_value: Variant = snapshot.get("steps_left_by_entity_id")
	var attacks_value: Variant = snapshot.get("attacks_left_by_entity_id")
	var interactions_value: Variant = snapshot.get("interactions_left_by_entity_id")
	if not _is_valid_member_values(steps_value, valid_entity_ids, MAX_STEPS_PER_MEMBER):
		return false
	if not _is_valid_member_values(attacks_value, valid_entity_ids, MAX_ATTACKS_PER_MEMBER):
		return false
	if not _is_valid_member_values(interactions_value, valid_entity_ids, MAX_INTERACTIONS_PER_MEMBER):
		return false
	return _have_matching_member_keys(steps_value, attacks_value, interactions_value)


func _is_valid_member_values(value: Variant, valid_entity_ids: Array[String], maximum_value: int) -> bool:
	if not (value is Dictionary):
		return false
	var values: Dictionary = value as Dictionary
	if values.size() > NetworkProtocol.MAX_PLAYER_CHARACTERS:
		return false
	for entity_id_value: Variant in values.keys():
		var entity_id: String = str(entity_id_value)
		var member_value_variant: Variant = values[entity_id_value]
		if not (member_value_variant is int):
			return false
		var member_value: int = int(member_value_variant)
		if entity_id not in valid_entity_ids or member_value < 0 or member_value > maximum_value:
			return false
	return true


func _have_matching_member_keys(first: Variant, second: Variant, third: Variant) -> bool:
	var first_values: Dictionary = first as Dictionary
	var second_values: Dictionary = second as Dictionary
	var third_values: Dictionary = third as Dictionary
	if first_values.size() != second_values.size() or first_values.size() != third_values.size():
		return false
	for entity_id_value: Variant in first_values.keys():
		if not second_values.has(entity_id_value) or not third_values.has(entity_id_value):
			return false
	return true
