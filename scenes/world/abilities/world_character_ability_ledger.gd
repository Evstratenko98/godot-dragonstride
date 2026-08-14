class_name WorldCharacterAbilityLedger
extends RefCounted

var cooldowns_by_entity_id: Dictionary[String, int] = {}
var reservation_request_ids_by_entity_id: Dictionary[String, int] = {}


func clear() -> void:
	cooldowns_by_entity_id.clear()
	reservation_request_ids_by_entity_id.clear()


func can_use(entity_id: String) -> bool:
	return (
		not entity_id.is_empty()
		and get_remaining_turns(entity_id) == 0
		and not reservation_request_ids_by_entity_id.has(entity_id)
	)


func can_validate_action(action: WorldActionRecord) -> bool:
	if action == null or action.actor_entity_id.is_empty() or action.request_id <= 0:
		return false
	if get_remaining_turns(action.actor_entity_id) > 0:
		return false
	return (
		not reservation_request_ids_by_entity_id.has(action.actor_entity_id)
		or int(reservation_request_ids_by_entity_id[action.actor_entity_id]) == action.request_id
	)


func get_remaining_turns(entity_id: String) -> int:
	return maxi(int(cooldowns_by_entity_id.get(entity_id, 0)), 0)


func reserve(action: WorldActionRecord) -> String:
	if action == null or action.request_id <= 0 or not can_use(action.actor_entity_id):
		return WorldCharacterAbilities.REJECTION_ABILITY_UNAVAILABLE
	reservation_request_ids_by_entity_id[action.actor_entity_id] = action.request_id
	return ""


func release(action: WorldActionRecord) -> void:
	if (
		action != null
		and int(reservation_request_ids_by_entity_id.get(action.actor_entity_id, -1)) == action.request_id
	):
		reservation_request_ids_by_entity_id.erase(action.actor_entity_id)


func record_use(action: WorldActionRecord, ability_id: String) -> void:
	if action == null:
		return
	release(action)
	cooldowns_by_entity_id[action.actor_entity_id] = CharacterAbilityCatalog.get_cooldown_turns(ability_id)


func begin_player_turn(members: Array[PlayerCharacter]) -> void:
	for member: PlayerCharacter in members:
		var remaining_turns: int = get_remaining_turns(member.entity_id)
		if remaining_turns <= 1:
			cooldowns_by_entity_id.erase(member.entity_id)
		else:
			cooldowns_by_entity_id[member.entity_id] = remaining_turns - 1


func create_snapshot() -> Dictionary:
	return {"cooldowns_by_entity_id": cooldowns_by_entity_id.duplicate()}


func apply_snapshot(snapshot: Dictionary) -> void:
	cooldowns_by_entity_id.clear()
	reservation_request_ids_by_entity_id.clear()
	var values: Dictionary = snapshot.get("cooldowns_by_entity_id", {}) as Dictionary
	for entity_id_value: Variant in values.keys():
		cooldowns_by_entity_id[str(entity_id_value)] = int(values[entity_id_value])


func is_valid_snapshot(snapshot: Dictionary, valid_entity_ids: Array[String]) -> bool:
	var values_variant: Variant = snapshot.get("cooldowns_by_entity_id", {})
	if not (values_variant is Dictionary):
		return false
	var values: Dictionary = values_variant as Dictionary
	if values.size() > NetworkProtocol.MAX_PLAYER_CHARACTERS:
		return false
	for entity_id_value: Variant in values.keys():
		var entity_id: String = str(entity_id_value)
		var remaining_value: Variant = values[entity_id_value]
		if (
			not NetworkProtocol.is_valid_identifier(entity_id)
			or entity_id not in valid_entity_ids
			or not (remaining_value is int)
			or int(remaining_value) < 1
			or int(remaining_value) > CharacterAbilityCatalog.KNIGHT_TAUNT_COOLDOWN_TURNS
		):
			return false
	return true
