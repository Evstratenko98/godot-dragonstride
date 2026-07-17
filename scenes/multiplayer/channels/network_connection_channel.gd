class_name NetworkConnectionChannel
extends Node

signal network_started()
signal network_failed(reason: String)
signal network_stopped()
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal server_disconnected()
signal steam_peer_disconnected(steam_id: int)
signal client_match_ready_received(steam_id: int, match_id: String, roster_hash: String)
signal match_load_requested(match_id: String)

var peer: MultiplayerPeer = null
var is_network_active: bool = false
var is_host: bool = false
var lobby_id: int = 0
var host_steam_id: int = 0
var local_steam_id: int = 0
var last_error: String = ""
var has_reported_ready: bool = false
var has_registered_with_host: bool = false
var peers: NetworkPeerRegistry = null
var store: NetworkReplicationStore = null
var is_accepting_match_peers: bool = true


func _process(_delta: float) -> void:
	if is_network_active and not has_reported_ready and is_ready():
		_complete_network_ready()


func configure_context(new_peers: NetworkPeerRegistry, new_store: NetworkReplicationStore) -> void:
	peers = new_peers
	store = new_store


func start_from_session() -> int:
	if GameSession.is_singleplayer():
		stop_network()
		return OK
	if not GameSession.is_multiplayer():
		return _fail("Cannot start network: GameSession mode is " + str(GameSession.mode))

	lobby_id = GameSession.lobby_id
	host_steam_id = GameSession.host_steam_id
	local_steam_id = GameSession.local_steam_id
	var transport_local_steam_id: int = int(Steam.getSteamID())
	if local_steam_id == 0 or local_steam_id != transport_local_steam_id:
		return _fail("Cannot start network: local Steam identity does not match transport identity")
	if GameSession.is_host():
		return start_host()
	return start_client()


func start_host() -> int:
	var session_lobby_id: int = lobby_id
	var session_host_steam_id: int = host_steam_id
	var session_local_steam_id: int = local_steam_id
	stop_network()
	lobby_id = session_lobby_id
	host_steam_id = session_host_steam_id
	local_steam_id = session_local_steam_id
	if lobby_id == 0:
		return _fail("Cannot host: lobby_id is empty")

	var new_peer: MultiplayerPeer = _create_steam_multiplayer_peer()
	if new_peer == null:
		return _fail("Cannot host: SteamMultiplayerPeer is not available")
	_prepare_steam_peer(new_peer)

	var result: int = ERR_UNAVAILABLE
	if new_peer.has_method("create_host"):
		result = _call_peer_method(new_peer, "create_host", [])
	elif new_peer.has_method("host_with_lobby"):
		result = _call_peer_method(new_peer, "host_with_lobby", [lobby_id])
	if result != OK:
		return _fail("Cannot host: peer returned error " + str(result))

	_add_lobby_members_to_host_peer(new_peer)
	_activate_peer(new_peer, true)
	return OK


func start_client() -> int:
	var session_lobby_id: int = lobby_id
	var session_host_steam_id: int = host_steam_id
	var session_local_steam_id: int = local_steam_id
	stop_network()
	lobby_id = session_lobby_id
	host_steam_id = session_host_steam_id
	local_steam_id = session_local_steam_id
	if lobby_id == 0:
		return _fail("Cannot connect: lobby_id is empty")
	if host_steam_id == 0:
		return _fail("Cannot connect: host_steam_id is empty")

	var new_peer: MultiplayerPeer = _create_steam_multiplayer_peer()
	if new_peer == null:
		return _fail("Cannot connect: SteamMultiplayerPeer is not available")
	_prepare_steam_peer(new_peer)

	var result: int = ERR_UNAVAILABLE
	if new_peer.has_method("create_client"):
		result = _call_peer_method(new_peer, "create_client", [host_steam_id])
	elif new_peer.has_method("connect_to_lobby"):
		result = _call_peer_method(new_peer, "connect_to_lobby", [lobby_id])
	elif new_peer.has_method("connect_lobby"):
		result = _call_peer_method(new_peer, "connect_lobby", [lobby_id])
	if result != OK:
		return _fail("Cannot connect: peer returned error " + str(result))

	_activate_peer(new_peer, false)
	return OK


func stop_network() -> void:
	if peer != null and peer.has_method("close"):
		peer.call("close")
	if multiplayer.multiplayer_peer == peer:
		multiplayer.multiplayer_peer = null

	peer = null
	is_network_active = false
	is_host = false
	lobby_id = 0
	host_steam_id = 0
	local_steam_id = 0
	has_reported_ready = false
	has_registered_with_host = false
	is_accepting_match_peers = true
	if peers != null:
		peers.clear()
	if store != null:
		store.clear()
	network_stopped.emit()


func is_ready() -> bool:
	return (
		is_network_active
		and peer != null
		and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	)


func set_accepting_match_peers(is_accepting: bool) -> void:
	is_accepting_match_peers = is_accepting


func send_client_match_ready(match_id: String, roster_hash: String) -> void:
	if not is_ready() or is_host or match_id.is_empty() or roster_hash.is_empty():
		return
	rpc_id(1, "_submit_client_match_ready", match_id, roster_hash)


func broadcast_match_load(match_id: String) -> void:
	if not is_host or not is_ready() or match_id.is_empty():
		return
	match_load_requested.emit(match_id)
	rpc("_receive_match_load", match_id)


func _create_steam_multiplayer_peer() -> MultiplayerPeer:
	if not ClassDB.class_exists("SteamMultiplayerPeer"):
		return null
	return ClassDB.instantiate("SteamMultiplayerPeer") as MultiplayerPeer


func _prepare_steam_peer(new_peer: MultiplayerPeer) -> void:
	if new_peer.has_method("set_no_delay"):
		new_peer.call("set_no_delay", true)
	if new_peer.has_method("set_no_nagle"):
		new_peer.call("set_no_nagle", true)
	if _peer_has_property(new_peer, "server_relay"):
		new_peer.set("server_relay", true)


func _add_lobby_members_to_host_peer(new_peer: MultiplayerPeer) -> void:
	if not new_peer.has_method("add_peer") or lobby_id == 0:
		return
	var member_count: int = Steam.getNumLobbyMembers(lobby_id)
	for index: int in range(member_count):
		var member_steam_id: int = int(Steam.getLobbyMemberByIndex(lobby_id, index))
		if member_steam_id == 0 or member_steam_id == local_steam_id:
			continue
		var add_result: int = int(new_peer.call("add_peer", member_steam_id))
		if add_result != OK:
			push_warning("Failed to add lobby member to Steam peer: " + str(add_result))


func _peer_has_property(object: Object, property_name: String) -> bool:
	for property_variant: Variant in object.get_property_list():
		var property: Dictionary = property_variant
		if String(property.get("name", "")) == property_name:
			return true
	return false


func _call_peer_method(target_peer: MultiplayerPeer, method_name: String, arguments: Array) -> int:
	if not target_peer.has_method(method_name):
		return ERR_UNAVAILABLE
	return int(target_peer.callv(method_name, arguments))


func _activate_peer(new_peer: MultiplayerPeer, should_host: bool) -> void:
	peer = new_peer
	is_host = should_host
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
	var local_peer_id: int = multiplayer.get_unique_id()
	if local_peer_id != 0:
		peers.register_peer(local_peer_id, local_steam_id)


func _broadcast_peer_map() -> void:
	if not is_host:
		return
	var peer_map: Dictionary = peers.get_peer_map()
	_receive_peer_map(peer_map)
	rpc("_receive_peer_map", peer_map)


func _complete_network_ready() -> void:
	if has_reported_ready:
		return
	has_reported_ready = true
	if not is_host and not has_registered_with_host:
		has_registered_with_host = true
		rpc_id(1, "_register_remote_steam_id", local_steam_id, NetworkProtocol.PROTOCOL_VERSION)
	network_started.emit()


func _is_allowed_session_steam_id(steam_id: int) -> bool:
	return (
		steam_id != 0
		and steam_id != local_steam_id
		and not GameSession.get_player_by_steam_id(steam_id).is_empty()
	)


func _get_transport_steam_id_for_peer_id(peer_id: int) -> int:
	if peer == null or peer_id == 0 or not peer.has_method("get_steam_id_for_peer_id"):
		return 0
	return int(peer.call("get_steam_id_for_peer_id", peer_id))


@rpc("any_peer", "reliable")
func _register_remote_steam_id(claimed_steam_id: int, protocol_version: int) -> void:
	if not is_host:
		return
	var sender_peer_id: int = multiplayer.get_remote_sender_id()
	var transport_steam_id: int = _get_transport_steam_id_for_peer_id(sender_peer_id)
	if (
		sender_peer_id == 0
		or transport_steam_id == 0
		or claimed_steam_id != transport_steam_id
		or protocol_version != NetworkProtocol.PROTOCOL_VERSION
		or not _is_allowed_session_steam_id(transport_steam_id)
	):
		push_warning("Rejected peer registration because Steam transport identity was not verified")
		_disconnect_transport_peer(sender_peer_id)
		return
	if not peers.register_peer(sender_peer_id, transport_steam_id):
		return
	_broadcast_peer_map()


@rpc("any_peer", "call_remote", "reliable")
func _submit_client_match_ready(submitted_match_id: String, submitted_roster_hash: String) -> void:
	var sender_peer_id: int = _get_registered_sender_peer_id()
	if sender_peer_id == 0:
		return
	var sender_steam_id: int = peers.get_steam_id_for_peer_id(sender_peer_id)
	if (
		submitted_match_id != GameSession.get_match_id()
		or submitted_roster_hash != GameSession.get_roster_hash()
		or GameSession.get_player_by_steam_id(sender_steam_id).is_empty()
	):
		_disconnect_transport_peer(sender_peer_id)
		return
	client_match_ready_received.emit(sender_steam_id, submitted_match_id, submitted_roster_hash)


@rpc("authority", "call_remote", "reliable")
func _receive_match_load(submitted_match_id: String) -> void:
	if submitted_match_id == GameSession.get_match_id():
		match_load_requested.emit(submitted_match_id)


@rpc("authority", "reliable")
func _receive_peer_map(remote_steam_id_by_peer_id: Dictionary) -> void:
	peers.replace_peer_map(remote_steam_id_by_peer_id)


func _on_peer_connected(peer_id: int) -> void:
	if is_host and not is_accepting_match_peers and not peers.has_steam_id_for_peer(peer_id):
		_disconnect_transport_peer(peer_id)
		return
	if is_host:
		_broadcast_peer_map()
	peer_connected.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	var disconnected_steam_id: int = peers.get_steam_id_for_peer_id(peer_id)
	if is_host:
		peers.remove_peer(peer_id)
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


func _get_registered_sender_peer_id() -> int:
	if not is_host:
		return 0
	var sender_peer_id: int = multiplayer.get_remote_sender_id()
	if sender_peer_id == 0 or not peers.has_steam_id_for_peer(sender_peer_id):
		return 0
	return sender_peer_id


func _disconnect_transport_peer(peer_id: int) -> void:
	if peer == null or peer_id == 0 or not peer.has_method("disconnect_peer"):
		return
	peer.call("disconnect_peer", peer_id, true)
