class_name NetworkWorldChannel
extends NetworkChannel

signal world_spawn_requested(type_key: String, cell: Vector2i, requester_peer_id: int)
signal world_spawn_received(record: Dictionary)
signal world_spawns_received(records: Array[Dictionary])
signal world_fill_requested(type_key: String, requester_peer_id: int)
signal world_clear_requested(type_key: String, requester_peer_id: int)
signal world_items_removed_received(sequence_id: int, records: Array[Dictionary])
signal world_spawn_failed_received(message: String)


func request_world_spawn(type_key: String, cell: Vector2i) -> void:
	if not GameSession.is_multiplayer():
		return
	if not _can_send():
		world_spawn_failed_received.emit("Cannot create spawn: network is not ready.")
		return
	if connection.is_host:
		world_spawn_requested.emit(type_key, cell, 0)
		return
	rpc_id(1, "_submit_world_spawn", type_key, cell)


func request_world_fill(type_key: String) -> void:
	if not GameSession.is_multiplayer():
		return
	if not _can_send():
		world_spawn_failed_received.emit("Cannot fill world: network is not ready.")
		return
	if connection.is_host:
		world_fill_requested.emit(type_key, 0)
		return
	rpc_id(1, "_submit_world_fill", type_key)


func request_world_clear(type_key: String) -> void:
	if not GameSession.is_multiplayer():
		return
	if not _can_send():
		world_spawn_failed_received.emit("Cannot clear world: network is not ready.")
		return
	if connection.is_host:
		world_clear_requested.emit(type_key, 0)
		return
	rpc_id(1, "_submit_world_clear", type_key)


func broadcast_world_spawn(record: Dictionary) -> void:
	if not _can_host_send():
		return
	store.cache_world_spawn(record)
	rpc("_receive_world_spawn", record)


func broadcast_world_spawns(records: Array[Dictionary]) -> void:
	if not _can_host_send() or records.is_empty():
		return
	store.cache_world_spawns(records)
	rpc("_receive_world_spawns", records)


func broadcast_world_items_removed(records: Array[Dictionary], sequence_id: int = 0) -> void:
	if not _can_host_send() or records.is_empty():
		return
	store.cache_world_item_removals(records)
	rpc("_receive_world_items_removed", sequence_id, records)


func send_world_spawn_failed(peer_id: int, message: String) -> void:
	if not connection.is_host:
		return
	if peer_id == 0 or peer_id == multiplayer.get_unique_id():
		world_spawn_failed_received.emit(message)
		return
	if _can_host_send():
		rpc_id(peer_id, "_receive_world_spawn_failed", message)


func send_world_spawns_to_peer(peer_id: int) -> void:
	var records: Array[Dictionary] = store.get_world_spawn_records()
	if _can_host_send() and peer_id != 0 and not records.is_empty():
		rpc_id(peer_id, "_receive_world_spawns", records)


func send_world_removals_to_peer(peer_id: int) -> void:
	var records: Array[Dictionary] = store.get_removed_world_items()
	if _can_host_send() and peer_id != 0 and not records.is_empty():
		rpc_id(peer_id, "_receive_world_items_removed", 0, records)


@rpc("any_peer", "reliable")
func _submit_world_spawn(type_key: String, cell: Vector2i) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id != 0:
		world_spawn_requested.emit(type_key, cell, requester_peer_id)


@rpc("any_peer", "reliable")
func _submit_world_fill(type_key: String) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id != 0:
		world_fill_requested.emit(type_key, requester_peer_id)


@rpc("any_peer", "reliable")
func _submit_world_clear(type_key: String) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id != 0:
		world_clear_requested.emit(type_key, requester_peer_id)


@rpc("authority", "reliable")
func _receive_world_spawn(record: Dictionary) -> void:
	store.cache_world_spawn(record)
	world_spawn_received.emit(record)


@rpc("authority", "reliable")
func _receive_world_spawns(records: Array[Dictionary]) -> void:
	store.cache_world_spawns(records)
	world_spawns_received.emit(records)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_world_items_removed(sequence_id: int, records: Array[Dictionary]) -> void:
	store.cache_world_item_removals(records)
	world_items_removed_received.emit(sequence_id, records)


@rpc("authority", "reliable")
func _receive_world_spawn_failed(message: String) -> void:
	world_spawn_failed_received.emit(message)
