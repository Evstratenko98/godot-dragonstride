class_name NetworkSpellChannel
extends NetworkChannel

signal spell_cast_requested(spell_slot_index: int, target_cell: Vector2i, requester_peer_id: int)
signal spell_cast_received(
	cast_id: String,
	caster_entity_id: String,
	spell_id: String,
	spell_slot_index: int,
	target_cell: Vector2i
)
signal spell_cast_rejected(reason_code: String)


func request_spell_cast(spell_slot_index: int, target_cell: Vector2i) -> void:
	if not _can_send():
		return
	if connection.is_host:
		spell_cast_requested.emit(spell_slot_index, target_cell, 0)
		return
	rpc_id(1, "_submit_spell_cast", spell_slot_index, target_cell)


func broadcast_spell_cast(
	cast_id: String,
	caster_entity_id: String,
	spell_id: String,
	spell_slot_index: int,
	target_cell: Vector2i
) -> void:
	if _can_host_send():
		rpc(
			"_receive_spell_cast",
			cast_id,
			caster_entity_id,
			spell_id,
			spell_slot_index,
			target_cell
		)


func send_spell_cast_rejection(peer_id: int, reason_code: String) -> void:
	if not _can_host_send() or peer_id == 0 or reason_code.is_empty():
		return
	rpc_id(peer_id, "_receive_spell_cast_rejection", reason_code)


@rpc("any_peer", "reliable")
func _submit_spell_cast(spell_slot_index: int, target_cell: Vector2i) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id != 0:
		spell_cast_requested.emit(spell_slot_index, target_cell, requester_peer_id)


@rpc("authority", "reliable")
func _receive_spell_cast(
	cast_id: String,
	caster_entity_id: String,
	spell_id: String,
	spell_slot_index: int,
	target_cell: Vector2i
) -> void:
	spell_cast_received.emit(cast_id, caster_entity_id, spell_id, spell_slot_index, target_cell)


@rpc("authority", "reliable")
func _receive_spell_cast_rejection(reason_code: String) -> void:
	spell_cast_rejected.emit(reason_code)
