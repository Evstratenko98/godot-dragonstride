class_name ChestLootDialog
extends Control

signal open_state_changed(is_open: bool)

const PANEL_COLOR := Color(0.035, 0.045, 0.065, 0.97)
const BORDER_COLOR := Color(0.92, 0.70, 0.20, 0.96)

var runtime: WorldRuntime = null
var bound_player: PlayerCharacter = null
var chest_id: String = ""
var reward_item_id: String = ""
var reward_inventory_kind: String = ""
var reward_amount: int = 0
var is_request_pending: bool = false
var reward_row: HBoxContainer = null
var status_label: Label = null
var close_button: Button = null


func _ready() -> void:
	_build_dialog()
	visible = false
	set_process_unhandled_input(false)


func _exit_tree() -> void:
	_disconnect_runtime_signals()


func _unhandled_input(_event: InputEvent) -> void:
	if visible:
		get_viewport().set_input_as_handled()


func configure_runtime(new_runtime: WorldRuntime) -> void:
	_disconnect_runtime_signals()
	runtime = new_runtime
	if runtime == null or runtime.loot == null:
		return
	if not runtime.loot.loot_revealed.is_connected(_on_loot_revealed):
		runtime.loot.loot_revealed.connect(_on_loot_revealed)
	if not runtime.loot.loot_resolved.is_connected(_on_loot_resolved):
		runtime.loot.loot_resolved.connect(_on_loot_resolved)
	if not runtime.loot.loot_request_failed.is_connected(_on_loot_request_failed):
		runtime.loot.loot_request_failed.connect(_on_loot_request_failed)


func bind_character(player: PlayerCharacter) -> void:
	bound_player = player
	if runtime != null and runtime.loot != null:
		runtime.loot.reveal_pending_for_local_player()


func is_open() -> bool:
	return visible


func can_drag_reward() -> bool:
	return visible and not is_request_pending and not reward_item_id.is_empty()


func matches_active_reward(data: ChestLootDragData) -> bool:
	return (
		data != null
		and can_drag_reward()
		and data.chest_id == chest_id
		and data.item_id == reward_item_id
		and data.inventory_kind == reward_inventory_kind
		and data.amount == reward_amount
	)


func is_request_pending_for_inventory_changes() -> bool:
	return visible and is_request_pending


func request_claim(inventory_kind: String, target_slot_index: int) -> void:
	if runtime == null or runtime.loot == null or is_request_pending:
		return
	_set_request_pending(true, "Получение награды…")
	if not runtime.loot.request_claim(chest_id, inventory_kind, target_slot_index):
		_set_request_pending(false, "Не удалось отправить запрос.")


func _show_reward(new_chest_id: String, loot_entries: Array[Dictionary]) -> void:
	if loot_entries.is_empty() or bound_player == null or bound_player.character_inventory == null:
		return
	var entry: Dictionary = loot_entries[0]
	var new_reward_item_id: String = str(entry.get(ChestLootRecord.ENTRY_KEY_ITEM_ID, ""))
	var inventory: CharacterInventory = bound_player.character_inventory
	var new_inventory_kind: String = inventory.get_inventory_kind_for_item_id(new_reward_item_id)
	var target_inventory: Inventory = inventory.item_inventory if new_inventory_kind == CharacterInventory.INVENTORY_KIND_ITEM else inventory.spell_inventory
	if new_reward_item_id.is_empty() or target_inventory == null:
		return

	chest_id = new_chest_id
	reward_item_id = new_reward_item_id
	reward_inventory_kind = new_inventory_kind
	reward_amount = int(entry.get(ChestLootRecord.ENTRY_KEY_QUANTITY, 1))
	_set_request_pending(false, "Перетащите награду в подходящий слот.")
	_clear_children(reward_row)
	var reward_item: InventoryItem = InventoryItem.new(target_inventory.protoset, reward_item_id)
	reward_item.set_stack_size(reward_amount)
	var reward_slot: ChestLootSlotControl = ChestLootSlotControl.new()
	reward_slot.configure_reward(
		self,
		chest_id,
		reward_item_id,
		reward_inventory_kind,
		reward_amount,
		reward_item
	)
	reward_row.add_child(reward_slot)
	visible = true
	set_process_unhandled_input(true)
	open_state_changed.emit(true)
	close_button.grab_focus()


func _close() -> void:
	if not visible:
		return
	visible = false
	set_process_unhandled_input(false)
	is_request_pending = false
	chest_id = ""
	reward_item_id = ""
	reward_inventory_kind = ""
	reward_amount = 0
	open_state_changed.emit(false)


func _set_request_pending(should_be_pending: bool, status_text: String) -> void:
	is_request_pending = should_be_pending
	if close_button != null:
		close_button.disabled = should_be_pending
	if status_label != null:
		status_label.text = status_text


func _build_dialog() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.68)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(520.0, 180.0)
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = PANEL_COLOR
	panel_style.border_color = BORDER_COLOR
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)
	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)
	var header: HBoxContainer = HBoxContainer.new()
	content.add_child(header)
	var title: Label = Label.new()
	title.text = "Награда из сундука"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 20)
	header.add_child(title)
	close_button = Button.new()
	close_button.text = "Отказаться"
	close_button.pressed.connect(_on_close_pressed)
	header.add_child(close_button)
	content.add_child(_create_section_label("Награда"))
	reward_row = HBoxContainer.new()
	content.add_child(reward_row)
	status_label = Label.new()
	status_label.add_theme_color_override("font_color", Color(0.76, 0.79, 0.84, 1.0))
	content.add_child(status_label)


func _create_section_label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	return label


func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _disconnect_runtime_signals() -> void:
	if runtime == null or runtime.loot == null:
		return
	if runtime.loot.loot_revealed.is_connected(_on_loot_revealed):
		runtime.loot.loot_revealed.disconnect(_on_loot_revealed)
	if runtime.loot.loot_resolved.is_connected(_on_loot_resolved):
		runtime.loot.loot_resolved.disconnect(_on_loot_resolved)
	if runtime.loot.loot_request_failed.is_connected(_on_loot_request_failed):
		runtime.loot.loot_request_failed.disconnect(_on_loot_request_failed)


func _on_close_pressed() -> void:
	if runtime == null or runtime.loot == null or is_request_pending:
		return
	_set_request_pending(true, "Отказ от награды…")
	if not runtime.loot.request_discard(chest_id):
		_set_request_pending(false, "Не удалось отправить запрос.")


func _on_loot_revealed(new_chest_id: String, loot_entries: Array[Dictionary]) -> void:
	_show_reward(new_chest_id, loot_entries)


func _on_loot_resolved(resolved_chest_id: String) -> void:
	if resolved_chest_id == chest_id:
		_close()


func _on_loot_request_failed(failed_chest_id: String, reason_code: String) -> void:
	if failed_chest_id == chest_id:
		_set_request_pending(false, "Награда не получена: %s" % reason_code)
