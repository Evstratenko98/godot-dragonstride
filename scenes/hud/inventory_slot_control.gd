class_name InventorySlotControl
extends PanelContainer

const SLOT_SIZE := Vector2(48.0, 48.0)

var inventory_bar: InventoryBar = null
var slot_index: int = -1
var is_trash: bool = false
var inventory_item: InventoryItem = null
var item_control: CtrlInventoryItem = null


func _ready() -> void:
	custom_minimum_size = SLOT_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", _create_slot_style())
	if is_trash:
		_add_label("Trash")
		return

	item_control = CtrlInventoryItem.new()
	item_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_control.custom_minimum_size = SLOT_SIZE
	item_control.item = inventory_item
	add_child(item_control)


func configure(new_inventory_bar: InventoryBar, new_slot_index: int, should_be_trash: bool = false) -> void:
	inventory_bar = new_inventory_bar
	slot_index = new_slot_index
	is_trash = should_be_trash


func set_inventory_item(new_inventory_item: InventoryItem) -> void:
	inventory_item = new_inventory_item
	if item_control != null:
		item_control.item = inventory_item


func _gui_input(event: InputEvent) -> void:
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event == null or mouse_event.button_index != MOUSE_BUTTON_RIGHT or not mouse_event.pressed:
		return

	accept_event()
	if is_trash or inventory_item == null or inventory_bar == null:
		return

	inventory_bar.request_use(slot_index)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if is_trash or inventory_item == null:
		return null

	var preview: CtrlInventoryItem = CtrlInventoryItem.new()
	preview.custom_minimum_size = SLOT_SIZE
	preview.size = SLOT_SIZE
	preview.position = -SLOT_SIZE * 0.5
	preview.item = inventory_item
	var preview_root: Control = Control.new()
	preview_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_root.add_child(preview)
	set_drag_preview(preview_root)
	return {
		"source_slot_index": slot_index,
	}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if inventory_bar == null or not (data is Dictionary):
		return false

	var drag_data: Dictionary = data as Dictionary
	var source_slot_index: int = int(drag_data.get("source_slot_index", -1))
	return source_slot_index >= 0 and source_slot_index < CharacterInventory.SLOT_COUNT


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(Vector2.ZERO, data):
		return

	var drag_data: Dictionary = data as Dictionary
	var source_slot_index: int = int(drag_data.get("source_slot_index", -1))
	if is_trash:
		inventory_bar.request_delete(source_slot_index)
	else:
		inventory_bar.request_move(source_slot_index, slot_index)


func _add_label(label_text: String) -> void:
	var label: Label = Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)


func _create_slot_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.9)
	style.border_color = Color(0.65, 0.65, 0.7, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	return style
