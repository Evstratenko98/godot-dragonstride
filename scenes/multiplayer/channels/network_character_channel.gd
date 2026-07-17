class_name NetworkCharacterChannel
extends NetworkChannel

signal interaction_requested(target_cell: Vector2i, match_id: String, turn_revision: int, request_id: int, requester_peer_id: int)
signal character_action_payload_received(match_id: String, sequence_id: int, payload: Dictionary)
signal entity_move_requested(
	requester_steam_id: int,
	direction: Vector2i,
	match_id: String,
	turn_revision: int,
	request_id: int
)
signal entity_move_received(
	parent_sequence_id: int,
	subsequence_id: int,
	entity_id: String,
	from_cell: Vector2i,
	target_cell: Vector2i
)
signal character_kill_requested(match_id: String, turn_revision: int, request_id: int, requester_peer_id: int)


func request_interaction(target_cell: Vector2i, match_id: String, turn_revision: int, request_id: int) -> void:
	if not _can_send():
		return
	if connection.is_host:
		interaction_requested.emit(target_cell, match_id, turn_revision, request_id, 0)
		return
	rpc_id(1, "_submit_interaction", target_cell, match_id, turn_revision, request_id)


func broadcast_action_payload(match_id: String, sequence_id: int, payload: Dictionary) -> void:
	if _can_host_send() and _is_valid_match_message(match_id) and sequence_id > 0 and _is_payload_size_valid(payload):
		rpc("_receive_action_payload", match_id, sequence_id, payload)


func request_entity_move(direction: Vector2i, match_id: String, turn_revision: int, request_id: int) -> void:
	if not _can_send():
		return
	if connection.is_host:
		entity_move_requested.emit(connection.local_steam_id, direction, match_id, turn_revision, request_id)
		return
	rpc_id(1, "_submit_entity_move", direction, match_id, turn_revision, request_id)


func broadcast_entity_move(
	parent_sequence_id: int,
	subsequence_id: int,
	entity_id: String,
	from_cell: Vector2i,
	target_cell: Vector2i
) -> void:
	if (
		_can_host_send()
		and parent_sequence_id > 0
		and subsequence_id >= 0
		and NetworkProtocol.is_valid_identifier(entity_id)
		and NetworkProtocol.is_valid_cell_value(from_cell)
		and NetworkProtocol.is_valid_cell_value(target_cell)
	):
		rpc("_receive_entity_move", GameSession.get_match_id(), parent_sequence_id, subsequence_id, entity_id, from_cell, target_cell)


func request_character_kill(match_id: String, turn_revision: int, request_id: int) -> void:
	if not _can_send():
		return
	if connection.is_host:
		character_kill_requested.emit(match_id, turn_revision, request_id, 0)
		return
	rpc_id(1, "_submit_character_kill", match_id, turn_revision, request_id)


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_interaction(target_cell: Vector2i, match_id: String, turn_revision: int, request_id: int) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id != 0 and turn_revision >= 0 and NetworkProtocol.is_valid_cell_value(target_cell) and _is_valid_intent(match_id, request_id, {"target_cell": target_cell, "turn_revision": turn_revision}):
		interaction_requested.emit(target_cell, match_id, turn_revision, request_id, requester_peer_id)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_action_payload(match_id: String, sequence_id: int, payload: Dictionary) -> void:
	if _is_valid_match_message(match_id) and sequence_id > 0 and _is_payload_size_valid(payload):
		character_action_payload_received.emit(match_id, sequence_id, payload)


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_entity_move(direction: Vector2i, match_id: String, turn_revision: int, request_id: int) -> void:
	var requester_steam_id: int = _get_registered_sender_steam_id()
	if requester_steam_id != 0 and turn_revision >= 0 and direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN] and _is_valid_intent(match_id, request_id, {"direction": direction, "turn_revision": turn_revision}):
		entity_move_requested.emit(requester_steam_id, direction, match_id, turn_revision, request_id)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_entity_move(
	match_id: String,
	parent_sequence_id: int,
	subsequence_id: int,
	entity_id: String,
	from_cell: Vector2i,
	target_cell: Vector2i
) -> void:
	if _is_valid_match_message(match_id) and parent_sequence_id > 0 and subsequence_id >= 0 and NetworkProtocol.is_valid_identifier(entity_id) and NetworkProtocol.is_valid_cell_value(from_cell) and NetworkProtocol.is_valid_cell_value(target_cell):
		entity_move_received.emit(parent_sequence_id, subsequence_id, entity_id, from_cell, target_cell)


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_character_kill(match_id: String, turn_revision: int, request_id: int) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id != 0 and turn_revision >= 0 and _is_valid_intent(match_id, request_id, {"turn_revision": turn_revision}):
		character_kill_requested.emit(match_id, turn_revision, request_id, requester_peer_id)
