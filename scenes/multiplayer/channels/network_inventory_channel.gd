class_name NetworkInventoryChannel
extends NetworkChannel

signal inventory_add_requested(item_id: String, amount: int, request_id: int, requester_peer_id: int)
signal inventory_move_requested(
	inventory_kind: String,
	source_slot_index: int,
	target_slot_index: int,
	request_id: int,
	requester_peer_id: int
)
signal inventory_delete_requested(inventory_kind: String, slot_index: int, request_id: int, requester_peer_id: int)
signal inventory_use_requested(slot_index: int, request_id: int, requester_peer_id: int)
signal inventory_snapshot_received(snapshot: Dictionary, sequence_id: int)
signal inventory_action_payload_received(sequence_id: int, payload: Dictionary)


func request_inventory_add(item_id: String, amount: int, request_id: int) -> void:
	if not _can_send():
		return
	if connection.is_host:
		inventory_add_requested.emit(item_id, amount, request_id, 0)
		return
	rpc_id(1, "_submit_inventory_add", item_id, amount, request_id)


func request_inventory_move(inventory_kind: String, source_slot_index: int, target_slot_index: int, request_id: int) -> void:
	if not _can_send():
		return
	if connection.is_host:
		inventory_move_requested.emit(inventory_kind, source_slot_index, target_slot_index, request_id, 0)
		return
	rpc_id(1, "_submit_inventory_move", inventory_kind, source_slot_index, target_slot_index, request_id)


func request_inventory_delete(inventory_kind: String, slot_index: int, request_id: int) -> void:
	if not _can_send():
		return
	if connection.is_host:
		inventory_delete_requested.emit(inventory_kind, slot_index, request_id, 0)
		return
	rpc_id(1, "_submit_inventory_delete", inventory_kind, slot_index, request_id)


func request_inventory_use(slot_index: int, request_id: int) -> void:
	if not _can_send():
		return
	if connection.is_host:
		inventory_use_requested.emit(slot_index, request_id, 0)
		return
	rpc_id(1, "_submit_inventory_use", slot_index, request_id)


func broadcast_action_payload(sequence_id: int, payload: Dictionary) -> void:
	if _can_host_send() and sequence_id > 0:
		rpc("_receive_action_payload", sequence_id, payload)


func send_inventory_snapshot(peer_id: int, snapshot: Dictionary, sequence_id: int = 0) -> void:
	if not _can_host_send() or peer_id == 0:
		return
	if peer_id == multiplayer.get_unique_id():
		inventory_snapshot_received.emit(snapshot, sequence_id)
		return
	rpc_id(peer_id, "_receive_inventory_snapshot", snapshot, sequence_id)


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_inventory_add(item_id: String, amount: int, request_id: int) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id != 0 and request_id > 0:
		inventory_add_requested.emit(item_id, amount, request_id, requester_peer_id)


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_inventory_move(inventory_kind: String, source_slot_index: int, target_slot_index: int, request_id: int) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id != 0 and request_id > 0:
		inventory_move_requested.emit(
			inventory_kind,
			source_slot_index,
			target_slot_index,
			request_id,
			requester_peer_id
		)


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_inventory_delete(inventory_kind: String, slot_index: int, request_id: int) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id != 0 and request_id > 0:
		inventory_delete_requested.emit(inventory_kind, slot_index, request_id, requester_peer_id)


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_inventory_use(slot_index: int, request_id: int) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id != 0 and request_id > 0:
		inventory_use_requested.emit(slot_index, request_id, requester_peer_id)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_inventory_snapshot(snapshot: Dictionary, sequence_id: int) -> void:
	inventory_snapshot_received.emit(snapshot, sequence_id)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_action_payload(sequence_id: int, payload: Dictionary) -> void:
	inventory_action_payload_received.emit(sequence_id, payload)
