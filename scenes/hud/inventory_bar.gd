class_name InventoryBar
extends HBoxContainer

const SLOT_SIZE := Vector2(48.0, 48.0)
const SLOT_SEPARATION := 6

var runtime: WorldRuntime = null
var character_inventory: CharacterInventory = null
var bound_player: PlayerCharacter = null
var item_slots: Array[InventorySlotControl] = []
var action_buttons: Array[Button] = []


func _ready() -> void:
	add_theme_constant_override("separation", SLOT_SEPARATION)
	_build_bar()


func configure_runtime(new_runtime: WorldRuntime) -> void:
	runtime = new_runtime


func bind_character(player: PlayerCharacter) -> void:
	if player == null:
		return
	if player == bound_player:
		_refresh_action_buttons(player.action_mode)
		return
	if bound_player != null and bound_player.action_mode_changed.is_connected(_on_player_action_mode_changed):
		bound_player.action_mode_changed.disconnect(_on_player_action_mode_changed)
	if character_inventory != null and character_inventory.inventory_changed.is_connected(_refresh_items):
		character_inventory.inventory_changed.disconnect(_refresh_items)

	bound_player = player
	character_inventory = player.character_inventory
	if not character_inventory.inventory_changed.is_connected(_refresh_items):
		character_inventory.inventory_changed.connect(_refresh_items)
	if not bound_player.action_mode_changed.is_connected(_on_player_action_mode_changed):
		bound_player.action_mode_changed.connect(_on_player_action_mode_changed)
	_refresh_items()
	_refresh_action_buttons(bound_player.action_mode)


func request_move(source_slot_index: int, target_slot_index: int) -> void:
	if runtime == null or source_slot_index == target_slot_index:
		return

	runtime.request_inventory_move(source_slot_index, target_slot_index)


func request_delete(source_slot_index: int) -> void:
	if runtime == null:
		return

	runtime.request_inventory_delete(source_slot_index)


func request_use(slot_index: int) -> void:
	if runtime == null:
		return

	runtime.request_inventory_use(slot_index)


func _build_bar() -> void:
	for slot_index in range(CharacterInventory.SLOT_COUNT):
		var item_slot: InventorySlotControl = InventorySlotControl.new()
		item_slot.configure(self, slot_index)
		item_slots.append(item_slot)
		add_child(item_slot)

	var attack_button: Button = _create_action_button(
		"A1",
		"Attack",
		PlayerCharacter.ActionMode.ATTACK
	)
	var interaction_button: Button = _create_action_button(
		"A2",
		"Interact",
		PlayerCharacter.ActionMode.INTERACT
	)
	action_buttons.append(attack_button)
	action_buttons.append(interaction_button)
	add_child(attack_button)
	add_child(interaction_button)

	for spell_index in range(5):
		add_child(_create_placeholder("S%d" % [spell_index + 1]))

	var trash_slot: InventorySlotControl = InventorySlotControl.new()
	trash_slot.configure(self, -1, true)
	add_child(trash_slot)


func _refresh_items() -> void:
	if character_inventory == null:
		return

	for slot_index in range(item_slots.size()):
		item_slots[slot_index].set_inventory_item(
			character_inventory.get_item_at_slot(slot_index)
		)


func _create_action_button(label_text: String, tooltip_text: String, action_mode: int) -> Button:
	var action_button: Button = Button.new()
	action_button.text = label_text
	action_button.tooltip_text = tooltip_text
	action_button.custom_minimum_size = SLOT_SIZE
	action_button.focus_mode = Control.FOCUS_NONE
	action_button.mouse_filter = Control.MOUSE_FILTER_STOP
	action_button.pressed.connect(_on_action_button_pressed.bind(action_mode))
	_apply_action_button_style(action_button, false)
	return action_button


func _refresh_action_buttons(action_mode: int) -> void:
	for button_index in range(action_buttons.size()):
		var is_selected: bool = button_index == action_mode
		_apply_action_button_style(action_buttons[button_index], is_selected)


func _apply_action_button_style(action_button: Button, is_selected: bool) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.32, 0.24, 0.06, 0.95) if is_selected else Color(0.06, 0.06, 0.08, 0.9)
	style.border_color = Color(1.0, 0.78, 0.18, 1.0) if is_selected else Color(0.3, 0.3, 0.35, 1.0)
	style.set_border_width_all(3 if is_selected else 2)
	style.set_corner_radius_all(4)
	action_button.add_theme_stylebox_override("normal", style)
	action_button.add_theme_stylebox_override("hover", style)
	action_button.add_theme_stylebox_override("pressed", style)
	action_button.add_theme_color_override(
		"font_color",
		Color(1.0, 0.93, 0.68, 1.0) if is_selected else Color(0.7, 0.7, 0.75, 1.0)
	)


func _on_action_button_pressed(action_mode: int) -> void:
	if bound_player == null:
		return

	bound_player.set_action_mode(action_mode)


func _on_player_action_mode_changed(action_mode: int) -> void:
	_refresh_action_buttons(action_mode)


func _create_placeholder(label_text: String) -> PanelContainer:
	var placeholder: PanelContainer = PanelContainer.new()
	placeholder.custom_minimum_size = SLOT_SIZE
	placeholder.mouse_filter = Control.MOUSE_FILTER_STOP
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.08, 0.75)
	style.border_color = Color(0.3, 0.3, 0.35, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	placeholder.add_theme_stylebox_override("panel", style)

	var label: Label = Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.modulate = Color(0.55, 0.55, 0.6, 1.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	placeholder.add_child(label)
	return placeholder
