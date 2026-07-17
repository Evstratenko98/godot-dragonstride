extends Node

signal session_started(mode: String)
signal session_cleared()
signal session_committed(match_id: String)

const MODE_NONE := "none"
const MODE_SINGLEPLAYER := "singleplayer"
const MODE_MULTIPLAYER_HOST := "multiplayer_host"
const MODE_MULTIPLAYER_CLIENT := "multiplayer_client"
const MATCH_SCENE_PATH := "res://scenes/world/match_world.tscn"
const ROSTER_REVISION := 1

var mode: String = MODE_NONE
var selected_level_id: String = LevelCatalog.DEFAULT_LEVEL_ID
var lobby_id: int = 0
var host_steam_id: int = 0
var local_steam_id: int = 0
var match_id: String = ""
var roster_revision: int = 0
var players: Array[Dictionary] = []
var match_settings: Dictionary = {}
var is_committed: bool = false


func start_singleplayer(settings: Dictionary = {}) -> void:
	clear()
	mode = MODE_SINGLEPLAYER
	match_settings = settings.duplicate(true)
	_select_level_from_settings()
	players = [_make_player_info(0, "Player", true, true, "player_1", 0)]
	is_committed = true
	session_started.emit(mode)


func prepare_host_match(new_match_id: String, level_id: String) -> bool:
	if not SteamManager.is_lobby_owner() or new_match_id.is_empty() or not LevelCatalog.has_level(level_id):
		return false
	var roster: Array[Dictionary] = _build_frozen_roster(SteamManager.get_current_lobby_members())
	if not _is_valid_roster(roster, SteamManager.get_lobby_owner_id()):
		return false
	return _prepare_multiplayer_state(new_match_id, level_id, roster)


func prepare_remote_match(payload: Dictionary) -> bool:
	if int(payload.get("protocol_version", 0)) != NetworkProtocol.PROTOCOL_VERSION:
		return false
	var new_match_id: String = str(payload.get("match_id", ""))
	var level_id: String = str(payload.get("level_id", ""))
	var payload_revision: int = int(payload.get("roster_revision", 0))
	var roster_value: Variant = payload.get("players", [])
	if (
		new_match_id.is_empty()
		or not LevelCatalog.has_level(level_id)
		or payload_revision != ROSTER_REVISION
		or not (roster_value is Array)
	):
		return false

	var roster: Array[Dictionary] = []
	for record_value: Variant in roster_value as Array:
		if not (record_value is Dictionary):
			return false
		var record: Dictionary = (record_value as Dictionary).duplicate(true)
		var record_steam_id: int = int(str(record.get("steam_id", "0")))
		record["steam_id"] = record_steam_id
		record["is_local"] = record_steam_id == _get_local_steam_id()
		roster.append(record)
	if not _is_valid_roster(roster, SteamManager.get_lobby_owner_id()):
		return false
	if not _contains_steam_id(roster, _get_local_steam_id()):
		return false
	return _prepare_multiplayer_state(new_match_id, level_id, roster)


func create_match_prepare_payload() -> Dictionary:
	return {
		"protocol_version": NetworkProtocol.PROTOCOL_VERSION,
		"match_id": match_id,
		"level_id": selected_level_id,
		"roster_revision": roster_revision,
		"roster_hash": get_roster_hash(),
		"players": _create_network_roster(),
	}


func commit_multiplayer_match() -> bool:
	if not is_multiplayer() or match_id.is_empty() or players.is_empty():
		return false
	is_committed = true
	session_committed.emit(match_id)
	return true


func clear() -> void:
	mode = MODE_NONE
	selected_level_id = LevelCatalog.DEFAULT_LEVEL_ID
	lobby_id = 0
	host_steam_id = 0
	local_steam_id = 0
	match_id = ""
	roster_revision = 0
	players.clear()
	match_settings.clear()
	is_committed = false
	session_cleared.emit()


func is_singleplayer() -> bool:
	return mode == MODE_SINGLEPLAYER


func is_multiplayer() -> bool:
	return mode == MODE_MULTIPLAYER_HOST or mode == MODE_MULTIPLAYER_CLIENT


func is_host() -> bool:
	return is_singleplayer() or mode == MODE_MULTIPLAYER_HOST


func has_active_session() -> bool:
	return mode != MODE_NONE


func has_committed_match() -> bool:
	return is_committed


func get_match_id() -> String:
	return match_id


func get_roster_hash() -> String:
	var canonical_parts: PackedStringArray = PackedStringArray()
	for player: Dictionary in players:
		canonical_parts.append("%d|%s|%d|%d" % [
			int(player.get("steam_id", 0)),
			str(player.get("entity_id", "")),
			int(bool(player.get("is_host", false))),
			int(player.get("color_index", 0)),
		])
	return "\n".join(canonical_parts).sha256_text()


func get_players() -> Array[Dictionary]:
	return players.duplicate(true)


func get_local_player() -> Dictionary:
	for player: Dictionary in players:
		if bool(player.get("is_local", false)):
			return player.duplicate(true)
	return {}


func get_player_by_steam_id(steam_id: int) -> Dictionary:
	for player: Dictionary in players:
		if int(player.get("steam_id", 0)) == steam_id:
			return player.duplicate(true)
	return {}


func get_match_setting(key: String, default_value: Variant = null) -> Variant:
	return match_settings.get(key, default_value)


func set_match_setting(key: String, value: Variant) -> void:
	match_settings[key] = value


func set_selected_level(level_id: String, should_sync_lobby: bool = true) -> bool:
	if not LevelCatalog.has_level(level_id):
		return false
	if is_multiplayer() and should_sync_lobby:
		if not is_host() or not SteamManager.set_lobby_level_id(level_id):
			return false
	selected_level_id = level_id
	match_settings["level_id"] = level_id
	return true


func get_selected_level_scene() -> PackedScene:
	return LevelCatalog.get_level_scene(selected_level_id)


func get_available_level_ids() -> PackedStringArray:
	return LevelCatalog.get_level_ids()


func go_to_selected_scene() -> void:
	get_tree().change_scene_to_file(MATCH_SCENE_PATH)


func _prepare_multiplayer_state(new_match_id: String, level_id: String, roster: Array[Dictionary]) -> bool:
	clear()
	local_steam_id = _get_local_steam_id()
	host_steam_id = SteamManager.get_lobby_owner_id()
	if local_steam_id == 0 or host_steam_id == 0:
		return false
	mode = MODE_MULTIPLAYER_HOST if local_steam_id == host_steam_id else MODE_MULTIPLAYER_CLIENT
	lobby_id = SteamManager.get_current_lobby_id()
	match_id = new_match_id
	roster_revision = ROSTER_REVISION
	players = roster.duplicate(true)
	selected_level_id = level_id
	match_settings = {"level_id": level_id}
	is_committed = false
	session_started.emit(mode)
	return true


func _build_frozen_roster(members: Array) -> Array[Dictionary]:
	var sorted_members: Array[Dictionary] = []
	for member_value: Variant in members:
		if member_value is Dictionary:
			sorted_members.append((member_value as Dictionary).duplicate(true))
	sorted_members.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return int(first.get("id", 0)) < int(second.get("id", 0))
	)

	var result: Array[Dictionary] = []
	for index: int in range(sorted_members.size()):
		var member: Dictionary = sorted_members[index]
		result.append(_make_player_info(
			int(member.get("id", 0)),
			str(member.get("name", "Player")),
			bool(member.get("is_owner", false)),
			bool(member.get("is_me", false)),
			"player_%d" % [index + 1],
			index
		))
	return result


func _create_network_roster() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for player: Dictionary in players:
		result.append({
			# Steam IDs exceed JSON's exact numeric range, so lobby chat carries them as strings.
			"steam_id": str(int(player.get("steam_id", 0))),
			"name": str(player.get("name", "Player")),
			"is_host": bool(player.get("is_host", false)),
			"entity_id": str(player.get("entity_id", "")),
			"color_index": int(player.get("color_index", 0)),
		})
	return result


func _is_valid_roster(roster: Array[Dictionary], expected_host_steam_id: int) -> bool:
	if roster.is_empty() or roster.size() > NetworkProtocol.MAX_ROSTER_SIZE or expected_host_steam_id == 0:
		return false
	var seen_steam_ids: Dictionary[int, bool] = {}
	var seen_entity_ids: Dictionary[String, bool] = {}
	var host_count: int = 0
	var previous_steam_id: int = 0
	for index: int in range(roster.size()):
		var record: Dictionary = roster[index]
		var steam_id: int = int(record.get("steam_id", 0))
		var entity_id: String = str(record.get("entity_id", ""))
		if (
			steam_id == 0
			or steam_id <= previous_steam_id
			or entity_id != "player_%d" % [index + 1]
			or int(record.get("color_index", -1)) != index
			or seen_steam_ids.has(steam_id)
			or seen_entity_ids.has(entity_id)
			or not NetworkProtocol.is_valid_identifier(entity_id)
			or str(record.get("name", "")).length() > NetworkProtocol.MAX_IDENTIFIER_LENGTH
		):
			return false
		previous_steam_id = steam_id
		seen_steam_ids[steam_id] = true
		seen_entity_ids[entity_id] = true
		if bool(record.get("is_host", false)):
			host_count += 1
			if steam_id != expected_host_steam_id:
				return false
	return host_count == 1


func _contains_steam_id(roster: Array[Dictionary], steam_id: int) -> bool:
	for record: Dictionary in roster:
		if int(record.get("steam_id", 0)) == steam_id:
			return true
	return false


func _make_player_info(
	steam_id: int,
	player_name: String,
	is_host_player: bool,
	is_local_player: bool,
	entity_id: String,
	color_index: int
) -> Dictionary:
	return {
		"steam_id": steam_id,
		"name": player_name.left(64),
		"is_host": is_host_player,
		"is_local": is_local_player,
		"entity_id": entity_id,
		"color_index": color_index,
	}


func _select_level_from_settings() -> void:
	var fallback_level_id: String = LevelCatalog.DEFAULT_LEVEL_ID
	var requested_level_id: String = str(match_settings.get("level_id", fallback_level_id))
	if not set_selected_level(requested_level_id, false):
		selected_level_id = LevelCatalog.DEFAULT_LEVEL_ID


func _get_local_steam_id() -> int:
	if not SteamManager.is_steam_initialized:
		return 0
	return int(Steam.getSteamID())
