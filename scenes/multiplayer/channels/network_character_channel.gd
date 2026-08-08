class_name NetworkCharacterChannel
extends NetworkChannel

signal interaction_requested(actor_entity_id: String, target_surface: Vector3i, match_id: String, turn_revision: int, request_id: int, requester_peer_id: int)
signal character_action_payload_received(match_id: String, sequence_id: int, payload: Dictionary)
signal character_move_path_requested(
	requester_steam_id: int,
	actor_entity_id: String,
	requested_path: Array[Vector3i],
	match_id: String,
	turn_revision: int,
	request_id: int
)
signal entity_move_received(
	parent_sequence_id: int,
	subsequence_id: int,
	entity_id: String,
	from_surface: Vector3i,
	target_surface: Vector3i
)
signal movement_input_state_requested(
	requester_steam_id: int,
	actor_entity_id: String,
	is_held: bool,
	match_id: String,
	turn_revision: int,
	request_id: int
)
signal movement_input_state_received(actor_entity_id: String, is_held: bool)
signal character_kill_requested(actor_entity_id: String, match_id: String, turn_revision: int, request_id: int, requester_peer_id: int)


func request_interaction(actor_entity_id: String, target_surface: Vector3i, match_id: String, turn_revision: int, request_id: int) -> void:
	if not _can_send():
		return
	if connection.is_host:
		interaction_requested.emit(actor_entity_id, target_surface, match_id, turn_revision, request_id, 0)
		return
	rpc_id(1, "_submit_interaction", actor_entity_id, target_surface, match_id, turn_revision, request_id)


func broadcast_action_payload(match_id: String, sequence_id: int, payload: Dictionary) -> void:
	if _can_host_send() and _is_valid_match_message(match_id) and sequence_id > 0 and _is_payload_size_valid(payload):
		rpc("_receive_action_payload", match_id, sequence_id, payload)


func request_character_move_path(
	actor_entity_id: String,
	requested_path: Array[Vector3i],
	match_id: String,
	turn_revision: int,
	request_id: int
) -> void:
	if not _can_send() or not NetworkProtocol.is_valid_move_path(requested_path):
		return
	if connection.is_host:
		character_move_path_requested.emit(
			connection.local_steam_id,
			actor_entity_id,
			requested_path,
			match_id,
			turn_revision,
			request_id
		)
		return
	rpc_id(1, "_submit_character_move_path", actor_entity_id, requested_path, match_id, turn_revision, request_id)


func broadcast_entity_move(
	parent_sequence_id: int,
	subsequence_id: int,
	entity_id: String,
	from_surface: Vector3i,
	target_surface: Vector3i
) -> void:
	if (
		_can_host_send()
		and parent_sequence_id > 0
		and subsequence_id >= 0
		and NetworkProtocol.is_valid_identifier(entity_id)
		and NetworkProtocol.is_valid_surface_value(from_surface)
		and NetworkProtocol.is_valid_surface_value(target_surface)
	):
		rpc("_receive_entity_move", GameSession.get_match_id(), parent_sequence_id, subsequence_id, entity_id, from_surface, target_surface)


func request_movement_input_state(
	actor_entity_id: String,
	is_held: bool,
	match_id: String,
	turn_revision: int,
	request_id: int
) -> void:
	if not _can_send() or not NetworkProtocol.is_valid_identifier(actor_entity_id) or turn_revision < 0 or request_id <= 0:
		return
	if connection.is_host:
		movement_input_state_requested.emit(
			connection.local_steam_id,
			actor_entity_id,
			is_held,
			match_id,
			turn_revision,
			request_id
		)
		return
	rpc_id(1, "_submit_movement_input_state", actor_entity_id, is_held, match_id, turn_revision, request_id)


func broadcast_movement_input_state(actor_entity_id: String, is_held: bool) -> void:
	if _can_host_send() and NetworkProtocol.is_valid_identifier(actor_entity_id):
		rpc("_receive_movement_input_state", GameSession.get_match_id(), actor_entity_id, is_held)


func request_character_kill(actor_entity_id: String, match_id: String, turn_revision: int, request_id: int) -> void:
	if not _can_send():
		return
	if connection.is_host:
		character_kill_requested.emit(actor_entity_id, match_id, turn_revision, request_id, 0)
		return
	rpc_id(1, "_submit_character_kill", actor_entity_id, match_id, turn_revision, request_id)


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_interaction(actor_entity_id: String, target_surface: Vector3i, match_id: String, turn_revision: int, request_id: int) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id != 0 and NetworkProtocol.is_valid_identifier(actor_entity_id) and turn_revision >= 0 and NetworkProtocol.is_valid_surface_value(target_surface) and _is_valid_intent(match_id, request_id, {"actor_entity_id": actor_entity_id, "target_surface": target_surface, "turn_revision": turn_revision}):
		interaction_requested.emit(actor_entity_id, target_surface, match_id, turn_revision, request_id, requester_peer_id)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_action_payload(match_id: String, sequence_id: int, payload: Dictionary) -> void:
	if _is_valid_match_message(match_id) and sequence_id > 0 and _is_payload_size_valid(payload):
		character_action_payload_received.emit(match_id, sequence_id, payload)


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_character_move_path(
	actor_entity_id: String,
	requested_path: Array[Vector3i],
	match_id: String,
	turn_revision: int,
	request_id: int
) -> void:
	var requester_steam_id: int = _get_registered_sender_steam_id()
	if (
		requester_steam_id != 0
		and NetworkProtocol.is_valid_identifier(actor_entity_id)
		and turn_revision >= 0
		and NetworkProtocol.is_valid_move_path(requested_path)
		and _is_valid_intent(
			match_id,
			request_id,
			{"actor_entity_id": actor_entity_id, "requested_path": requested_path, "turn_revision": turn_revision}
		)
	):
		character_move_path_requested.emit(
			requester_steam_id,
			actor_entity_id,
			requested_path,
			match_id,
			turn_revision,
			request_id
		)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_entity_move(
	match_id: String,
	parent_sequence_id: int,
	subsequence_id: int,
	entity_id: String,
	from_surface: Vector3i,
	target_surface: Vector3i
) -> void:
	if _is_valid_match_message(match_id) and parent_sequence_id > 0 and subsequence_id >= 0 and NetworkProtocol.is_valid_identifier(entity_id) and NetworkProtocol.is_valid_surface_value(from_surface) and NetworkProtocol.is_valid_surface_value(target_surface):
		entity_move_received.emit(parent_sequence_id, subsequence_id, entity_id, from_surface, target_surface)


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_movement_input_state(
	actor_entity_id: String,
	is_held: bool,
	match_id: String,
	turn_revision: int,
	request_id: int
) -> void:
	var requester_steam_id: int = _get_registered_sender_steam_id()
	if (
		requester_steam_id != 0
		and NetworkProtocol.is_valid_identifier(actor_entity_id)
		and turn_revision >= 0
		and _is_valid_intent(
			match_id,
			request_id,
			{"actor_entity_id": actor_entity_id, "is_held": is_held, "turn_revision": turn_revision}
		)
	):
		movement_input_state_requested.emit(
			requester_steam_id,
			actor_entity_id,
			is_held,
			match_id,
			turn_revision,
			request_id
		)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_movement_input_state(match_id: String, actor_entity_id: String, is_held: bool) -> void:
	if _is_valid_match_message(match_id) and NetworkProtocol.is_valid_identifier(actor_entity_id):
		movement_input_state_received.emit(actor_entity_id, is_held)


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_character_kill(actor_entity_id: String, match_id: String, turn_revision: int, request_id: int) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id != 0 and NetworkProtocol.is_valid_identifier(actor_entity_id) and turn_revision >= 0 and _is_valid_intent(match_id, request_id, {"actor_entity_id": actor_entity_id, "turn_revision": turn_revision}):
		character_kill_requested.emit(actor_entity_id, match_id, turn_revision, request_id, requester_peer_id)
