class_name NetworkEntityChannel
extends NetworkChannel

signal object_state_received(sequence_id: int, object_id: String, object_state: int)
signal entity_ai_state_received(sequence_id: int, entity_id: String, state: String, target_entity_id: String, reason: String)
signal entity_respawn_received(sequence_id: int, entity_id: String, cell: Vector2i, health: int)
signal entity_removed_received(sequence_id: int, entity_id: String)


func broadcast_object_state(object_id: String, object_state: int, sequence_id: int = 0) -> void:
	if not _can_host_send() or not _is_valid_object_state(object_id, object_state, sequence_id):
		return
	store.cache_object_state(object_id, object_state)
	rpc("_receive_object_state", GameSession.get_match_id(), sequence_id, object_id, object_state)


func broadcast_entity_ai_state(
	entity_id: String,
	state: String,
	target_entity_id: String,
	reason: String,
	sequence_id: int = 0
) -> void:
	if not _can_host_send() or not _is_valid_ai_state(entity_id, state, target_entity_id, reason, sequence_id):
		return
	store.cache_entity_ai_state(entity_id, state, target_entity_id, reason)
	rpc("_receive_entity_ai_state", GameSession.get_match_id(), sequence_id, entity_id, state, target_entity_id, reason)


func broadcast_entity_respawn(entity_id: String, cell: Vector2i, health: int, sequence_id: int = 0) -> void:
	if _can_host_send() and _is_valid_entity_lifecycle(entity_id, sequence_id) and NetworkProtocol.is_valid_cell_value(cell) and NetworkProtocol.is_valid_nonnegative_value(health):
		rpc("_receive_entity_respawn", GameSession.get_match_id(), sequence_id, entity_id, cell, health)


func broadcast_entity_removed(entity_id: String, sequence_id: int = 0) -> void:
	if _can_host_send() and _is_valid_entity_lifecycle(entity_id, sequence_id):
		rpc("_receive_entity_removed", GameSession.get_match_id(), sequence_id, entity_id)


func send_entity_ai_states_to_peer(peer_id: int) -> void:
	if not _can_host_send() or peer_id == 0:
		return
	var entity_ai_states: Dictionary = store.get_entity_ai_states()
	for entity_id_variant: Variant in entity_ai_states.keys():
		var entity_id: String = str(entity_id_variant)
		var state: Dictionary = entity_ai_states[entity_id_variant]
		rpc_id(
			peer_id,
			"_receive_entity_ai_state",
			GameSession.get_match_id(),
			0,
			entity_id,
			str(state.get("state", "")),
			str(state.get("target_entity_id", "")),
			str(state.get("reason", ""))
		)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_object_state(match_id: String, sequence_id: int, object_id: String, object_state: int) -> void:
	if not _is_valid_match_message(match_id) or not _is_valid_object_state(object_id, object_state, sequence_id):
		return
	store.cache_object_state(object_id, object_state)
	object_state_received.emit(sequence_id, object_id, object_state)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_entity_ai_state(match_id: String, sequence_id: int, entity_id: String, state: String, target_entity_id: String, reason: String) -> void:
	if not _is_valid_match_message(match_id) or not _is_valid_ai_state(entity_id, state, target_entity_id, reason, sequence_id):
		return
	store.cache_entity_ai_state(entity_id, state, target_entity_id, reason)
	entity_ai_state_received.emit(sequence_id, entity_id, state, target_entity_id, reason)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_entity_respawn(match_id: String, sequence_id: int, entity_id: String, cell: Vector2i, health: int) -> void:
	if _is_valid_match_message(match_id) and _is_valid_entity_lifecycle(entity_id, sequence_id) and NetworkProtocol.is_valid_cell_value(cell) and NetworkProtocol.is_valid_nonnegative_value(health):
		entity_respawn_received.emit(sequence_id, entity_id, cell, health)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_entity_removed(match_id: String, sequence_id: int, entity_id: String) -> void:
	if _is_valid_match_message(match_id) and _is_valid_entity_lifecycle(entity_id, sequence_id):
		entity_removed_received.emit(sequence_id, entity_id)


func _is_valid_object_state(object_id: String, object_state: int, sequence_id: int) -> bool:
	return NetworkProtocol.is_valid_identifier(object_id) and object_state in [0, 1] and sequence_id >= 0


func _is_valid_ai_state(entity_id: String, state: String, target_entity_id: String, reason: String, sequence_id: int) -> bool:
	return (
		NetworkProtocol.is_valid_identifier(entity_id)
		and NetworkProtocol.is_valid_bounded_text(state)
		and NetworkProtocol.is_valid_optional_identifier(target_entity_id)
		and NetworkProtocol.is_valid_bounded_text(reason)
		and sequence_id >= 0
	)


func _is_valid_entity_lifecycle(entity_id: String, sequence_id: int) -> bool:
	return NetworkProtocol.is_valid_identifier(entity_id) and sequence_id >= 0
