class_name WorldNetwork
extends Node

var runtime: WorldRuntime = null
var level: WorldLevel = null


func _ready() -> void:
	level = get_parent() as WorldLevel
	if level != null:
		runtime = level.get_runtime()


func configure_context(new_runtime: WorldRuntime, new_level: WorldLevel) -> void:
	runtime = new_runtime
	level = new_level


func connect_signals() -> void:
	if not NetworkManager.peer_map_updated.is_connected(_on_peer_map_updated):
		NetworkManager.peer_map_updated.connect(_on_peer_map_updated)

	if not NetworkManager.peer_connected.is_connected(_on_peer_connected):
		NetworkManager.peer_connected.connect(_on_peer_connected)

	if not NetworkManager.character_state_received.is_connected(_on_character_state_received):
		NetworkManager.character_state_received.connect(_on_character_state_received)

	if not NetworkManager.attack_requested.is_connected(_on_attack_requested):
		NetworkManager.attack_requested.connect(_on_attack_requested)

	if not NetworkManager.attack_received.is_connected(_on_attack_received):
		NetworkManager.attack_received.connect(_on_attack_received)

	if not NetworkManager.object_state_received.is_connected(_on_object_state_received):
		NetworkManager.object_state_received.connect(_on_object_state_received)

	if not NetworkManager.entity_move_received.is_connected(_on_entity_move_received):
		NetworkManager.entity_move_received.connect(_on_entity_move_received)

	if not NetworkManager.entity_attack_received.is_connected(_on_entity_attack_received):
		NetworkManager.entity_attack_received.connect(_on_entity_attack_received)

	if not NetworkManager.entity_attack_result_received.is_connected(_on_entity_attack_result_received):
		NetworkManager.entity_attack_result_received.connect(_on_entity_attack_result_received)

	if not NetworkManager.entity_health_received.is_connected(_on_entity_health_received):
		NetworkManager.entity_health_received.connect(_on_entity_health_received)

	if not NetworkManager.entity_ai_state_received.is_connected(_on_entity_ai_state_received):
		NetworkManager.entity_ai_state_received.connect(_on_entity_ai_state_received)

	if not NetworkManager.entity_respawn_received.is_connected(_on_entity_respawn_received):
		NetworkManager.entity_respawn_received.connect(_on_entity_respawn_received)

	if not NetworkManager.entity_removed_received.is_connected(_on_entity_removed_received):
		NetworkManager.entity_removed_received.connect(_on_entity_removed_received)

	if not NetworkManager.end_game_requested.is_connected(_on_end_game_requested):
		NetworkManager.end_game_requested.connect(_on_end_game_requested)


func disconnect_signals() -> void:
	if NetworkManager.peer_map_updated.is_connected(_on_peer_map_updated):
		NetworkManager.peer_map_updated.disconnect(_on_peer_map_updated)

	if NetworkManager.peer_connected.is_connected(_on_peer_connected):
		NetworkManager.peer_connected.disconnect(_on_peer_connected)

	if NetworkManager.character_state_received.is_connected(_on_character_state_received):
		NetworkManager.character_state_received.disconnect(_on_character_state_received)

	if NetworkManager.attack_requested.is_connected(_on_attack_requested):
		NetworkManager.attack_requested.disconnect(_on_attack_requested)

	if NetworkManager.attack_received.is_connected(_on_attack_received):
		NetworkManager.attack_received.disconnect(_on_attack_received)

	if NetworkManager.object_state_received.is_connected(_on_object_state_received):
		NetworkManager.object_state_received.disconnect(_on_object_state_received)

	if NetworkManager.entity_move_received.is_connected(_on_entity_move_received):
		NetworkManager.entity_move_received.disconnect(_on_entity_move_received)

	if NetworkManager.entity_attack_received.is_connected(_on_entity_attack_received):
		NetworkManager.entity_attack_received.disconnect(_on_entity_attack_received)

	if NetworkManager.entity_attack_result_received.is_connected(_on_entity_attack_result_received):
		NetworkManager.entity_attack_result_received.disconnect(_on_entity_attack_result_received)

	if NetworkManager.entity_health_received.is_connected(_on_entity_health_received):
		NetworkManager.entity_health_received.disconnect(_on_entity_health_received)

	if NetworkManager.entity_ai_state_received.is_connected(_on_entity_ai_state_received):
		NetworkManager.entity_ai_state_received.disconnect(_on_entity_ai_state_received)

	if NetworkManager.entity_respawn_received.is_connected(_on_entity_respawn_received):
		NetworkManager.entity_respawn_received.disconnect(_on_entity_respawn_received)

	if NetworkManager.entity_removed_received.is_connected(_on_entity_removed_received):
		NetworkManager.entity_removed_received.disconnect(_on_entity_removed_received)

	if NetworkManager.end_game_requested.is_connected(_on_end_game_requested):
		NetworkManager.end_game_requested.disconnect(_on_end_game_requested)


func apply_cached_object_states() -> void:
	var cached_states: Dictionary = NetworkManager.get_object_states()
	for object_id in cached_states.keys():
		_on_object_state_received(
			str(object_id),
			int(cached_states[object_id])
		)


func apply_cached_entity_ai_states() -> void:
	var cached_states: Dictionary = NetworkManager.get_entity_ai_states()
	for entity_id in cached_states.keys():
		var state: Dictionary = cached_states[entity_id]
		_on_entity_ai_state_received(
			str(entity_id),
			str(state.get("state", "")),
			str(state.get("target_entity_id", "")),
			str(state.get("reason", ""))
		)


func broadcast_entity_move_started(entity: Node, from_cell: Vector2i, target_cell: Vector2i, should_broadcast: bool = true) -> void:
	if not should_broadcast or not GameSession.is_multiplayer():
		return

	var id: String = runtime.get_entity_id(entity)
	if id.is_empty():
		return

	NetworkManager.broadcast_entity_move(id, from_cell, target_cell)


func broadcast_object_state(target_object: Node) -> void:
	if not GameSession.is_multiplayer():
		return

	var grid_object: GridObject = target_object as GridObject
	if grid_object == null or grid_object.object_id.is_empty():
		return

	NetworkManager.broadcast_object_state(
		grid_object.object_id,
		int(grid_object.object_state)
	)


func broadcast_all_object_states() -> void:
	if not GameSession.is_multiplayer() or not GameSession.is_host():
		return

	for target_object in runtime.get_registered_objects():
		broadcast_object_state(target_object)


func _on_peer_map_updated() -> void:
	runtime.update_player_authorities()


func _on_peer_connected(_peer_id: int) -> void:
	if GameSession.is_host():
		NetworkManager.send_world_spawns_to_peer(_peer_id)
		NetworkManager.send_entity_ai_states_to_peer(_peer_id)
		broadcast_all_object_states()


func _on_character_state_received(
	steam_id: int,
	player_position: Vector2,
	animation: String,
	is_moving_player: bool,
	facing_left_player: bool
) -> void:
	var player: PlayerCharacter = runtime.get_player_by_steam_id(steam_id)
	if player == null:
		return

	if bool(player.get("is_local_player")):
		return

	if GameSession.is_host() and not runtime.can_entity_sync_state_in_turn(player):
		return

	player.apply_remote_state(player_position, animation, is_moving_player, facing_left_player)


func _on_attack_requested(steam_id: int, target_cell: Vector2i) -> void:
	if not GameSession.is_host():
		return

	var player: PlayerCharacter = runtime.get_player_by_steam_id(steam_id)
	if player == null:
		return

	if not player.can_attack_cell(target_cell):
		return

	if not runtime.can_entity_attack_in_turn(player, target_cell):
		return

	runtime.notify_entity_attacked_in_turn(player, target_cell)
	player.play_remote_attack(target_cell, false)
	NetworkManager.broadcast_attack(steam_id, target_cell)
	runtime.apply_attack_to_cell(player, target_cell, false)


func _on_attack_received(steam_id: int, target_cell: Vector2i) -> void:
	var player: PlayerCharacter = runtime.get_player_by_steam_id(steam_id)
	if player == null:
		return

	if bool(player.get("is_local_player")):
		return

	player.play_remote_attack(target_cell, false)


func _on_entity_move_received(entity_id: String, from_cell: Vector2i, target_cell: Vector2i) -> void:
	var entity: Entity = runtime.get_entity_by_id(entity_id) as Entity
	if entity == null or entity == runtime.get_local_player():
		return

	if GameSession.is_host() and not runtime.can_entity_move_in_turn(entity):
		return

	if entity is NonPlayerEntity:
		(entity as NonPlayerEntity).play_remote_move(from_cell, target_cell)
		return

	if not runtime.reserve_entity_cell(entity, from_cell, target_cell):
		return

	if GameSession.is_host():
		runtime.notify_entity_moved_in_turn(entity, from_cell, target_cell)


func _on_entity_attack_received(entity_id: String, target_cell: Vector2i) -> void:
	var attacker: Entity = runtime.get_entity_by_id(entity_id) as Entity
	if attacker == null:
		return

	if attacker == runtime.get_local_player():
		return

	if GameSession.is_host() and not attacker.can_attack_cell(target_cell):
		return

	if GameSession.is_host() and not runtime.can_entity_attack_in_turn(attacker, target_cell):
		return

	if attacker is PlayerCharacter:
		(attacker as PlayerCharacter).play_remote_attack(target_cell, false)
	elif attacker is NonPlayerEntity:
		(attacker as NonPlayerEntity).play_remote_attack(target_cell, false)
	else:
		attacker.request_attack_cell(target_cell, false, false)

	if GameSession.is_host():
		runtime.notify_entity_attacked_in_turn(attacker, target_cell)

	if GameSession.is_host():
		runtime.apply_attack_to_cell(attacker, target_cell, true, false)
	else:
		runtime.print_non_entity_attack_result(attacker, target_cell)


func _on_entity_attack_result_received(
	attacker_entity_id: String,
	target_entity_id: String,
	damage_amount: int,
	target_health: int,
	target_max_health: int
) -> void:
	if runtime.get_entity_by_id(attacker_entity_id) == runtime.get_local_player():
		return

	runtime.print_entity_attack_result(
		attacker_entity_id,
		target_entity_id,
		damage_amount,
		target_health,
		target_max_health
	)


func _on_entity_health_received(entity_id: String, new_health: int) -> void:
	var entity: Entity = runtime.get_entity_by_id(entity_id) as Entity
	if entity == null:
		return

	entity.set_health(new_health)


func _on_entity_ai_state_received(entity_id: String, state: String, target_entity_id: String, reason: String) -> void:
	var entity: NonPlayerEntity = runtime.get_entity_by_id(entity_id) as NonPlayerEntity
	if entity == null:
		return

	entity.apply_remote_ai_state(state, target_entity_id, reason)


func _on_entity_respawn_received(entity_id: String, cell: Vector2i, new_health: int) -> void:
	var entity: Entity = runtime.get_entity_by_id(entity_id) as Entity
	if entity == null:
		return

	entity.set("spawn_cell", cell)
	entity.set("current_cell", cell)
	entity.set("is_moving", false)
	entity.set("is_attacking", false)
	entity.set_health(new_health)
	runtime.respawn_entity(entity, cell)
	if entity is Node2D:
		entity.global_position = runtime.cell_to_world(cell)


func _on_entity_removed_received(entity_id: String) -> void:
	var entity: Node = runtime.get_entity_by_id(entity_id)
	if entity == null:
		return

	runtime.unregister_entity(entity)
	entity.queue_free()


func _on_object_state_received(object_id: String, object_state: int) -> void:
	var target_object: GridObject = runtime.get_object_by_id(object_id) as GridObject
	if target_object == null:
		return

	target_object.apply_network_state(object_state)


func _on_end_game_requested() -> void:
	var match_controller: MatchController = level.get_match_controller()
	if match_controller != null:
		match_controller.game_over(false)
