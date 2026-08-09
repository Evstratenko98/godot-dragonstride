class_name WorldActionSnapshotResponder
extends RefCounted

var runtime: WorldRuntime = null
var action_stream: WorldActionStream = null
var pending_peer_requests: Dictionary[int, Dictionary] = {}


func configure_context(new_runtime: WorldRuntime, new_action_stream: WorldActionStream) -> void:
	disconnect_signals()
	runtime = new_runtime
	action_stream = new_action_stream
	if not NetworkManager.actions.stream_snapshot_requested.is_connected(_on_stream_snapshot_requested):
		NetworkManager.actions.stream_snapshot_requested.connect(_on_stream_snapshot_requested)
	if not GameSession.session_cleared.is_connected(_on_session_cleared):
		GameSession.session_cleared.connect(_on_session_cleared)


func disconnect_signals() -> void:
	if NetworkManager.actions.stream_snapshot_requested.is_connected(_on_stream_snapshot_requested):
		NetworkManager.actions.stream_snapshot_requested.disconnect(_on_stream_snapshot_requested)
	if GameSession.session_cleared.is_connected(_on_session_cleared):
		GameSession.session_cleared.disconnect(_on_session_cleared)


func request_peer_snapshot(peer_id: int) -> void:
	if not GameSession.is_host() or peer_id <= 0:
		return
	_queue_request(
		peer_id,
		GameSession.get_match_id(),
		("%s-sync-%d" % [GameSession.get_match_id(), Time.get_ticks_usec()]).left(
			NetworkProtocol.MAX_IDENTIFIER_LENGTH
		)
	)


func cancel_peer_snapshot(peer_id: int) -> void:
	pending_peer_requests.erase(peer_id)


func prune_disconnected_peers() -> void:
	for peer_id: int in pending_peer_requests.keys():
		if not NetworkManager.peers.has_steam_id_for_peer(peer_id):
			pending_peer_requests.erase(peer_id)


func try_send_pending() -> void:
	if (
		pending_peer_requests.is_empty()
		or runtime == null
		or action_stream == null
		or action_stream.get_current_sequence_id() > 0
	):
		return
	var boundary_sequence_id: int = action_stream.get_snapshot_boundary_sequence_id()
	var base_snapshot: Dictionary = runtime.create_action_stream_snapshot(boundary_sequence_id)
	for peer_id: int in pending_peer_requests.keys():
		var request: Dictionary = pending_peer_requests[peer_id]
		var match_id: String = str(request.get("match_id", ""))
		var sync_id: String = str(request.get("sync_id", ""))
		var snapshot: Dictionary = WorldActionSnapshotCodec.create_envelope(
			base_snapshot,
			match_id,
			sync_id,
			boundary_sequence_id
		)
		var rejection_reason: String = WorldActionSnapshotCodec.get_capacity_rejection_reason(snapshot)
		if rejection_reason.is_empty():
			rejection_reason = NetworkManager.actions.send_stream_snapshot(
				peer_id,
				match_id,
				sync_id,
				snapshot
			)
		if not rejection_reason.is_empty():
			NetworkManager.actions.send_stream_snapshot_rejected(
				peer_id,
				match_id,
				sync_id,
				rejection_reason
			)
	pending_peer_requests.clear()


func clear() -> void:
	pending_peer_requests.clear()


func _queue_request(peer_id: int, match_id: String, sync_id: String) -> void:
	pending_peer_requests[peer_id] = {
		"match_id": match_id,
		"sync_id": sync_id,
	}
	if action_stream.get_current_sequence_id() <= 0:
		try_send_pending()
	else:
		NetworkManager.actions.send_stream_snapshot_pending(
			peer_id,
			match_id,
			sync_id,
			action_stream.get_current_sequence_id()
		)


func _on_stream_snapshot_requested(
	requester_peer_id: int,
	match_id: String,
	sync_id: String,
	_expected_sequence_id: int
) -> void:
	if not GameSession.is_host() or match_id != GameSession.get_match_id():
		return
	_queue_request(requester_peer_id, match_id, sync_id)


func _on_session_cleared() -> void:
	clear()
