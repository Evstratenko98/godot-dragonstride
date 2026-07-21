class_name WorldSpellUsageLedger
extends RefCounted

var used_slots: Dictionary[String, Dictionary] = {}
var reserved_slots: Dictionary[String, bool] = {}


func clear() -> void:
	used_slots.clear()
	reserved_slots.clear()


func get_remaining_uses(entity_id: String, slot_index: int, is_turn_mode_enabled: bool) -> int:
	if not is_turn_mode_enabled:
		return 1
	return 0 if is_used(entity_id, slot_index) or is_reserved(entity_id, slot_index) else 1


func reserve(action: WorldActionRecord) -> String:
	var slot_index: int = int(action.payload.get("spell_slot_index", -1))
	var reservation_key: String = make_key(action.actor_entity_id, slot_index)
	if slot_index < 0 or reserved_slots.has(reservation_key):
		return WorldSpells.REJECTION_SPELL_UNAVAILABLE
	reserved_slots[reservation_key] = true
	action.payload["reservation_key"] = reservation_key
	return ""


func release(action: WorldActionRecord) -> bool:
	var reservation_key: String = str(action.payload.get("reservation_key", ""))
	if reservation_key.is_empty():
		return false
	reserved_slots.erase(reservation_key)
	action.payload.erase("reservation_key")
	return true


func create_snapshot() -> Dictionary:
	return {"used_spell_slots": used_slots.duplicate(true)}


func apply_snapshot(snapshot: Dictionary) -> void:
	var value: Variant = snapshot.get("used_spell_slots", {})
	used_slots = (value as Dictionary).duplicate(true)
	reserved_slots.clear()


func is_valid_snapshot(snapshot: Dictionary) -> bool:
	var value: Variant = snapshot.get("used_spell_slots", {})
	if not (value is Dictionary) or (value as Dictionary).size() > NetworkProtocol.MAX_ROSTER_SIZE:
		return false
	for entity_id_value: Variant in (value as Dictionary).keys():
		var entity_id: String = str(entity_id_value)
		var slots_value: Variant = (value as Dictionary)[entity_id_value]
		if not NetworkProtocol.is_valid_identifier(entity_id) or not (slots_value is Dictionary):
			return false
		var slots: Dictionary = slots_value as Dictionary
		if slots.size() > CharacterInventory.SPELL_SLOT_COUNT:
			return false
		for slot_index_value: Variant in slots.keys():
			var slot_index: int = int(slot_index_value)
			if slot_index < 0 or slot_index >= CharacterInventory.SPELL_SLOT_COUNT or not bool(slots[slot_index_value]):
				return false
	return true


func record_use(entity_id: String, slot_index: int) -> void:
	var entity_slots: Dictionary = used_slots.get(entity_id, {}) as Dictionary
	entity_slots[slot_index] = true
	used_slots[entity_id] = entity_slots


func remove_use(entity_id: String, slot_index: int) -> void:
	var entity_slots: Dictionary = used_slots.get(entity_id, {}) as Dictionary
	entity_slots.erase(slot_index)
	if entity_slots.is_empty():
		used_slots.erase(entity_id)
	else:
		used_slots[entity_id] = entity_slots


func is_used(entity_id: String, slot_index: int) -> bool:
	var entity_slots: Dictionary = used_slots.get(entity_id, {}) as Dictionary
	return bool(entity_slots.get(slot_index, false))


func is_reserved(entity_id: String, slot_index: int) -> bool:
	return reserved_slots.has(make_key(entity_id, slot_index))


func is_reservation_key_reserved(reservation_key: String) -> bool:
	return reserved_slots.has(reservation_key)


func make_key(entity_id: String, slot_index: int) -> String:
	return "%s:%d" % [entity_id, slot_index]
