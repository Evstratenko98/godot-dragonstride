class_name NetworkCharacterChannel
extends NetworkChannel

signal interaction_requested(target_cell: Vector2i, request_id: int, requester_peer_id: int)
signal character_action_payload_received(sequence_id: int, payload: Dictionary)
signal entity_move_requested(
	requester_steam_id: int,
	direction: Vector2i,
	request_id: int
)
signal entity_move_received(
	parent_sequence_id: int,
	subsequence_id: int,
	entity_id: String,
	from_cell: Vector2i,
	target_cell: Vector2i
)
signal character_kill_requested(request_id: int, requester_peer_id: int)


func request_interaction(target_cell: Vector2i, request_id: int) -> void:
	if not _can_send():
		return
	if connection.is_host:
		interaction_requested.emit(target_cell, request_id, 0)
		return
	rpc_id(1, "_submit_interaction", target_cell, request_id)


func broadcast_action_payload(sequence_id: int, payload: Dictionary) -> void:
	if _can_host_send() and sequence_id > 0:
		rpc("_receive_action_payload", sequence_id, payload)


func request_entity_move(direction: Vector2i, request_id: int) -> void:
	if not _can_send():
		return
	if connection.is_host:
		entity_move_requested.emit(connection.local_steam_id, direction, request_id)
		return
	rpc_id(1, "_submit_entity_move", direction, request_id)


func broadcast_entity_move(
	parent_sequence_id: int,
	subsequence_id: int,
	entity_id: String,
	from_cell: Vector2i,
	target_cell: Vector2i
) -> void:
	if _can_host_send():
		rpc("_receive_entity_move", parent_sequence_id, subsequence_id, entity_id, from_cell, target_cell)


func request_character_kill(request_id: int) -> void:
	if not _can_send():
		return
	if connection.is_host:
		character_kill_requested.emit(request_id, 0)
		return
	rpc_id(1, "_submit_character_kill", request_id)


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_interaction(target_cell: Vector2i, request_id: int) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id != 0 and request_id > 0:
		interaction_requested.emit(target_cell, request_id, requester_peer_id)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_action_payload(sequence_id: int, payload: Dictionary) -> void:
	character_action_payload_received.emit(sequence_id, payload)


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_entity_move(direction: Vector2i, request_id: int) -> void:
	var requester_steam_id: int = _get_registered_sender_steam_id()
	if requester_steam_id != 0 and request_id > 0 and direction != Vector2i.ZERO:
		entity_move_requested.emit(requester_steam_id, direction, request_id)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_entity_move(
	parent_sequence_id: int,
	subsequence_id: int,
	entity_id: String,
	from_cell: Vector2i,
	target_cell: Vector2i
) -> void:
	entity_move_received.emit(parent_sequence_id, subsequence_id, entity_id, from_cell, target_cell)


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_character_kill(request_id: int) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id != 0 and request_id > 0:
		character_kill_requested.emit(request_id, requester_peer_id)
