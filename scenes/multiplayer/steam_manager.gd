extends Node

signal lobby_created(lobby_id: int)
signal lobby_creation_failed(result: int)

signal lobby_joined(lobby_id: int)
signal lobby_join_failed(response: int)

signal lobby_left()

signal lobby_list_received(lobbies: Array)
signal lobby_members_updated(members: Array)
signal lobby_game_start_requested()

const LOBBY_GAME_KEY := "game"
const LOBBY_GAME_VALUE := "dragonsride"
const LOBBY_STATUS_KEY := "status"
const LOBBY_LEVEL_KEY := "level_id"
const LOBBY_STATUS_WAITING := "waiting"
const LOBBY_STATUS_IN_GAME := "in_game"
const LOBBY_MESSAGE_START_GAME := "start_game"
const LOBBY_MESSAGE_HOST_NETWORK_READY := "host_network_ready"

var is_steam_initialized := false
var is_starting_game_from_lobby := false
var is_waiting_for_host_network := false

var lobby_id: int = 0
var lobby_members: Array = []


func _ready() -> void:
	is_steam_initialized = Steam.steamInit()

	if not is_steam_initialized:
		print("Steam is not initialized")
		return

	if Steam.has_method("initRelayNetworkAccess"):
		Steam.initRelayNetworkAccess()

	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	Steam.lobby_message.connect(_on_lobby_message)
	Steam.persona_state_change.connect(_on_persona_state_change)


func _process(_delta: float) -> void:
	if is_steam_initialized:
		Steam.run_callbacks()


func create_lobby(max_members: int = 4) -> void:
	if not is_steam_initialized:
		print("Steam is not initialized")
		return

	if lobby_id != 0:
		print("Already in lobby: ", lobby_id)
		return

	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, max_members)


func _on_lobby_created(result: int, created_lobby_id: int) -> void:
	if result != Steam.RESULT_OK:
		print("Failed to create lobby. Result: ", result)
		lobby_creation_failed.emit(result)
		return

	lobby_id = created_lobby_id

	Steam.setLobbyData(lobby_id, "name", Steam.getPersonaName() + "'s Lobby")
	Steam.setLobbyData(lobby_id, LOBBY_GAME_KEY, LOBBY_GAME_VALUE)
	Steam.setLobbyData(lobby_id, LOBBY_STATUS_KEY, LOBBY_STATUS_WAITING)
	Steam.setLobbyData(lobby_id, LOBBY_LEVEL_KEY, LevelCatalog.DEFAULT_LEVEL_ID)
	Steam.setLobbyData(lobby_id, "host_id", str(Steam.getSteamID()))
	Steam.setLobbyJoinable(lobby_id, true)

	update_lobby_members()

	lobby_created.emit(lobby_id)


func request_lobbies() -> void:
	if not is_steam_initialized:
		print("Steam is not initialized")
		return

	Steam.addRequestLobbyListStringFilter(
		LOBBY_GAME_KEY,
		LOBBY_GAME_VALUE,
		Steam.LOBBY_COMPARISON_EQUAL
	)

	Steam.addRequestLobbyListStringFilter(
		LOBBY_STATUS_KEY,
		LOBBY_STATUS_WAITING,
		Steam.LOBBY_COMPARISON_EQUAL
	)

	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)

	Steam.requestLobbyList()


func _on_lobby_match_list(lobbies: Array) -> void:
	var lobby_infos: Array = []

	for found_lobby_id in lobbies:
		var lobby_game := Steam.getLobbyData(found_lobby_id, LOBBY_GAME_KEY)
		var lobby_status := Steam.getLobbyData(found_lobby_id, LOBBY_STATUS_KEY)

		if lobby_game != LOBBY_GAME_VALUE:
			continue

		if lobby_status != LOBBY_STATUS_WAITING:
			continue

		var lobby_name := Steam.getLobbyData(found_lobby_id, "name")
		var lobby_host := Steam.getLobbyData(found_lobby_id, "host_id")
		var member_count := Steam.getNumLobbyMembers(found_lobby_id)
		var max_members := Steam.getLobbyMemberLimit(found_lobby_id)

		var lobby_info := {
			"id": found_lobby_id,
			"name": lobby_name,
			"game": lobby_game,
			"status": lobby_status,
			"host_id": lobby_host,
			"member_count": member_count,
			"max_members": max_members
		}

		lobby_infos.append(lobby_info)

	lobby_list_received.emit(lobby_infos)


func join_lobby(selected_lobby_id: int) -> void:
	if not is_steam_initialized:
		print("Steam is not initialized")
		return

	if lobby_id != 0:
		print("Already in lobby: ", lobby_id)
		return

	Steam.joinLobby(selected_lobby_id)


func _on_lobby_joined(
	joined_lobby_id: int,
	_permissions: int,
	_locked: bool,
	response: int
) -> void:
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		print("Failed to join lobby. Response: ", response)
		lobby_join_failed.emit(response)
		return

	lobby_id = joined_lobby_id

	update_lobby_members()

	lobby_joined.emit(lobby_id)


func leave_lobby() -> void:
	if lobby_id == 0:
		return

	Steam.leaveLobby(lobby_id)

	NetworkManager.connection.stop_network()
	lobby_id = 0
	is_starting_game_from_lobby = false
	is_waiting_for_host_network = false
	lobby_members.clear()

	lobby_left.emit()
	lobby_members_updated.emit(lobby_members)


func update_lobby_members() -> void:
	if lobby_id == 0:
		return

	lobby_members.clear()

	var member_count := Steam.getNumLobbyMembers(lobby_id)
	var owner_id := Steam.getLobbyOwner(lobby_id)

	for i in range(member_count):
		var member_id := Steam.getLobbyMemberByIndex(lobby_id, i)
		var member_name := Steam.getFriendPersonaName(member_id)

		var member_info := {
			"id": member_id,
			"name": member_name,
			"is_owner": member_id == owner_id,
			"is_me": member_id == Steam.getSteamID()
		}

		lobby_members.append(member_info)

	lobby_members_updated.emit(lobby_members)


func _on_persona_state_change(_steam_id: int, _flag: int) -> void:
	if lobby_id != 0:
		update_lobby_members()


func is_lobby_owner() -> bool:
	if lobby_id == 0:
		return false

	return Steam.getLobbyOwner(lobby_id) == Steam.getSteamID()


func get_lobby_owner_id() -> int:
	if lobby_id == 0:
		return 0

	return Steam.getLobbyOwner(lobby_id)


func get_current_lobby_id() -> int:
	return lobby_id


func get_current_lobby_members() -> Array:
	return lobby_members


func set_lobby_status(status: String) -> void:
	if lobby_id == 0:
		return

	if not is_lobby_owner():
		print("Only lobby owner can change lobby status")
		return

	Steam.setLobbyData(lobby_id, LOBBY_STATUS_KEY, status)


func set_lobby_level_id(level_id: String) -> bool:
	if lobby_id == 0 or not is_lobby_owner():
		return false

	return bool(Steam.setLobbyData(lobby_id, LOBBY_LEVEL_KEY, level_id))


func get_lobby_level_id() -> String:
	if lobby_id == 0:
		return LevelCatalog.DEFAULT_LEVEL_ID

	var level_id: String = str(Steam.getLobbyData(lobby_id, LOBBY_LEVEL_KEY))
	if level_id.is_empty():
		return LevelCatalog.DEFAULT_LEVEL_ID

	return level_id


func request_start_game_from_lobby() -> void:
	if lobby_id == 0:
		print("Cannot start game: not in a lobby")
		return

	if not is_lobby_owner():
		print("Only lobby owner can start the game")
		return

	if is_starting_game_from_lobby:
		return

	if not is_relay_network_ready():
		push_warning("Cannot start multiplayer: Steam relay network is not ready on host")

		if Steam.has_method("initRelayNetworkAccess"):
			Steam.initRelayNetworkAccess()

		return

	update_lobby_members()
	set_lobby_status(LOBBY_STATUS_IN_GAME)

	var start_message_sent := Steam.sendLobbyChatMsg(lobby_id, LOBBY_MESSAGE_START_GAME)
	if not start_message_sent:
		print("Failed to send lobby start game message")

	start_game_from_lobby()

	if not is_starting_game_from_lobby:
		return

	var was_sent := Steam.sendLobbyChatMsg(lobby_id, LOBBY_MESSAGE_HOST_NETWORK_READY)

	if not was_sent:
		print("Failed to send host network ready message")


func start_game_from_lobby() -> void:
	if is_starting_game_from_lobby:
		return

	if lobby_id == 0:
		print("Cannot start game: not in a lobby")
		return

	is_starting_game_from_lobby = true
	lobby_game_start_requested.emit()

	update_lobby_members()
	GameSession.start_multiplayer_from_lobby()
	var network_result: int = NetworkManager.connection.start_from_session()

	if network_result != OK:
		is_starting_game_from_lobby = false
		is_waiting_for_host_network = false
		GameSession.clear()
		return

	if NetworkManager.connection.is_ready():
		is_waiting_for_host_network = false
		GameSession.go_to_selected_scene()
		return

	if not NetworkManager.connection.network_started.is_connected(_on_network_started_for_game):
		NetworkManager.connection.network_started.connect(_on_network_started_for_game, CONNECT_ONE_SHOT)


func wait_for_host_network_from_lobby() -> void:
	if is_starting_game_from_lobby or is_waiting_for_host_network:
		return

	if lobby_id == 0:
		print("Cannot prepare game: not in a lobby")
		return

	is_waiting_for_host_network = true
	lobby_game_start_requested.emit()
	update_lobby_members()
	GameSession.start_multiplayer_from_lobby()


func _on_network_started_for_game() -> void:
	if not is_starting_game_from_lobby:
		return

	is_waiting_for_host_network = false
	GameSession.go_to_selected_scene()


func _on_lobby_message(
	message_lobby_id: int,
	_user: int,
	message: String,
	_chat_type: int
) -> void:
	if message_lobby_id != lobby_id:
		return

	if message == LOBBY_MESSAGE_START_GAME:
		wait_for_host_network_from_lobby()
	elif message == LOBBY_MESSAGE_HOST_NETWORK_READY:
		start_game_from_lobby()


func is_relay_network_ready() -> bool:
	if not Steam.has_method("getRelayNetworkStatus"):
		return true

	return int(Steam.getRelayNetworkStatus()) == 100


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		leave_lobby()
		get_tree().quit()
