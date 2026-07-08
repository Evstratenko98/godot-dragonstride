extends Node2D

@export var grid_size: Vector2i = Vector2i(18, 18)
@export var walkable_layer_names: PackedStringArray = ["Ground"]
@export var spawn_cells: Array[Vector2i] = [
	Vector2i(5, 5),
	Vector2i(6, 5),
	Vector2i(5, 6),
	Vector2i(6, 6),
]

@onready var grid = $Grid
@onready var registry = $Registry
@onready var players_service = $PlayersService
@onready var combat = $Combat
@onready var network = $Network
@onready var turn_manager = $TurnManager
@onready var music: AudioStreamPlayer = $Music
@onready var death_sound: AudioStreamPlayer = $DeathSound

var is_ending_game: bool = false


func _ready() -> void:
	_configure_services()
	if not GameSession.has_active_session():
		GameSession.start_singleplayer()

	network.connect_signals()
	new_game()


func _exit_tree() -> void:
	network.disconnect_signals()


func new_game() -> void:
	_configure_services()
	registry.collect_blockers()
	network.apply_cached_object_states()
	players_service.prepare_players_root()

	if GameSession.is_singleplayer():
		players_service.start_singleplayer()
	elif GameSession.is_multiplayer():
		if not NetworkManager.is_ready():
			push_warning("Multiplayer session started before network became ready: " + NetworkManager.last_error)
		players_service.start_multiplayer()
	else:
		push_warning("Unknown game session mode: " + str(GameSession.mode))
		players_service.start_singleplayer()

	_register_world_entities()

	if music.stream != null:
		music.play()


func game_over(should_broadcast := true) -> void:
	if is_ending_game:
		return

	if should_broadcast and GameSession.is_multiplayer():
		NetworkManager.request_end_game()
		return

	is_ending_game = true
	music.stop()
	if death_sound.stream != null:
		death_sound.play()
	_leave_active_multiplayer_session()
	GameSession.clear()
	get_tree().change_scene_to_file("res://scenes/menu/main_menu/main_menu.tscn")


func handle_entity_attack(attacker: Node, target_cell: Vector2i, should_broadcast := true) -> void:
	apply_attack_to_cell(attacker, target_cell, should_broadcast)


func handle_entity_move_started(entity: Node, from_cell: Vector2i, target_cell: Vector2i, should_broadcast := true) -> void:
	network.broadcast_entity_move_started(entity, from_cell, target_cell, should_broadcast)


func handle_character_attack(attacker: Node, target_cell: Vector2i) -> void:
	handle_entity_attack(attacker, target_cell, true)


func register_entity(entity: Node) -> void:
	registry.register_entity(entity)


func unregister_entity(entity: Node) -> void:
	registry.unregister_entity(entity)


func register_object(target_object: Node, anchor_cell: Vector2i) -> void:
	registry.register_object(target_object, anchor_cell)


func get_placement_error(spawn_node: Node, anchor_cell: Vector2i) -> String:
	return registry.get_placement_error(spawn_node, anchor_cell)


func reserve_entity_cell(entity: Node, from_cell: Vector2i, target_cell: Vector2i) -> bool:
	return registry.reserve_entity_cell(entity, from_cell, target_cell)


func complete_entity_move(entity: Node, from_cell: Vector2i, target_cell: Vector2i) -> void:
	registry.complete_entity_move(entity, from_cell, target_cell)


func respawn_entity(entity: Node, cell: Vector2i) -> void:
	registry.respawn_entity(entity, cell)


func sync_entity_cell(entity: Node, cell: Vector2i) -> void:
	registry.sync_entity_cell(entity, cell)


func clear_registered_entities() -> void:
	registry.clear_entities()


func _register_world_entities() -> void:
	var world_entities_root: Node = get_node_or_null("WorldEntities")
	if world_entities_root == null:
		return

	_register_world_entity_children(world_entities_root)


func _register_world_entity_children(parent: Node) -> void:
	for child in parent.get_children():
		if child.get("entity_type") != null and int(child.get("entity_type")) != Entity.EntityType.CHARACTER:
			_ensure_world_entity_id(child)
			register_entity(child)

		_register_world_entity_children(child)


func _ensure_world_entity_id(entity: Node) -> void:
	if entity.get("entity_id") == null:
		return

	if not str(entity.get("entity_id")).is_empty():
		return

	entity.set("entity_id", entity.name)


func get_entity_by_id(entity_id: String) -> Node:
	return registry.get_entity_by_id(entity_id)


func get_entity_at_cell(cell: Vector2i) -> Node:
	return registry.get_entity_at_cell(cell)


func get_object_at_cell(cell: Vector2i) -> Node:
	return registry.get_object_at_cell(cell)


func get_object_by_id(object_id: String) -> Node:
	return registry.get_object_by_id(object_id)


func get_registered_objects() -> Array:
	return registry.get_registered_objects()


func can_enter_cell(cell: Vector2i, moving_entity: Node = null) -> bool:
	return registry.can_enter_cell(cell, moving_entity)


func is_cell_interactable(cell: Vector2i) -> bool:
	return registry.is_cell_interactable(cell)


func get_cell_display_name(cell: Vector2i) -> String:
	return registry.get_cell_display_name(cell)


func apply_attack_to_cell(
	attacker: Node,
	cell: Vector2i,
	should_broadcast := true,
	should_broadcast_action := true
) -> void:
	combat.apply_attack_to_cell(attacker, cell, should_broadcast, should_broadcast_action)


func can_entity_move_in_turn(entity: Node) -> bool:
	if turn_manager == null or not turn_manager.has_method("can_entity_move"):
		return true

	return turn_manager.can_entity_move(entity)


func can_entity_attack_in_turn(entity: Node, target_cell: Vector2i) -> bool:
	if turn_manager == null or not turn_manager.has_method("can_entity_attack"):
		return true

	return turn_manager.can_entity_attack(entity, target_cell)


func can_entity_sync_state_in_turn(entity: Node) -> bool:
	if turn_manager == null or not turn_manager.has_method("can_entity_sync_state"):
		return true

	return turn_manager.can_entity_sync_state(entity)


func notify_entity_moved_in_turn(entity: Node, from_cell: Vector2i, target_cell: Vector2i) -> void:
	if turn_manager != null and turn_manager.has_method("notify_entity_moved"):
		turn_manager.notify_entity_moved(entity, from_cell, target_cell)


func notify_entity_attacked_in_turn(entity: Node, target_cell: Vector2i) -> void:
	if turn_manager != null and turn_manager.has_method("notify_entity_attacked"):
		turn_manager.notify_entity_attacked(entity, target_cell)


func notify_entity_action_finished_in_turn(entity: Node) -> void:
	if turn_manager != null and turn_manager.has_method("notify_entity_action_finished"):
		turn_manager.notify_entity_action_finished(entity)


func request_end_turn(entity: Node) -> void:
	if turn_manager != null and turn_manager.has_method("request_end_turn"):
		turn_manager.request_end_turn(entity)


func is_turn_mode_enabled() -> bool:
	if turn_manager == null or not turn_manager.has_method("is_turn_mode_enabled"):
		return false

	return turn_manager.is_turn_mode_enabled()


func get_entity_id(entity: Node) -> String:
	return combat.get_entity_id(entity)


func get_entity_display_name(entity: Node) -> String:
	return combat.get_entity_display_name(entity)


func print_entity_attack_result(
	attacker_entity_id: String,
	target_entity_id: String,
	damage_amount: int,
	target_health: int,
	target_max_health: int
) -> void:
	combat.print_entity_attack_result(
		attacker_entity_id,
		target_entity_id,
		damage_amount,
		target_health,
		target_max_health
	)


func print_non_entity_attack_result(attacker: Node, target_cell: Vector2i) -> void:
	combat.print_non_entity_attack_result(attacker, target_cell)


func get_player_by_steam_id(steam_id: int) -> Node:
	return players_service.get_player_by_steam_id(steam_id)


func get_local_player() -> Node:
	return players_service.get_local_player()


func update_player_authorities() -> void:
	players_service.update_player_authorities()


func broadcast_object_state(target_object: Node) -> void:
	network.broadcast_object_state(target_object)


func broadcast_all_object_states() -> void:
	network.broadcast_all_object_states()


func is_cell_walkable(cell: Vector2i) -> bool:
	return grid.is_cell_walkable(cell)


func is_cell_inside(cell: Vector2i) -> bool:
	return grid.is_cell_inside(cell)


func get_grid_size() -> Vector2i:
	return _get_grid_service().get_grid_size()


func get_cell_size() -> int:
	return _get_grid_service().get_cell_size()


func world_to_cell(world_position: Vector2) -> Vector2i:
	return _get_grid_service().world_to_cell(world_position)


func cell_to_world(cell: Vector2i) -> Vector2:
	return _get_grid_service().cell_to_world(cell)


func get_cell_center(world_position: Vector2) -> Vector2:
	return _get_grid_service().get_cell_center(world_position)


func get_adjacent_cell_center(world_position: Vector2, direction: Vector2i) -> Vector2:
	return _get_grid_service().get_adjacent_cell_center(world_position, direction)


func print_console(text: String) -> void:
	ConsoleOutput.print_line(text)


func _configure_services() -> void:
	grid.configure(grid_size, walkable_layer_names)
	players_service.configure(spawn_cells)


func _get_grid_service() -> Node:
	if grid != null:
		return grid

	return get_node("Grid")


func _leave_active_multiplayer_session() -> void:
	if SteamManager.get_current_lobby_id() != 0:
		SteamManager.leave_lobby()
		return

	NetworkManager.stop_network()
