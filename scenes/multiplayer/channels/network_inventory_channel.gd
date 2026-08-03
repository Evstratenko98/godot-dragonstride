class_name NetworkInventoryChannel
extends NetworkChannel

signal inventory_add_requested(actor_entity_id: String, item_id: String, amount: int, expected_inventory_revision: int, match_id: String, turn_revision: int, request_id: int, requester_peer_id: int)
signal inventory_move_requested(
	actor_entity_id: String,
	inventory_kind: String,
	source_slot_index: int,
	target_slot_index: int,
	expected_inventory_revision: int,
	match_id: String,
	turn_revision: int,
	request_id: int,
	requester_peer_id: int
)
signal inventory_delete_requested(actor_entity_id: String, inventory_kind: String, slot_index: int, expected_inventory_revision: int, match_id: String, turn_revision: int, request_id: int, requester_peer_id: int)
signal inventory_use_requested(actor_entity_id: String, slot_index: int, expected_inventory_revision: int, match_id: String, turn_revision: int, request_id: int, requester_peer_id: int)
signal inventory_snapshot_received(snapshot: Dictionary, sequence_id: int)
signal inventory_action_payload_received(match_id: String, sequence_id: int, payload: Dictionary)


func request_inventory_add(actor_entity_id: String, item_id: String, amount: int, expected_inventory_revision: int, match_id: String, turn_revision: int, request_id: int) -> void:
	if not _can_send():
		return
	if connection.is_host:
		inventory_add_requested.emit(actor_entity_id, item_id, amount, expected_inventory_revision, match_id, turn_revision, request_id, 0)
		return
	rpc_id(1, "_submit_inventory_add", actor_entity_id, item_id, amount, expected_inventory_revision, match_id, turn_revision, request_id)


func request_inventory_move(actor_entity_id: String, inventory_kind: String, source_slot_index: int, target_slot_index: int, expected_inventory_revision: int, match_id: String, turn_revision: int, request_id: int) -> void:
	if not _can_send():
		return
	if connection.is_host:
		inventory_move_requested.emit(actor_entity_id, inventory_kind, source_slot_index, target_slot_index, expected_inventory_revision, match_id, turn_revision, request_id, 0)
		return
	rpc_id(1, "_submit_inventory_move", actor_entity_id, inventory_kind, source_slot_index, target_slot_index, expected_inventory_revision, match_id, turn_revision, request_id)


func request_inventory_delete(actor_entity_id: String, inventory_kind: String, slot_index: int, expected_inventory_revision: int, match_id: String, turn_revision: int, request_id: int) -> void:
	if not _can_send():
		return
	if connection.is_host:
		inventory_delete_requested.emit(actor_entity_id, inventory_kind, slot_index, expected_inventory_revision, match_id, turn_revision, request_id, 0)
		return
	rpc_id(1, "_submit_inventory_delete", actor_entity_id, inventory_kind, slot_index, expected_inventory_revision, match_id, turn_revision, request_id)


func request_inventory_use(actor_entity_id: String, slot_index: int, expected_inventory_revision: int, match_id: String, turn_revision: int, request_id: int) -> void:
	if not _can_send():
		return
	if connection.is_host:
		inventory_use_requested.emit(actor_entity_id, slot_index, expected_inventory_revision, match_id, turn_revision, request_id, 0)
		return
	rpc_id(1, "_submit_inventory_use", actor_entity_id, slot_index, expected_inventory_revision, match_id, turn_revision, request_id)


func broadcast_action_payload(match_id: String, sequence_id: int, payload: Dictionary) -> void:
	if _can_host_send() and _is_valid_match_message(match_id) and sequence_id > 0 and _is_payload_size_valid(payload):
		rpc("_receive_action_payload", match_id, sequence_id, payload)


func send_inventory_snapshot(peer_id: int, snapshot: Dictionary, sequence_id: int = 0) -> void:
	if not _can_host_send() or peer_id == 0 or not _is_payload_size_valid(snapshot):
		return
	if peer_id == multiplayer.get_unique_id():
		inventory_snapshot_received.emit(snapshot, sequence_id)
		return
	rpc_id(peer_id, "_receive_inventory_snapshot", GameSession.get_match_id(), snapshot, sequence_id)


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_inventory_add(actor_entity_id: String, item_id: String, amount: int, expected_inventory_revision: int, match_id: String, turn_revision: int, request_id: int) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if (
		requester_peer_id != 0
		and NetworkProtocol.is_valid_identifier(actor_entity_id)
		and NetworkProtocol.is_valid_identifier(item_id)
		and amount > 0
		and amount <= CharacterInventory.get_max_intent_amount()
		and expected_inventory_revision >= 0
		and turn_revision >= 0
		and _is_valid_intent(match_id, request_id, {
			"actor_entity_id": actor_entity_id,
			"item_id": item_id,
			"amount": amount,
			"expected_inventory_revision": expected_inventory_revision,
			"turn_revision": turn_revision,
		})
	):
		inventory_add_requested.emit(actor_entity_id, item_id, amount, expected_inventory_revision, match_id, turn_revision, request_id, requester_peer_id)


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_inventory_move(actor_entity_id: String, inventory_kind: String, source_slot_index: int, target_slot_index: int, expected_inventory_revision: int, match_id: String, turn_revision: int, request_id: int) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id != 0 and NetworkProtocol.is_valid_identifier(actor_entity_id) and CharacterInventory.is_valid_slot_index_for_kind(inventory_kind, source_slot_index) and CharacterInventory.is_valid_slot_index_for_kind(inventory_kind, target_slot_index) and expected_inventory_revision >= 0 and turn_revision >= 0 and _is_valid_intent(match_id, request_id, {
		"actor_entity_id": actor_entity_id,
		"inventory_kind": inventory_kind,
		"source_slot_index": source_slot_index,
		"target_slot_index": target_slot_index,
		"expected_inventory_revision": expected_inventory_revision,
		"turn_revision": turn_revision,
	}):
		inventory_move_requested.emit(
			actor_entity_id,
			inventory_kind,
			source_slot_index,
			target_slot_index,
			expected_inventory_revision,
			match_id,
			turn_revision,
			request_id,
			requester_peer_id
		)


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_inventory_delete(actor_entity_id: String, inventory_kind: String, slot_index: int, expected_inventory_revision: int, match_id: String, turn_revision: int, request_id: int) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id != 0 and NetworkProtocol.is_valid_identifier(actor_entity_id) and CharacterInventory.is_valid_slot_index_for_kind(inventory_kind, slot_index) and expected_inventory_revision >= 0 and turn_revision >= 0 and _is_valid_intent(match_id, request_id, {
		"actor_entity_id": actor_entity_id,
		"inventory_kind": inventory_kind,
		"slot_index": slot_index,
		"expected_inventory_revision": expected_inventory_revision,
		"turn_revision": turn_revision,
	}):
		inventory_delete_requested.emit(actor_entity_id, inventory_kind, slot_index, expected_inventory_revision, match_id, turn_revision, request_id, requester_peer_id)


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_inventory_use(actor_entity_id: String, slot_index: int, expected_inventory_revision: int, match_id: String, turn_revision: int, request_id: int) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id != 0 and NetworkProtocol.is_valid_identifier(actor_entity_id) and CharacterInventory.is_valid_slot_index_for_kind(CharacterInventory.INVENTORY_KIND_ITEM, slot_index) and expected_inventory_revision >= 0 and turn_revision >= 0 and _is_valid_intent(match_id, request_id, {
		"actor_entity_id": actor_entity_id,
		"slot_index": slot_index,
		"expected_inventory_revision": expected_inventory_revision,
		"turn_revision": turn_revision,
	}):
		inventory_use_requested.emit(actor_entity_id, slot_index, expected_inventory_revision, match_id, turn_revision, request_id, requester_peer_id)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_inventory_snapshot(match_id: String, snapshot: Dictionary, sequence_id: int) -> void:
	if _is_valid_match_message(match_id) and sequence_id >= 0 and _is_payload_size_valid(snapshot):
		inventory_snapshot_received.emit(snapshot, sequence_id)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_action_payload(match_id: String, sequence_id: int, payload: Dictionary) -> void:
	if _is_valid_match_message(match_id) and sequence_id > 0 and _is_payload_size_valid(payload):
		inventory_action_payload_received.emit(match_id, sequence_id, payload)
