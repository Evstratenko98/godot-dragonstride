class_name NetworkActionChannel
extends NetworkChannel

signal action_started(record: Dictionary)
signal action_completed(record: Dictionary)
signal action_cancelled(record: Dictionary, reason_code: String)
signal action_accepted(request_id: int, sequence_id: int)
signal action_rejected(request_id: int, reason_code: String)
signal stream_snapshot_received(sync_id: String, snapshot: Dictionary)
signal stream_snapshot_pending(sync_id: String, active_sequence_id: int)
signal stream_snapshot_invalid(sync_id: String)
signal stream_snapshot_requested(
	requester_peer_id: int,
	match_id: String,
	sync_id: String,
	expected_sequence_id: int
)

var snapshot_assemblies: Dictionary[String, Dictionary] = {}


func _ready() -> void:
	if not GameSession.session_cleared.is_connected(_on_session_cleared):
		GameSession.session_cleared.connect(_on_session_cleared)


func _exit_tree() -> void:
	if GameSession.session_cleared.is_connected(_on_session_cleared):
		GameSession.session_cleared.disconnect(_on_session_cleared)


func broadcast_action_started(record: Dictionary) -> void:
	if _can_host_send() and _is_valid_lifecycle_record(record):
		rpc("_receive_action_started", record)


func broadcast_action_completed(match_id: String, sequence_id: int) -> void:
	if not _can_host_send() or not _is_valid_match_message(match_id) or sequence_id <= 0:
		return
	rpc("_receive_action_completed", {
		"protocol_version": NetworkProtocol.PROTOCOL_VERSION,
		"match_id": match_id,
		"sequence_id": sequence_id,
	})


func broadcast_action_cancelled(record: Dictionary, reason_code: String) -> void:
	if (
		_can_host_send()
		and _is_valid_lifecycle_record(record)
		and NetworkProtocol.is_safe_reason_code(reason_code)
	):
		rpc("_receive_action_cancelled", record, reason_code)


func send_action_accepted(peer_id: int, request_id: int, sequence_id: int) -> void:
	if not _can_host_send() or peer_id <= 0 or request_id <= 0 or sequence_id <= 0:
		return
	if peer_id == multiplayer.get_unique_id():
		action_accepted.emit(request_id, sequence_id)
		return
	rpc_id(peer_id, "_receive_action_accepted", GameSession.get_match_id(), request_id, sequence_id)


func send_action_rejected(peer_id: int, request_id: int, reason_code: String) -> void:
	if (
		not _can_host_send()
		or peer_id <= 0
		or request_id <= 0
		or not NetworkProtocol.is_safe_reason_code(reason_code)
	):
		return
	if peer_id == multiplayer.get_unique_id():
		action_rejected.emit(request_id, reason_code)
		return
	rpc_id(peer_id, "_receive_action_rejected", GameSession.get_match_id(), request_id, reason_code)


func send_stream_snapshot(peer_id: int, match_id: String, sync_id: String, snapshot: Dictionary) -> void:
	if (
		not _can_host_send()
		or peer_id <= 0
		or not _is_valid_match_message(match_id)
		or not NetworkProtocol.is_valid_identifier(sync_id)
	):
		return
	var serialized_snapshot: PackedByteArray = var_to_bytes(snapshot)
	if not NetworkProtocol.is_valid_snapshot_size(serialized_snapshot):
		return
	var chunk_count: int = ceili(
		float(serialized_snapshot.size()) / float(NetworkProtocol.SNAPSHOT_CHUNK_BYTES)
	)
	if chunk_count <= 0 or chunk_count > NetworkProtocol.MAX_SNAPSHOT_CHUNKS:
		return
	var checksum: String = _get_sha256(serialized_snapshot)
	if checksum.length() != 64:
		return
	for chunk_index: int in range(chunk_count):
		var start_offset: int = chunk_index * NetworkProtocol.SNAPSHOT_CHUNK_BYTES
		var end_offset: int = mini(
			start_offset + NetworkProtocol.SNAPSHOT_CHUNK_BYTES,
			serialized_snapshot.size()
		)
		var chunk: PackedByteArray = serialized_snapshot.slice(start_offset, end_offset)
		rpc_id(
			peer_id,
			"_receive_stream_snapshot_chunk",
			NetworkProtocol.PROTOCOL_VERSION,
			match_id,
			sync_id,
			chunk_index,
			chunk_count,
			checksum,
			chunk
		)


func send_stream_snapshot_pending(
	peer_id: int,
	match_id: String,
	sync_id: String,
	active_sequence_id: int
) -> void:
	if not _can_host_send() or peer_id <= 0 or not _is_valid_match_message(match_id):
		return
	rpc_id(
		peer_id,
		"_receive_stream_snapshot_pending",
		NetworkProtocol.PROTOCOL_VERSION,
		match_id,
		sync_id,
		active_sequence_id
	)


func request_stream_snapshot(match_id: String, sync_id: String, expected_sequence_id: int) -> void:
	if (
		not GameSession.is_multiplayer()
		or not _can_send()
		or connection.is_host
		or not _is_valid_match_message(match_id)
		or not NetworkProtocol.is_valid_identifier(sync_id)
		or expected_sequence_id <= 0
	):
		return
	rpc_id(
		1,
		"_submit_stream_snapshot_request",
		NetworkProtocol.PROTOCOL_VERSION,
		match_id,
		sync_id,
		expected_sequence_id
	)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_action_started(record: Dictionary) -> void:
	if _is_valid_lifecycle_record(record):
		action_started.emit(record)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_action_completed(record: Dictionary) -> void:
	if _is_valid_lifecycle_record(record):
		action_completed.emit(record)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_action_cancelled(record: Dictionary, reason_code: String) -> void:
	if _is_valid_lifecycle_record(record) and NetworkProtocol.is_safe_reason_code(reason_code):
		action_cancelled.emit(record, reason_code)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_action_accepted(match_id: String, request_id: int, sequence_id: int) -> void:
	if _is_valid_match_message(match_id) and request_id > 0 and sequence_id > 0:
		action_accepted.emit(request_id, sequence_id)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_action_rejected(match_id: String, request_id: int, reason_code: String) -> void:
	if _is_valid_match_message(match_id) and request_id > 0 and NetworkProtocol.is_safe_reason_code(reason_code):
		action_rejected.emit(request_id, reason_code)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_stream_snapshot_pending(
	protocol_version: int,
	match_id: String,
	sync_id: String,
	active_sequence_id: int
) -> void:
	if _is_valid_match_message(match_id, protocol_version) and NetworkProtocol.is_valid_identifier(sync_id):
		stream_snapshot_pending.emit(sync_id, active_sequence_id)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_stream_snapshot_chunk(
	protocol_version: int,
	match_id: String,
	sync_id: String,
	chunk_index: int,
	chunk_count: int,
	checksum: String,
	chunk: PackedByteArray
) -> void:
	if not _is_valid_match_message(match_id, protocol_version) or not NetworkProtocol.is_valid_identifier(sync_id):
		return
	if (
		chunk_count <= 0
		or chunk_count > NetworkProtocol.MAX_SNAPSHOT_CHUNKS
		or chunk_index < 0
		or chunk_index >= chunk_count
		or checksum.length() != 64
		or chunk.is_empty()
		or chunk.size() > NetworkProtocol.SNAPSHOT_CHUNK_BYTES
	):
		_reject_snapshot_assembly(sync_id)
		return
	var assembly: Dictionary = snapshot_assemblies.get(sync_id, {}) as Dictionary
	if assembly.is_empty():
		if snapshot_assemblies.size() >= 2:
			return
		assembly = {
			"match_id": match_id,
			"chunk_count": chunk_count,
			"checksum": checksum,
			"chunks": {},
			"total_size": 0,
		}
	if (
		str(assembly.get("match_id", "")) != match_id
		or int(assembly.get("chunk_count", 0)) != chunk_count
		or str(assembly.get("checksum", "")) != checksum
	):
		_reject_snapshot_assembly(sync_id)
		return
	var chunks: Dictionary = assembly.get("chunks", {}) as Dictionary
	if not chunks.has(chunk_index):
		chunks[chunk_index] = chunk
		assembly["total_size"] = int(assembly.get("total_size", 0)) + chunk.size()
	if int(assembly.get("total_size", 0)) > NetworkProtocol.MAX_SNAPSHOT_BYTES:
		_reject_snapshot_assembly(sync_id)
		return
	assembly["chunks"] = chunks
	snapshot_assemblies[sync_id] = assembly
	if chunks.size() == chunk_count:
		_complete_snapshot_assembly(sync_id)


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_stream_snapshot_request(
	protocol_version: int,
	match_id: String,
	sync_id: String,
	expected_sequence_id: int
) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if (
		requester_peer_id > 0
		and _is_valid_match_message(match_id, protocol_version)
		and NetworkProtocol.is_valid_identifier(sync_id)
		and expected_sequence_id > 0
	):
		stream_snapshot_requested.emit(requester_peer_id, match_id, sync_id, expected_sequence_id)


func _complete_snapshot_assembly(sync_id: String) -> void:
	var assembly: Dictionary = snapshot_assemblies.get(sync_id, {}) as Dictionary
	var chunks: Dictionary = assembly.get("chunks", {}) as Dictionary
	var chunk_count: int = int(assembly.get("chunk_count", 0))
	var serialized_snapshot: PackedByteArray = PackedByteArray()
	for chunk_index: int in range(chunk_count):
		if not chunks.has(chunk_index):
			_reject_snapshot_assembly(sync_id)
			return
		serialized_snapshot.append_array(chunks[chunk_index] as PackedByteArray)
	snapshot_assemblies.erase(sync_id)
	if not NetworkProtocol.is_valid_snapshot_size(serialized_snapshot):
		stream_snapshot_invalid.emit(sync_id)
		return
	var checksum: String = _get_sha256(serialized_snapshot)
	if checksum != str(assembly.get("checksum", "")):
		stream_snapshot_invalid.emit(sync_id)
		return
	var snapshot_value: Variant = bytes_to_var(serialized_snapshot)
	if not (snapshot_value is Dictionary):
		stream_snapshot_invalid.emit(sync_id)
		return
	stream_snapshot_received.emit(sync_id, snapshot_value as Dictionary)


func _is_valid_lifecycle_record(record: Dictionary) -> bool:
	return (
		_is_valid_match_message(
			str(record.get("match_id", "")),
			int(record.get("protocol_version", 0))
		)
		and int(record.get("sequence_id", 0)) > 0
		and _is_payload_size_valid(record)
	)


func _get_sha256(data: PackedByteArray) -> String:
	var hashing_context: HashingContext = HashingContext.new()
	if hashing_context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if hashing_context.update(data) != OK:
		return ""
	return hashing_context.finish().hex_encode()


func _reject_snapshot_assembly(sync_id: String) -> void:
	snapshot_assemblies.erase(sync_id)
	stream_snapshot_invalid.emit(sync_id)


func _on_session_cleared() -> void:
	snapshot_assemblies.clear()
