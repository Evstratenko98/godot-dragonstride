class_name NetworkMatchChannel
extends NetworkChannel

signal match_end_requested()

const END_ACK_TIMEOUT_MSEC := 3000

var pending_end_id: String = ""
var acknowledged_peer_ids: Dictionary[int, bool] = {}
var expected_peer_ids: Dictionary[int, bool] = {}
var handled_remote_end_ids: Dictionary[String, bool] = {}


func _ready() -> void:
	if not GameSession.session_cleared.is_connected(_on_session_cleared):
		GameSession.session_cleared.connect(_on_session_cleared)


func _exit_tree() -> void:
	if GameSession.session_cleared.is_connected(_on_session_cleared):
		GameSession.session_cleared.disconnect(_on_session_cleared)


func request_end_game() -> void:
	if not GameSession.is_multiplayer() or not _can_send():
		match_end_requested.emit()
		return
	if not connection.is_host:
		match_end_requested.emit()
		return
	_begin_host_end()


func _begin_host_end() -> void:
	if not _can_host_send() or not pending_end_id.is_empty():
		return
	pending_end_id = ("%s:end:%d" % [GameSession.get_match_id(), Time.get_ticks_usec()]).sha256_text()
	acknowledged_peer_ids.clear()
	expected_peer_ids.clear()
	var local_peer_id: int = multiplayer.get_unique_id()
	for peer_id: int in peers.get_peer_map().keys():
		if peer_id != local_peer_id:
			expected_peer_ids[peer_id] = true
	rpc("_receive_match_end", GameSession.get_match_id(), pending_end_id)
	_wait_for_end_acknowledgements(pending_end_id)


func _wait_for_end_acknowledgements(end_id: String) -> void:
	var deadline_msec: int = Time.get_ticks_msec() + END_ACK_TIMEOUT_MSEC
	while is_inside_tree() and pending_end_id == end_id and Time.get_ticks_msec() < deadline_msec:
		if _has_all_acknowledgements():
			break
		await get_tree().process_frame
	if pending_end_id != end_id:
		return
	pending_end_id = ""
	expected_peer_ids.clear()
	acknowledged_peer_ids.clear()
	match_end_requested.emit()


func _has_all_acknowledgements() -> bool:
	for peer_id: int in expected_peer_ids.keys():
		if not peers.has_steam_id_for_peer(peer_id):
			continue
		if not acknowledged_peer_ids.has(peer_id):
			return false
	return true


@rpc("authority", "call_remote", "reliable", 1)
func _receive_match_end(match_id: String, end_id: String) -> void:
	if not _is_valid_match_message(match_id) or not NetworkProtocol.is_valid_identifier(end_id):
		return
	rpc_id(1, "_submit_match_end_ack", match_id, end_id)
	if handled_remote_end_ids.has(end_id):
		return
	handled_remote_end_ids[end_id] = true
	_finish_remote_end_after_network_frame(end_id)


func _finish_remote_end_after_network_frame(end_id: String) -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if is_inside_tree() and handled_remote_end_ids.has(end_id):
		match_end_requested.emit()


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_match_end_ack(match_id: String, end_id: String) -> void:
	var sender_peer_id: int = _get_registered_sender_peer_id()
	if sender_peer_id != 0 and _is_valid_match_message(match_id) and end_id == pending_end_id and expected_peer_ids.has(sender_peer_id):
		acknowledged_peer_ids[sender_peer_id] = true


func _on_session_cleared() -> void:
	pending_end_id = ""
	acknowledged_peer_ids.clear()
	expected_peer_ids.clear()
	handled_remote_end_ids.clear()
