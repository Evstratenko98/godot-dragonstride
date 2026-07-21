class_name CharacterInventorySnapshotCodec
extends RefCounted


static func create_snapshot(inventory: CharacterInventory) -> Dictionary:
	return {
		"entity_id": inventory.owner_entity_id,
		"revision": inventory.revision,
		"item_slots": _create_slot_records(inventory, CharacterInventory.INVENTORY_KIND_ITEM),
		"spell_slots": _create_slot_records(inventory, CharacterInventory.INVENTORY_KIND_SPELL),
	}


static func is_valid_authoritative_snapshot(
	inventory: CharacterInventory,
	snapshot: Dictionary,
	expected_entity_id: String
) -> bool:
	var item_slots_value: Variant = snapshot.get("item_slots")
	var spell_slots_value: Variant = snapshot.get("spell_slots")
	if (
		str(snapshot.get("entity_id", "")) != expected_entity_id
		or int(snapshot.get("revision", -1)) < 0
		or not (item_slots_value is Array)
		or not (spell_slots_value is Array)
		or (item_slots_value as Array).size() > CharacterInventory.ITEM_SLOT_COUNT
		or (spell_slots_value as Array).size() > CharacterInventory.SPELL_SLOT_COUNT
		or not NetworkProtocol.is_valid_intent_payload(snapshot)
	):
		return false
	return (
		is_valid_slot_records(inventory, item_slots_value as Array, CharacterInventory.INVENTORY_KIND_ITEM)
		and is_valid_slot_records(inventory, spell_slots_value as Array, CharacterInventory.INVENTORY_KIND_SPELL)
	)


static func is_valid_slot_records(
	inventory: CharacterInventory,
	slot_records: Array,
	inventory_kind: String
) -> bool:
	var occupied_slot_indices: Dictionary[int, bool] = {}
	for record_variant: Variant in slot_records:
		if not (record_variant is Dictionary):
			return false
		var record: Dictionary = record_variant as Dictionary
		var slot_index: int = int(record.get("slot_index", -1))
		var item_id: String = str(record.get("item_id", ""))
		var quantity: int = int(record.get("quantity", 0))
		if slot_index < 0 or slot_index >= inventory.get_slot_count(inventory_kind):
			return false
		if occupied_slot_indices.has(slot_index):
			return false
		if not inventory.has_item_id(item_id) or inventory.get_inventory_kind_for_item_id(item_id) != inventory_kind:
			return false
		if quantity <= 0 or quantity > inventory.get_max_stack_size(item_id):
			return false
		occupied_slot_indices[slot_index] = true
	return true


static func _create_slot_records(
	inventory: CharacterInventory,
	inventory_kind: String
) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for slot_index: int in range(inventory.get_slot_count(inventory_kind)):
		var target_item: InventoryItem = inventory.get_item_at_slot(inventory_kind, slot_index)
		if target_item == null:
			continue
		records.append({
			"slot_index": slot_index,
			"item_id": inventory.get_item_id(target_item),
			"quantity": target_item.get_stack_size(),
		})
	return records
