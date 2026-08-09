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
		or not NetworkProtocol.is_safe_snapshot_sync_failure_reason(reason_code)
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
	if not GameSession.get_player_record_by_steam_id(steam_id).is_empty():
		player_world_ready_received.emit(steam_id, match_id)


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_player_world_failed(match_id: String, reason_code: String) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if (
		requester_peer_id == 0
		or not _is_valid_match_message(match_id)
		or not NetworkProtocol.is_safe_snapshot_sync_failure_reason(reason_code)
	):
		return
	var steam_id: int = peers.get_steam_id_for_peer_id(requester_peer_id)
	if not GameSession.get_player_record_by_steam_id(steam_id).is_empty():
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
	var members_value: Variant = snapshot.get("members")
	var squad_size: int = int(snapshot.get("squad_size", 0))
	var expected_member_count: int = GameSession.get_players().size() * GameSession.get_squad_size()
	if (
		int(snapshot.get("protocol_version", 0)) != NetworkProtocol.PROTOCOL_VERSION
		or str(snapshot.get("match_id", "")) != GameSession.get_match_id()
		or str(snapshot.get("roster_hash", "")) != GameSession.get_roster_hash()
		or str(snapshot.get("level_id", "")) != GameSession.selected_level_id
		or squad_size != GameSession.get_squad_size()
		or not (members_value is Array)
		or (members_value as Array).size() != expected_member_count
		or (members_value as Array).size() > NetworkProtocol.MAX_PLAYER_CHARACTERS
		or not _is_payload_size_valid(snapshot, NetworkProtocol.MAX_SNAPSHOT_BYTES)
	):
		return false
	var seen_entity_ids: Dictionary[String, bool] = {}
	var seen_surfaces: Dictionary[Vector3i, bool] = {}
	var member_count_by_player_id: Dictionary[String, int] = {}
	var warrior_color_by_player_id: Dictionary[String, String] = {}
	for record_value: Variant in members_value as Array:
		if not (record_value is Dictionary):
			return false
		var record: Dictionary = record_value as Dictionary
		var steam_id: int = int(record.get("steam_id", 0))
		var player_id: String = str(record.get("player_id", ""))
		var squad_slot: int = int(record.get("squad_slot", -1))
		var entity_id: String = str(record.get("entity_id", ""))
		var cell_value: Variant = record.get("spawn_surface")
		var surface: Vector3i = record.get("spawn_surface", Vector3i.ZERO)
		var warrior_color: String = str(record.get("warrior_color", ""))
		var roster_player: Dictionary = GameSession.get_player_record_by_steam_id(steam_id)
		if (
			steam_id <= 0
			or roster_player.is_empty()
			or str(roster_player.get("player_id", "")) != player_id
			or squad_slot < 0
			or squad_slot >= squad_size
			or not NetworkProtocol.is_valid_identifier(entity_id)
			or entity_id != NetworkProtocol.make_squad_member_entity_id(player_id, squad_slot)
			or seen_entity_ids.has(entity_id)
			or not (cell_value is Vector3i)
			or not NetworkProtocol.is_valid_surface_value(surface)
			or seen_surfaces.has(surface)
			or warrior_color not in ALLOWED_WARRIOR_COLORS
		):
			return false
		if warrior_color_by_player_id.has(player_id) and warrior_color_by_player_id[player_id] != warrior_color:
			return false
		warrior_color_by_player_id[player_id] = warrior_color
		seen_entity_ids[entity_id] = true
		seen_surfaces[surface] = true
		member_count_by_player_id[player_id] = int(member_count_by_player_id.get(player_id, 0)) + 1
	for player: Dictionary in GameSession.get_players():
		if int(member_count_by_player_id.get(str(player.get("player_id", "")), 0)) != squad_size:
			return false
	return true
