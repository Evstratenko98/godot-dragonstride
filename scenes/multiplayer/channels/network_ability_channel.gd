class_name NetworkAbilityChannel
extends NetworkChannel

signal character_ability_requested(
	actor_entity_id: String,
	ability_id: String,
	target_surface: Vector3i,
	match_id: String,
	turn_revision: int,
	request_id: int,
	requester_peer_id: int
)
signal ability_action_payload_received(match_id: String, sequence_id: int, payload: Dictionary)


func request_character_ability(
	actor_entity_id: String,
	ability_id: String,
	target_surface: Vector3i,
	match_id: String,
	turn_revision: int,
	request_id: int
) -> void:
	if not _can_send() or not _is_valid_request(actor_entity_id, ability_id, target_surface, turn_revision, request_id):
		return
	if connection.is_host:
		character_ability_requested.emit(
			actor_entity_id,
			ability_id,
			target_surface,
			match_id,
			turn_revision,
			request_id,
			0
		)
		return
	rpc_id(
		1,
		"_submit_character_ability",
		actor_entity_id,
		ability_id,
		target_surface,
		match_id,
		turn_revision,
		request_id
	)


func broadcast_action_payload(match_id: String, sequence_id: int, payload: Dictionary) -> void:
	if _can_host_send() and _is_valid_match_message(match_id) and sequence_id > 0 and _is_payload_size_valid(payload):
		rpc("_receive_ability_action_payload", match_id, sequence_id, payload)


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_character_ability(
	actor_entity_id: String,
	ability_id: String,
	target_surface: Vector3i,
	match_id: String,
	turn_revision: int,
	request_id: int
) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if (
		requester_peer_id == 0
		or not _is_valid_request(actor_entity_id, ability_id, target_surface, turn_revision, request_id)
		or not _is_valid_intent(match_id, request_id, {
			"actor_entity_id": actor_entity_id,
			"ability_id": ability_id,
			"target_surface": target_surface,
			"turn_revision": turn_revision,
		})
	):
		return
	character_ability_requested.emit(
		actor_entity_id,
		ability_id,
		target_surface,
		match_id,
		turn_revision,
		request_id,
		requester_peer_id
	)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_ability_action_payload(match_id: String, sequence_id: int, payload: Dictionary) -> void:
	if _is_valid_match_message(match_id) and sequence_id > 0 and _is_payload_size_valid(payload):
		ability_action_payload_received.emit(match_id, sequence_id, payload)


func _is_valid_request(
	actor_entity_id: String,
	ability_id: String,
	target_surface: Vector3i,
	turn_revision: int,
	request_id: int
) -> bool:
	return (
		NetworkProtocol.is_valid_identifier(actor_entity_id)
		and NetworkProtocol.is_valid_identifier(ability_id)
		and NetworkProtocol.is_valid_surface_value(target_surface)
		and turn_revision >= 0
		and request_id > 0
	)
