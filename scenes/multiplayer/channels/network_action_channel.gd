class_name NetworkActionChannel
extends NetworkChannel

signal action_started(record: Dictionary)
signal action_completed(sequence_id: int)
signal action_cancelled(record: Dictionary, reason_code: String)
signal action_accepted(request_id: int, sequence_id: int)
signal action_rejected(request_id: int, reason_code: String)
signal stream_snapshot_received(snapshot: Dictionary)
signal stream_snapshot_requested(requester_peer_id: int)


func broadcast_action_started(record: Dictionary) -> void:
	if _can_host_send():
		rpc("_receive_action_started", record)


func broadcast_action_completed(sequence_id: int) -> void:
	if _can_host_send():
		rpc("_receive_action_completed", sequence_id)


func broadcast_action_cancelled(record: Dictionary, reason_code: String) -> void:
	if _can_host_send():
		rpc("_receive_action_cancelled", record, reason_code)


func send_action_accepted(peer_id: int, request_id: int, sequence_id: int) -> void:
	if not _can_host_send() or peer_id <= 0:
		return
	rpc_id(peer_id, "_receive_action_accepted", request_id, sequence_id)


func send_action_rejected(peer_id: int, request_id: int, reason_code: String) -> void:
	if not _can_host_send() or peer_id <= 0:
		return
	rpc_id(peer_id, "_receive_action_rejected", request_id, reason_code)


func send_stream_snapshot(peer_id: int, snapshot: Dictionary) -> void:
	if not _can_host_send() or peer_id <= 0:
		return
	rpc_id(peer_id, "_receive_stream_snapshot", snapshot)


func request_stream_snapshot() -> void:
	if not GameSession.is_multiplayer() or not _can_send() or connection.is_host:
		return
	rpc_id(1, "_submit_stream_snapshot_request")


@rpc("authority", "call_remote", "reliable", 1)
func _receive_action_started(record: Dictionary) -> void:
	action_started.emit(record)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_action_completed(sequence_id: int) -> void:
	action_completed.emit(sequence_id)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_action_cancelled(record: Dictionary, reason_code: String) -> void:
	action_cancelled.emit(record, reason_code)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_action_accepted(request_id: int, sequence_id: int) -> void:
	action_accepted.emit(request_id, sequence_id)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_action_rejected(request_id: int, reason_code: String) -> void:
	action_rejected.emit(request_id, reason_code)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_stream_snapshot(snapshot: Dictionary) -> void:
	stream_snapshot_received.emit(snapshot)


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_stream_snapshot_request() -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id > 0:
		stream_snapshot_requested.emit(requester_peer_id)
