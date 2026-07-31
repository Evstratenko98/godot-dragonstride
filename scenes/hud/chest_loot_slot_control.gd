class_name ChestLootSlotControl
extends PanelContainer

const SLOT_SIZE := Vector2(38.0, 38.0)
const DRAG_PREVIEW_Z_INDEX := 4096

var dialog: ChestLootDialog = null
var chest_id: String = ""
var item_id: String = ""
var inventory_kind: String = ""
var amount: int = 0
var inventory_item: InventoryItem = null
var item_control: CtrlInventoryItem = null


func _ready() -> void:
	custom_minimum_size = SLOT_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", InventorySlotStyle.create())
	item_control = CtrlInventoryItem.new()
	item_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_control.custom_minimum_size = SLOT_SIZE
	item_control.item = inventory_item
	add_child.call_deferred(item_control)


func configure_reward(
	new_dialog: ChestLootDialog,
	new_chest_id: String,
	new_item_id: String,
	new_inventory_kind: String,
	new_amount: int,
	new_inventory_item: InventoryItem
) -> void:
	dialog = new_dialog
	chest_id = new_chest_id
	item_id = new_item_id
	inventory_kind = new_inventory_kind
	amount = new_amount
	inventory_item = new_inventory_item


func _get_drag_data(_at_position: Vector2) -> Variant:
	if inventory_item == null or dialog == null or not dialog.can_drag_reward():
		return null
	var preview: CtrlInventoryItem = CtrlInventoryItem.new()
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.custom_minimum_size = SLOT_SIZE
	preview.size = SLOT_SIZE
	preview.position = -SLOT_SIZE * 0.5
	preview.item = inventory_item
	var preview_root: Control = Control.new()
	preview_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_root.z_as_relative = false
	preview_root.z_index = DRAG_PREVIEW_Z_INDEX
	preview_root.add_child.call_deferred(preview)
	set_drag_preview(preview_root)
	return ChestLootDragData.create(chest_id, item_id, inventory_kind, amount)
