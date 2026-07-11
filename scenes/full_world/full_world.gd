extends "res://scenes/full_world/world_level.gd"


func new_game() -> void:
	var runtime: WorldRuntime = get_runtime()
	if runtime != null:
		runtime.start_game()


func game_over(should_broadcast: bool = true) -> void:
	var match_controller: MatchController = get_match_controller()
	if match_controller != null:
		match_controller.game_over(should_broadcast)


func handle_entity_attack(attacker: Node, target_cell: Vector2i, should_broadcast: bool = true) -> void:
	get_runtime().handle_entity_attack(attacker, target_cell, should_broadcast)


func handle_entity_move_started(entity: Node, from_cell: Vector2i, target_cell: Vector2i, should_broadcast: bool = true) -> void:
	get_runtime().handle_entity_move_started(entity, from_cell, target_cell, should_broadcast)


func handle_character_attack(attacker: Node, target_cell: Vector2i) -> void:
	get_runtime().handle_character_attack(attacker, target_cell)


func register_entity(entity: Node) -> void:
	get_runtime().register_entity(entity)


func unregister_entity(entity: Node) -> void:
	get_runtime().unregister_entity(entity)


func register_object(target_object: Node, anchor_cell: Vector2i) -> void:
	get_runtime().register_object(target_object, anchor_cell)


func get_placement_error(spawn_node: Node, anchor_cell: Vector2i) -> String:
	return get_runtime().get_placement_error(spawn_node, anchor_cell)


func reserve_entity_cell(entity: Node, from_cell: Vector2i, target_cell: Vector2i) -> bool:
	return get_runtime().reserve_entity_cell(entity, from_cell, target_cell)


func complete_entity_move(entity: Node, from_cell: Vector2i, target_cell: Vector2i) -> void:
	get_runtime().complete_entity_move(entity, from_cell, target_cell)


func respawn_entity(entity: Node, cell: Vector2i) -> void:
	get_runtime().respawn_entity(entity, cell)


func sync_entity_cell(entity: Node, cell: Vector2i) -> void:
	get_runtime().sync_entity_cell(entity, cell)


func clear_registered_entities() -> void:
	get_runtime().clear_registered_entities()


func get_entity_by_id(entity_id: String) -> Node:
	return get_runtime().get_entity_by_id(entity_id)


func get_entity_at_cell(cell: Vector2i) -> Node:
	return get_runtime().get_entity_at_cell(cell)


func get_object_at_cell(cell: Vector2i) -> Node:
	return get_runtime().get_object_at_cell(cell)


func get_object_by_id(object_id: String) -> Node:
	return get_runtime().get_object_by_id(object_id)


func get_registered_objects() -> Array:
	return get_runtime().get_registered_objects()


func get_registered_entities() -> Array:
	return get_runtime().get_registered_entities()


func can_enter_cell(cell: Vector2i, moving_entity: Node = null) -> bool:
	return get_runtime().can_enter_cell(cell, moving_entity)


func is_cell_interactable(cell: Vector2i) -> bool:
	return get_runtime().is_cell_interactable(cell)


func get_cell_display_name(cell: Vector2i) -> String:
	return get_runtime().get_cell_display_name(cell)


func apply_attack_to_cell(
	attacker: Node,
	cell: Vector2i,
	should_broadcast: bool = true,
	should_broadcast_action: bool = true
) -> void:
	get_runtime().apply_attack_to_cell(attacker, cell, should_broadcast, should_broadcast_action)


func can_entity_move_in_turn(entity: Node) -> bool:
	return get_runtime().can_entity_move_in_turn(entity)


func can_entity_attack_in_turn(entity: Node, target_cell: Vector2i) -> bool:
	return get_runtime().can_entity_attack_in_turn(entity, target_cell)


func can_entity_sync_state_in_turn(entity: Node) -> bool:
	return get_runtime().can_entity_sync_state_in_turn(entity)


func notify_entity_moved_in_turn(entity: Node, from_cell: Vector2i, target_cell: Vector2i) -> void:
	get_runtime().notify_entity_moved_in_turn(entity, from_cell, target_cell)


func notify_entity_attacked_in_turn(entity: Node, target_cell: Vector2i) -> void:
	get_runtime().notify_entity_attacked_in_turn(entity, target_cell)


func notify_entity_action_finished_in_turn(entity: Node) -> void:
	get_runtime().notify_entity_action_finished_in_turn(entity)


func request_end_turn(entity: Node) -> void:
	get_runtime().request_end_turn(entity)


func is_turn_mode_enabled() -> bool:
	return get_runtime().is_turn_mode_enabled()


func get_entity_id(entity: Node) -> String:
	return get_runtime().get_entity_id(entity)


func get_entity_display_name(entity: Node) -> String:
	return get_runtime().get_entity_display_name(entity)


func print_entity_attack_result(
	attacker_entity_id: String,
	target_entity_id: String,
	damage_amount: int,
	target_health: int,
	target_max_health: int
) -> void:
	get_runtime().print_entity_attack_result(
		attacker_entity_id,
		target_entity_id,
		damage_amount,
		target_health,
		target_max_health
	)


func print_non_entity_attack_result(attacker: Node, target_cell: Vector2i) -> void:
	get_runtime().print_non_entity_attack_result(attacker, target_cell)


func get_player_by_steam_id(steam_id: int) -> Node:
	return get_runtime().get_player_by_steam_id(steam_id)


func get_local_player() -> Node:
	return get_runtime().get_local_player()


func update_player_authorities() -> void:
	get_runtime().update_player_authorities()


func broadcast_object_state(target_object: Node) -> void:
	get_runtime().broadcast_object_state(target_object)


func broadcast_all_object_states() -> void:
	get_runtime().broadcast_all_object_states()


func is_cell_walkable(cell: Vector2i) -> bool:
	return get_runtime().is_cell_walkable(cell)


func is_cell_inside(cell: Vector2i) -> bool:
	return get_runtime().is_cell_inside(cell)


func get_grid_size() -> Vector2i:
	return get_runtime().get_grid_size()


func get_cell_size() -> int:
	return get_runtime().get_cell_size()


func world_to_cell(world_position: Vector2) -> Vector2i:
	return get_runtime().world_to_cell(world_position)


func cell_to_world(cell: Vector2i) -> Vector2:
	return get_runtime().cell_to_world(cell)


func get_cell_center(world_position: Vector2) -> Vector2:
	return get_runtime().get_cell_center(world_position)


func get_adjacent_cell_center(world_position: Vector2, direction: Vector2i) -> Vector2:
	return get_runtime().get_adjacent_cell_center(world_position, direction)


func print_console(text: String) -> void:
	var runtime: WorldRuntime = get_runtime()
	if runtime != null:
		runtime.print_console(text)
		return

	ConsoleOutput.print_line(text)
