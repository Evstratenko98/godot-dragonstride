extends Node

signal network_started()
signal network_failed(reason: String)
signal network_stopped()
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal server_disconnected()
signal peer_map_updated()
signal player_state_received(steam_id: int, player_position: Vector2, animation: String, is_moving: bool)
signal character_state_received(
	steam_id: int,
	player_position: Vector2,
	animation: String,
	is_moving: bool,
	facing_left: bool
)
signal attack_requested(steam_id: int, target_cell: Vector2i)
signal attack_received(steam_id: int, target_cell: Vector2i)
signal object_state_received(object_id: String, object_state: int)
signal entity_move_received(entity_id: String, from_cell: Vector2i, target_cell: Vector2i)
signal entity_attack_received(entity_id: String, target_cell: Vector2i)
signal entity_attack_result_received(
	attacker_entity_id: String,
	target_entity_id: String,
	damage: int,
	target_health: int,
	target_max_health: int
)
signal entity_health_received(entity_id: String, health: int)
signal entity_respawn_received(entity_id: String, cell: Vector2i, health: int)
signal entity_removed_received(entity_id: String)
signal end_game_requested()
signal turn_state_received(snapshot: Dictionary)
signal turn_end_requested(steam_id: int)
signal steam_peer_disconnected(steam_id: int)
signal world_spawn_requested(type_key: String, cell: Vector2i, requester_peer_id: int)
signal world_spawn_received(record: Dictionary)
signal world_spawn_failed_received(message: String)

var peer: MultiplayerPeer = null
var is_network_active := false
var is_host := false
var lobby_id: int = 0
var host_steam_id: int = 0
var local_steam_id: int = 0
var last_error := ""
var steam_id_by_peer_id: Dictionary = {}
var peer_id_by_steam_id: Dictionary = {}
var object_states: Dictionary = {}
var world_spawn_records: Array = []
var has_reported_ready := false
var has_registered_with_host := false


func _process(_delta: float) -> void:
	if not is_network_active:
		return

	if has_reported_ready:
		return

	if is_ready():
		_complete_network_ready()


func start_from_session() -> int:
	if GameSession.is_singleplayer():
		stop_network()
		return OK

	if not GameSession.is_multiplayer():
		return _fail("Cannot start network: GameSession mode is " + str(GameSession.mode))

	lobby_id = GameSession.lobby_id
	host_steam_id = GameSession.host_steam_id
	local_steam_id = GameSession.local_steam_id

	if GameSession.is_host():
		return start_host()

	return start_client()


func start_host() -> int:
	var session_lobby_id := lobby_id
	var session_host_steam_id := host_steam_id
	var session_local_steam_id := local_steam_id
	stop_network()
	lobby_id = session_lobby_id
	host_steam_id = session_host_steam_id
	local_steam_id = session_local_steam_id

	if lobby_id == 0:
		return _fail("Cannot host: lobby_id is empty")

	var new_peer := _create_steam_multiplayer_peer()
	if new_peer == null:
		return _fail("Cannot host: SteamMultiplayerPeer is not available")

	_prepare_steam_peer(new_peer)

	var result := ERR_UNAVAILABLE
	if new_peer.has_method("create_host"):
		result = new_peer.create_host()
	elif new_peer.has_method("host_with_lobby"):
		result = new_peer.host_with_lobby(lobby_id)
	else:
		return _fail("Cannot host: SteamMultiplayerPeer has no host method")

	if result != OK:
		return _fail("Cannot host: peer returned error " + str(result))

	_add_lobby_members_to_host_peer(new_peer)
	_activate_peer(new_peer, true)
	return OK


func start_client() -> int:
	var session_lobby_id := lobby_id
	var session_host_steam_id := host_steam_id
	var session_local_steam_id := local_steam_id
	stop_network()
	lobby_id = session_lobby_id
	host_steam_id = session_host_steam_id
	local_steam_id = session_local_steam_id

	if lobby_id == 0:
		return _fail("Cannot connect: lobby_id is empty")

	if host_steam_id == 0:
		return _fail("Cannot connect: host_steam_id is empty")

	var new_peer := _create_steam_multiplayer_peer()
	if new_peer == null:
		return _fail("Cannot connect: SteamMultiplayerPeer is not available")

	_prepare_steam_peer(new_peer)

	var result := ERR_UNAVAILABLE
	if new_peer.has_method("create_client"):
		result = new_peer.create_client(host_steam_id)
	elif new_peer.has_method("connect_to_lobby"):
		result = new_peer.connect_to_lobby(lobby_id)
	elif new_peer.has_method("connect_lobby"):
		result = new_peer.connect_lobby(lobby_id)
	else:
		return _fail("Cannot connect: SteamMultiplayerPeer has no client method")

	if result != OK:
		return _fail("Cannot connect: peer returned error " + str(result))

	_activate_peer(new_peer, false)
	return OK


func stop_network() -> void:
	if peer != null and peer.has_method("close"):
		peer.close()

	if multiplayer.multiplayer_peer == peer:
		multiplayer.multiplayer_peer = null

	peer = null
	is_network_active = false
	is_host = false
	lobby_id = 0
	host_steam_id = 0
	local_steam_id = 0
	steam_id_by_peer_id.clear()
	peer_id_by_steam_id.clear()
	object_states.clear()
	world_spawn_records.clear()
	has_reported_ready = false
	has_registered_with_host = false

	network_stopped.emit()


func is_ready() -> bool:
	if not is_network_active:
		return false

	if peer == null:
		return false

	return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func get_peer_id_for_steam_id(steam_id: int) -> int:
	return int(peer_id_by_steam_id.get(steam_id, 0))


func get_steam_id_for_peer_id(peer_id: int) -> int:
	return int(steam_id_by_peer_id.get(peer_id, 0))


func has_peer_for_steam_id(steam_id: int) -> bool:
	return peer_id_by_steam_id.has(steam_id)


func has_steam_id_for_peer(peer_id: int) -> bool:
	return steam_id_by_peer_id.has(peer_id)


func send_player_state(
	steam_id: int,
	player_position: Vector2,
	animation: String,
	is_moving_player: bool
) -> void:
	if not GameSession.is_multiplayer():
		return

	if not is_ready():
		return

	if is_host:
		rpc("_receive_player_state", steam_id, player_position, animation, is_moving_player)
		return

	rpc_id(1, "_submit_player_state", steam_id, player_position, animation, is_moving_player)


func send_character_state(
	steam_id: int,
	player_position: Vector2,
	animation: String,
	is_moving_player: bool,
	facing_left_player: bool
) -> void:
	if not GameSession.is_multiplayer():
		return

	if not is_ready():
		return

	if is_host:
		rpc(
			"_receive_character_state",
			steam_id,
			player_position,
			animation,
			is_moving_player,
			facing_left_player
		)
		return

	rpc_id(
		1,
		"_submit_character_state",
		steam_id,
		player_position,
		animation,
		is_moving_player,
		facing_left_player
	)


func request_attack(steam_id: int, target_cell: Vector2i) -> void:
	if not GameSession.is_multiplayer():
		return

	if not is_ready():
		return

	if is_host:
		attack_requested.emit(steam_id, target_cell)
		return

	rpc_id(1, "_submit_attack", steam_id, target_cell)


func broadcast_attack(steam_id: int, target_cell: Vector2i) -> void:
	if not GameSession.is_multiplayer() or not is_host or not is_ready():
		return

	rpc("_receive_attack", steam_id, target_cell)


func broadcast_entity_move(entity_id: String, from_cell: Vector2i, target_cell: Vector2i) -> void:
	if not GameSession.is_multiplayer() or not is_ready():
		return

	if is_host:
		rpc("_receive_entity_move", entity_id, from_cell, target_cell)
		return

	rpc_id(1, "_relay_entity_move", entity_id, from_cell, target_cell)


func broadcast_entity_attack(entity_id: String, target_cell: Vector2i) -> void:
	if not GameSession.is_multiplayer() or not is_ready():
		return

	if is_host:
		rpc("_receive_entity_attack", entity_id, target_cell)
		return

	rpc_id(1, "_relay_entity_attack", entity_id, target_cell)


func broadcast_entity_attack_result(
	attacker_entity_id: String,
	target_entity_id: String,
	damage: int,
	target_health: int,
	target_max_health: int
) -> void:
	if not GameSession.is_multiplayer() or not is_ready():
		return

	if is_host:
		rpc(
			"_receive_entity_attack_result",
			attacker_entity_id,
			target_entity_id,
			damage,
			target_health,
			target_max_health
		)
		return

	rpc_id(
		1,
		"_relay_entity_attack_result",
		attacker_entity_id,
		target_entity_id,
		damage,
		target_health,
		target_max_health
	)


func broadcast_entity_health(entity_id: String, health: int) -> void:
	if not GameSession.is_multiplayer() or not is_ready():
		return

	if is_host:
		rpc("_receive_entity_health", entity_id, health)
		return

	rpc_id(1, "_relay_entity_health", entity_id, health)


func broadcast_entity_respawn(entity_id: String, cell: Vector2i, health: int) -> void:
	if not GameSession.is_multiplayer() or not is_ready():
		return

	if is_host:
		rpc("_receive_entity_respawn", entity_id, cell, health)
		return

	rpc_id(1, "_relay_entity_respawn", entity_id, cell, health)


func broadcast_entity_removed(entity_id: String) -> void:
	if not GameSession.is_multiplayer() or not is_ready():
		return

	if is_host:
		rpc("_receive_entity_removed", entity_id)
		return

	rpc_id(1, "_relay_entity_removed", entity_id)


func broadcast_object_state(object_id: String, object_state: int) -> void:
	if not GameSession.is_multiplayer() or not is_ready():
		return

	object_states[object_id] = object_state
	if is_host:
		rpc("_receive_object_state", object_id, object_state)
		return

	rpc_id(1, "_relay_object_state", object_id, object_state)


func get_object_states() -> Dictionary:
	return object_states.duplicate()


func request_world_spawn(type_key: String, cell: Vector2i) -> void:
	if not GameSession.is_multiplayer():
		return

	if not is_ready():
		world_spawn_failed_received.emit("Cannot create spawn: network is not ready.")
		return

	if is_host:
		world_spawn_requested.emit(type_key, cell, 0)
		return

	rpc_id(1, "_submit_world_spawn", type_key, cell)


func broadcast_world_spawn(record: Dictionary) -> void:
	if not GameSession.is_multiplayer() or not is_host or not is_ready():
		return

	_cache_world_spawn_record(record)
	rpc("_receive_world_spawn", record)


func send_world_spawn_failed(peer_id: int, message: String) -> void:
	if peer_id == 0 or peer_id == multiplayer.get_unique_id():
		world_spawn_failed_received.emit(message)
		return

	if not is_ready():
		return

	rpc_id(peer_id, "_receive_world_spawn_failed", message)


func send_world_spawns_to_peer(peer_id: int) -> void:
	if not GameSession.is_multiplayer() or not is_host or not is_ready():
		return

	for record in world_spawn_records:
		rpc_id(peer_id, "_receive_world_spawn", record)


func get_world_spawn_records() -> Array:
	return world_spawn_records.duplicate(true)


func request_end_game() -> void:
	if not GameSession.is_multiplayer():
		end_game_requested.emit()
		return

	if not is_ready():
		end_game_requested.emit()
		return

	if is_host:
		_broadcast_end_game()
		return

	rpc_id(1, "_submit_end_game")


func broadcast_turn_state(snapshot: Dictionary) -> void:
	if not GameSession.is_multiplayer() or not is_host or not is_ready():
		return

	rpc("_receive_turn_state", snapshot)


func request_turn_end(steam_id: int) -> void:
	if not GameSession.is_multiplayer():
		turn_end_requested.emit(steam_id)
		return

	if not is_ready():
		return

	if is_host:
		turn_end_requested.emit(steam_id)
		return

	rpc_id(1, "_submit_turn_end", steam_id)


func _create_steam_multiplayer_peer() -> MultiplayerPeer:
	if not ClassDB.class_exists("SteamMultiplayerPeer"):
		return null

	return ClassDB.instantiate("SteamMultiplayerPeer") as MultiplayerPeer


func _prepare_steam_peer(new_peer: MultiplayerPeer) -> void:
	if new_peer.has_method("set_no_delay"):
		new_peer.set_no_delay(true)

	if new_peer.has_method("set_no_nagle"):
		new_peer.set_no_nagle(true)

	if _peer_has_property(new_peer, "server_relay"):
		new_peer.set("server_relay", true)


func _add_lobby_members_to_host_peer(new_peer: MultiplayerPeer) -> void:
	if not new_peer.has_method("add_peer"):
		return

	if lobby_id == 0:
		return

	var member_count := Steam.getNumLobbyMembers(lobby_id)

	for i in range(member_count):
		var member_steam_id := int(Steam.getLobbyMemberByIndex(lobby_id, i))

		if member_steam_id == 0:
			continue

		if member_steam_id == local_steam_id:
			continue

		var add_result: int = new_peer.add_peer(member_steam_id)
		if add_result != OK:
			push_warning("Failed to add lobby member to Steam peer: " + str(add_result))


func _peer_has_property(object: Object, property_name: String) -> bool:
	for property in object.get_property_list():
		if String(property.get("name", "")) == property_name:
			return true

	return false


func _activate_peer(new_peer: MultiplayerPeer, host_mode: bool) -> void:
	peer = new_peer
	is_host = host_mode
	is_network_active = true
	last_error = ""

	multiplayer.multiplayer_peer = peer
	_connect_multiplayer_signals()
	_register_local_peer()

	if is_ready():
		_complete_network_ready()


func _connect_multiplayer_signals() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)

	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)

	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)

	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)


func _fail(reason: String) -> int:
	last_error = reason
	is_network_active = false
	print(reason)
	network_failed.emit(reason)
	return ERR_CANT_CREATE


func _register_local_peer() -> void:
	var local_peer_id := multiplayer.get_unique_id()

	if local_peer_id == 0:
		return

	_register_peer_mapping(local_peer_id, local_steam_id)


func _register_peer_mapping(peer_id: int, steam_id: int) -> void:
	if peer_id == 0 or steam_id == 0:
		return

	steam_id_by_peer_id[peer_id] = steam_id
	peer_id_by_steam_id[steam_id] = peer_id
	peer_map_updated.emit()


func _remove_peer_mapping(peer_id: int) -> void:
	if not steam_id_by_peer_id.has(peer_id):
		return

	var steam_id := int(steam_id_by_peer_id[peer_id])
	steam_id_by_peer_id.erase(peer_id)
	peer_id_by_steam_id.erase(steam_id)
	peer_map_updated.emit()


func _broadcast_peer_map() -> void:
	if not is_host:
		return

	var peer_map := steam_id_by_peer_id.duplicate()
	_receive_peer_map(peer_map)
	rpc("_receive_peer_map", peer_map)


@rpc("any_peer", "reliable")
func _register_remote_steam_id(steam_id: int) -> void:
	if not is_host:
		return

	var sender_peer_id := multiplayer.get_remote_sender_id()
	_register_peer_mapping(sender_peer_id, steam_id)
	_broadcast_peer_map()


func _complete_network_ready() -> void:
	if has_reported_ready:
		return

	has_reported_ready = true

	if not is_host and not has_registered_with_host:
		has_registered_with_host = true
		rpc_id(1, "_register_remote_steam_id", local_steam_id)

	network_started.emit()


@rpc("authority", "reliable")
func _receive_peer_map(remote_steam_id_by_peer_id: Dictionary) -> void:
	steam_id_by_peer_id.clear()
	peer_id_by_steam_id.clear()

	for peer_id_key in remote_steam_id_by_peer_id.keys():
		var peer_id := int(peer_id_key)
		var steam_id := int(remote_steam_id_by_peer_id[peer_id_key])
		_register_peer_mapping(peer_id, steam_id)


@rpc("any_peer", "unreliable")
func _submit_player_state(
	steam_id: int,
	player_position: Vector2,
	animation: String,
	is_moving_player: bool
) -> void:
	if not is_host:
		return

	var sender_peer_id := multiplayer.get_remote_sender_id()
	var registered_steam_id := get_steam_id_for_peer_id(sender_peer_id)

	if registered_steam_id != steam_id:
		return

	player_state_received.emit(steam_id, player_position, animation, is_moving_player)
	rpc("_receive_player_state", steam_id, player_position, animation, is_moving_player)


@rpc("authority", "unreliable")
func _receive_player_state(
	steam_id: int,
	player_position: Vector2,
	animation: String,
	is_moving_player: bool
) -> void:
	if steam_id == local_steam_id:
		return

	player_state_received.emit(steam_id, player_position, animation, is_moving_player)


@rpc("any_peer", "unreliable")
func _submit_character_state(
	steam_id: int,
	player_position: Vector2,
	animation: String,
	is_moving_player: bool,
	facing_left_player: bool
) -> void:
	if not is_host:
		return

	var sender_peer_id := multiplayer.get_remote_sender_id()
	var registered_steam_id := get_steam_id_for_peer_id(sender_peer_id)

	if registered_steam_id != steam_id:
		return

	character_state_received.emit(
		steam_id,
		player_position,
		animation,
		is_moving_player,
		facing_left_player
	)
	rpc(
		"_receive_character_state",
		steam_id,
		player_position,
		animation,
		is_moving_player,
		facing_left_player
	)


@rpc("authority", "unreliable")
func _receive_character_state(
	steam_id: int,
	player_position: Vector2,
	animation: String,
	is_moving_player: bool,
	facing_left_player: bool
) -> void:
	if steam_id == local_steam_id:
		return

	character_state_received.emit(
		steam_id,
		player_position,
		animation,
		is_moving_player,
		facing_left_player
	)


@rpc("any_peer", "reliable")
func _submit_attack(steam_id: int, target_cell: Vector2i) -> void:
	if not is_host:
		return

	var sender_peer_id := multiplayer.get_remote_sender_id()
	var registered_steam_id := get_steam_id_for_peer_id(sender_peer_id)

	if registered_steam_id != steam_id:
		return

	attack_requested.emit(steam_id, target_cell)


@rpc("authority", "reliable")
func _receive_attack(steam_id: int, target_cell: Vector2i) -> void:
	if steam_id == local_steam_id:
		return

	attack_received.emit(steam_id, target_cell)


@rpc("any_peer", "reliable")
func _relay_entity_move(entity_id: String, from_cell: Vector2i, target_cell: Vector2i) -> void:
	if not is_host:
		return

	entity_move_received.emit(entity_id, from_cell, target_cell)
	rpc("_receive_entity_move", entity_id, from_cell, target_cell)


@rpc("authority", "reliable")
func _receive_entity_move(entity_id: String, from_cell: Vector2i, target_cell: Vector2i) -> void:
	entity_move_received.emit(entity_id, from_cell, target_cell)


@rpc("any_peer", "reliable")
func _relay_entity_attack(entity_id: String, target_cell: Vector2i) -> void:
	if not is_host:
		return

	entity_attack_received.emit(entity_id, target_cell)
	rpc("_receive_entity_attack", entity_id, target_cell)


@rpc("authority", "reliable")
func _receive_entity_attack(entity_id: String, target_cell: Vector2i) -> void:
	entity_attack_received.emit(entity_id, target_cell)


@rpc("any_peer", "reliable")
func _relay_entity_attack_result(
	attacker_entity_id: String,
	target_entity_id: String,
	damage: int,
	target_health: int,
	target_max_health: int
) -> void:
	if not is_host:
		return

	entity_attack_result_received.emit(
		attacker_entity_id,
		target_entity_id,
		damage,
		target_health,
		target_max_health
	)
	rpc(
		"_receive_entity_attack_result",
		attacker_entity_id,
		target_entity_id,
		damage,
		target_health,
		target_max_health
	)


@rpc("authority", "reliable")
func _receive_entity_attack_result(
	attacker_entity_id: String,
	target_entity_id: String,
	damage: int,
	target_health: int,
	target_max_health: int
) -> void:
	entity_attack_result_received.emit(
		attacker_entity_id,
		target_entity_id,
		damage,
		target_health,
		target_max_health
	)


@rpc("any_peer", "reliable")
func _relay_entity_health(entity_id: String, health: int) -> void:
	if not is_host:
		return

	entity_health_received.emit(entity_id, health)
	rpc("_receive_entity_health", entity_id, health)


@rpc("authority", "reliable")
func _receive_entity_health(entity_id: String, health: int) -> void:
	entity_health_received.emit(entity_id, health)


@rpc("any_peer", "reliable")
func _relay_entity_respawn(entity_id: String, cell: Vector2i, health: int) -> void:
	if not is_host:
		return

	entity_respawn_received.emit(entity_id, cell, health)
	rpc("_receive_entity_respawn", entity_id, cell, health)


@rpc("authority", "reliable")
func _receive_entity_respawn(entity_id: String, cell: Vector2i, health: int) -> void:
	entity_respawn_received.emit(entity_id, cell, health)


@rpc("any_peer", "reliable")
func _relay_entity_removed(entity_id: String) -> void:
	if not is_host:
		return

	entity_removed_received.emit(entity_id)
	rpc("_receive_entity_removed", entity_id)


@rpc("authority", "reliable")
func _receive_entity_removed(entity_id: String) -> void:
	entity_removed_received.emit(entity_id)


@rpc("any_peer", "reliable")
func _relay_object_state(object_id: String, object_state: int) -> void:
	if not is_host:
		return

	object_states[object_id] = object_state
	object_state_received.emit(object_id, object_state)
	rpc("_receive_object_state", object_id, object_state)


@rpc("authority", "reliable")
func _receive_object_state(object_id: String, object_state: int) -> void:
	object_states[object_id] = object_state
	object_state_received.emit(object_id, object_state)


@rpc("any_peer", "reliable")
func _submit_world_spawn(type_key: String, cell: Vector2i) -> void:
	if not is_host:
		return

	world_spawn_requested.emit(type_key, cell, multiplayer.get_remote_sender_id())


@rpc("authority", "reliable")
func _receive_world_spawn(record: Dictionary) -> void:
	_cache_world_spawn_record(record)
	world_spawn_received.emit(record)


@rpc("authority", "reliable")
func _receive_world_spawn_failed(message: String) -> void:
	world_spawn_failed_received.emit(message)


func _broadcast_end_game() -> void:
	_receive_end_game()
	rpc("_receive_end_game")


@rpc("any_peer", "reliable")
func _submit_end_game() -> void:
	if not is_host:
		return

	_broadcast_end_game()


@rpc("authority", "reliable")
func _receive_end_game() -> void:
	end_game_requested.emit()


@rpc("authority", "reliable")
func _receive_turn_state(snapshot: Dictionary) -> void:
	turn_state_received.emit(snapshot)


@rpc("any_peer", "reliable")
func _submit_turn_end(steam_id: int) -> void:
	if not is_host:
		return

	var sender_peer_id := multiplayer.get_remote_sender_id()
	var registered_steam_id := get_steam_id_for_peer_id(sender_peer_id)

	if registered_steam_id != steam_id:
		return

	turn_end_requested.emit(steam_id)


func _on_peer_connected(peer_id: int) -> void:
	if is_host:
		_broadcast_peer_map()
	peer_connected.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	var disconnected_steam_id := get_steam_id_for_peer_id(peer_id)
	if is_host:
		_remove_peer_mapping(peer_id)
		_broadcast_peer_map()
	if disconnected_steam_id != 0:
		steam_peer_disconnected.emit(disconnected_steam_id)
	peer_disconnected.emit(peer_id)


func _on_connected_to_server() -> void:
	_complete_network_ready()


func _on_connection_failed() -> void:
	_fail("Connection failed")


func _on_server_disconnected() -> void:
	is_network_active = false
	print("Server disconnected")
	server_disconnected.emit()


func _cache_world_spawn_record(record: Dictionary) -> void:
	var spawn_id := str(record.get("spawn_id", ""))
	if spawn_id.is_empty():
		return

	for existing_record in world_spawn_records:
		if str(existing_record.get("spawn_id", "")) == spawn_id:
			return

	world_spawn_records.append(record.duplicate(true))
