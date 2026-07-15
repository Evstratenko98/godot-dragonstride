class_name NetworkSpellChannel
extends NetworkChannel

signal spell_cast_requested(spell_slot_index: int, target_cell: Vector2i, request_id: int, requester_peer_id: int)
signal spell_action_payload_received(sequence_id: int, payload: Dictionary)


func request_spell_cast(spell_slot_index: int, target_cell: Vector2i, request_id: int) -> void:
	if not _can_send():
		return
	if connection.is_host:
		spell_cast_requested.emit(spell_slot_index, target_cell, request_id, 0)
		return
	rpc_id(1, "_submit_spell_cast", spell_slot_index, target_cell, request_id)


func broadcast_action_payload(sequence_id: int, payload: Dictionary) -> void:
	if _can_host_send() and sequence_id > 0:
		rpc("_receive_action_payload", sequence_id, payload)


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_spell_cast(spell_slot_index: int, target_cell: Vector2i, request_id: int) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id != 0 and request_id > 0:
		spell_cast_requested.emit(spell_slot_index, target_cell, request_id, requester_peer_id)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_action_payload(sequence_id: int, payload: Dictionary) -> void:
	spell_action_payload_received.emit(sequence_id, payload)
