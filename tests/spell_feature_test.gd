extends Node

const MATCH_WORLD_SCENE := preload("res://scenes/world/match_world.tscn")
const CHARACTER_SCENE := preload("res://scenes/entities/character/character.tscn")

var match_world: Node2D = null
var runtime: WorldRuntime = null
var player: PlayerCharacter = null


func _ready() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await _start_match()
	await _test_inventory_storage_and_snapshot()
	await _test_action_mode_hud()
	await _test_meteor_damage_and_lifecycle()
	await _test_cell_target_resolution()
	_test_grid_object_damage()
	await _test_turn_spell_uses()
	print("SPELL_FEATURE_TESTS_PASSED")
	await _finish_tests()


func _start_match() -> void:
	GameSession.clear()
	GameSession.start_singleplayer()
	match_world = MATCH_WORLD_SCENE.instantiate() as Node2D
	add_child.call_deferred(match_world)
	await get_tree().process_frame

	for _frame_index: int in range(20):
		await get_tree().process_frame
		runtime = match_world.get_node_or_null("WorldRuntime") as WorldRuntime
		if runtime == null:
			continue
		player = runtime.get_local_player()
		if player != null:
			break

	assert(runtime != null)
	assert(player != null)


func _test_inventory_storage_and_snapshot() -> void:
	var inventory: CharacterInventory = player.character_inventory
	assert(inventory.try_add_item(CharacterInventory.ITEM_ID_MEAT, 1))
	assert(inventory.try_add_item(CharacterInventory.ITEM_ID_METEOR_SCROLL, 5))
	assert(inventory.get_item_at_slot(CharacterInventory.INVENTORY_KIND_ITEM, 0) != null)
	assert(inventory.get_item_at_slot(CharacterInventory.INVENTORY_KIND_SPELL, 0) != null)
	assert(inventory.get_item_id_at_slot(CharacterInventory.INVENTORY_KIND_ITEM, 0) == CharacterInventory.ITEM_ID_MEAT)
	for slot_index: int in range(CharacterInventory.SPELL_SLOT_COUNT):
		var spell_item: InventoryItem = inventory.get_item_at_slot(
			CharacterInventory.INVENTORY_KIND_SPELL,
			slot_index
		)
		assert(spell_item != null)
		assert(spell_item.get_stack_size() == 1)
		assert(
			inventory.get_item_id_at_slot(CharacterInventory.INVENTORY_KIND_SPELL, slot_index)
			== CharacterInventory.ITEM_ID_METEOR_SCROLL
		)
	assert(inventory.get_spell_count(WorldSpells.SPELL_ID_METEOR) == 5)
	assert(not inventory.try_add_item(CharacterInventory.ITEM_ID_METEOR_SCROLL, 1))

	var inventory_copy_player: PlayerCharacter = CHARACTER_SCENE.instantiate() as PlayerCharacter
	add_child.call_deferred(inventory_copy_player)
	await get_tree().process_frame
	var inventory_copy: CharacterInventory = inventory_copy_player.character_inventory
	assert(inventory_copy.apply_snapshot(inventory.create_snapshot()))
	assert(inventory_copy.get_item_id_at_slot(CharacterInventory.INVENTORY_KIND_ITEM, 0) == CharacterInventory.ITEM_ID_MEAT)
	assert(inventory_copy.get_spell_count(WorldSpells.SPELL_ID_METEOR) == 5)
	var invalid_snapshot: Dictionary = inventory.create_snapshot().duplicate(true)
	invalid_snapshot["revision"] = int(invalid_snapshot.get("revision", 0)) + 1
	var invalid_item_slots: Array = invalid_snapshot.get("item_slots", []) as Array
	invalid_item_slots.append({
		"slot_index": 1,
		"item_id": CharacterInventory.ITEM_ID_METEOR_SCROLL,
		"quantity": 1,
	})
	assert(not inventory_copy.apply_snapshot(invalid_snapshot))
	var invalid_spell_snapshot: Dictionary = inventory.create_snapshot().duplicate(true)
	invalid_spell_snapshot["revision"] = int(invalid_spell_snapshot.get("revision", 0)) + 1
	var invalid_spell_slots: Array = invalid_spell_snapshot.get("spell_slots", []) as Array
	var first_spell_record: Dictionary = invalid_spell_slots[0] as Dictionary
	first_spell_record["quantity"] = 2
	assert(not inventory_copy.apply_snapshot(invalid_spell_snapshot))
	inventory_copy_player.queue_free()
	await get_tree().process_frame


func _test_action_mode_hud() -> void:
	var inventory_bar: InventoryBar = match_world.get_node("HUD/InventoryBar") as InventoryBar
	assert(inventory_bar != null)
	assert(inventory_bar.action_buttons.size() == 2)
	assert(player.action_mode == PlayerCharacter.ActionMode.ATTACK)

	var attack_button: Button = inventory_bar.action_buttons[PlayerCharacter.ActionMode.ATTACK]
	var interaction_button: Button = inventory_bar.action_buttons[PlayerCharacter.ActionMode.INTERACT]
	assert(attack_button.text.is_empty())
	assert(interaction_button.text.is_empty())
	assert(attack_button.icon.resource_path == "res://art/pointers/tool_sword_a.svg")
	assert(interaction_button.icon.resource_path == "res://art/pointers/hand_open.svg")
	assert(attack_button.icon.get_size() == Vector2(32.0, 32.0))
	assert(interaction_button.icon.get_size() == Vector2(32.0, 32.0))
	assert(attack_button.tooltip_text == "Attack (Q)")
	assert(interaction_button.tooltip_text == "Interact (E)")
	assert(_is_action_button_selected(attack_button))
	assert(not _is_action_button_selected(interaction_button))

	interaction_button.pressed.emit()
	assert(player.action_mode == PlayerCharacter.ActionMode.INTERACT)
	assert(not _is_action_button_selected(attack_button))
	assert(_is_action_button_selected(interaction_button))

	await _send_physical_key(KEY_Q)
	assert(player.action_mode == PlayerCharacter.ActionMode.ATTACK)
	assert(_is_action_button_selected(attack_button))
	assert(not _is_action_button_selected(interaction_button))

	await _send_physical_key(KEY_E)
	assert(player.action_mode == PlayerCharacter.ActionMode.INTERACT)
	assert(not _is_action_button_selected(attack_button))
	assert(_is_action_button_selected(interaction_button))

	await _send_physical_key(KEY_Q)
	assert(player.action_mode == PlayerCharacter.ActionMode.ATTACK)

	assert(runtime.toggle_spell_targeting(player, 0))
	assert(runtime.has_selected_spell(player))
	await _send_physical_key(KEY_Q)
	assert(not runtime.has_selected_spell(player))
	assert(player.action_mode == PlayerCharacter.ActionMode.ATTACK)

	var text_input: LineEdit = LineEdit.new()
	match_world.add_child.call_deferred(text_input)
	await get_tree().process_frame
	text_input.grab_focus()
	await get_tree().process_frame
	await _send_physical_key(KEY_E)
	assert(player.action_mode == PlayerCharacter.ActionMode.ATTACK)
	text_input.release_focus()
	text_input.queue_free()
	await get_tree().process_frame


func _send_physical_key(keycode: Key) -> void:
	var pressed_event: InputEventKey = InputEventKey.new()
	pressed_event.physical_keycode = keycode
	pressed_event.pressed = true
	Input.parse_input_event(pressed_event)
	await get_tree().process_frame

	var released_event: InputEventKey = InputEventKey.new()
	released_event.physical_keycode = keycode
	released_event.pressed = false
	Input.parse_input_event(released_event)
	await get_tree().process_frame


func _is_action_button_selected(action_button: Button) -> bool:
	var style: StyleBoxFlat = action_button.get_theme_stylebox("normal") as StyleBoxFlat
	return style != null and style.border_color.is_equal_approx(Color(1.0, 0.78, 0.18, 1.0))


func _test_meteor_damage_and_lifecycle() -> void:
	var starting_health: int = player.health
	assert(runtime.toggle_spell_targeting(player, 0))
	assert(runtime.request_selected_spell_cast(player, player.current_cell))
	assert(player.character_inventory.get_spell_count(WorldSpells.SPELL_ID_METEOR) == 5)
	await get_tree().create_timer(0.9).timeout
	assert(player.health == starting_health - WorldSpells.METEOR_DAMAGE)
	await get_tree().create_timer(0.9).timeout
	assert(not runtime.is_entity_casting(player))
	assert(runtime.spells.effects_root.get_child_count() == 0)


func _test_cell_target_resolution() -> void:
	player.set_health(player.max_health)
	var movement_pair: Array[Vector2i] = _find_empty_walkable_pair()
	assert(movement_pair.size() == 2)
	var original_cell: Vector2i = movement_pair[0]
	var movement_cell: Vector2i = movement_pair[1]
	_move_player_for_test(original_cell)

	assert(runtime.toggle_spell_targeting(player, 0))
	assert(runtime.request_selected_spell_cast(player, original_cell))
	assert(runtime.is_entity_movement_blocked_by_spell(player))
	assert(not player.request_move(movement_cell - original_cell))
	await get_tree().create_timer(0.9).timeout
	assert(player.health == player.max_health - WorldSpells.METEOR_DAMAGE)
	await get_tree().create_timer(0.9).timeout

	player.set_health(player.max_health)
	var target_cell: Vector2i = _find_empty_target_cell([original_cell, movement_cell])
	assert(target_cell != Vector2i(-1, -1))
	assert(runtime.toggle_spell_targeting(player, 0))
	assert(runtime.request_selected_spell_cast(player, target_cell))
	assert(not runtime.is_entity_movement_blocked_by_spell(player))
	assert(player.request_move(movement_cell - original_cell))
	await get_tree().create_timer(0.25).timeout
	assert(player.current_cell == movement_cell)
	assert(runtime.is_entity_casting(player))
	await get_tree().create_timer(0.65).timeout
	assert(player.health == player.max_health)
	await get_tree().create_timer(0.9).timeout


func _test_grid_object_damage() -> void:
	var tree_cell: Vector2i = _find_empty_walkable_cell()
	assert(runtime.spawn_world_object("tree", tree_cell))
	var tree: GridObject = runtime.get_object_at_cell(tree_cell) as GridObject
	assert(tree != null)
	runtime.apply_spell_damage_to_cell(player, tree_cell, WorldSpells.METEOR_DAMAGE)
	assert(tree.object_state == GridObject.ObjectState.DESTROYED)

	var scroll_cell: Vector2i = _find_empty_walkable_cell()
	assert(runtime.spawn_world_object("meteor_scroll", scroll_cell))
	assert(runtime.get_object_at_cell(scroll_cell) is MeteorScroll)
	runtime.apply_spell_damage_to_cell(player, scroll_cell, WorldSpells.METEOR_DAMAGE)
	assert(runtime.get_object_at_cell(scroll_cell) == null)


func _test_turn_spell_uses() -> void:
	runtime.turn_manager.enable_turn_mode()
	await get_tree().process_frame
	var target_cell: Vector2i = _find_empty_target_cell()
	assert(runtime.is_cell_inside(target_cell))
	assert(runtime.toggle_spell_targeting(player, 0))
	assert(runtime.request_selected_spell_cast(player, Vector2i(-1, -1)))
	assert(runtime.get_remaining_spell_slot_uses(player, 0) == 1)

	for spell_slot_index: int in range(CharacterInventory.SPELL_SLOT_COUNT):
		for untouched_slot_index: int in range(spell_slot_index, CharacterInventory.SPELL_SLOT_COUNT):
			assert(runtime.get_remaining_spell_slot_uses(player, untouched_slot_index) == 1)
		assert(runtime.toggle_spell_targeting(player, spell_slot_index))
		assert(runtime.request_selected_spell_cast(player, target_cell))
		assert(not runtime.toggle_spell_targeting(player, spell_slot_index))
		assert(runtime.get_remaining_spell_slot_uses(player, spell_slot_index) == 0)
		await get_tree().create_timer(1.7).timeout

	for spell_slot_index: int in range(CharacterInventory.SPELL_SLOT_COUNT):
		assert(not runtime.toggle_spell_targeting(player, spell_slot_index))
	assert(player.character_inventory.get_spell_count(WorldSpells.SPELL_ID_METEOR) == 5)
	runtime.turn_manager.disable_turn_mode()
	for spell_slot_index: int in range(CharacterInventory.SPELL_SLOT_COUNT):
		assert(runtime.get_remaining_spell_slot_uses(player, spell_slot_index) == 1)


func _find_empty_target_cell(excluded_cells: Array[Vector2i] = []) -> Vector2i:
	var grid_size: Vector2i = runtime.get_grid_size()
	for y: int in range(grid_size.y):
		for x: int in range(grid_size.x):
			var cell: Vector2i = Vector2i(x, y)
			if excluded_cells.has(cell):
				continue
			if runtime.get_entity_at_cell(cell) == null and runtime.get_object_at_cell(cell) == null:
				return cell

	return Vector2i(-1, -1)


func _find_empty_walkable_cell() -> Vector2i:
	var grid_size: Vector2i = runtime.get_grid_size()
	for y: int in range(grid_size.y):
		for x: int in range(grid_size.x):
			var cell: Vector2i = Vector2i(x, y)
			if not runtime.is_cell_walkable(cell):
				continue
			if runtime.get_entity_at_cell(cell) == null and runtime.get_object_at_cell(cell) == null:
				return cell

	return Vector2i(-1, -1)


func _find_empty_walkable_pair() -> Array[Vector2i]:
	var grid_size: Vector2i = runtime.get_grid_size()
	var directions: Array[Vector2i] = [
		Vector2i.RIGHT,
		Vector2i.DOWN,
	]
	for y: int in range(grid_size.y):
		for x: int in range(grid_size.x):
			var origin_cell: Vector2i = Vector2i(x, y)
			if not runtime.is_cell_walkable(origin_cell):
				continue
			if runtime.get_entity_at_cell(origin_cell) != null or runtime.get_object_at_cell(origin_cell) != null:
				continue
			for direction: Vector2i in directions:
				var target_cell: Vector2i = origin_cell + direction
				if not runtime.is_cell_walkable(target_cell):
					continue
				if runtime.get_entity_at_cell(target_cell) == null and runtime.get_object_at_cell(target_cell) == null:
					return [origin_cell, target_cell]

	return []


func _move_player_for_test(target_cell: Vector2i) -> void:
	runtime.sync_entity_cell(player, target_cell)
	player.current_cell = target_cell
	player.global_position = runtime.cell_to_world(target_cell)


func _finish_tests() -> void:
	match_world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	GameSession.clear()
	get_tree().quit()
