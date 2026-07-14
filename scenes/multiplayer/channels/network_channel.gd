class_name NetworkChannel
extends Node

var connection: NetworkConnectionChannel = null
var peers: NetworkPeerRegistry = null
var store: NetworkReplicationStore = null


func configure_context(
	new_connection: NetworkConnectionChannel,
	new_peers: NetworkPeerRegistry,
	new_store: NetworkReplicationStore
) -> void:
	connection = new_connection
	peers = new_peers
	store = new_store


func _can_send() -> bool:
	return GameSession.is_multiplayer() and connection != null and connection.is_ready()


func _can_host_send() -> bool:
	return _can_send() and connection.is_host


func _get_registered_sender_peer_id() -> int:
	if connection == null or not connection.is_host or peers == null:
		return 0
	var sender_peer_id: int = multiplayer.get_remote_sender_id()
	if sender_peer_id == 0 or not peers.has_steam_id_for_peer(sender_peer_id):
		return 0
	return sender_peer_id


func _get_registered_sender_steam_id() -> int:
	var sender_peer_id: int = _get_registered_sender_peer_id()
	if sender_peer_id == 0:
		return 0
	return peers.get_steam_id_for_peer_id(sender_peer_id)
