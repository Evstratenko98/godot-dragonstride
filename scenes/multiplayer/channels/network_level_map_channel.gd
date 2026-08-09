class_name NetworkLevelMapChannel
extends NetworkChannel

signal level_map_requested(requester_peer_id: int, transfer_id: String)
signal level_map_transfer_started(transfer_id: String, total_bytes: int)
signal level_map_transfer_progress(transfer_id: String, received_bytes: int, total_bytes: int)
signal level_map_received(transfer_id: String, payload: PackedByteArray)
signal level_map_invalid(transfer_id: String, should_retry: bool)

var expected_transfer_id: String = ""
var assembly: Dictionary = {}


func _ready() -> void:
	if not GameSession.session_cleared.is_connected(_on_session_cleared):
		GameSession.session_cleared.connect(_on_session_cleared)


func _exit_tree() -> void:
	if GameSession.session_cleared.is_connected(_on_session_cleared):
		GameSession.session_cleared.disconnect(_on_session_cleared)


func request_level_map(transfer_id: String) -> void:
	if (
		not _can_send()
		or connection.is_host
		or not NetworkProtocol.is_valid_identifier(transfer_id)
	):
		return
	expected_transfer_id = transfer_id
	assembly.clear()
	rpc_id(
		1,
		"_submit_level_map_request",
		NetworkProtocol.PROTOCOL_VERSION,
		GameSession.get_match_id(),
		transfer_id
	)


func send_level_map(peer_id: int, transfer_id: String, payload: PackedByteArray) -> String:
	if (
		not _can_host_send()
		or peer_id <= 0
		or not NetworkProtocol.is_valid_identifier(transfer_id)
		or payload.is_empty()
	):
		return "map_invalid"
	if payload.size() > NetworkProtocol.MAX_LEVEL_MAP_BYTES:
		return "map_too_large"
	var chunk_count: int = ceili(
		float(payload.size()) / float(NetworkProtocol.LEVEL_MAP_CHUNK_BYTES)
	)
	if chunk_count <= 0 or chunk_count > NetworkProtocol.MAX_LEVEL_MAP_CHUNKS:
		return "map_too_large"
	var checksum: String = WorldMapDocumentCodec.get_sha256(payload)
	if checksum.length() != 64:
		return "map_invalid"
	rpc_id(
		peer_id,
		"_receive_level_map_manifest",
		NetworkProtocol.PROTOCOL_VERSION,
		NetworkProtocol.MAP_SCHEMA_VERSION,
		GameSession.get_match_id(),
		GameSession.selected_level_id,
		transfer_id,
		payload.size(),
		chunk_count,
		checksum
	)
	for chunk_index: int in range(chunk_count):
		var start_offset: int = chunk_index * NetworkProtocol.LEVEL_MAP_CHUNK_BYTES
		var end_offset: int = mini(
			start_offset + NetworkProtocol.LEVEL_MAP_CHUNK_BYTES,
			payload.size()
		)
		var chunk: PackedByteArray = payload.slice(start_offset, end_offset)
		rpc_id(
			peer_id,
			"_receive_level_map_chunk",
			NetworkProtocol.PROTOCOL_VERSION,
			GameSession.get_match_id(),
			transfer_id,
			chunk_index,
			chunk
		)
	return ""


func reset_transfer() -> void:
	expected_transfer_id = ""
	assembly.clear()


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_level_map_request(
	protocol_version: int,
	match_id: String,
	transfer_id: String
) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if (
		requester_peer_id > 0
		and _is_valid_match_message(match_id, protocol_version)
		and NetworkProtocol.is_valid_identifier(transfer_id)
	):
		level_map_requested.emit(requester_peer_id, transfer_id)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_level_map_manifest(
	protocol_version: int,
	map_schema_version: int,
	match_id: String,
	level_id: String,
	transfer_id: String,
	total_bytes: int,
	chunk_count: int,
	checksum: String
) -> void:
	if connection.is_host:
		return
	if transfer_id != expected_transfer_id:
		return
	var expected_chunk_count: int = ceili(
		float(total_bytes) / float(NetworkProtocol.LEVEL_MAP_CHUNK_BYTES)
	) if total_bytes > 0 else 0
	if (
		not _is_valid_match_message(match_id, protocol_version)
		or map_schema_version != NetworkProtocol.MAP_SCHEMA_VERSION
		or level_id != GameSession.selected_level_id
		or total_bytes <= 0
		or total_bytes > NetworkProtocol.MAX_LEVEL_MAP_BYTES
		or chunk_count <= 0
		or chunk_count > NetworkProtocol.MAX_LEVEL_MAP_CHUNKS
		or chunk_count != expected_chunk_count
		or checksum.length() != 64
	):
		_reject_transfer(transfer_id, false)
		return
	if not assembly.is_empty():
		if not _manifest_matches(transfer_id, total_bytes, chunk_count, checksum):
			_reject_transfer(transfer_id, true)
		return
	assembly = {
		"transfer_id": transfer_id,
		"total_bytes": total_bytes,
		"chunk_count": chunk_count,
		"checksum": checksum,
		"chunks": {},
		"received_bytes": 0,
	}
	level_map_transfer_started.emit(transfer_id, total_bytes)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_level_map_chunk(
	protocol_version: int,
	match_id: String,
	transfer_id: String,
	chunk_index: int,
	chunk: PackedByteArray
) -> void:
	if connection.is_host:
		return
	if transfer_id != expected_transfer_id:
		return
	if (
		not _is_valid_match_message(match_id, protocol_version)
		or assembly.is_empty()
		or transfer_id != str(assembly.get("transfer_id", ""))
	):
		_reject_transfer(transfer_id, true)
		return
	var chunk_count: int = int(assembly.get("chunk_count", 0))
	if (
		chunk_index < 0
		or chunk_index >= chunk_count
		or chunk.is_empty()
		or chunk.size() > NetworkProtocol.LEVEL_MAP_CHUNK_BYTES
	):
		_reject_transfer(transfer_id, true)
		return
	var chunks: Dictionary = assembly.get("chunks", {}) as Dictionary
	if chunks.has(chunk_index):
		if chunks[chunk_index] != chunk:
			_reject_transfer(transfer_id, true)
		return
	chunks[chunk_index] = chunk
	assembly["chunks"] = chunks
	var received_bytes: int = int(assembly.get("received_bytes", 0)) + chunk.size()
	assembly["received_bytes"] = received_bytes
	var total_bytes: int = int(assembly.get("total_bytes", 0))
	if received_bytes > total_bytes:
		_reject_transfer(transfer_id, true)
		return
	level_map_transfer_progress.emit(transfer_id, received_bytes, total_bytes)
	if chunks.size() == chunk_count:
		_complete_transfer()


func _complete_transfer() -> void:
	var transfer_id: String = str(assembly.get("transfer_id", ""))
	var chunks: Dictionary = assembly.get("chunks", {}) as Dictionary
	var chunk_count: int = int(assembly.get("chunk_count", 0))
	var payload: PackedByteArray = PackedByteArray()
	for chunk_index: int in range(chunk_count):
		if not chunks.has(chunk_index):
			_reject_transfer(transfer_id, true)
			return
		payload.append_array(chunks[chunk_index] as PackedByteArray)
	var expected_size: int = int(assembly.get("total_bytes", 0))
	var expected_checksum: String = str(assembly.get("checksum", ""))
	assembly.clear()
	if (
		payload.size() != expected_size
		or WorldMapDocumentCodec.get_sha256(payload) != expected_checksum
	):
		_reject_transfer(transfer_id, true)
		return
	expected_transfer_id = ""
	level_map_received.emit(transfer_id, payload)


func _manifest_matches(
	transfer_id: String,
	total_bytes: int,
	chunk_count: int,
	checksum: String
) -> bool:
	return (
		str(assembly.get("transfer_id", "")) == transfer_id
		and int(assembly.get("total_bytes", 0)) == total_bytes
		and int(assembly.get("chunk_count", 0)) == chunk_count
		and str(assembly.get("checksum", "")) == checksum
	)


func _reject_transfer(transfer_id: String, should_retry: bool) -> void:
	assembly.clear()
	level_map_invalid.emit(transfer_id, should_retry)


func _on_session_cleared() -> void:
	reset_transfer()
