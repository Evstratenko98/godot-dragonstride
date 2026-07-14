class_name InventorySlotControl
extends PanelContainer

const SLOT_SIZE := Vector2(48.0, 48.0)

var inventory_bar: InventoryBar = null
var inventory_kind: String = ""
var slot_index: int = -1
var is_trash: bool = false
var is_selected: bool = false
var is_exhausted: bool = false
var inventory_item: InventoryItem = null
var item_control: CtrlInventoryItem = null
var usage_label: Label = null


func _ready() -> void:
	custom_minimum_size = SLOT_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	_refresh_style()
	if is_trash:
		_add_label("Trash")
		return

	item_control = CtrlInventoryItem.new()
	item_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_control.custom_minimum_size = SLOT_SIZE
	item_control.item = inventory_item
	add_child.call_deferred(item_control)

	usage_label = Label.new()
	usage_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	usage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	usage_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	usage_label.add_theme_font_size_override("font_size", 11)
	usage_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35, 1.0))
	add_child.call_deferred(usage_label)


func configure(
	new_inventory_bar: InventoryBar,
	new_inventory_kind: String,
	new_slot_index: int,
	should_be_trash: bool = false
) -> void:
	inventory_bar = new_inventory_bar
	inventory_kind = new_inventory_kind
	slot_index = new_slot_index
	is_trash = should_be_trash


func set_inventory_item(new_inventory_item: InventoryItem) -> void:
	inventory_item = new_inventory_item
	if item_control != null:
		item_control.item = inventory_item


func set_spell_state(
	should_be_selected: bool,
	remaining_uses: int,
	total_uses: int,
	should_show_usage: bool
) -> void:
	is_selected = should_be_selected
	is_exhausted = should_show_usage and total_uses > 0 and remaining_uses <= 0
	if usage_label != null:
		usage_label.text = "%d/%d" % [remaining_uses, total_uses] if should_show_usage and total_uses > 0 else ""
	if item_control != null:
		item_control.modulate = Color(0.45, 0.45, 0.45, 0.8) if is_exhausted else Color.WHITE
	_refresh_style()


func _gui_input(event: InputEvent) -> void:
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event == null or mouse_event.button_index != MOUSE_BUTTON_RIGHT or not mouse_event.pressed:
		return

	accept_event()
	if is_trash or inventory_item == null or inventory_bar == null:
		return

	inventory_bar.request_use(inventory_kind, slot_index)


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
	preview_root.add_child.call_deferred(preview)
	set_drag_preview(preview_root)
	return {
		"inventory_kind": inventory_kind,
		"source_slot_index": slot_index,
	}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if inventory_bar == null or not (data is Dictionary):
		return false

	var drag_data: Dictionary = data as Dictionary
	var source_inventory_kind: String = str(drag_data.get("inventory_kind", ""))
	var source_slot_index: int = int(drag_data.get("source_slot_index", -1))
	if source_inventory_kind == CharacterInventory.INVENTORY_KIND_ITEM:
		if source_slot_index < 0 or source_slot_index >= CharacterInventory.ITEM_SLOT_COUNT:
			return false
	elif source_inventory_kind == CharacterInventory.INVENTORY_KIND_SPELL:
		if source_slot_index < 0 or source_slot_index >= CharacterInventory.SPELL_SLOT_COUNT:
			return false
	else:
		return false

	return is_trash or source_inventory_kind == inventory_kind


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(Vector2.ZERO, data):
		return

	var drag_data: Dictionary = data as Dictionary
	var source_inventory_kind: String = str(drag_data.get("inventory_kind", ""))
	var source_slot_index: int = int(drag_data.get("source_slot_index", -1))
	if is_trash:
		inventory_bar.request_delete(source_inventory_kind, source_slot_index)
	else:
		inventory_bar.request_move(source_inventory_kind, source_slot_index, slot_index)


func _add_label(label_text: String) -> void:
	var label: Label = Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child.call_deferred(label)


func _refresh_style() -> void:
	add_theme_stylebox_override("panel", _create_slot_style())


func _create_slot_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.9)
	if is_selected:
		style.border_color = Color(1.0, 0.72, 0.12, 1.0)
	elif is_exhausted:
		style.border_color = Color(0.42, 0.18, 0.18, 1.0)
	else:
		style.border_color = Color(0.65, 0.65, 0.7, 1.0)
	style.set_border_width_all(3 if is_selected else 2)
	style.set_corner_radius_all(4)
	return style
