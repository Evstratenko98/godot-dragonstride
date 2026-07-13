class_name CharacterInventory
extends Node

signal inventory_changed()

const SLOT_COUNT := 5
const DEFAULT_MAX_STACK_SIZE := 10
const ITEM_ID_MEAT := "meat"
const KNOWN_ITEM_IDS: PackedStringArray = [ITEM_ID_MEAT]

@onready var inventory: Inventory = get_node("Inventory") as Inventory
@onready var grid_constraint: GridConstraint = get_node("Inventory/GridConstraint") as GridConstraint

var revision: int = 0
var owner_entity_id: String = ""


func configure_owner(new_owner_entity_id: String) -> void:
	owner_entity_id = new_owner_entity_id


func has_item_id(item_id: String) -> bool:
	return item_id in KNOWN_ITEM_IDS


func try_add_item(item_id: String, amount: int) -> bool:
	if not has_item_id(item_id) or amount <= 0:
		return false
	if get_available_capacity(item_id) < amount:
		return false

	var remaining_amount: int = amount
	for target_item in inventory.get_items_with_prototype_id(item_id):
		var inventory_item: InventoryItem = target_item as InventoryItem
		if inventory_item == null:
			continue
		var added_amount: int = mini(inventory_item.get_free_stack_space(), remaining_amount)
		if added_amount <= 0:
			continue
		inventory_item.set_stack_size(inventory_item.get_stack_size() + added_amount)
		remaining_amount -= added_amount
		if remaining_amount == 0:
			break

	while remaining_amount > 0:
		var free_slot_index: int = _find_free_slot_index()
		if free_slot_index < 0:
			return false
		var new_stack: InventoryItem = InventoryItem.new(inventory.protoset, item_id)
		var stack_amount: int = mini(new_stack.get_max_stack_size(), remaining_amount)
		if not new_stack.set_stack_size(stack_amount):
			return false
		if not grid_constraint.add_item_at(new_stack, Vector2i(free_slot_index, 0)):
			return false
		remaining_amount -= stack_amount

	_commit_change()
	return true


func try_move_stack(source_slot_index: int, target_slot_index: int) -> bool:
	if not _is_valid_slot_index(source_slot_index) or not _is_valid_slot_index(target_slot_index):
		return false
	if source_slot_index == target_slot_index:
		return false

	var source_item: InventoryItem = get_item_at_slot(source_slot_index)
	if source_item == null:
		return false

	var target_item: InventoryItem = get_item_at_slot(target_slot_index)
	var was_changed: bool = false
	if target_item == null:
		was_changed = grid_constraint.move_item_to(source_item, Vector2i(target_slot_index, 0))
	elif source_item.compatible_with(target_item):
		was_changed = source_item.merge_into(target_item, true)
	else:
		was_changed = InventoryItem.swap(source_item, target_item)

	if not was_changed:
		return false

	_commit_change()
	return true


func try_delete_stack(slot_index: int) -> bool:
	if not _is_valid_slot_index(slot_index):
		return false

	var target_item: InventoryItem = get_item_at_slot(slot_index)
	if target_item == null or not inventory.remove_item(target_item):
		return false

	_commit_change()
	return true


func try_consume_one(slot_index: int) -> bool:
	if not _is_valid_slot_index(slot_index):
		return false

	var target_item: InventoryItem = get_item_at_slot(slot_index)
	if target_item == null:
		return false

	var stack_size: int = target_item.get_stack_size()
	if stack_size <= 0:
		return false
	if stack_size == 1:
		if not inventory.remove_item(target_item):
			return false
	elif not target_item.set_stack_size(stack_size - 1):
		return false

	_commit_change()
	return true


func get_item_at_slot(slot_index: int) -> InventoryItem:
	if not _is_valid_slot_index(slot_index):
		return null

	return grid_constraint.get_item_at(Vector2i(slot_index, 0))


func get_item_id_at_slot(slot_index: int) -> String:
	return _get_item_id(get_item_at_slot(slot_index))


func is_item_usable(slot_index: int) -> bool:
	var target_item: InventoryItem = get_item_at_slot(slot_index)
	if target_item == null:
		return false

	return bool(target_item.get_property("is_usable", false))


func get_item_use_effect_id(slot_index: int) -> String:
	var target_item: InventoryItem = get_item_at_slot(slot_index)
	if target_item == null:
		return ""

	return str(target_item.get_property("use_effect_id", ""))


func get_available_capacity(item_id: String) -> int:
	if not has_item_id(item_id):
		return 0

	var prototype_item: InventoryItem = InventoryItem.new(inventory.protoset, item_id)
	var maximum_stack_size: int = prototype_item.get_max_stack_size()
	var capacity: int = 0
	for slot_index in range(SLOT_COUNT):
		var target_item: InventoryItem = get_item_at_slot(slot_index)
		if target_item == null:
			capacity += maximum_stack_size
		elif _get_item_id(target_item) == item_id:
			capacity += target_item.get_free_stack_space()

	return capacity


func create_snapshot() -> Dictionary:
	var slots: Array[Dictionary] = []
	for slot_index in range(SLOT_COUNT):
		var target_item: InventoryItem = get_item_at_slot(slot_index)
		if target_item == null:
			continue
		slots.append({
			"slot_index": slot_index,
			"item_id": _get_item_id(target_item),
			"quantity": target_item.get_stack_size(),
		})

	return {
		"entity_id": owner_entity_id,
		"revision": revision,
		"slots": slots,
	}


func apply_snapshot(snapshot: Dictionary) -> bool:
	var snapshot_revision: int = int(snapshot.get("revision", -1))
	if snapshot_revision <= revision:
		return false

	var slot_records: Array = snapshot.get("slots", []) as Array
	if not _is_valid_snapshot(slot_records):
		return false

	inventory.clear()
	for record_variant: Variant in slot_records:
		var record: Dictionary = record_variant as Dictionary
		var item_id: String = str(record.get("item_id", ""))
		var quantity: int = int(record.get("quantity", 0))
		var slot_index: int = int(record.get("slot_index", -1))
		var target_item: InventoryItem = InventoryItem.new(inventory.protoset, item_id)
		if not target_item.set_stack_size(quantity):
			inventory.clear()
			return false
		if not grid_constraint.add_item_at(target_item, Vector2i(slot_index, 0)):
			inventory.clear()
			return false

	revision = snapshot_revision
	inventory_changed.emit()
	return true


func _commit_change() -> void:
	revision += 1
	inventory_changed.emit()


func _find_free_slot_index() -> int:
	for slot_index in range(SLOT_COUNT):
		if get_item_at_slot(slot_index) == null:
			return slot_index

	return -1


func _is_valid_slot_index(slot_index: int) -> bool:
	return slot_index >= 0 and slot_index < SLOT_COUNT


func _get_item_id(target_item: InventoryItem) -> String:
	if target_item == null or target_item.get_prototype() == null:
		return ""

	return target_item.get_prototype().get_prototype_id()


func _is_valid_snapshot(slot_records: Array) -> bool:
	var occupied_slot_indices: Dictionary = {}
	for record_variant: Variant in slot_records:
		if not (record_variant is Dictionary):
			return false
		var record: Dictionary = record_variant as Dictionary
		var slot_index: int = int(record.get("slot_index", -1))
		var item_id: String = str(record.get("item_id", ""))
		var quantity: int = int(record.get("quantity", 0))
		if not _is_valid_slot_index(slot_index) or occupied_slot_indices.has(slot_index):
			return false
		if not has_item_id(item_id) or quantity <= 0 or quantity > _get_max_stack_size(item_id):
			return false
		occupied_slot_indices[slot_index] = true

	return true


func _get_max_stack_size(item_id: String) -> int:
	if not has_item_id(item_id):
		return DEFAULT_MAX_STACK_SIZE

	var prototype_item: InventoryItem = InventoryItem.new(inventory.protoset, item_id)
	return prototype_item.get_max_stack_size()
