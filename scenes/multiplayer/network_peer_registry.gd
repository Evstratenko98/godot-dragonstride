class_name NetworkPeerRegistry
extends RefCounted

signal peer_map_updated()

var steam_id_by_peer_id: Dictionary[int, int] = {}
var peer_id_by_steam_id: Dictionary[int, int] = {}


func clear() -> void:
	steam_id_by_peer_id.clear()
	peer_id_by_steam_id.clear()
	peer_map_updated.emit()


func register_peer(peer_id: int, steam_id: int) -> bool:
	if peer_id == 0 or steam_id == 0:
		return false

	var mapped_peer_id: int = get_peer_id_for_steam_id(steam_id)
	if mapped_peer_id != 0 and mapped_peer_id != peer_id:
		return false

	var previous_steam_id: int = get_steam_id_for_peer_id(peer_id)
	if previous_steam_id != 0 and previous_steam_id != steam_id:
		peer_id_by_steam_id.erase(previous_steam_id)

	steam_id_by_peer_id[peer_id] = steam_id
	peer_id_by_steam_id[steam_id] = peer_id
	peer_map_updated.emit()
	return true


func remove_peer(peer_id: int) -> int:
	var steam_id: int = get_steam_id_for_peer_id(peer_id)
	if steam_id == 0:
		return 0

	steam_id_by_peer_id.erase(peer_id)
	peer_id_by_steam_id.erase(steam_id)
	peer_map_updated.emit()
	return steam_id


func replace_peer_map(remote_map: Dictionary) -> void:
	steam_id_by_peer_id.clear()
	peer_id_by_steam_id.clear()
	for peer_id_variant: Variant in remote_map.keys():
		var peer_id: int = int(peer_id_variant)
		var steam_id: int = int(remote_map[peer_id_variant])
		if peer_id != 0 and steam_id != 0:
			steam_id_by_peer_id[peer_id] = steam_id
			peer_id_by_steam_id[steam_id] = peer_id
	peer_map_updated.emit()


func get_peer_id_for_steam_id(steam_id: int) -> int:
	return int(peer_id_by_steam_id.get(steam_id, 0))


func get_steam_id_for_peer_id(peer_id: int) -> int:
	return int(steam_id_by_peer_id.get(peer_id, 0))


func has_peer_for_steam_id(steam_id: int) -> bool:
	return peer_id_by_steam_id.has(steam_id)


func has_steam_id_for_peer(peer_id: int) -> bool:
	return steam_id_by_peer_id.has(peer_id)


func get_peer_map() -> Dictionary:
	return steam_id_by_peer_id.duplicate()
