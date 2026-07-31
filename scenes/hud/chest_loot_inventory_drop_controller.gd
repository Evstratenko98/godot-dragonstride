class_name ChestLootInventoryDropController
extends RefCounted

var dialog: ChestLootDialog = null
var character_inventory: CharacterInventory = null


func configure_dialog(new_dialog: ChestLootDialog) -> void:
	dialog = new_dialog


func bind_inventory(new_character_inventory: CharacterInventory) -> void:
	character_inventory = new_character_inventory


func can_drop(
	data: ChestLootDragData,
	target_inventory_kind: String,
	target_slot_index: int
) -> bool:
	return (
		data != null
		and dialog != null
		and character_inventory != null
		and data.inventory_kind == target_inventory_kind
		and dialog.matches_active_reward(data)
		and character_inventory.can_add_item_at(data.item_id, data.amount, target_slot_index)
	)


func request_drop(
	data: ChestLootDragData,
	target_inventory_kind: String,
	target_slot_index: int
) -> void:
	if can_drop(data, target_inventory_kind, target_slot_index):
		dialog.request_claim(target_inventory_kind, target_slot_index)


func is_request_pending() -> bool:
	return dialog != null and dialog.is_request_pending_for_inventory_changes()
