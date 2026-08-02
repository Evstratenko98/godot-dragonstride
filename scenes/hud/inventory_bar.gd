class_name InventoryBar
extends HBoxContainer

const SLOT_SEPARATION := 5
const INVENTORY_GROUP_SEPARATION := 18.0
const SLOT_ACTIONS: Array[StringName] = [
	&"use_inventory_slot_1",
	&"use_inventory_slot_2",
	&"use_inventory_slot_3",
	&"use_inventory_slot_4",
	&"use_inventory_slot_5",
	&"use_inventory_slot_6",
	&"use_inventory_slot_7",
	&"use_inventory_slot_8",
	&"use_inventory_slot_9",
	&"use_inventory_slot_10",
]
const SLOT_SHORTCUT_TEXTS: Array[String] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

var runtime: WorldRuntime = null
var character_inventory: CharacterInventory = null
var bound_player: PlayerCharacter = null
var item_slots: Array[InventorySlotControl] = []
var spell_slots: Array[InventorySlotControl] = []
var selected_spell_slot_index: int = -1
var is_loot_modal_mode: bool = false
var loot_drop_controller: ChestLootInventoryDropController = ChestLootInventoryDropController.new()


func _ready() -> void:
	add_theme_constant_override("separation", SLOT_SEPARATION)
	alignment = BoxContainer.ALIGNMENT_CENTER
	_build_bar()


func _exit_tree() -> void:
	_disconnect_turn_signal()
	if character_inventory != null and character_inventory.inventory_changed.is_connected(_refresh_items):
		character_inventory.inventory_changed.disconnect(_refresh_items)
	if runtime == null or runtime.spells == null:
		return
	if runtime.spells.targeting_changed.is_connected(_on_spell_targeting_changed):
		runtime.spells.targeting_changed.disconnect(_on_spell_targeting_changed)
	if runtime.spells.spell_usage_changed.is_connected(_on_spell_usage_changed):
		runtime.spells.spell_usage_changed.disconnect(_on_spell_usage_changed)


func _unhandled_key_input(event: InputEvent) -> void:
	if (
		bound_player == null
		or not bound_player.can_process_local_input()
		or _is_console_open()
		or _is_text_input_focused()
	):
		return

	for hotbar_slot_index: int in range(SLOT_ACTIONS.size()):
		if not event.is_action_pressed(SLOT_ACTIONS[hotbar_slot_index]):
			continue
		_activate_hotbar_slot(hotbar_slot_index)
		get_viewport().set_input_as_handled()
		return


func configure_runtime(new_runtime: WorldRuntime) -> void:
	_disconnect_turn_signal()
	runtime = new_runtime
	if runtime != null and runtime.turn_manager != null:
		if not runtime.turn_manager.turn_state_changed.is_connected(_on_turn_state_changed):
			runtime.turn_manager.turn_state_changed.connect(_on_turn_state_changed)
	_connect_spell_signals()


func configure_loot_dialog(dialog: ChestLootDialog) -> void:
	loot_drop_controller.configure_dialog(dialog)


func bind_character(player: PlayerCharacter) -> void:
	if player == null:
		return
	_connect_spell_signals()
	if player == bound_player:
		_refresh_spell_states()
		return
	if character_inventory != null and character_inventory.inventory_changed.is_connected(_refresh_items):
		character_inventory.inventory_changed.disconnect(_refresh_items)

	bound_player = player
	character_inventory = player.character_inventory
	loot_drop_controller.bind_inventory(character_inventory)
	if not character_inventory.inventory_changed.is_connected(_refresh_items):
		character_inventory.inventory_changed.connect(_refresh_items)
	selected_spell_slot_index = runtime.get_selected_spell_slot_index(bound_player)
	_refresh_items()


func request_move(inventory_kind: String, source_slot_index: int, target_slot_index: int) -> void:
	if runtime == null or bound_player == null or not can_rearrange_inventory() or source_slot_index == target_slot_index:
		return

	runtime.request_inventory_move(inventory_kind, source_slot_index, target_slot_index)


func request_delete(inventory_kind: String, source_slot_index: int) -> void:
	if runtime == null or bound_player == null or not bound_player.can_process_local_input():
		return

	runtime.request_inventory_delete(inventory_kind, source_slot_index)


func request_use(inventory_kind: String, slot_index: int) -> void:
	if runtime == null or bound_player == null or not bound_player.can_process_local_input():
		return

	if inventory_kind == CharacterInventory.INVENTORY_KIND_SPELL:
		runtime.toggle_spell_targeting(bound_player, slot_index)
		return

	runtime.request_inventory_use(slot_index)


func set_loot_modal_mode(should_enable: bool) -> void:
	is_loot_modal_mode = should_enable
	alignment = BoxContainer.ALIGNMENT_CENTER


func can_rearrange_inventory() -> bool:
	return runtime != null and bound_player != null and (
		bound_player.can_process_local_input()
		or (is_loot_modal_mode and not loot_drop_controller.is_request_pending())
	)


func can_accept_chest_loot(data: ChestLootDragData, inventory_kind: String, target_slot_index: int) -> bool:
	return is_loot_modal_mode and loot_drop_controller.can_drop(data, inventory_kind, target_slot_index)


func request_chest_loot_drop(data: ChestLootDragData, inventory_kind: String, target_slot_index: int) -> void:
	if is_loot_modal_mode:
		loot_drop_controller.request_drop(data, inventory_kind, target_slot_index)


func _build_bar() -> void:
	for slot_index: int in range(CharacterInventory.ITEM_SLOT_COUNT):
		var item_slot: InventorySlotControl = InventorySlotControl.new()
		item_slot.configure(
			self,
			CharacterInventory.INVENTORY_KIND_ITEM,
			slot_index,
			SLOT_SHORTCUT_TEXTS[slot_index]
		)
		item_slots.append(item_slot)
		add_child.call_deferred(item_slot)

	var group_spacer: Control = Control.new()
	group_spacer.custom_minimum_size = Vector2(INVENTORY_GROUP_SEPARATION, 0.0)
	group_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child.call_deferred(group_spacer)

	for spell_index: int in range(CharacterInventory.SPELL_SLOT_COUNT):
		var spell_slot: InventorySlotControl = InventorySlotControl.new()
		spell_slot.configure(
			self,
			CharacterInventory.INVENTORY_KIND_SPELL,
			spell_index,
			SLOT_SHORTCUT_TEXTS[CharacterInventory.ITEM_SLOT_COUNT + spell_index]
		)
		spell_slots.append(spell_slot)
		add_child.call_deferred(spell_slot)


func _refresh_items() -> void:
	if character_inventory == null:
		return

	for slot_index: int in range(item_slots.size()):
		item_slots[slot_index].set_inventory_item(
			character_inventory.get_item_at_slot(CharacterInventory.INVENTORY_KIND_ITEM, slot_index)
		)
	for slot_index: int in range(spell_slots.size()):
		spell_slots[slot_index].set_inventory_item(
			character_inventory.get_item_at_slot(CharacterInventory.INVENTORY_KIND_SPELL, slot_index)
		)

	if selected_spell_slot_index >= 0:
		var selected_spell_id: String = character_inventory.get_spell_id_at_slot(selected_spell_slot_index)
		if selected_spell_id.is_empty():
			runtime.cancel_spell_targeting(bound_player)
	_refresh_spell_states()


func _refresh_spell_states() -> void:
	if runtime == null or character_inventory == null or bound_player == null:
		return

	var should_show_usage: bool = runtime.is_turn_mode_enabled()
	for slot_index: int in range(spell_slots.size()):
		var spell_id: String = character_inventory.get_spell_id_at_slot(slot_index)
		var total_uses: int = 0 if spell_id.is_empty() else 1
		var remaining_uses: int = runtime.get_remaining_spell_slot_uses(bound_player, slot_index)
		spell_slots[slot_index].set_spell_state(
			slot_index == selected_spell_slot_index,
			remaining_uses,
			total_uses,
			should_show_usage
		)


func _activate_hotbar_slot(hotbar_slot_index: int) -> void:
	if character_inventory == null:
		return

	var inventory_kind: String = CharacterInventory.INVENTORY_KIND_ITEM
	var inventory_slot_index: int = hotbar_slot_index
	if hotbar_slot_index >= CharacterInventory.ITEM_SLOT_COUNT:
		inventory_kind = CharacterInventory.INVENTORY_KIND_SPELL
		inventory_slot_index -= CharacterInventory.ITEM_SLOT_COUNT

	var inventory_item: InventoryItem = character_inventory.get_item_at_slot(
		inventory_kind,
		inventory_slot_index
	)
	if inventory_item != null:
		request_use(inventory_kind, inventory_slot_index)


func _is_text_input_focused() -> bool:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit


func _is_console_open() -> bool:
	var console: Node = get_node_or_null("/root/Console")
	return console != null and console.has_method("is_visible") and console.is_visible()


func _on_spell_targeting_changed(is_targeting: bool, spell_slot_index: int) -> void:
	selected_spell_slot_index = spell_slot_index if is_targeting else -1
	_refresh_spell_states()


func _on_spell_usage_changed() -> void:
	_refresh_spell_states()


func _on_turn_state_changed() -> void:
	_refresh_spell_states()


func _connect_spell_signals() -> void:
	if runtime == null or runtime.spells == null:
		return
	if not runtime.spells.targeting_changed.is_connected(_on_spell_targeting_changed):
		runtime.spells.targeting_changed.connect(_on_spell_targeting_changed)
	if not runtime.spells.spell_usage_changed.is_connected(_on_spell_usage_changed):
		runtime.spells.spell_usage_changed.connect(_on_spell_usage_changed)


func _disconnect_turn_signal() -> void:
	if runtime == null or runtime.turn_manager == null:
		return
	if runtime.turn_manager.turn_state_changed.is_connected(_on_turn_state_changed):
		runtime.turn_manager.turn_state_changed.disconnect(_on_turn_state_changed)
