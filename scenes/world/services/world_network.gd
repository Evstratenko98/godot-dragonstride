class_name WorldNetwork
extends Node

signal match_end_requested()

var runtime: WorldRuntime = null
var level: WorldLevel = null
var pending_inventory_snapshots: Dictionary[int, Dictionary] = {}
var pending_combat_messages: Dictionary[int, Array] = {}
var pending_entity_messages: Dictionary[int, Array] = {}
var pending_npc_action_messages: Dictionary[int, Array] = {}
var pending_local_move_request_id: int = 0
var pending_local_move_sequence_id: int = 0
var signal_bindings: WorldNetworkSignalBindings = WorldNetworkSignalBindings.new()


func configure_context(new_runtime: WorldRuntime, new_level: WorldLevel) -> void:
	runtime = new_runtime
	level = new_level
	signal_bindings.configure(self)


func connect_signals() -> void:
	signal_bindings.connect_signals()


func disconnect_signals() -> void:
	signal_bindings.disconnect_signals()


func apply_cached_object_states() -> void:
	var cached_states: Dictionary = NetworkManager.store.get_object_states()
	for object_id in cached_states.keys():
		_on_object_state_received(
			0,
			str(object_id),
			int(cached_states[object_id])
		)


func apply_cached_entity_ai_states() -> void:
	var cached_states: Dictionary = NetworkManager.store.get_entity_ai_states()
	for entity_id in cached_states.keys():
		var state: Dictionary = cached_states[entity_id]
		_on_entity_ai_state_received(
			0,
			str(entity_id),
			str(state.get("state", "")),
			str(state.get("target_entity_id", "")),
			str(state.get("reason", ""))
		)


func apply_cached_entity_vitality_states() -> void:
	var cached_states: Dictionary = NetworkManager.store.get_entity_vitality_states()
	for entity_id_variant: Variant in cached_states.keys():
		var entity_id: String = str(entity_id_variant)
		var state: Dictionary = cached_states[entity_id_variant]
		_on_entity_vitality_received(
			0,
			entity_id,
			int(state.get("health", 0)),
			int(state.get("max_health", 1)),
			int(state.get("damage", 0))
		)


func request_entity_move_started(entity: Node, from_cell: Vector2i, target_cell: Vector2i, should_broadcast: bool = true) -> void:
	if not should_broadcast or not GameSession.is_multiplayer() or not GameSession.is_host():
		return

	var id: String = runtime.get_entity_id(entity)
	if id.is_empty():
		return

	NetworkManager.character.broadcast_entity_move(
		runtime.get_current_action_sequence_id(),
		runtime.claim_current_action_subsequence_id(),
		id,
		from_cell,
		target_cell
	)


func broadcast_entity_ai_state(
	entity_id: String,
	state: String,
	target_entity_id: String,
	reason: String
) -> void:
	NetworkManager.entity.broadcast_entity_ai_state(
		entity_id,
		state,
		target_entity_id,
		reason,
		runtime.get_current_action_sequence_id()
	)


func request_character_move(player: PlayerCharacter, direction: Vector2i) -> bool:
	if player == null or player != runtime.get_local_player() or direction == Vector2i.ZERO:
		return false
	if runtime.has_pending_move(player) or pending_local_move_request_id > 0:
		return false
	var request_id: int = runtime.create_action_request_id()
	if GameSession.is_singleplayer():
		return runtime.enqueue_player_action(
			WorldActionRecord.ActionType.MOVE,
			player,
			{"direction": direction},
			request_id,
			0
		)
	if not NetworkManager.connection.is_ready():
		return false
	pending_local_move_request_id = request_id
	pending_local_move_sequence_id = 0
	NetworkManager.character.request_entity_move(direction, GameSession.get_match_id(), runtime.get_turn_revision(), request_id)
	return true


func broadcast_character_action_payload(action: WorldActionRecord) -> void:
	NetworkManager.character.broadcast_action_payload(action.match_id, action.sequence_id, action.payload)


func broadcast_combat_action_payload(action: WorldActionRecord) -> void:
	NetworkManager.combat.broadcast_action_payload(action.match_id, action.sequence_id, action.payload)


func broadcast_inventory_action_payload(action: WorldActionRecord) -> void:
	NetworkManager.inventory.broadcast_action_payload(action.match_id, action.sequence_id, action.payload)


func request_character_interaction(interactor: PlayerCharacter, target_cell: Vector2i) -> void:
	if interactor == null or interactor != runtime.get_local_player():
		return

	var request_id: int = runtime.create_action_request_id()
	if GameSession.is_singleplayer():
		runtime.enqueue_player_action(
			WorldActionRecord.ActionType.INTERACTION,
			interactor,
			{"target_cell": target_cell},
			request_id,
			0
		)
		return

	NetworkManager.character.request_interaction(target_cell, GameSession.get_match_id(), runtime.get_turn_revision(), request_id)


func request_character_attack(attacker: PlayerCharacter, target_cell: Vector2i) -> bool:
	if attacker == null or attacker != runtime.get_local_player():
		return false
	if attacker.health <= 0:
		return false

	attacker.current_cell = runtime.world_to_cell(attacker.global_position)
	if not attacker.can_attack_cell(target_cell):
		return false
	if not runtime.can_entity_attack_in_turn(attacker, target_cell):
		return false

	var request_id: int = runtime.create_action_request_id()
	if GameSession.is_singleplayer():
		return runtime.enqueue_player_action(
			WorldActionRecord.ActionType.ATTACK,
			attacker,
			{"target_cell": target_cell},
			request_id,
			0
		)
	if not NetworkManager.connection.is_ready():
		return false

	NetworkManager.combat.request_attack(target_cell, GameSession.get_match_id(), runtime.get_turn_revision(), request_id)
	return true


func request_inventory_add(item_id: String, amount: int) -> void:
	var local_player: PlayerCharacter = runtime.get_local_player()
	if local_player == null:
		return
	var request_id: int = runtime.create_action_request_id()
	var inventory_revision: int = local_player.character_inventory.revision
	if GameSession.is_singleplayer():
		runtime.enqueue_player_action(
			WorldActionRecord.ActionType.INVENTORY_ADD,
			local_player,
			{"item_id": item_id, "amount": amount, "expected_inventory_revision": inventory_revision},
			request_id,
			0
		)
		return

	NetworkManager.inventory.request_inventory_add(item_id, amount, inventory_revision, GameSession.get_match_id(), runtime.get_turn_revision(), request_id)


func request_inventory_move(inventory_kind: String, source_slot_index: int, target_slot_index: int) -> void:
	var local_player: PlayerCharacter = runtime.get_local_player()
	if local_player == null:
		return
	var request_id: int = runtime.create_action_request_id()
	var inventory_revision: int = local_player.character_inventory.revision
	if GameSession.is_singleplayer():
		runtime.enqueue_player_action(
			WorldActionRecord.ActionType.INVENTORY_MOVE,
			local_player,
			{
				"inventory_kind": inventory_kind,
				"source_slot_index": source_slot_index,
				"target_slot_index": target_slot_index,
				"expected_inventory_revision": inventory_revision,
			},
			request_id,
			0
		)
		return

	NetworkManager.inventory.request_inventory_move(inventory_kind, source_slot_index, target_slot_index, inventory_revision, GameSession.get_match_id(), runtime.get_turn_revision(), request_id)


func request_inventory_delete(inventory_kind: String, slot_index: int) -> void:
	var local_player: PlayerCharacter = runtime.get_local_player()
	if local_player == null:
		return
	var request_id: int = runtime.create_action_request_id()
	var inventory_revision: int = local_player.character_inventory.revision
	if GameSession.is_singleplayer():
		runtime.enqueue_player_action(
			WorldActionRecord.ActionType.INVENTORY_DELETE,
			local_player,
			{"inventory_kind": inventory_kind, "slot_index": slot_index, "expected_inventory_revision": inventory_revision},
			request_id,
			0
		)
		return

	NetworkManager.inventory.request_inventory_delete(inventory_kind, slot_index, inventory_revision, GameSession.get_match_id(), runtime.get_turn_revision(), request_id)


func request_inventory_use(slot_index: int) -> void:
	var local_player: PlayerCharacter = runtime.get_local_player()
	if local_player == null:
		return
	var request_id: int = runtime.create_action_request_id()
	var inventory_revision: int = local_player.character_inventory.revision
	if GameSession.is_singleplayer():
		runtime.enqueue_player_action(
			WorldActionRecord.ActionType.INVENTORY_USE,
			local_player,
			{"slot_index": slot_index, "expected_inventory_revision": inventory_revision},
			request_id,
			0
		)
		return

	NetworkManager.inventory.request_inventory_use(slot_index, inventory_revision, GameSession.get_match_id(), runtime.get_turn_revision(), request_id)


func broadcast_object_state(target_object: Node) -> void:
	if not GameSession.is_multiplayer():
		return

	var grid_object: GridObject = target_object as GridObject
	if grid_object == null or grid_object.object_id.is_empty():
		return

	NetworkManager.entity.broadcast_object_state(
		grid_object.object_id,
		int(grid_object.object_state),
		runtime.get_current_action_sequence_id()
	)


func broadcast_all_object_states() -> void:
	if not GameSession.is_multiplayer() or not GameSession.is_host():
		return

	for target_object in runtime.get_registered_objects():
		broadcast_object_state(target_object)


func finalize_authoritative_action(action: WorldActionRecord) -> void:
	if action == null or not GameSession.is_multiplayer() or not GameSession.is_host():
		return
	var player: PlayerCharacter = runtime.get_entity_by_id(action.actor_entity_id) as PlayerCharacter
	if player == null:
		return
	var peer_id: int = NetworkManager.peers.get_peer_id_for_steam_id(action.requester_steam_id)
	if action.action_type in [
		WorldActionRecord.ActionType.INTERACTION,
		WorldActionRecord.ActionType.INVENTORY_ADD,
		WorldActionRecord.ActionType.INVENTORY_MOVE,
		WorldActionRecord.ActionType.INVENTORY_DELETE,
		WorldActionRecord.ActionType.INVENTORY_USE,
	]:
		_send_inventory_snapshot(player, peer_id, action.sequence_id)
	if action.action_type == WorldActionRecord.ActionType.INVENTORY_USE:
		NetworkManager.combat.broadcast_entity_vitality(
			player.entity_id,
			player.health,
			player.max_health,
			player.damage,
			action.sequence_id
		)


func _on_peer_map_updated() -> void:
	runtime.update_player_authorities()
	if GameSession.is_host():
		_send_inventory_snapshots_to_owners()
		_send_entity_vitality_states_to_mapped_peers()


func _on_attack_requested(target_cell: Vector2i, match_id: String, turn_revision: int, request_id: int, requester_peer_id: int) -> void:
	if not GameSession.is_host():
		return

	var player: PlayerCharacter = _get_requesting_player(requester_peer_id)
	if player == null:
		return
	runtime.enqueue_player_action(
		WorldActionRecord.ActionType.ATTACK,
		player,
		{"target_cell": target_cell},
		request_id,
		requester_peer_id,
		turn_revision,
		match_id
	)


func _on_action_profile_payload_received(match_id: String, sequence_id: int, payload: Dictionary) -> void:
	if not GameSession.is_host() and match_id == GameSession.get_match_id():
		runtime.receive_action_profile_payload(sequence_id, payload)


func _on_interaction_requested(target_cell: Vector2i, match_id: String, turn_revision: int, request_id: int, requester_peer_id: int) -> void:
	if not GameSession.is_host():
		return

	var player: PlayerCharacter = _get_requesting_player(requester_peer_id)
	if player == null:
		return
	runtime.enqueue_player_action(
		WorldActionRecord.ActionType.INTERACTION,
		player,
		{"target_cell": target_cell},
		request_id,
		requester_peer_id,
		turn_revision,
		match_id
	)


func _on_entity_move_received(
	parent_sequence_id: int,
	subsequence_id: int,
	entity_id: String,
	from_cell: Vector2i,
	target_cell: Vector2i
) -> void:
	if _buffer_npc_action_message(parent_sequence_id, {
		"kind": "move",
		"subsequence_id": subsequence_id,
		"entity_id": entity_id,
		"from_cell": from_cell,
		"target_cell": target_cell,
	}):
		return
	_apply_npc_move_message(entity_id, from_cell, target_cell)


func _apply_npc_move_message(entity_id: String, from_cell: Vector2i, target_cell: Vector2i) -> void:
	var entity: Entity = runtime.get_entity_by_id(entity_id) as Entity
	if entity == null or entity == runtime.get_local_player():
		return

	if entity is NonPlayerEntity:
		(entity as NonPlayerEntity).play_remote_move(from_cell, target_cell)
		return

	runtime.reserve_entity_cell(entity, from_cell, target_cell)


func _on_entity_move_requested(
	requester_steam_id: int,
	direction: Vector2i,
	match_id: String,
	turn_revision: int,
	request_id: int
) -> void:
	var player: PlayerCharacter = _get_requested_player(requester_steam_id)
	if player == null:
		return
	var peer_id: int = NetworkManager.peers.get_peer_id_for_steam_id(requester_steam_id)
	runtime.enqueue_player_action(
		WorldActionRecord.ActionType.MOVE,
		player,
		{"direction": direction},
		request_id,
		peer_id,
		turn_revision,
		match_id
	)


func _get_requested_player(requester_steam_id: int) -> PlayerCharacter:
	if not GameSession.is_host() or requester_steam_id == 0:
		return null

	return runtime.get_player_by_steam_id(requester_steam_id)


func _on_entity_attack_received(
	parent_sequence_id: int,
	subsequence_id: int,
	entity_id: String,
	target_cell: Vector2i
) -> void:
	if _buffer_npc_action_message(parent_sequence_id, {
		"kind": "attack",
		"subsequence_id": subsequence_id,
		"entity_id": entity_id,
		"target_cell": target_cell,
	}):
		return
	_apply_npc_attack_message(entity_id, target_cell)


func _apply_npc_attack_message(entity_id: String, target_cell: Vector2i) -> void:
	var attacker: Entity = runtime.get_entity_by_id(entity_id) as Entity
	if attacker == null:
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
	sequence_id: int,
	attacker_entity_id: String,
	target_entity_id: String,
	damage_amount: int,
	target_health: int,
	target_max_health: int
) -> void:
	if _buffer_combat_message(sequence_id, {
		"kind": "attack_result",
		"attacker_entity_id": attacker_entity_id,
		"target_entity_id": target_entity_id,
		"damage_amount": damage_amount,
		"target_health": target_health,
		"target_max_health": target_max_health,
	}):
		return
	_apply_attack_result_message(attacker_entity_id, target_entity_id, damage_amount, target_health, target_max_health)


func _apply_attack_result_message(
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


func _on_entity_health_received(sequence_id: int, entity_id: String, new_health: int) -> void:
	if _buffer_combat_message(sequence_id, {
		"kind": "health",
		"entity_id": entity_id,
		"health": new_health,
	}):
		return
	_apply_health_message(entity_id, new_health)


func _apply_health_message(entity_id: String, new_health: int) -> void:
	var entity: Entity = runtime.get_entity_by_id(entity_id) as Entity
	if entity == null:
		return

	entity.set_health(new_health)


func _on_entity_vitality_received(
	sequence_id: int,
	entity_id: String,
	new_health: int,
	new_max_health: int,
	new_damage: int
) -> void:
	if _buffer_combat_message(sequence_id, {
		"kind": "vitality",
		"entity_id": entity_id,
		"health": new_health,
		"max_health": new_max_health,
		"damage": new_damage,
	}):
		return
	_apply_vitality_message(entity_id, new_health, new_max_health, new_damage)


func _apply_vitality_message(
	entity_id: String,
	new_health: int,
	new_max_health: int,
	new_damage: int
) -> void:
	var player: PlayerCharacter = runtime.get_entity_by_id(entity_id) as PlayerCharacter
	if player == null:
		return

	player.apply_vitality_state(new_health, new_max_health)
	player.apply_attack_damage_state(new_damage)


func _on_entity_ai_state_received(
	sequence_id: int,
	entity_id: String,
	state: String,
	target_entity_id: String,
	reason: String
) -> void:
	if _buffer_entity_message(sequence_id, {
		"kind": "ai_state",
		"entity_id": entity_id,
		"state": state,
		"target_entity_id": target_entity_id,
		"reason": reason,
	}):
		return
	_apply_ai_state_message(entity_id, state, target_entity_id, reason)


func _apply_ai_state_message(entity_id: String, state: String, target_entity_id: String, reason: String) -> void:
	var entity: NonPlayerEntity = runtime.get_entity_by_id(entity_id) as NonPlayerEntity
	if entity == null:
		return

	entity.apply_remote_ai_state(state, target_entity_id, reason)


func _on_entity_respawn_received(sequence_id: int, entity_id: String, cell: Vector2i, new_health: int) -> void:
	if _buffer_entity_message(sequence_id, {
		"kind": "respawn",
		"entity_id": entity_id,
		"cell": cell,
		"health": new_health,
	}):
		return
	_apply_respawn_message(entity_id, cell, new_health)


func _apply_respawn_message(entity_id: String, cell: Vector2i, new_health: int) -> void:
	var entity: Entity = runtime.get_entity_by_id(entity_id) as Entity
	if entity == null:
		entity = runtime.get_player_by_entity_id(entity_id)
	if entity == null:
		return

	entity.respawn_at_cell(cell)
	entity.set_health(new_health)


func _on_entity_removed_received(sequence_id: int, entity_id: String) -> void:
	if _buffer_entity_message(sequence_id, {"kind": "removed", "entity_id": entity_id}):
		return
	_apply_removed_message(entity_id)


func _apply_removed_message(entity_id: String) -> void:
	var entity: Node = runtime.get_entity_by_id(entity_id)
	if entity == null:
		return

	runtime.unregister_entity(entity)
	entity.queue_free()


func _on_inventory_add_requested(item_id: String, amount: int, expected_inventory_revision: int, match_id: String, turn_revision: int, request_id: int, requester_peer_id: int) -> void:
	if not GameSession.is_host() or level == null or not level.allows_debug_commands():
		return

	var player: PlayerCharacter = _get_requesting_player(requester_peer_id)
	if player == null:
		return
	runtime.enqueue_player_action(
		WorldActionRecord.ActionType.INVENTORY_ADD,
		player,
		{"item_id": item_id, "amount": amount, "expected_inventory_revision": expected_inventory_revision},
		request_id,
		requester_peer_id,
		turn_revision,
		match_id
	)


func _on_inventory_move_requested(
	inventory_kind: String,
	source_slot_index: int,
	target_slot_index: int,
	expected_inventory_revision: int,
	match_id: String,
	turn_revision: int,
	request_id: int,
	requester_peer_id: int
) -> void:
	if not GameSession.is_host():
		return

	var player: PlayerCharacter = _get_requesting_player(requester_peer_id)
	if player == null:
		return
	runtime.enqueue_player_action(
		WorldActionRecord.ActionType.INVENTORY_MOVE,
		player,
		{
			"inventory_kind": inventory_kind,
			"source_slot_index": source_slot_index,
			"target_slot_index": target_slot_index,
			"expected_inventory_revision": expected_inventory_revision,
		},
		request_id,
		requester_peer_id,
		turn_revision,
		match_id
	)


func _on_inventory_delete_requested(
	inventory_kind: String,
	slot_index: int,
	expected_inventory_revision: int,
	match_id: String,
	turn_revision: int,
	request_id: int,
	requester_peer_id: int
) -> void:
	if not GameSession.is_host():
		return

	var player: PlayerCharacter = _get_requesting_player(requester_peer_id)
	if player == null:
		return
	runtime.enqueue_player_action(
		WorldActionRecord.ActionType.INVENTORY_DELETE,
		player,
		{"inventory_kind": inventory_kind, "slot_index": slot_index, "expected_inventory_revision": expected_inventory_revision},
		request_id,
		requester_peer_id,
		turn_revision,
		match_id
	)


func _on_inventory_use_requested(slot_index: int, expected_inventory_revision: int, match_id: String, turn_revision: int, request_id: int, requester_peer_id: int) -> void:
	if not GameSession.is_host():
		return

	var player: PlayerCharacter = _get_requesting_player(requester_peer_id)
	if player == null:
		return
	runtime.enqueue_player_action(
		WorldActionRecord.ActionType.INVENTORY_USE,
		player,
		{"slot_index": slot_index, "expected_inventory_revision": expected_inventory_revision},
		request_id,
		requester_peer_id,
		turn_revision,
		match_id
	)


func _on_inventory_snapshot_received(snapshot: Dictionary, sequence_id: int) -> void:
	if GameSession.is_host():
		return
	if sequence_id > 0 and runtime.get_current_action_sequence_id() != sequence_id:
		if not _can_buffer_profile_sequence(sequence_id) or pending_inventory_snapshots.size() >= NetworkProtocol.MAX_BUFFERED_SEQUENCES:
			_request_profile_resync()
			return
		pending_inventory_snapshots[sequence_id] = snapshot.duplicate(true)
		return
	_apply_inventory_snapshot(snapshot)


func _apply_inventory_snapshot(snapshot: Dictionary) -> void:
	var entity_id: String = str(snapshot.get("entity_id", ""))
	var player: PlayerCharacter = runtime.get_entity_by_id(entity_id) as PlayerCharacter
	if player == null or not player.is_local_player:
		return

	player.character_inventory.apply_snapshot(snapshot)


func _get_requesting_player(requester_peer_id: int) -> PlayerCharacter:
	if requester_peer_id == 0:
		return runtime.get_local_player()

	var requester_steam_id: int = NetworkManager.peers.get_steam_id_for_peer_id(requester_peer_id)
	if requester_steam_id == 0:
		return null

	return runtime.get_player_by_steam_id(requester_steam_id)


func _send_inventory_snapshot(player: PlayerCharacter, requester_peer_id: int, sequence_id: int = 0) -> void:
	if player == null or requester_peer_id == 0:
		return

	NetworkManager.inventory.send_inventory_snapshot(
		requester_peer_id,
		player.character_inventory.create_snapshot(),
		sequence_id
	)


func _on_stream_action_started(action: WorldActionRecord) -> void:
	if action != null and pending_npc_action_messages.has(action.sequence_id):
		var npc_messages: Array = pending_npc_action_messages[action.sequence_id]
		pending_npc_action_messages.erase(action.sequence_id)
		npc_messages.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
			return int(first.get("subsequence_id", 0)) < int(second.get("subsequence_id", 0))
		)
		for message_value: Variant in npc_messages:
			_apply_buffered_npc_action_message(message_value as Dictionary)
	if action != null and pending_entity_messages.has(action.sequence_id):
		var entity_messages: Array = pending_entity_messages[action.sequence_id]
		pending_entity_messages.erase(action.sequence_id)
		for message_value: Variant in entity_messages:
			_apply_buffered_entity_message(message_value as Dictionary)
	if action != null and pending_combat_messages.has(action.sequence_id):
		var messages: Array = pending_combat_messages[action.sequence_id]
		pending_combat_messages.erase(action.sequence_id)
		for message_value: Variant in messages:
			_apply_buffered_combat_message(message_value as Dictionary)
	if action != null and pending_inventory_snapshots.has(action.sequence_id):
		var snapshot: Dictionary = pending_inventory_snapshots[action.sequence_id]
		pending_inventory_snapshots.erase(action.sequence_id)
		_apply_inventory_snapshot(snapshot)


func _on_stream_action_finished(action: WorldActionRecord) -> void:
	if action != null and action.action_type == WorldActionRecord.ActionType.MOVE:
		if action.request_id == pending_local_move_request_id:
			_clear_pending_local_move_request()


func _on_stream_action_cancelled(action: WorldActionRecord, reason_code: String) -> void:
	_on_stream_action_finished(action)
	if GameSession.is_host() and action != null and reason_code == "stale_inventory":
		var player: PlayerCharacter = runtime.get_entity_by_id(action.actor_entity_id) as PlayerCharacter
		var peer_id: int = NetworkManager.peers.get_peer_id_for_steam_id(action.requester_steam_id)
		_send_inventory_snapshot(player, peer_id)
	if action != null and action.requester_steam_id == GameSession.local_steam_id:
		runtime.notify_local_action_rejected(reason_code)


func _on_action_rejected(request_id: int, reason_code: String) -> void:
	if request_id == pending_local_move_request_id:
		_clear_pending_local_move_request()
	runtime.notify_local_action_rejected(reason_code)


func _on_action_accepted(request_id: int, sequence_id: int) -> void:
	if request_id == pending_local_move_request_id:
		pending_local_move_sequence_id = sequence_id


func _on_remote_snapshot_committed(boundary_sequence_id: int) -> void:
	if (
		pending_local_move_request_id > 0
		and pending_local_move_sequence_id > 0
		and pending_local_move_sequence_id < boundary_sequence_id
	):
		_clear_pending_local_move_request()


func _clear_pending_local_move_request() -> void:
	pending_local_move_request_id = 0
	pending_local_move_sequence_id = 0


func _buffer_combat_message(sequence_id: int, message: Dictionary) -> bool:
	if sequence_id <= 0 or runtime.get_current_action_sequence_id() == sequence_id:
		return false
	if not _can_buffer_profile_sequence(sequence_id):
		if sequence_id >= runtime.get_expected_remote_action_sequence_id():
			_request_profile_resync()
		return true
	var messages: Array = pending_combat_messages.get(sequence_id, []) as Array
	if messages.size() >= NetworkProtocol.MAX_MESSAGES_PER_SEQUENCE or _get_buffered_message_count() >= NetworkProtocol.MAX_BUFFERED_MESSAGES:
		_request_profile_resync()
		return true
	messages.append(message)
	pending_combat_messages[sequence_id] = messages
	return true


func _apply_buffered_combat_message(message: Dictionary) -> void:
	match str(message.get("kind", "")):
		"attack_result":
			_apply_attack_result_message(
				str(message.get("attacker_entity_id", "")),
				str(message.get("target_entity_id", "")),
				int(message.get("damage_amount", 0)),
				int(message.get("target_health", 0)),
				int(message.get("target_max_health", 1))
			)
		"health":
			_apply_health_message(str(message.get("entity_id", "")), int(message.get("health", 0)))
		"vitality":
			_apply_vitality_message(
				str(message.get("entity_id", "")),
				int(message.get("health", 0)),
				int(message.get("max_health", 1)),
				int(message.get("damage", 0))
			)


func _buffer_entity_message(sequence_id: int, message: Dictionary) -> bool:
	if sequence_id <= 0 or runtime.get_current_action_sequence_id() == sequence_id:
		return false
	if not _can_buffer_profile_sequence(sequence_id):
		if sequence_id >= runtime.get_expected_remote_action_sequence_id():
			_request_profile_resync()
		return true
	var messages: Array = pending_entity_messages.get(sequence_id, []) as Array
	if messages.size() >= NetworkProtocol.MAX_MESSAGES_PER_SEQUENCE or _get_buffered_message_count() >= NetworkProtocol.MAX_BUFFERED_MESSAGES:
		_request_profile_resync()
		return true
	messages.append(message)
	pending_entity_messages[sequence_id] = messages
	return true


func _apply_buffered_entity_message(message: Dictionary) -> void:
	match str(message.get("kind", "")):
		"object_state":
			_apply_object_state_message(
				str(message.get("object_id", "")),
				int(message.get("object_state", 0))
			)
		"ai_state":
			_apply_ai_state_message(
				str(message.get("entity_id", "")),
				str(message.get("state", "")),
				str(message.get("target_entity_id", "")),
				str(message.get("reason", ""))
			)
		"respawn":
			_apply_respawn_message(
				str(message.get("entity_id", "")),
				message.get("cell", Vector2i.ZERO),
				int(message.get("health", 0))
			)
		"removed":
			_apply_removed_message(str(message.get("entity_id", "")))


func _buffer_npc_action_message(parent_sequence_id: int, message: Dictionary) -> bool:
	if parent_sequence_id <= 0 or runtime.get_current_action_sequence_id() == parent_sequence_id:
		return false
	if not _can_buffer_profile_sequence(parent_sequence_id):
		if parent_sequence_id >= runtime.get_expected_remote_action_sequence_id():
			_request_profile_resync()
		return true
	var messages: Array = pending_npc_action_messages.get(parent_sequence_id, []) as Array
	if messages.size() >= NetworkProtocol.MAX_MESSAGES_PER_SEQUENCE or _get_buffered_message_count() >= NetworkProtocol.MAX_BUFFERED_MESSAGES:
		_request_profile_resync()
		return true
	messages.append(message)
	pending_npc_action_messages[parent_sequence_id] = messages
	return true


func _apply_buffered_npc_action_message(message: Dictionary) -> void:
	match str(message.get("kind", "")):
		"move":
			_apply_npc_move_message(
				str(message.get("entity_id", "")),
				message.get("from_cell", Vector2i.ZERO),
				message.get("target_cell", Vector2i.ZERO)
			)
		"attack":
			_apply_npc_attack_message(
				str(message.get("entity_id", "")),
				message.get("target_cell", Vector2i.ZERO)
			)


func _send_inventory_snapshots_to_owners() -> void:
	for entity_variant: Variant in runtime.get_registered_entities():
		var player: PlayerCharacter = entity_variant as PlayerCharacter
		if player == null or player.is_local_player or player.steam_id == 0:
			continue
		var peer_id: int = NetworkManager.peers.get_peer_id_for_steam_id(player.steam_id)
		if peer_id != 0:
			_send_inventory_snapshot(player, peer_id)


func _can_buffer_profile_sequence(sequence_id: int) -> bool:
	var expected_sequence_id: int = runtime.get_expected_remote_action_sequence_id()
	return WorldNetworkBufferPolicy.can_buffer_sequence(sequence_id, expected_sequence_id)


func _get_buffered_message_count() -> int:
	return WorldNetworkBufferPolicy.get_message_count(
		pending_inventory_snapshots,
		pending_combat_messages,
		pending_entity_messages,
		pending_npc_action_messages
	)


func _request_profile_resync() -> void:
	if runtime.action_stream != null:
		runtime.action_stream.request_runtime_resync(WorldActionStream.REJECTION_SEQUENCE_GAP)


func _on_session_cleared() -> void:
	pending_inventory_snapshots.clear()
	pending_combat_messages.clear()
	pending_entity_messages.clear()
	pending_npc_action_messages.clear()
	_clear_pending_local_move_request()


func _send_entity_vitality_states_to_peer(peer_id: int) -> void:
	for entity_variant: Variant in runtime.get_registered_entities():
		var player: PlayerCharacter = entity_variant as PlayerCharacter
		if player == null:
			continue

		NetworkManager.combat.send_entity_vitality_to_peer(
			peer_id,
			player.entity_id,
			player.health,
			player.max_health,
			player.damage
		)


func _send_entity_vitality_states_to_mapped_peers() -> void:
	for entity_variant: Variant in runtime.get_registered_entities():
		var remote_player: PlayerCharacter = entity_variant as PlayerCharacter
		if remote_player == null or remote_player.is_local_player or remote_player.steam_id == 0:
			continue

		var peer_id: int = NetworkManager.peers.get_peer_id_for_steam_id(remote_player.steam_id)
		if peer_id != 0:
			_send_entity_vitality_states_to_peer(peer_id)


func _on_object_state_received(sequence_id: int, object_id: String, object_state: int) -> void:
	if _buffer_entity_message(sequence_id, {
		"kind": "object_state",
		"object_id": object_id,
		"object_state": object_state,
	}):
		return
	_apply_object_state_message(object_id, object_state)


func _apply_object_state_message(object_id: String, object_state: int) -> void:
	var target_object: GridObject = runtime.get_object_by_id(object_id) as GridObject
	if target_object == null:
		return

	target_object.apply_network_state(object_state)


func _on_end_game_requested() -> void:
	match_end_requested.emit()
