class_name WorldNetwork
extends Node

signal match_end_requested()

var runtime: WorldRuntime = null
var level: WorldLevel = null
var signal_bindings: WorldNetworkSignalBindings = WorldNetworkSignalBindings.new()
var character_movement: WorldCharacterMovementBridge = WorldCharacterMovementBridge.new()
var combat_bridge: WorldCombatNetworkBridge = WorldCombatNetworkBridge.new()
var inventory_intents: WorldInventoryIntentController = WorldInventoryIntentController.new()
var message_buffer: WorldNetworkMessageBuffer = WorldNetworkMessageBuffer.new()
var inventory_bridge: WorldInventoryNetworkBridge = WorldInventoryNetworkBridge.new()


func configure_context(new_runtime: WorldRuntime, new_level: WorldLevel) -> void:
	runtime = new_runtime
	level = new_level
	character_movement.configure(self)
	combat_bridge.configure(self)
	inventory_intents.configure(runtime)
	message_buffer.configure(self)
	inventory_bridge.configure(self)
	signal_bindings.configure(self)


func connect_signals() -> void:
	signal_bindings.connect_signals()
	character_movement.connect_signals()


func disconnect_signals() -> void:
	character_movement.disconnect_signals()
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
	combat_bridge.apply_cached_vitality_states()


func request_entity_move_started(entity: Node, from_surface: Vector3i, target_surface: Vector3i, should_broadcast: bool = true) -> void:
	character_movement.request_entity_move_started(entity, from_surface, target_surface, should_broadcast)


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


func request_character_move_path(player: PlayerCharacter, requested_path: Array[Vector3i]) -> bool:
	return character_movement.request_move_path(player, requested_path)


func broadcast_character_action_payload(action: WorldActionRecord) -> void:
	NetworkManager.character.broadcast_action_payload(action.match_id, action.sequence_id, action.payload)


func broadcast_combat_action_payload(action: WorldActionRecord) -> void:
	NetworkManager.combat.broadcast_action_payload(action.match_id, action.sequence_id, action.payload)


func broadcast_inventory_action_payload(action: WorldActionRecord) -> void:
	NetworkManager.inventory.broadcast_action_payload(action.match_id, action.sequence_id, action.payload)


func request_character_interaction(interactor: PlayerCharacter, target_surface: Vector3i) -> void:
	if interactor == null or interactor != runtime.get_selected_local_character():
		return

	var request_id: int = runtime.create_action_request_id()
	if GameSession.is_singleplayer():
		runtime.enqueue_player_action(
			WorldActionRecord.ActionType.INTERACTION,
			interactor,
			{"target_surface": target_surface},
			request_id,
			0
		)
		return

	NetworkManager.character.request_interaction(interactor.entity_id, target_surface, GameSession.get_match_id(), runtime.get_turn_revision(), request_id)


func request_character_attack(attacker: PlayerCharacter, target_surface: Vector3i) -> bool:
	return combat_bridge.request_attack(attacker, target_surface)


func request_inventory_add(item_id: String, amount: int) -> void:
	inventory_intents.request_add(item_id, amount)


func request_inventory_move(inventory_kind: String, source_slot_index: int, target_slot_index: int) -> void:
	inventory_intents.request_move(inventory_kind, source_slot_index, target_slot_index)


func request_inventory_delete(inventory_kind: String, slot_index: int) -> void:
	inventory_intents.request_delete(inventory_kind, slot_index)


func request_inventory_use(slot_index: int) -> void:
	inventory_intents.request_use(slot_index)


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
		inventory_bridge.send_snapshot(player, peer_id, action.sequence_id)
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
		inventory_bridge.send_snapshots_to_owners()
		combat_bridge.send_vitality_states_to_mapped_peers()


func _on_attack_requested(actor_entity_id: String, target_surface: Vector3i, match_id: String, turn_revision: int, request_id: int, requester_peer_id: int) -> void:
	combat_bridge.on_attack_requested(actor_entity_id, target_surface, match_id, turn_revision, request_id, requester_peer_id)


func _on_action_profile_payload_received(match_id: String, sequence_id: int, payload: Dictionary) -> void:
	if not GameSession.is_host() and match_id == GameSession.get_match_id():
		runtime.receive_action_profile_payload(sequence_id, payload)


func _on_interaction_requested(actor_entity_id: String, target_surface: Vector3i, match_id: String, turn_revision: int, request_id: int, requester_peer_id: int) -> void:
	if not GameSession.is_host():
		return

	var player: PlayerCharacter = get_requesting_player(requester_peer_id, actor_entity_id)
	if player == null:
		return
	runtime.enqueue_player_action(
		WorldActionRecord.ActionType.INTERACTION,
		player,
		{"target_surface": target_surface},
		request_id,
		requester_peer_id,
		turn_revision,
		match_id
	)


func _on_entity_move_received(
	parent_sequence_id: int,
	subsequence_id: int,
	entity_id: String,
	from_surface: Vector3i,
	target_surface: Vector3i
) -> void:
	character_movement.on_entity_move_received(parent_sequence_id, subsequence_id, entity_id, from_surface, target_surface)


func _apply_npc_move_message(entity_id: String, from_surface: Vector3i, target_surface: Vector3i) -> void:
	character_movement.apply_npc_move(entity_id, from_surface, target_surface)


func _on_entity_attack_received(
	parent_sequence_id: int,
	subsequence_id: int,
	entity_id: String,
	target_surface: Vector3i
) -> void:
	combat_bridge.on_entity_attack_received(parent_sequence_id, subsequence_id, entity_id, target_surface)


func _apply_npc_attack_message(entity_id: String, target_surface: Vector3i) -> void:
	combat_bridge.apply_npc_attack(entity_id, target_surface)


func _on_entity_attack_result_received(
	sequence_id: int,
	attacker_entity_id: String,
	target_entity_id: String,
	damage_amount: int,
	target_health: int,
	target_max_health: int
) -> void:
	combat_bridge.on_attack_result_received(sequence_id, attacker_entity_id, target_entity_id, damage_amount, target_health, target_max_health)


func _apply_attack_result_message(
	attacker_entity_id: String,
	target_entity_id: String,
	damage_amount: int,
	target_health: int,
	target_max_health: int
) -> void:
	combat_bridge.apply_attack_result(attacker_entity_id, target_entity_id, damage_amount, target_health, target_max_health)


func _on_entity_health_received(sequence_id: int, entity_id: String, new_health: int) -> void:
	combat_bridge.on_health_received(sequence_id, entity_id, new_health)


func _apply_health_message(entity_id: String, new_health: int) -> void:
	combat_bridge.apply_health(entity_id, new_health)


func _on_entity_vitality_received(
	sequence_id: int,
	entity_id: String,
	new_health: int,
	new_max_health: int,
	new_damage: int
) -> void:
	combat_bridge.on_vitality_received(sequence_id, entity_id, new_health, new_max_health, new_damage)


func _apply_vitality_message(
	entity_id: String,
	new_health: int,
	new_max_health: int,
	new_damage: int
) -> void:
	combat_bridge.apply_vitality(entity_id, new_health, new_max_health, new_damage)


func _on_entity_ai_state_received(
	sequence_id: int,
	entity_id: String,
	state: String,
	target_entity_id: String,
	reason: String
) -> void:
	if message_buffer.buffer_entity(sequence_id, {
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


func _on_entity_respawn_received(sequence_id: int, entity_id: String, surface: Vector3i, new_health: int) -> void:
	if message_buffer.buffer_entity(sequence_id, {
		"kind": "respawn",
		"entity_id": entity_id,
		"surface": surface,
		"health": new_health,
	}):
		return
	_apply_respawn_message(entity_id, surface, new_health)


func _apply_respawn_message(entity_id: String, surface: Vector3i, new_health: int) -> void:
	var entity: Entity = runtime.get_entity_by_id(entity_id) as Entity
	if entity == null:
		entity = runtime.get_player_by_entity_id(entity_id)
	if entity == null:
		return

	entity.respawn_at_surface(surface)
	entity.set_health(new_health)


func _on_entity_removed_received(sequence_id: int, entity_id: String) -> void:
	if message_buffer.buffer_entity(sequence_id, {"kind": "removed", "entity_id": entity_id}):
		return
	_apply_removed_message(entity_id)


func _apply_removed_message(entity_id: String) -> void:
	var entity: Node = runtime.get_entity_by_id(entity_id)
	if entity == null:
		return

	runtime.unregister_entity(entity)
	entity.queue_free()


func _on_inventory_add_requested(actor_entity_id: String, item_id: String, amount: int, expected_inventory_revision: int, match_id: String, turn_revision: int, request_id: int, requester_peer_id: int) -> void:
	inventory_bridge.on_add_requested(actor_entity_id, item_id, amount, expected_inventory_revision, match_id, turn_revision, request_id, requester_peer_id)


func _on_inventory_move_requested(
	actor_entity_id: String,
	inventory_kind: String,
	source_slot_index: int,
	target_slot_index: int,
	expected_inventory_revision: int,
	match_id: String,
	turn_revision: int,
	request_id: int,
	requester_peer_id: int
) -> void:
	inventory_bridge.on_move_requested(actor_entity_id, inventory_kind, source_slot_index, target_slot_index, expected_inventory_revision, match_id, turn_revision, request_id, requester_peer_id)


func _on_inventory_delete_requested(
	actor_entity_id: String,
	inventory_kind: String,
	slot_index: int,
	expected_inventory_revision: int,
	match_id: String,
	turn_revision: int,
	request_id: int,
	requester_peer_id: int
) -> void:
	inventory_bridge.on_delete_requested(actor_entity_id, inventory_kind, slot_index, expected_inventory_revision, match_id, turn_revision, request_id, requester_peer_id)


func _on_inventory_use_requested(actor_entity_id: String, slot_index: int, expected_inventory_revision: int, match_id: String, turn_revision: int, request_id: int, requester_peer_id: int) -> void:
	inventory_bridge.on_use_requested(actor_entity_id, slot_index, expected_inventory_revision, match_id, turn_revision, request_id, requester_peer_id)


func _on_inventory_snapshot_received(snapshot: Dictionary, sequence_id: int) -> void:
	inventory_bridge.on_snapshot_received(snapshot, sequence_id)


func get_requesting_player(requester_peer_id: int, actor_entity_id: String = "") -> PlayerCharacter:
	if requester_peer_id == 0:
		var local_actor: PlayerCharacter = runtime.get_selected_local_character()
		if not actor_entity_id.is_empty():
			local_actor = runtime.get_player_by_entity_id(actor_entity_id)
		return local_actor

	var requester_steam_id: int = NetworkManager.peers.get_steam_id_for_peer_id(requester_peer_id)
	if requester_steam_id == 0:
		return null

	if actor_entity_id.is_empty() or not runtime.is_character_owned_by_steam_id(actor_entity_id, requester_steam_id):
		return null
	return runtime.get_player_by_entity_id(actor_entity_id)


func _on_stream_action_started(action: WorldActionRecord) -> void:
	message_buffer.flush_action(action)


func _on_stream_action_finished(action: WorldActionRecord) -> void:
	character_movement.handle_action_finished(action)


func _on_stream_action_cancelled(action: WorldActionRecord, reason_code: String) -> void:
	_on_stream_action_finished(action)
	if GameSession.is_host() and action != null and reason_code == "stale_inventory":
		var player: PlayerCharacter = runtime.get_entity_by_id(action.actor_entity_id) as PlayerCharacter
		var peer_id: int = NetworkManager.peers.get_peer_id_for_steam_id(action.requester_steam_id)
		inventory_bridge.send_snapshot(player, peer_id)
	if action != null and action.requester_steam_id == GameSession.local_steam_id:
		runtime.notify_local_action_rejected(reason_code)


func _on_action_rejected(request_id: int, reason_code: String) -> void:
	character_movement.handle_action_rejected(request_id)
	runtime.notify_local_action_rejected(reason_code)


func _on_action_accepted(request_id: int, sequence_id: int) -> void:
	character_movement.handle_action_accepted(request_id, sequence_id)


func _on_remote_snapshot_committed(boundary_sequence_id: int) -> void:
	character_movement.handle_snapshot_committed(boundary_sequence_id)


func _on_session_cleared() -> void:
	message_buffer.clear()
	character_movement.clear()


func _send_entity_vitality_states_to_peer(peer_id: int) -> void:
	combat_bridge.send_vitality_states_to_peer(peer_id)


func _send_entity_vitality_states_to_mapped_peers() -> void:
	combat_bridge.send_vitality_states_to_mapped_peers()


func _on_object_state_received(sequence_id: int, object_id: String, object_state: int) -> void:
	if message_buffer.buffer_entity(sequence_id, {
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
	if runtime.visibility != null:
		runtime.visibility.request_recompute()


func _on_end_game_requested() -> void:
	match_end_requested.emit()
