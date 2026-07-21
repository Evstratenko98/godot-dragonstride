class_name CharacterInventory
extends Node

signal inventory_changed()

enum MutationResult {
	NONE,
	UNKNOWN_ITEM,
	INVALID_KIND,
	INVALID_SLOT,
	EMPTY_SLOT,
	INSUFFICIENT_CAPACITY,
	STALE_REVISION,
	EFFECT_UNAVAILABLE,
	EFFECT_FAILED,
	MUTATION_FAILED,
}

const ITEM_SLOT_COUNT := 5
const SPELL_SLOT_COUNT := 5
const DEFAULT_MAX_STACK_SIZE := 10
const INVENTORY_KIND_ITEM := "item"
const INVENTORY_KIND_SPELL := "spell"
const ITEM_ID_MEAT := "meat"
const ITEM_ID_PRECISION_STONE := "precision_stone"
const ITEM_ID_METEOR_SCROLL := "meteor_scroll"
const KNOWN_ITEM_IDS: PackedStringArray = [
	ITEM_ID_MEAT,
	ITEM_ID_PRECISION_STONE,
	ITEM_ID_METEOR_SCROLL,
]

@onready var item_inventory: Inventory = get_node("Inventory") as Inventory
@onready var item_grid_constraint: GridConstraint = get_node("Inventory/GridConstraint") as GridConstraint
@onready var spell_inventory: Inventory = get_node("SpellInventory") as Inventory
@onready var spell_grid_constraint: GridConstraint = get_node("SpellInventory/GridConstraint") as GridConstraint

var revision: int = 0
var owner_entity_id: String = ""
var last_mutation_result: MutationResult = MutationResult.NONE


func configure_owner(new_owner_entity_id: String) -> void:
	owner_entity_id = new_owner_entity_id


func has_item_id(item_id: String) -> bool:
	return item_id in KNOWN_ITEM_IDS


func get_inventory_kind_for_item_id(item_id: String) -> String:
	if not has_item_id(item_id):
		return ""

	var prototype_item: InventoryItem = InventoryItem.new(item_inventory.protoset, item_id)
	return str(prototype_item.get_property("inventory_kind", INVENTORY_KIND_ITEM))


func try_add_item(item_id: String, amount: int) -> bool:
	if not has_item_id(item_id) or amount <= 0:
		last_mutation_result = MutationResult.UNKNOWN_ITEM
		return false

	var inventory_kind: String = get_inventory_kind_for_item_id(item_id)
	var target_inventory: Inventory = _get_inventory(inventory_kind)
	var target_grid: GridConstraint = _get_grid_constraint(inventory_kind)
	if target_inventory == null or target_grid == null:
		last_mutation_result = MutationResult.INVALID_KIND
		return false
	if get_available_capacity(item_id) < amount:
		last_mutation_result = MutationResult.INSUFFICIENT_CAPACITY
		return false
	var rollback_snapshot: Dictionary = create_snapshot()

	var remaining_amount: int = amount
	for target_item_variant: Variant in target_inventory.get_items_with_prototype_id(item_id):
		var inventory_item: InventoryItem = target_item_variant as InventoryItem
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
		var free_slot_index: int = _find_free_slot_index(inventory_kind)
		if free_slot_index < 0:
			restore_snapshot(rollback_snapshot)
			last_mutation_result = MutationResult.MUTATION_FAILED
			return false
		var new_stack: InventoryItem = InventoryItem.new(target_inventory.protoset, item_id)
		var stack_amount: int = mini(new_stack.get_max_stack_size(), remaining_amount)
		if not new_stack.set_stack_size(stack_amount):
			restore_snapshot(rollback_snapshot)
			last_mutation_result = MutationResult.MUTATION_FAILED
			return false
		if not target_grid.add_item_at(new_stack, Vector2i(free_slot_index, 0)):
			restore_snapshot(rollback_snapshot)
			last_mutation_result = MutationResult.MUTATION_FAILED
			return false
		remaining_amount -= stack_amount

	_commit_change()
	last_mutation_result = MutationResult.NONE
	return true


func try_move_stack(inventory_kind: String, source_slot_index: int, target_slot_index: int) -> bool:
	if not _is_valid_slot_index(inventory_kind, source_slot_index):
		last_mutation_result = MutationResult.INVALID_SLOT
		return false
	if not _is_valid_slot_index(inventory_kind, target_slot_index):
		last_mutation_result = MutationResult.INVALID_SLOT
		return false
	if source_slot_index == target_slot_index:
		return false
	var rollback_snapshot: Dictionary = create_snapshot()

	var source_item: InventoryItem = get_item_at_slot(inventory_kind, source_slot_index)
	if source_item == null:
		last_mutation_result = MutationResult.EMPTY_SLOT
		return false

	var target_item: InventoryItem = get_item_at_slot(inventory_kind, target_slot_index)
	var grid_constraint: GridConstraint = _get_grid_constraint(inventory_kind)
	var was_changed: bool = false
	if target_item == null:
		was_changed = grid_constraint.move_item_to(source_item, Vector2i(target_slot_index, 0))
	elif source_item.compatible_with(target_item):
		was_changed = source_item.merge_into(target_item, true)
	else:
		was_changed = InventoryItem.swap(source_item, target_item)

	if not was_changed:
		restore_snapshot(rollback_snapshot)
		last_mutation_result = MutationResult.MUTATION_FAILED
		return false

	_commit_change()
	last_mutation_result = MutationResult.NONE
	return true


func try_delete_stack(inventory_kind: String, slot_index: int) -> bool:
	if not _is_valid_slot_index(inventory_kind, slot_index):
		last_mutation_result = MutationResult.INVALID_SLOT
		return false

	var target_item: InventoryItem = get_item_at_slot(inventory_kind, slot_index)
	var target_inventory: Inventory = _get_inventory(inventory_kind)
	if target_item == null or target_inventory == null or not target_inventory.remove_item(target_item):
		last_mutation_result = MutationResult.EMPTY_SLOT if target_item == null else MutationResult.MUTATION_FAILED
		return false

	_commit_change()
	last_mutation_result = MutationResult.NONE
	return true


func try_consume_one(inventory_kind: String, slot_index: int) -> bool:
	if not _is_valid_slot_index(inventory_kind, slot_index):
		last_mutation_result = MutationResult.INVALID_SLOT
		return false

	var target_item: InventoryItem = get_item_at_slot(inventory_kind, slot_index)
	var target_inventory: Inventory = _get_inventory(inventory_kind)
	if target_item == null or target_inventory == null:
		last_mutation_result = MutationResult.EMPTY_SLOT
		return false

	var stack_size: int = target_item.get_stack_size()
	if stack_size <= 0:
		last_mutation_result = MutationResult.EMPTY_SLOT
		return false
	if stack_size == 1:
		if not target_inventory.remove_item(target_item):
			return false
	elif not target_item.set_stack_size(stack_size - 1):
		return false

	_commit_change()
	last_mutation_result = MutationResult.NONE
	return true


func get_item_at_slot(inventory_kind: String, slot_index: int) -> InventoryItem:
	if not _is_valid_slot_index(inventory_kind, slot_index):
		return null

	var grid_constraint: GridConstraint = _get_grid_constraint(inventory_kind)
	return grid_constraint.get_item_at(Vector2i(slot_index, 0))


func get_item_id_at_slot(inventory_kind: String, slot_index: int) -> String:
	return _get_item_id(get_item_at_slot(inventory_kind, slot_index))


func is_item_usable(slot_index: int) -> bool:
	var target_item: InventoryItem = get_item_at_slot(INVENTORY_KIND_ITEM, slot_index)
	if target_item == null:
		return false

	return bool(target_item.get_property("is_usable", false))


func get_item_use_effect_id(slot_index: int) -> String:
	var target_item: InventoryItem = get_item_at_slot(INVENTORY_KIND_ITEM, slot_index)
	if target_item == null:
		return ""

	return str(target_item.get_property("use_effect_id", ""))


func get_spell_id_at_slot(slot_index: int) -> String:
	var target_item: InventoryItem = get_item_at_slot(INVENTORY_KIND_SPELL, slot_index)
	if target_item == null:
		return ""

	return str(target_item.get_property("spell_id", ""))


func get_spell_count(spell_id: String) -> int:
	if spell_id.is_empty():
		return 0

	var total_count: int = 0
	for item_variant: Variant in spell_inventory.get_items():
		var inventory_item: InventoryItem = item_variant as InventoryItem
		if inventory_item == null:
			continue
		if str(inventory_item.get_property("spell_id", "")) == spell_id:
			total_count += inventory_item.get_stack_size()

	return total_count


func get_available_capacity(item_id: String) -> int:
	if not has_item_id(item_id):
		return 0

	var inventory_kind: String = get_inventory_kind_for_item_id(item_id)
	var target_inventory: Inventory = _get_inventory(inventory_kind)
	if target_inventory == null:
		return 0

	var prototype_item: InventoryItem = InventoryItem.new(target_inventory.protoset, item_id)
	var maximum_stack_size: int = prototype_item.get_max_stack_size()
	var capacity: int = 0
	for slot_index: int in range(_get_slot_count(inventory_kind)):
		var target_item: InventoryItem = get_item_at_slot(inventory_kind, slot_index)
		if target_item == null:
			capacity += maximum_stack_size
		elif _get_item_id(target_item) == item_id:
			capacity += target_item.get_free_stack_space()

	return capacity


func create_snapshot() -> Dictionary:
	return CharacterInventorySnapshotCodec.create_snapshot(self)


func apply_snapshot(snapshot: Dictionary) -> bool:
	var snapshot_revision: int = int(snapshot.get("revision", -1))
	if snapshot_revision <= revision:
		return false

	var item_slot_records: Array = snapshot.get("item_slots", []) as Array
	var spell_slot_records: Array = snapshot.get("spell_slots", []) as Array
	if not CharacterInventorySnapshotCodec.is_valid_slot_records(self, item_slot_records, INVENTORY_KIND_ITEM):
		return false
	if not CharacterInventorySnapshotCodec.is_valid_slot_records(self, spell_slot_records, INVENTORY_KIND_SPELL):
		return false

	return _replace_with_snapshot(snapshot, true)


func restore_snapshot(snapshot: Dictionary) -> bool:
	var item_slot_records: Array = snapshot.get("item_slots", []) as Array
	var spell_slot_records: Array = snapshot.get("spell_slots", []) as Array
	if not CharacterInventorySnapshotCodec.is_valid_slot_records(self, item_slot_records, INVENTORY_KIND_ITEM):
		return false
	if not CharacterInventorySnapshotCodec.is_valid_slot_records(self, spell_slot_records, INVENTORY_KIND_SPELL):
		return false
	return _replace_with_snapshot(snapshot, true)


func apply_authoritative_snapshot(snapshot: Dictionary) -> bool:
	if not is_valid_authoritative_snapshot(snapshot, owner_entity_id):
		return false
	var item_slot_records: Array = snapshot.get("item_slots", []) as Array
	var spell_slot_records: Array = snapshot.get("spell_slots", []) as Array
	return _replace_with_snapshot(snapshot, true)


func is_valid_authoritative_snapshot(snapshot: Dictionary, expected_entity_id: String) -> bool:
	return CharacterInventorySnapshotCodec.is_valid_authoritative_snapshot(
		self,
		snapshot,
		expected_entity_id
	)


func matches_revision(expected_revision: int) -> bool:
	return expected_revision >= 0 and revision == expected_revision


func get_last_mutation_result() -> MutationResult:
	return last_mutation_result


func _commit_change() -> void:
	revision += 1
	inventory_changed.emit()


func _replace_with_snapshot(snapshot: Dictionary, should_emit: bool) -> bool:
	var previous_snapshot: Dictionary = create_snapshot()
	var item_slot_records: Array = snapshot.get("item_slots", []) as Array
	var spell_slot_records: Array = snapshot.get("spell_slots", []) as Array
	_clear_inventories()
	if (
		not _apply_slot_records(item_slot_records, INVENTORY_KIND_ITEM)
		or not _apply_slot_records(spell_slot_records, INVENTORY_KIND_SPELL)
	):
		_clear_inventories()
		_apply_slot_records(previous_snapshot.get("item_slots", []) as Array, INVENTORY_KIND_ITEM)
		_apply_slot_records(previous_snapshot.get("spell_slots", []) as Array, INVENTORY_KIND_SPELL)
		revision = int(previous_snapshot.get("revision", revision))
		return false
	revision = int(snapshot.get("revision", revision))
	if should_emit:
		inventory_changed.emit()
	return true


func _apply_slot_records(slot_records: Array, inventory_kind: String) -> bool:
	var target_inventory: Inventory = _get_inventory(inventory_kind)
	var target_grid: GridConstraint = _get_grid_constraint(inventory_kind)
	for record_variant: Variant in slot_records:
		var record: Dictionary = record_variant as Dictionary
		var item_id: String = str(record.get("item_id", ""))
		var quantity: int = int(record.get("quantity", 0))
		var slot_index: int = int(record.get("slot_index", -1))
		var target_item: InventoryItem = InventoryItem.new(target_inventory.protoset, item_id)
		if not target_item.set_stack_size(quantity):
			return false
		if not target_grid.add_item_at(target_item, Vector2i(slot_index, 0)):
			return false

	return true


func _find_free_slot_index(inventory_kind: String) -> int:
	for slot_index: int in range(_get_slot_count(inventory_kind)):
		if get_item_at_slot(inventory_kind, slot_index) == null:
			return slot_index

	return -1


func _is_valid_slot_index(inventory_kind: String, slot_index: int) -> bool:
	return slot_index >= 0 and slot_index < _get_slot_count(inventory_kind)


func _get_item_id(target_item: InventoryItem) -> String:
	if target_item == null or target_item.get_prototype() == null:
		return ""

	return target_item.get_prototype().get_prototype_id()


func get_max_stack_size(item_id: String) -> int:
	if not has_item_id(item_id):
		return DEFAULT_MAX_STACK_SIZE

	var target_inventory: Inventory = _get_inventory(get_inventory_kind_for_item_id(item_id))
	var prototype_item: InventoryItem = InventoryItem.new(target_inventory.protoset, item_id)
	return prototype_item.get_max_stack_size()


func _get_inventory(inventory_kind: String) -> Inventory:
	if inventory_kind == INVENTORY_KIND_ITEM:
		return item_inventory
	if inventory_kind == INVENTORY_KIND_SPELL:
		return spell_inventory

	return null


func _get_grid_constraint(inventory_kind: String) -> GridConstraint:
	if inventory_kind == INVENTORY_KIND_ITEM:
		return item_grid_constraint
	if inventory_kind == INVENTORY_KIND_SPELL:
		return spell_grid_constraint

	return null


func _get_slot_count(inventory_kind: String) -> int:
	if inventory_kind == INVENTORY_KIND_ITEM:
		return ITEM_SLOT_COUNT
	if inventory_kind == INVENTORY_KIND_SPELL:
		return SPELL_SLOT_COUNT

	return 0


func get_slot_count(inventory_kind: String) -> int:
	return _get_slot_count(inventory_kind)


func get_item_id(target_item: InventoryItem) -> String:
	return _get_item_id(target_item)


func _clear_inventories() -> void:
	item_inventory.clear()
	spell_inventory.clear()
