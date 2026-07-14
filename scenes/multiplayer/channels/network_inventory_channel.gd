class_name NetworkInventoryChannel
extends NetworkChannel

signal inventory_add_requested(item_id: String, amount: int, requester_peer_id: int)
signal inventory_move_requested(
	inventory_kind: String,
	source_slot_index: int,
	target_slot_index: int,
	requester_peer_id: int
)
signal inventory_delete_requested(inventory_kind: String, slot_index: int, requester_peer_id: int)
signal inventory_use_requested(slot_index: int, requester_peer_id: int)
signal inventory_snapshot_received(snapshot: Dictionary)


func request_inventory_add(item_id: String, amount: int) -> void:
	if not _can_send():
		return
	if connection.is_host:
		inventory_add_requested.emit(item_id, amount, 0)
		return
	rpc_id(1, "_submit_inventory_add", item_id, amount)


func request_inventory_move(inventory_kind: String, source_slot_index: int, target_slot_index: int) -> void:
	if not _can_send():
		return
	if connection.is_host:
		inventory_move_requested.emit(inventory_kind, source_slot_index, target_slot_index, 0)
		return
	rpc_id(1, "_submit_inventory_move", inventory_kind, source_slot_index, target_slot_index)


func request_inventory_delete(inventory_kind: String, slot_index: int) -> void:
	if not _can_send():
		return
	if connection.is_host:
		inventory_delete_requested.emit(inventory_kind, slot_index, 0)
		return
	rpc_id(1, "_submit_inventory_delete", inventory_kind, slot_index)


func request_inventory_use(slot_index: int) -> void:
	if not _can_send():
		return
	if connection.is_host:
		inventory_use_requested.emit(slot_index, 0)
		return
	rpc_id(1, "_submit_inventory_use", slot_index)


func send_inventory_snapshot(peer_id: int, snapshot: Dictionary) -> void:
	if not _can_host_send() or peer_id == 0:
		return
	if peer_id == multiplayer.get_unique_id():
		inventory_snapshot_received.emit(snapshot)
		return
	rpc_id(peer_id, "_receive_inventory_snapshot", snapshot)


@rpc("any_peer", "reliable")
func _submit_inventory_add(item_id: String, amount: int) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id != 0:
		inventory_add_requested.emit(item_id, amount, requester_peer_id)


@rpc("any_peer", "reliable")
func _submit_inventory_move(inventory_kind: String, source_slot_index: int, target_slot_index: int) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id != 0:
		inventory_move_requested.emit(
			inventory_kind,
			source_slot_index,
			target_slot_index,
			requester_peer_id
		)


@rpc("any_peer", "reliable")
func _submit_inventory_delete(inventory_kind: String, slot_index: int) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id != 0:
		inventory_delete_requested.emit(inventory_kind, slot_index, requester_peer_id)


@rpc("any_peer", "reliable")
func _submit_inventory_use(slot_index: int) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id != 0:
		inventory_use_requested.emit(slot_index, requester_peer_id)


@rpc("authority", "reliable")
func _receive_inventory_snapshot(snapshot: Dictionary) -> void:
	inventory_snapshot_received.emit(snapshot)
