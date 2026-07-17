class_name NetworkChannel
extends Node

var connection: NetworkConnectionChannel = null
var peers: NetworkPeerRegistry = null
var store: NetworkReplicationStore = null
var diagnostic_counters: Dictionary[String, int] = {
	"rejected_stale_packets": 0,
	"rejected_oversized_payloads": 0,
	"rejected_invalid_payloads": 0,
}


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


func _is_valid_match_message(match_id: String, protocol_version: int = NetworkProtocol.PROTOCOL_VERSION) -> bool:
	return NetworkProtocol.is_current_version(protocol_version) and NetworkProtocol.is_valid_match_id(match_id)


func _is_valid_intent(match_id: String, request_id: int, payload: Variant = null) -> bool:
	if request_id <= 0:
		_increment_network_diagnostic("rejected_invalid_payloads")
		return false
	if not _is_valid_match_message(match_id):
		_increment_network_diagnostic("rejected_stale_packets")
		return false
	if not _is_payload_size_valid(payload):
		return false
	return true


func get_diagnostic_counters() -> Dictionary:
	return diagnostic_counters.duplicate()


func _is_payload_size_valid(payload: Variant, maximum_bytes: int = NetworkProtocol.MAX_INTENT_PAYLOAD_BYTES) -> bool:
	if NetworkProtocol.get_payload_size(payload) <= maximum_bytes:
		return true
	_increment_network_diagnostic("rejected_oversized_payloads")
	return false


func _increment_network_diagnostic(counter_name: String) -> void:
	diagnostic_counters[counter_name] = int(diagnostic_counters.get(counter_name, 0)) + 1
