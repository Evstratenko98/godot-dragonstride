class_name ChestLootRecord
extends RefCounted

const KEY_CHEST_ID := "chest_id"
const KEY_OPENER_ENTITY_ID := "opener_entity_id"
const KEY_LOOT_ENTRIES := "loot_entries"
const ENTRY_KEY_ITEM_ID := "item_id"
const ENTRY_KEY_QUANTITY := "quantity"

var chest_id: String = ""
var opener_entity_id: String = ""
var loot_entries: Array[Dictionary] = []
var claim_reservation_action_id: int = 0
var is_local_request_pending: bool = false


static func create(
	new_chest_id: String,
	new_opener_entity_id: String,
	new_loot_entries: Array[Dictionary]
) -> ChestLootRecord:
	var record: ChestLootRecord = ChestLootRecord.new()
	record.chest_id = new_chest_id
	record.opener_entity_id = new_opener_entity_id
	record.loot_entries = new_loot_entries.duplicate(true)
	return record


static func create_single(
	new_chest_id: String,
	new_opener_entity_id: String,
	new_item_id: String,
	new_quantity: int
) -> ChestLootRecord:
	return create(new_chest_id, new_opener_entity_id, [{
		ENTRY_KEY_ITEM_ID: new_item_id,
		ENTRY_KEY_QUANTITY: new_quantity,
	}])


static func from_dictionary(record_data: Dictionary) -> ChestLootRecord:
	var entries: Array[Dictionary] = []
	for entry_value: Variant in record_data.get(KEY_LOOT_ENTRIES, []):
		if entry_value is Dictionary:
			entries.append((entry_value as Dictionary).duplicate(true))
	return create(
		str(record_data.get(KEY_CHEST_ID, "")),
		str(record_data.get(KEY_OPENER_ENTITY_ID, "")),
		entries
	)


func get_item_id(entry_index: int = 0) -> String:
	if entry_index < 0 or entry_index >= loot_entries.size():
		return ""
	return str(loot_entries[entry_index].get(ENTRY_KEY_ITEM_ID, ""))


func get_quantity(entry_index: int = 0) -> int:
	if entry_index < 0 or entry_index >= loot_entries.size():
		return 0
	return int(loot_entries[entry_index].get(ENTRY_KEY_QUANTITY, 0))


func to_dictionary() -> Dictionary:
	return {
		KEY_CHEST_ID: chest_id,
		KEY_OPENER_ENTITY_ID: opener_entity_id,
		KEY_LOOT_ENTRIES: loot_entries.duplicate(true),
	}
