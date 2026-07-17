class_name NetworkSpellChannel
extends NetworkChannel

signal spell_cast_requested(spell_slot_index: int, target_cell: Vector2i, match_id: String, turn_revision: int, request_id: int, requester_peer_id: int)
signal spell_action_payload_received(match_id: String, sequence_id: int, payload: Dictionary)


func request_spell_cast(spell_slot_index: int, target_cell: Vector2i, match_id: String, turn_revision: int, request_id: int) -> void:
	if not _can_send():
		return
	if connection.is_host:
		spell_cast_requested.emit(spell_slot_index, target_cell, match_id, turn_revision, request_id, 0)
		return
	rpc_id(1, "_submit_spell_cast", spell_slot_index, target_cell, match_id, turn_revision, request_id)


func broadcast_action_payload(match_id: String, sequence_id: int, payload: Dictionary) -> void:
	if _can_host_send() and _is_valid_match_message(match_id) and sequence_id > 0 and _is_payload_size_valid(payload):
		rpc("_receive_action_payload", match_id, sequence_id, payload)


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_spell_cast(spell_slot_index: int, target_cell: Vector2i, match_id: String, turn_revision: int, request_id: int) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id != 0 and spell_slot_index >= 0 and spell_slot_index < CharacterInventory.SPELL_SLOT_COUNT and turn_revision >= 0 and NetworkProtocol.is_valid_cell_value(target_cell) and _is_valid_intent(match_id, request_id, {"spell_slot_index": spell_slot_index, "target_cell": target_cell, "turn_revision": turn_revision}):
		spell_cast_requested.emit(spell_slot_index, target_cell, match_id, turn_revision, request_id, requester_peer_id)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_action_payload(match_id: String, sequence_id: int, payload: Dictionary) -> void:
	if _is_valid_match_message(match_id) and sequence_id > 0 and _is_payload_size_valid(payload):
		spell_action_payload_received.emit(match_id, sequence_id, payload)
