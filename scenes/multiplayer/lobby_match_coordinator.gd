extends Node

signal status_changed(reason_code: String)
signal coordinator_state_changed(state: State)

enum State {
	IDLE,
	PREPARING,
	WAITING_FOR_PEERS,
	LOADING_MATCH,
	WAITING_FOR_WORLD,
	IN_MATCH,
	CANCELLING,
}

const COMMAND_PREPARE_MATCH := "prepare_match"
const COMMAND_CANCEL_MATCH := "cancel_match"
const LOBBY_SCENE_PATH := "res://scenes/menu/lobby/lobby_host.tscn"
const MAIN_MENU_SCENE_PATH := "res://scenes/menu/main_menu/main_menu.tscn"
const PREPARE_RETRY_MSEC := 1000
const TRANSPORT_TIMEOUT_MSEC := 15000
const WORLD_TIMEOUT_MSEC := 10000
const MAX_HANDLED_MATCH_IDS := 32

var state: State = State.IDLE
var deadline_msec: int = 0
var next_prepare_send_msec: int = 0
var ready_steam_ids: Dictionary[int, bool] = {}
var world_ready_steam_ids: Dictionary[int, bool] = {}
var handled_match_ids: Dictionary[String, bool] = {}
var handled_match_id_order: Array[String] = []
var last_notice_code: String = ""
var last_lobby_status_code: String = ""


func _ready() -> void:
	_connect_signals()


func _process(_delta: float) -> void:
	var now_msec: int = Time.get_ticks_msec()
	if state == State.WAITING_FOR_PEERS:
		if GameSession.is_host() and now_msec >= next_prepare_send_msec:
			_send_prepare_message()
		if now_msec >= deadline_msec:
			_cancel_start("transport_timeout", true)
	elif state == State.LOADING_MATCH or state == State.WAITING_FOR_WORLD:
		if now_msec >= deadline_msec:
			_cancel_start("world_timeout", GameSession.is_host())


func request_start_match() -> void:
	if state != State.IDLE or not SteamManager.is_lobby_owner():
		return
	if not SteamManager.is_current_lobby_protocol_compatible():
		status_changed.emit("protocol_mismatch")
		return
	if not SteamManager.is_relay_network_ready():
		status_changed.emit("relay_unavailable")
		return

	SteamManager.update_lobby_members()
	var new_match_id: String = "%d-%d" % [
		SteamManager.get_current_lobby_id(),
		Time.get_ticks_usec(),
	]
	var level_id: String = SteamManager.get_lobby_level_id()
	if not GameSession.prepare_host_match(new_match_id, level_id):
		status_changed.emit("invalid_roster")
		return

	_set_state(State.PREPARING)
	if (
		not SteamManager.set_lobby_status(SteamManager.LOBBY_STATUS_STARTING)
		or not SteamManager.set_lobby_joinable(false)
	):
		_cancel_start("lobby_update_failed", false)
		return

	var network_result: int = NetworkManager.connection.start_from_session()
	if network_result != OK:
		_cancel_start("transport_failed", true)
		return

	ready_steam_ids.clear()
	ready_steam_ids[GameSession.local_steam_id] = true
	deadline_msec = Time.get_ticks_msec() + TRANSPORT_TIMEOUT_MSEC
	next_prepare_send_msec = 0
	_set_state(State.WAITING_FOR_PEERS)
	_send_prepare_message()
	_try_load_match()


func consume_last_notice() -> String:
	var notice_code: String = last_notice_code
	last_notice_code = ""
	return notice_code


func consume_lobby_status() -> String:
	var status_code: String = last_lobby_status_code
	last_lobby_status_code = ""
	return status_code


func is_starting_match() -> bool:
	return state in [
		State.PREPARING,
		State.WAITING_FOR_PEERS,
		State.LOADING_MATCH,
		State.WAITING_FOR_WORLD,
	]


func cancel_runtime_start(reason_code: String) -> void:
	if state in [State.LOADING_MATCH, State.WAITING_FOR_WORLD]:
		_cancel_start(reason_code, GameSession.is_host())


func handle_runtime_sync_failure(_reason_code: String) -> void:
	if not GameSession.is_multiplayer() or GameSession.is_host():
		return
	last_notice_code = "state_sync_failed"
	SteamManager.leave_lobby()
	GameSession.clear()
	_set_state(State.IDLE)
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _connect_signals() -> void:
	if not SteamManager.lobby_control_message_received.is_connected(_on_lobby_control_message_received):
		SteamManager.lobby_control_message_received.connect(_on_lobby_control_message_received)
	if not SteamManager.lobby_members_updated.is_connected(_on_lobby_members_updated):
		SteamManager.lobby_members_updated.connect(_on_lobby_members_updated)
	if not SteamManager.lobby_left.is_connected(_on_lobby_left):
		SteamManager.lobby_left.connect(_on_lobby_left)
	if not NetworkManager.connection.network_started.is_connected(_on_network_started):
		NetworkManager.connection.network_started.connect(_on_network_started)
	if not NetworkManager.connection.network_failed.is_connected(_on_network_failed):
		NetworkManager.connection.network_failed.connect(_on_network_failed)
	if not NetworkManager.connection.server_disconnected.is_connected(_on_server_disconnected):
		NetworkManager.connection.server_disconnected.connect(_on_server_disconnected)
	if not NetworkManager.connection.client_match_ready_received.is_connected(_on_client_match_ready_received):
		NetworkManager.connection.client_match_ready_received.connect(_on_client_match_ready_received)
	if not NetworkManager.connection.match_load_requested.is_connected(_on_match_load_requested):
		NetworkManager.connection.match_load_requested.connect(_on_match_load_requested)
	if not NetworkManager.players.player_world_ready_received.is_connected(_on_player_world_ready_received):
		NetworkManager.players.player_world_ready_received.connect(_on_player_world_ready_received)
	if not NetworkManager.players.players_committed_received.is_connected(_on_players_committed_received):
		NetworkManager.players.players_committed_received.connect(_on_players_committed_received)
	if not NetworkManager.players.player_world_failed_received.is_connected(_on_player_world_failed_received):
		NetworkManager.players.player_world_failed_received.connect(_on_player_world_failed_received)


func _send_prepare_message() -> void:
	if not GameSession.is_host() or state != State.WAITING_FOR_PEERS:
		return
	var was_sent: bool = SteamManager.send_lobby_control_message(
		COMMAND_PREPARE_MATCH,
		GameSession.create_match_prepare_payload()
	)
	if not was_sent:
		_cancel_start("lobby_message_failed", false)
		return
	next_prepare_send_msec = Time.get_ticks_msec() + PREPARE_RETRY_MSEC


func _on_lobby_control_message_received(command: String, payload: Dictionary) -> void:
	if command == COMMAND_PREPARE_MATCH:
		_prepare_client(payload)
	elif command == COMMAND_CANCEL_MATCH:
		var cancelled_match_id: String = str(payload.get("match_id", ""))
		if cancelled_match_id == GameSession.get_match_id():
			_cancel_start(str(payload.get("reason_code", "start_cancelled")), false)


func _prepare_client(payload: Dictionary) -> void:
	if SteamManager.is_lobby_owner():
		return
	if int(payload.get("protocol_version", 0)) != NetworkProtocol.PROTOCOL_VERSION:
		status_changed.emit("protocol_mismatch")
		return
	var submitted_match_id: String = str(payload.get("match_id", ""))
	if submitted_match_id.is_empty() or handled_match_ids.has(submitted_match_id):
		return
	if is_starting_match() and submitted_match_id == GameSession.get_match_id():
		_send_client_ready_if_possible()
		return
	if state != State.IDLE or not GameSession.prepare_remote_match(payload):
		return

	_set_state(State.PREPARING)
	var network_result: int = NetworkManager.connection.start_from_session()
	if network_result != OK:
		_cancel_start("transport_failed", false)
		return
	deadline_msec = Time.get_ticks_msec() + TRANSPORT_TIMEOUT_MSEC
	_set_state(State.WAITING_FOR_PEERS)
	_send_client_ready_if_possible()


func _on_network_started() -> void:
	if GameSession.is_host():
		_try_load_match()
	else:
		_send_client_ready_if_possible()


func _send_client_ready_if_possible() -> void:
	if (
		state != State.WAITING_FOR_PEERS
		or GameSession.is_host()
		or not NetworkManager.connection.is_ready()
	):
		return
	NetworkManager.connection.send_client_match_ready(
		GameSession.get_match_id(),
		GameSession.get_roster_hash()
	)


func _on_client_match_ready_received(steam_id: int, submitted_match_id: String, roster_hash: String) -> void:
	if (
		state != State.WAITING_FOR_PEERS
		or not GameSession.is_host()
		or submitted_match_id != GameSession.get_match_id()
		or roster_hash != GameSession.get_roster_hash()
	):
		return
	ready_steam_ids[steam_id] = true
	_try_load_match()


func _try_load_match() -> void:
	if (
		not GameSession.is_host()
		or state != State.WAITING_FOR_PEERS
		or not NetworkManager.connection.is_ready()
	):
		return
	for player: Dictionary in GameSession.get_players():
		if not ready_steam_ids.has(int(player.get("steam_id", 0))):
			return
	NetworkManager.connection.set_accepting_match_peers(false)
	NetworkManager.connection.broadcast_match_load(GameSession.get_match_id())


func _on_match_load_requested(submitted_match_id: String) -> void:
	if submitted_match_id != GameSession.get_match_id():
		return
	if state == State.LOADING_MATCH or state == State.WAITING_FOR_WORLD or state == State.IN_MATCH:
		return
	_set_state(State.LOADING_MATCH)
	deadline_msec = Time.get_ticks_msec() + WORLD_TIMEOUT_MSEC
	GameSession.go_to_selected_scene()
	_set_state(State.WAITING_FOR_WORLD)


func _on_player_world_ready_received(steam_id: int, submitted_match_id: String) -> void:
	if submitted_match_id != GameSession.get_match_id() or state != State.WAITING_FOR_WORLD:
		return
	world_ready_steam_ids[steam_id] = true
	if not GameSession.is_host():
		return
	for player: Dictionary in GameSession.get_players():
		if not world_ready_steam_ids.has(int(player.get("steam_id", 0))):
			return
	NetworkManager.players.broadcast_players_committed(GameSession.get_match_id())


func _on_player_world_failed_received(
	_steam_id: int,
	submitted_match_id: String,
	reason_code: String
) -> void:
	if GameSession.is_host() and submitted_match_id == GameSession.get_match_id() and is_starting_match():
		_cancel_start(reason_code, true)


func _on_players_committed_received(submitted_match_id: String) -> void:
	if submitted_match_id != GameSession.get_match_id() or state != State.WAITING_FOR_WORLD:
		return
	if not GameSession.commit_multiplayer_match():
		_cancel_start("session_commit_failed", GameSession.is_host())
		return
	if GameSession.is_host():
		SteamManager.set_lobby_status(SteamManager.LOBBY_STATUS_IN_GAME)
	_remember_handled_match_id(submitted_match_id)
	_set_state(State.IN_MATCH)
	status_changed.emit("match_started")


func _on_lobby_members_updated(_members: Array) -> void:
	if GameSession.is_multiplayer() and state != State.IDLE:
		var current_owner_steam_id: int = SteamManager.get_lobby_owner_id()
		if current_owner_steam_id == 0 or current_owner_steam_id != GameSession.host_steam_id:
			_on_server_disconnected()
			return
	if not GameSession.is_host() or state not in [
		State.PREPARING,
		State.WAITING_FOR_PEERS,
		State.LOADING_MATCH,
		State.WAITING_FOR_WORLD,
	]:
		return
	var session_steam_ids: Array[int] = []
	for player: Dictionary in GameSession.get_players():
		session_steam_ids.append(int(player.get("steam_id", 0)))
	session_steam_ids.sort()
	var lobby_steam_ids: Array[int] = []
	for member_value: Variant in SteamManager.get_current_lobby_members():
		var member: Dictionary = member_value as Dictionary
		lobby_steam_ids.append(int(member.get("id", 0)))
	lobby_steam_ids.sort()
	if session_steam_ids != lobby_steam_ids:
		_cancel_start("roster_changed", true)


func _on_network_failed(_reason: String) -> void:
	if is_starting_match():
		_cancel_start("transport_failed", GameSession.is_host())


func _on_server_disconnected() -> void:
	last_notice_code = "host_disconnected"
	SteamManager.leave_lobby()
	GameSession.clear()
	_set_state(State.IDLE)
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _cancel_start(reason_code: String, should_notify_lobby: bool) -> void:
	if state == State.CANCELLING:
		return
	var cancelled_match_id: String = GameSession.get_match_id()
	_remember_handled_match_id(cancelled_match_id)
	_set_state(State.CANCELLING)
	if SteamManager.is_lobby_owner():
		if should_notify_lobby:
			SteamManager.send_lobby_control_message(COMMAND_CANCEL_MATCH, {
				"match_id": cancelled_match_id,
				"reason_code": reason_code,
			})
		SteamManager.set_lobby_status(SteamManager.LOBBY_STATUS_WAITING)
		SteamManager.set_lobby_joinable(true)
	NetworkManager.connection.stop_network()
	GameSession.clear()
	ready_steam_ids.clear()
	world_ready_steam_ids.clear()
	_set_state(State.IDLE)
	last_lobby_status_code = reason_code
	status_changed.emit(reason_code)
	var current_scene: Node = get_tree().current_scene
	if current_scene != null and current_scene.scene_file_path == GameSession.MATCH_SCENE_PATH:
		get_tree().change_scene_to_file(LOBBY_SCENE_PATH)


func _on_lobby_left() -> void:
	ready_steam_ids.clear()
	world_ready_steam_ids.clear()
	_set_state(State.IDLE)


func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	coordinator_state_changed.emit(state)


func _remember_handled_match_id(match_id: String) -> void:
	if match_id.is_empty() or handled_match_ids.has(match_id):
		return
	handled_match_ids[match_id] = true
	handled_match_id_order.append(match_id)
	while handled_match_id_order.size() > MAX_HANDLED_MATCH_IDS:
		var expired_match_id: String = handled_match_id_order.pop_front()
		handled_match_ids.erase(expired_match_id)
