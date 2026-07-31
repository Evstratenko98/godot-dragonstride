class_name NetworkLootChannel
extends NetworkChannel

signal loot_claim_requested(
	chest_id: String,
	inventory_kind: String,
	target_slot_index: int,
	expected_inventory_revision: int,
	match_id: String,
	turn_revision: int,
	request_id: int,
	requester_peer_id: int
)
signal loot_discard_requested(chest_id: String, match_id: String, request_id: int, requester_peer_id: int)
signal loot_discarded_received(chest_id: String, opener_entity_id: String)
signal loot_discard_rejected(chest_id: String, reason_code: String)


func request_loot_claim(
	chest_id: String,
	inventory_kind: String,
	target_slot_index: int,
	expected_inventory_revision: int,
	match_id: String,
	turn_revision: int,
	request_id: int
) -> void:
	if not _can_send():
		return
	if connection.is_host:
		loot_claim_requested.emit(
			chest_id,
			inventory_kind,
			target_slot_index,
			expected_inventory_revision,
			match_id,
			turn_revision,
			request_id,
			0
		)
		return
	rpc_id(
		1,
		"_submit_loot_claim",
		chest_id,
		inventory_kind,
		target_slot_index,
		expected_inventory_revision,
		match_id,
		turn_revision,
		request_id
	)


func request_loot_discard(chest_id: String, match_id: String, request_id: int) -> void:
	if not _can_send():
		return
	if connection.is_host:
		loot_discard_requested.emit(chest_id, match_id, request_id, 0)
		return
	rpc_id(1, "_submit_loot_discard", chest_id, match_id, request_id)


func broadcast_loot_discarded(chest_id: String, opener_entity_id: String) -> void:
	if not _can_host_send() or not _is_valid_resolution(chest_id, opener_entity_id):
		return
	loot_discarded_received.emit(chest_id, opener_entity_id)
	rpc("_receive_loot_discarded", GameSession.get_match_id(), chest_id, opener_entity_id)


func send_loot_discard_rejected(peer_id: int, chest_id: String, reason_code: String) -> void:
	if (
		not _can_host_send()
		or peer_id <= 0
		or not NetworkProtocol.is_valid_identifier(chest_id)
		or not NetworkProtocol.is_safe_reason_code(reason_code)
	):
		return
	rpc_id(peer_id, "_receive_loot_discard_rejected", GameSession.get_match_id(), chest_id, reason_code)


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_loot_claim(
	chest_id: String,
	inventory_kind: String,
	target_slot_index: int,
	expected_inventory_revision: int,
	match_id: String,
	turn_revision: int,
	request_id: int
) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if (
		requester_peer_id == 0
		or not NetworkProtocol.is_valid_identifier(chest_id)
		or inventory_kind not in [
			CharacterInventory.INVENTORY_KIND_ITEM,
			CharacterInventory.INVENTORY_KIND_SPELL,
		]
		or target_slot_index < 0
		or target_slot_index >= CharacterInventory.ITEM_SLOT_COUNT
		or expected_inventory_revision < 0
		or turn_revision < 0
		or not _is_valid_intent(match_id, request_id, {
			"chest_id": chest_id,
			"inventory_kind": inventory_kind,
			"target_slot_index": target_slot_index,
			"expected_inventory_revision": expected_inventory_revision,
			"turn_revision": turn_revision,
		})
	):
		return
	loot_claim_requested.emit(
		chest_id,
		inventory_kind,
		target_slot_index,
		expected_inventory_revision,
		match_id,
		turn_revision,
		request_id,
		requester_peer_id
	)


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_loot_discard(chest_id: String, match_id: String, request_id: int) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if (
		requester_peer_id != 0
		and NetworkProtocol.is_valid_identifier(chest_id)
		and _is_valid_intent(match_id, request_id, {"chest_id": chest_id})
	):
		loot_discard_requested.emit(chest_id, match_id, request_id, requester_peer_id)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_loot_discarded(match_id: String, chest_id: String, opener_entity_id: String) -> void:
	if _is_valid_match_message(match_id) and _is_valid_resolution(chest_id, opener_entity_id):
		loot_discarded_received.emit(chest_id, opener_entity_id)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_loot_discard_rejected(
	match_id: String,
	chest_id: String,
	reason_code: String
) -> void:
	if (
		_is_valid_match_message(match_id)
		and NetworkProtocol.is_valid_identifier(chest_id)
		and NetworkProtocol.is_safe_reason_code(reason_code)
	):
		loot_discard_rejected.emit(chest_id, reason_code)


func _is_valid_resolution(chest_id: String, opener_entity_id: String) -> bool:
	return (
		NetworkProtocol.is_valid_identifier(chest_id)
		and NetworkProtocol.is_valid_identifier(opener_entity_id)
	)
