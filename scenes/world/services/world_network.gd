class_name WorldNetwork
extends Node

signal match_end_requested()

var runtime: WorldRuntime = null
var level: WorldLevel = null


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

	if not NetworkManager.interaction_requested.is_connected(_on_interaction_requested):
		NetworkManager.interaction_requested.connect(_on_interaction_requested)

	if not NetworkManager.object_state_received.is_connected(_on_object_state_received):
		NetworkManager.object_state_received.connect(_on_object_state_received)

	if not NetworkManager.entity_move_received.is_connected(_on_entity_move_received):
		NetworkManager.entity_move_received.connect(_on_entity_move_received)

	if not NetworkManager.entity_move_requested.is_connected(_on_entity_move_requested):
		NetworkManager.entity_move_requested.connect(_on_entity_move_requested)

	if not NetworkManager.entity_move_completed_requested.is_connected(_on_entity_move_completed_requested):
		NetworkManager.entity_move_completed_requested.connect(_on_entity_move_completed_requested)

	if not NetworkManager.entity_move_completed_received.is_connected(_on_entity_move_completed_received):
		NetworkManager.entity_move_completed_received.connect(_on_entity_move_completed_received)

	if not NetworkManager.entity_attack_received.is_connected(_on_entity_attack_received):
		NetworkManager.entity_attack_received.connect(_on_entity_attack_received)

	if not NetworkManager.entity_attack_result_received.is_connected(_on_entity_attack_result_received):
		NetworkManager.entity_attack_result_received.connect(_on_entity_attack_result_received)

	if not NetworkManager.entity_health_received.is_connected(_on_entity_health_received):
		NetworkManager.entity_health_received.connect(_on_entity_health_received)

	if not NetworkManager.entity_vitality_received.is_connected(_on_entity_vitality_received):
		NetworkManager.entity_vitality_received.connect(_on_entity_vitality_received)

	if not NetworkManager.entity_ai_state_received.is_connected(_on_entity_ai_state_received):
		NetworkManager.entity_ai_state_received.connect(_on_entity_ai_state_received)

	if not NetworkManager.entity_respawn_received.is_connected(_on_entity_respawn_received):
		NetworkManager.entity_respawn_received.connect(_on_entity_respawn_received)

	if not NetworkManager.entity_removed_received.is_connected(_on_entity_removed_received):
		NetworkManager.entity_removed_received.connect(_on_entity_removed_received)

	if not NetworkManager.inventory_add_requested.is_connected(_on_inventory_add_requested):
		NetworkManager.inventory_add_requested.connect(_on_inventory_add_requested)

	if not NetworkManager.inventory_move_requested.is_connected(_on_inventory_move_requested):
		NetworkManager.inventory_move_requested.connect(_on_inventory_move_requested)

	if not NetworkManager.inventory_delete_requested.is_connected(_on_inventory_delete_requested):
		NetworkManager.inventory_delete_requested.connect(_on_inventory_delete_requested)

	if not NetworkManager.inventory_use_requested.is_connected(_on_inventory_use_requested):
		NetworkManager.inventory_use_requested.connect(_on_inventory_use_requested)

	if not NetworkManager.inventory_snapshot_received.is_connected(_on_inventory_snapshot_received):
		NetworkManager.inventory_snapshot_received.connect(_on_inventory_snapshot_received)

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

	if NetworkManager.interaction_requested.is_connected(_on_interaction_requested):
		NetworkManager.interaction_requested.disconnect(_on_interaction_requested)

	if NetworkManager.object_state_received.is_connected(_on_object_state_received):
		NetworkManager.object_state_received.disconnect(_on_object_state_received)

	if NetworkManager.entity_move_received.is_connected(_on_entity_move_received):
		NetworkManager.entity_move_received.disconnect(_on_entity_move_received)

	if NetworkManager.entity_move_requested.is_connected(_on_entity_move_requested):
		NetworkManager.entity_move_requested.disconnect(_on_entity_move_requested)

	if NetworkManager.entity_move_completed_requested.is_connected(_on_entity_move_completed_requested):
		NetworkManager.entity_move_completed_requested.disconnect(_on_entity_move_completed_requested)

	if NetworkManager.entity_move_completed_received.is_connected(_on_entity_move_completed_received):
		NetworkManager.entity_move_completed_received.disconnect(_on_entity_move_completed_received)

	if NetworkManager.entity_attack_received.is_connected(_on_entity_attack_received):
		NetworkManager.entity_attack_received.disconnect(_on_entity_attack_received)

	if NetworkManager.entity_attack_result_received.is_connected(_on_entity_attack_result_received):
		NetworkManager.entity_attack_result_received.disconnect(_on_entity_attack_result_received)

	if NetworkManager.entity_health_received.is_connected(_on_entity_health_received):
		NetworkManager.entity_health_received.disconnect(_on_entity_health_received)

	if NetworkManager.entity_vitality_received.is_connected(_on_entity_vitality_received):
		NetworkManager.entity_vitality_received.disconnect(_on_entity_vitality_received)

	if NetworkManager.entity_ai_state_received.is_connected(_on_entity_ai_state_received):
		NetworkManager.entity_ai_state_received.disconnect(_on_entity_ai_state_received)

	if NetworkManager.entity_respawn_received.is_connected(_on_entity_respawn_received):
		NetworkManager.entity_respawn_received.disconnect(_on_entity_respawn_received)

	if NetworkManager.entity_removed_received.is_connected(_on_entity_removed_received):
		NetworkManager.entity_removed_received.disconnect(_on_entity_removed_received)

	if NetworkManager.inventory_add_requested.is_connected(_on_inventory_add_requested):
		NetworkManager.inventory_add_requested.disconnect(_on_inventory_add_requested)

	if NetworkManager.inventory_move_requested.is_connected(_on_inventory_move_requested):
		NetworkManager.inventory_move_requested.disconnect(_on_inventory_move_requested)

	if NetworkManager.inventory_delete_requested.is_connected(_on_inventory_delete_requested):
		NetworkManager.inventory_delete_requested.disconnect(_on_inventory_delete_requested)

	if NetworkManager.inventory_use_requested.is_connected(_on_inventory_use_requested):
		NetworkManager.inventory_use_requested.disconnect(_on_inventory_use_requested)

	if NetworkManager.inventory_snapshot_received.is_connected(_on_inventory_snapshot_received):
		NetworkManager.inventory_snapshot_received.disconnect(_on_inventory_snapshot_received)

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


func apply_cached_entity_vitality_states() -> void:
	var cached_states: Dictionary = NetworkManager.get_entity_vitality_states()
	for entity_id_variant: Variant in cached_states.keys():
		var entity_id: String = str(entity_id_variant)
		var state: Dictionary = cached_states[entity_id_variant]
		_on_entity_vitality_received(
			entity_id,
			int(state.get("health", 0)),
			int(state.get("max_health", 1))
		)


func request_entity_move_started(entity: Node, from_cell: Vector2i, target_cell: Vector2i, should_broadcast: bool = true) -> void:
	if not should_broadcast or not GameSession.is_multiplayer():
		return

	var id: String = runtime.get_entity_id(entity)
	if id.is_empty():
		return

	NetworkManager.request_entity_move(id, from_cell, target_cell)


func report_entity_move_completed(entity: Node, from_cell: Vector2i, target_cell: Vector2i, should_broadcast: bool = true) -> void:
	if not should_broadcast or not GameSession.is_multiplayer() or not (entity is PlayerCharacter):
		return

	var id: String = runtime.get_entity_id(entity)
	if id.is_empty():
		return

	NetworkManager.report_entity_move_completed(id, from_cell, target_cell)


func request_character_interaction(interactor: PlayerCharacter, target_cell: Vector2i) -> void:
	if interactor == null or interactor != runtime.get_local_player():
		return

	if GameSession.is_singleplayer():
		runtime.try_character_interaction(interactor, target_cell)
		return

	NetworkManager.request_interaction(target_cell)


func request_inventory_add(item_id: String, amount: int) -> void:
	if GameSession.is_singleplayer():
		var local_player: PlayerCharacter = runtime.get_local_player()
		if local_player != null:
			local_player.character_inventory.try_add_item(item_id, amount)
		return

	NetworkManager.request_inventory_add(item_id, amount)


func request_inventory_move(source_slot_index: int, target_slot_index: int) -> void:
	if GameSession.is_singleplayer():
		var local_player: PlayerCharacter = runtime.get_local_player()
		if local_player != null:
			local_player.character_inventory.try_move_stack(source_slot_index, target_slot_index)
		return

	NetworkManager.request_inventory_move(source_slot_index, target_slot_index)


func request_inventory_delete(slot_index: int) -> void:
	if GameSession.is_singleplayer():
		var local_player: PlayerCharacter = runtime.get_local_player()
		if local_player != null:
			local_player.character_inventory.try_delete_stack(slot_index)
		return

	NetworkManager.request_inventory_delete(slot_index)


func request_inventory_use(slot_index: int) -> void:
	if GameSession.is_singleplayer():
		var local_player: PlayerCharacter = runtime.get_local_player()
		if local_player != null:
			runtime.try_use_inventory_item(local_player, slot_index)
		return

	NetworkManager.request_inventory_use(slot_index)


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
	if GameSession.is_host():
		_send_inventory_snapshots_to_owners()
		_send_entity_vitality_states_to_mapped_peers()


func _on_peer_connected(_peer_id: int) -> void:
	if GameSession.is_host():
		NetworkManager.send_world_spawns_to_peer(_peer_id)
		NetworkManager.send_world_removals_to_peer(_peer_id)
		NetworkManager.send_entity_ai_states_to_peer(_peer_id)
		_send_entity_vitality_states_to_peer(_peer_id)
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

	var should_sync_cell: bool = not (GameSession.is_host() and runtime.is_turn_mode_enabled())
	player.apply_remote_state(
		player_position,
		animation,
		is_moving_player,
		facing_left_player,
		should_sync_cell
	)


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


func _on_interaction_requested(target_cell: Vector2i, requester_peer_id: int) -> void:
	if not GameSession.is_host():
		return

	var player: PlayerCharacter = _get_requesting_player(requester_peer_id)
	if player == null or not runtime.try_character_interaction(player, target_cell):
		return

	_send_inventory_snapshot(player, requester_peer_id)


func _on_entity_move_received(entity_id: String, from_cell: Vector2i, target_cell: Vector2i) -> void:
	var entity: Entity = runtime.get_entity_by_id(entity_id) as Entity
	if entity == null or entity == runtime.get_local_player():
		return

	if entity is NonPlayerEntity:
		(entity as NonPlayerEntity).play_remote_move(from_cell, target_cell)
		return

	runtime.reserve_entity_cell(entity, from_cell, target_cell)


func _on_entity_move_requested(
	requester_steam_id: int,
	entity_id: String,
	from_cell: Vector2i,
	target_cell: Vector2i
) -> void:
	var player: PlayerCharacter = _get_requested_player(requester_steam_id, entity_id)
	if not _can_accept_player_move_started(player, from_cell, target_cell):
		return

	if not runtime.reserve_entity_cell(player, from_cell, target_cell):
		return

	NetworkManager.broadcast_entity_move(entity_id, from_cell, target_cell)


func _on_entity_move_completed_requested(
	requester_steam_id: int,
	entity_id: String,
	from_cell: Vector2i,
	target_cell: Vector2i
) -> void:
	var player: PlayerCharacter = _get_requested_player(requester_steam_id, entity_id)
	if not _can_accept_player_move_completed(player, from_cell, target_cell):
		return

	_apply_confirmed_player_move(player, from_cell, target_cell)
	runtime.notify_entity_moved_in_turn(player, from_cell, target_cell)
	NetworkManager.broadcast_entity_move_completed(entity_id, from_cell, target_cell)


func _on_entity_move_completed_received(entity_id: String, from_cell: Vector2i, target_cell: Vector2i) -> void:
	var player: PlayerCharacter = runtime.get_entity_by_id(entity_id) as PlayerCharacter
	if player == null or player == runtime.get_local_player():
		return

	_apply_confirmed_player_move(player, from_cell, target_cell)


func _get_requested_player(requester_steam_id: int, entity_id: String) -> PlayerCharacter:
	if not GameSession.is_host() or requester_steam_id == 0:
		return null

	var player: PlayerCharacter = runtime.get_entity_by_id(entity_id) as PlayerCharacter
	if player == null or player.steam_id != requester_steam_id:
		return null

	if runtime.get_player_by_steam_id(requester_steam_id) != player:
		return null

	return player


func _can_accept_player_move_started(
	player: PlayerCharacter,
	from_cell: Vector2i,
	target_cell: Vector2i
) -> bool:
	if player == null or player.health <= 0:
		return false

	if not _is_single_cell_move(from_cell, target_cell):
		return false

	if not runtime.is_entity_registered_at_cell(player, from_cell):
		return false

	if not runtime.can_entity_move_in_turn(player):
		return false

	return runtime.can_enter_cell(target_cell, player)


func _can_accept_player_move_completed(
	player: PlayerCharacter,
	from_cell: Vector2i,
	target_cell: Vector2i
) -> bool:
	if player == null or player.health <= 0:
		return false

	if not _is_single_cell_move(from_cell, target_cell):
		return false

	if not runtime.is_entity_registered_at_cell(player, from_cell):
		return false

	if not runtime.has_entity_cell_reservation(player, target_cell):
		return false

	return runtime.can_entity_move_in_turn(player)


func _apply_confirmed_player_move(player: PlayerCharacter, from_cell: Vector2i, target_cell: Vector2i) -> void:
	player.global_position = runtime.cell_to_world(target_cell)
	player.current_cell = target_cell
	player.is_moving = false
	runtime.complete_entity_move(player, from_cell, target_cell)


func _is_single_cell_move(from_cell: Vector2i, target_cell: Vector2i) -> bool:
	var delta: Vector2i = target_cell - from_cell
	return absi(delta.x) + absi(delta.y) == 1


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


func _on_entity_vitality_received(entity_id: String, new_health: int, new_max_health: int) -> void:
	var player: PlayerCharacter = runtime.get_entity_by_id(entity_id) as PlayerCharacter
	if player == null:
		return

	player.apply_vitality_state(new_health, new_max_health)


func _on_entity_ai_state_received(entity_id: String, state: String, target_entity_id: String, reason: String) -> void:
	var entity: NonPlayerEntity = runtime.get_entity_by_id(entity_id) as NonPlayerEntity
	if entity == null:
		return

	entity.apply_remote_ai_state(state, target_entity_id, reason)


func _on_entity_respawn_received(entity_id: String, cell: Vector2i, new_health: int) -> void:
	var entity: Entity = runtime.get_entity_by_id(entity_id) as Entity
	if entity == null:
		return

	entity.spawn_cell = cell
	entity.respawn()
	entity.set_health(new_health)


func _on_entity_removed_received(entity_id: String) -> void:
	var entity: Node = runtime.get_entity_by_id(entity_id)
	if entity == null:
		return

	runtime.unregister_entity(entity)
	entity.queue_free()


func _on_inventory_add_requested(item_id: String, amount: int, requester_peer_id: int) -> void:
	if not GameSession.is_host():
		return

	var player: PlayerCharacter = _get_requesting_player(requester_peer_id)
	if player == null or not player.character_inventory.try_add_item(item_id, amount):
		return

	_send_inventory_snapshot(player, requester_peer_id)


func _on_inventory_move_requested(
	source_slot_index: int,
	target_slot_index: int,
	requester_peer_id: int
) -> void:
	if not GameSession.is_host():
		return

	var player: PlayerCharacter = _get_requesting_player(requester_peer_id)
	if player == null or not player.character_inventory.try_move_stack(source_slot_index, target_slot_index):
		return

	_send_inventory_snapshot(player, requester_peer_id)


func _on_inventory_delete_requested(slot_index: int, requester_peer_id: int) -> void:
	if not GameSession.is_host():
		return

	var player: PlayerCharacter = _get_requesting_player(requester_peer_id)
	if player == null or not player.character_inventory.try_delete_stack(slot_index):
		return

	_send_inventory_snapshot(player, requester_peer_id)


func _on_inventory_use_requested(slot_index: int, requester_peer_id: int) -> void:
	if not GameSession.is_host():
		return

	var player: PlayerCharacter = _get_requesting_player(requester_peer_id)
	if player == null or not runtime.try_use_inventory_item(player, slot_index):
		return

	_send_inventory_snapshot(player, requester_peer_id)
	NetworkManager.broadcast_entity_vitality(player.entity_id, player.health, player.max_health)


func _on_inventory_snapshot_received(snapshot: Dictionary) -> void:
	if GameSession.is_host():
		return

	var entity_id: String = str(snapshot.get("entity_id", ""))
	var player: PlayerCharacter = runtime.get_entity_by_id(entity_id) as PlayerCharacter
	if player == null or not player.is_local_player:
		return

	player.character_inventory.apply_snapshot(snapshot)


func _get_requesting_player(requester_peer_id: int) -> PlayerCharacter:
	if requester_peer_id == 0:
		return runtime.get_local_player()

	var requester_steam_id: int = NetworkManager.get_steam_id_for_peer_id(requester_peer_id)
	if requester_steam_id == 0:
		return null

	return runtime.get_player_by_steam_id(requester_steam_id)


func _send_inventory_snapshot(player: PlayerCharacter, requester_peer_id: int) -> void:
	if player == null or requester_peer_id == 0:
		return

	NetworkManager.send_inventory_snapshot(
		requester_peer_id,
		player.character_inventory.create_snapshot()
	)


func _send_inventory_snapshots_to_owners() -> void:
	for entity_variant: Variant in runtime.get_registered_entities():
		var player: PlayerCharacter = entity_variant as PlayerCharacter
		if player == null or player.is_local_player or player.steam_id == 0:
			continue
		var peer_id: int = NetworkManager.get_peer_id_for_steam_id(player.steam_id)
		if peer_id != 0:
			_send_inventory_snapshot(player, peer_id)


func _send_entity_vitality_states_to_peer(peer_id: int) -> void:
	for entity_variant: Variant in runtime.get_registered_entities():
		var player: PlayerCharacter = entity_variant as PlayerCharacter
		if player == null:
			continue

		NetworkManager.send_entity_vitality_to_peer(
			peer_id,
			player.entity_id,
			player.health,
			player.max_health
		)


func _send_entity_vitality_states_to_mapped_peers() -> void:
	for entity_variant: Variant in runtime.get_registered_entities():
		var remote_player: PlayerCharacter = entity_variant as PlayerCharacter
		if remote_player == null or remote_player.is_local_player or remote_player.steam_id == 0:
			continue

		var peer_id: int = NetworkManager.get_peer_id_for_steam_id(remote_player.steam_id)
		if peer_id != 0:
			_send_entity_vitality_states_to_peer(peer_id)


func _on_object_state_received(object_id: String, object_state: int) -> void:
	var target_object: GridObject = runtime.get_object_by_id(object_id) as GridObject
	if target_object == null:
		return

	target_object.apply_network_state(object_state)


func _on_end_game_requested() -> void:
	match_end_requested.emit()
