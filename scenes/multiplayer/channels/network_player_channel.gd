class_name NetworkPlayerChannel
extends NetworkChannel

signal player_spawn_snapshot_requested(requester_peer_id: int)
signal player_spawn_snapshot_received(snapshot: Dictionary)
signal player_world_ready_received(steam_id: int, match_id: String)
signal players_committed_received(match_id: String)
signal player_respawn_pending_received(match_id: String, entity_id: String)
signal player_world_failed_received(steam_id: int, match_id: String, reason_code: String)
signal player_connection_state_received(match_id: String, steam_id: int, is_connected: bool)

const ALLOWED_WARRIOR_COLORS: PackedStringArray = ["Blue", "Purple", "Red", "Yellow"]


func request_player_spawn_snapshot() -> void:
	if not _can_send() or connection.is_host:
		return
	rpc_id(1, "_submit_player_spawn_snapshot_request", GameSession.get_match_id())


func broadcast_player_spawn_snapshot(snapshot: Dictionary) -> void:
	if not _can_host_send() or not _is_valid_player_spawn_snapshot(snapshot):
		return
	player_spawn_snapshot_received.emit(snapshot.duplicate(true))
	rpc("_receive_player_spawn_snapshot", snapshot)


func send_player_spawn_snapshot(peer_id: int, snapshot: Dictionary) -> void:
	if not _can_host_send() or peer_id <= 0 or not _is_valid_player_spawn_snapshot(snapshot):
		return
	rpc_id(peer_id, "_receive_player_spawn_snapshot", snapshot)


func report_player_world_ready(match_id: String) -> void:
	if not _can_send() or match_id.is_empty():
		return
	if connection.is_host:
		player_world_ready_received.emit(connection.local_steam_id, match_id)
		return
	rpc_id(1, "_submit_player_world_ready", match_id)


func report_player_world_failed(match_id: String, reason_code: String) -> void:
	if (
		not _can_send()
		or connection.is_host
		or not _is_valid_match_message(match_id)
		or reason_code not in ["state_sync_timeout", "state_sync_invalid"]
	):
		return
	rpc_id(1, "_submit_player_world_failed", match_id, reason_code)


func broadcast_players_committed(match_id: String) -> void:
	if not _can_host_send() or match_id.is_empty():
		return
	players_committed_received.emit(match_id)
	rpc("_receive_players_committed", match_id)


func broadcast_player_respawn_pending(match_id: String, entity_id: String) -> void:
	if not _can_host_send() or match_id.is_empty() or entity_id.is_empty():
		return
	rpc("_receive_player_respawn_pending", match_id, entity_id)


func broadcast_player_connection_state(match_id: String, steam_id: int, is_connected: bool) -> void:
	if not _can_host_send() or not _is_valid_match_message(match_id) or steam_id <= 0:
		return
	player_connection_state_received.emit(match_id, steam_id, is_connected)
	rpc("_receive_player_connection_state", match_id, steam_id, is_connected)


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_player_spawn_snapshot_request(match_id: String) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id != 0 and match_id == GameSession.get_match_id():
		player_spawn_snapshot_requested.emit(requester_peer_id)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_player_spawn_snapshot(snapshot: Dictionary) -> void:
	if _is_valid_player_spawn_snapshot(snapshot):
		player_spawn_snapshot_received.emit(snapshot.duplicate(true))


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_player_world_ready(match_id: String) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id == 0 or match_id != GameSession.get_match_id():
		return
	var steam_id: int = peers.get_steam_id_for_peer_id(requester_peer_id)
	if not GameSession.get_player_by_steam_id(steam_id).is_empty():
		player_world_ready_received.emit(steam_id, match_id)


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_player_world_failed(match_id: String, reason_code: String) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if (
		requester_peer_id == 0
		or not _is_valid_match_message(match_id)
		or reason_code not in ["state_sync_timeout", "state_sync_invalid"]
	):
		return
	var steam_id: int = peers.get_steam_id_for_peer_id(requester_peer_id)
	if not GameSession.get_player_by_steam_id(steam_id).is_empty():
		player_world_failed_received.emit(steam_id, match_id, reason_code)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_players_committed(match_id: String) -> void:
	if match_id == GameSession.get_match_id():
		players_committed_received.emit(match_id)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_player_respawn_pending(match_id: String, entity_id: String) -> void:
	if match_id == GameSession.get_match_id() and not entity_id.is_empty():
		player_respawn_pending_received.emit(match_id, entity_id)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_player_connection_state(match_id: String, steam_id: int, is_connected: bool) -> void:
	if _is_valid_match_message(match_id) and steam_id > 0:
		player_connection_state_received.emit(match_id, steam_id, is_connected)


func _is_valid_player_spawn_snapshot(snapshot: Dictionary) -> bool:
	var players_value: Variant = snapshot.get("players")
	if (
		int(snapshot.get("protocol_version", 0)) != NetworkProtocol.PROTOCOL_VERSION
		or str(snapshot.get("match_id", "")) != GameSession.get_match_id()
		or str(snapshot.get("roster_hash", "")) != GameSession.get_roster_hash()
		or str(snapshot.get("level_id", "")) != GameSession.selected_level_id
		or not (players_value is Array)
		or (players_value as Array).size() != GameSession.get_players().size()
		or (players_value as Array).size() > NetworkProtocol.MAX_ROSTER_SIZE
		or not _is_payload_size_valid(snapshot, NetworkProtocol.MAX_SNAPSHOT_BYTES)
	):
		return false
	var seen_steam_ids: Dictionary[int, bool] = {}
	var seen_entity_ids: Dictionary[String, bool] = {}
	var seen_cells: Dictionary[Vector2i, bool] = {}
	for record_value: Variant in players_value as Array:
		if not (record_value is Dictionary):
			return false
		var record: Dictionary = record_value as Dictionary
		var steam_id: int = int(record.get("steam_id", 0))
		var entity_id: String = str(record.get("entity_id", ""))
		var cell_value: Variant = record.get("spawn_cell")
		var cell: Vector2i = record.get("spawn_cell", Vector2i.ZERO)
		var warrior_color: String = str(record.get("warrior_color", ""))
		var roster_player: Dictionary = GameSession.get_player_by_steam_id(steam_id)
		if (
			steam_id <= 0
			or seen_steam_ids.has(steam_id)
			or roster_player.is_empty()
			or not NetworkProtocol.is_valid_identifier(entity_id)
			or str(roster_player.get("entity_id", "")) != entity_id
			or seen_entity_ids.has(entity_id)
			or not (cell_value is Vector2i)
			or not NetworkProtocol.is_valid_cell_value(cell)
			or seen_cells.has(cell)
			or warrior_color not in ALLOWED_WARRIOR_COLORS
		):
			return false
		seen_steam_ids[steam_id] = true
		seen_entity_ids[entity_id] = true
		seen_cells[cell] = true
	return true
