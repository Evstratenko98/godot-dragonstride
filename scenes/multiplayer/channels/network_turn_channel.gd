class_name NetworkTurnChannel
extends NetworkChannel

signal turn_state_received(snapshot: Dictionary, sequence_id: int)
signal turn_end_requested(steam_id: int, match_id: String, turn_revision: int, request_id: int, requester_peer_id: int)


func broadcast_turn_state(snapshot: Dictionary, sequence_id: int) -> void:
	if _can_host_send() and sequence_id >= 0 and _is_payload_size_valid(snapshot):
		rpc("_receive_turn_state", GameSession.get_match_id(), snapshot, sequence_id)


func request_turn_end(steam_id: int, match_id: String, turn_revision: int, request_id: int) -> void:
	if not GameSession.is_multiplayer():
		turn_end_requested.emit(steam_id, match_id, turn_revision, request_id, 0)
		return
	if not _can_send():
		return
	if connection.is_host:
		turn_end_requested.emit(steam_id, match_id, turn_revision, request_id, 0)
		return
	rpc_id(1, "_submit_turn_end", steam_id, match_id, turn_revision, request_id)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_turn_state(match_id: String, snapshot: Dictionary, sequence_id: int) -> void:
	if _is_valid_match_message(match_id) and sequence_id >= 0 and _is_payload_size_valid(snapshot):
		turn_state_received.emit(snapshot, sequence_id)


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_turn_end(steam_id: int, match_id: String, turn_revision: int, request_id: int) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id != 0 and steam_id > 0 and turn_revision >= 0 and peers.get_steam_id_for_peer_id(requester_peer_id) == steam_id and _is_valid_intent(match_id, request_id, {"turn_revision": turn_revision}):
		turn_end_requested.emit(steam_id, match_id, turn_revision, request_id, requester_peer_id)
