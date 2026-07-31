class_name ChestLootDragData
extends RefCounted

var chest_id: String = ""
var item_id: String = ""
var inventory_kind: String = ""
var amount: int = 0


static func create(
	new_chest_id: String,
	new_item_id: String,
	new_inventory_kind: String,
	new_amount: int
) -> ChestLootDragData:
	var data: ChestLootDragData = ChestLootDragData.new()
	data.chest_id = new_chest_id
	data.item_id = new_item_id
	data.inventory_kind = new_inventory_kind
	data.amount = new_amount
	return data
