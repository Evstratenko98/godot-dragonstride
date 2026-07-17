class_name NetworkWorldChannel
extends NetworkChannel

signal world_spawn_requested(type_key: String, cell: Vector2i, requester_peer_id: int)
signal world_spawn_received(record: Dictionary)
signal world_spawns_received(records: Array[Dictionary])
signal world_fill_requested(type_key: String, requester_peer_id: int)
signal world_clear_requested(type_key: String, requester_peer_id: int)
signal world_items_removed_received(sequence_id: int, records: Array[Dictionary])
signal world_spawn_failed_received(reason_code: String)


func request_world_spawn(type_key: String, cell: Vector2i) -> void:
	if not GameSession.is_multiplayer():
		return
	if not _can_send():
		world_spawn_failed_received.emit("network_unavailable")
		return
	if connection.is_host:
		world_spawn_requested.emit(type_key, cell, 0)
		return
	rpc_id(1, "_submit_world_spawn", GameSession.get_match_id(), type_key, cell)


func request_world_fill(type_key: String) -> void:
	if not GameSession.is_multiplayer():
		return
	if not _can_send():
		world_spawn_failed_received.emit("network_unavailable")
		return
	if connection.is_host:
		world_fill_requested.emit(type_key, 0)
		return
	rpc_id(1, "_submit_world_fill", GameSession.get_match_id(), type_key)


func request_world_clear(type_key: String) -> void:
	if not GameSession.is_multiplayer():
		return
	if not _can_send():
		world_spawn_failed_received.emit("network_unavailable")
		return
	if connection.is_host:
		world_clear_requested.emit(type_key, 0)
		return
	rpc_id(1, "_submit_world_clear", GameSession.get_match_id(), type_key)


func broadcast_world_spawn(record: Dictionary) -> void:
	if not _can_host_send() or not _is_valid_spawn_record(record) or not _is_payload_size_valid(record):
		return
	store.cache_world_spawn(record)
	rpc("_receive_world_spawn", GameSession.get_match_id(), record)


func broadcast_world_spawns(records: Array[Dictionary]) -> void:
	if not _can_host_send() or not _are_valid_spawn_records(records):
		return
	store.cache_world_spawns(records)
	rpc("_receive_world_spawns", GameSession.get_match_id(), records)


func broadcast_world_items_removed(records: Array[Dictionary], sequence_id: int = 0) -> void:
	if not _can_host_send() or sequence_id < 0 or not _are_valid_removal_records(records):
		return
	store.cache_world_item_removals(records)
	rpc("_receive_world_items_removed", GameSession.get_match_id(), sequence_id, records)


func send_world_spawn_failed(peer_id: int, reason_code: String) -> void:
	if not connection.is_host:
		return
	if peer_id == 0 or peer_id == multiplayer.get_unique_id():
		world_spawn_failed_received.emit(reason_code)
		return
	if _can_host_send():
		rpc_id(peer_id, "_receive_world_spawn_failed", GameSession.get_match_id(), reason_code)


func send_world_spawns_to_peer(peer_id: int) -> void:
	var records: Array[Dictionary] = store.get_world_spawn_records()
	if _can_host_send() and peer_id != 0 and not records.is_empty():
		rpc_id(peer_id, "_receive_world_spawns", GameSession.get_match_id(), records)


func send_world_removals_to_peer(peer_id: int) -> void:
	var records: Array[Dictionary] = store.get_removed_world_items()
	if _can_host_send() and peer_id != 0 and not records.is_empty():
		rpc_id(peer_id, "_receive_world_items_removed", GameSession.get_match_id(), 0, records)


@rpc("any_peer", "reliable")
func _submit_world_spawn(match_id: String, type_key: String, cell: Vector2i) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id != 0 and _is_valid_match_message(match_id) and NetworkProtocol.is_valid_identifier(type_key) and NetworkProtocol.is_valid_cell_value(cell):
		world_spawn_requested.emit(type_key, cell, requester_peer_id)


@rpc("any_peer", "reliable")
func _submit_world_fill(match_id: String, type_key: String) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id != 0 and _is_valid_match_message(match_id) and NetworkProtocol.is_valid_identifier(type_key):
		world_fill_requested.emit(type_key, requester_peer_id)


@rpc("any_peer", "reliable")
func _submit_world_clear(match_id: String, type_key: String) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id != 0 and _is_valid_match_message(match_id) and NetworkProtocol.is_valid_bounded_text(type_key):
		world_clear_requested.emit(type_key, requester_peer_id)


@rpc("authority", "reliable")
func _receive_world_spawn(match_id: String, record: Dictionary) -> void:
	if not _is_valid_match_message(match_id) or not _is_valid_spawn_record(record) or not _is_payload_size_valid(record):
		return
	store.cache_world_spawn(record)
	world_spawn_received.emit(record)


@rpc("authority", "reliable")
func _receive_world_spawns(match_id: String, records: Array[Dictionary]) -> void:
	if not _is_valid_match_message(match_id) or not _are_valid_spawn_records(records):
		return
	store.cache_world_spawns(records)
	world_spawns_received.emit(records)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_world_items_removed(match_id: String, sequence_id: int, records: Array[Dictionary]) -> void:
	if not _is_valid_match_message(match_id) or sequence_id < 0 or not _are_valid_removal_records(records):
		return
	store.cache_world_item_removals(records)
	world_items_removed_received.emit(sequence_id, records)


@rpc("authority", "reliable")
func _receive_world_spawn_failed(match_id: String, reason_code: String) -> void:
	if _is_valid_match_message(match_id) and NetworkProtocol.is_safe_reason_code(reason_code):
		world_spawn_failed_received.emit(reason_code)


func _is_valid_spawn_record(record: Dictionary) -> bool:
	var spawn_id: String = str(record.get("spawn_id", ""))
	var type_key: String = str(record.get("type_key", ""))
	var cell_value: Variant = record.get("cell")
	var cell: Vector2i = record.get("cell", Vector2i.ZERO)
	return (
		NetworkProtocol.is_valid_identifier(spawn_id)
		and NetworkProtocol.is_valid_identifier(type_key)
		and cell_value is Vector2i
		and NetworkProtocol.is_valid_cell_value(cell)
	)


func _are_valid_spawn_records(records: Array[Dictionary]) -> bool:
	if (
		records.is_empty()
		or records.size() > NetworkProtocol.MAX_WORLD_RECORDS
		or not _is_payload_size_valid(records, NetworkProtocol.MAX_SNAPSHOT_BYTES)
	):
		return false
	for record: Dictionary in records:
		if not _is_valid_spawn_record(record):
			return false
	return true


func _are_valid_removal_records(records: Array[Dictionary]) -> bool:
	if (
		records.is_empty()
		or records.size() > NetworkProtocol.MAX_WORLD_RECORDS
		or not _is_payload_size_valid(records, NetworkProtocol.MAX_SNAPSHOT_BYTES)
	):
		return false
	for record: Dictionary in records:
		var kind: String = str(record.get("kind", ""))
		var item_id: String = str(record.get("id", ""))
		if kind not in ["entity", "object"] or not NetworkProtocol.is_valid_identifier(item_id):
			return false
	return true
