extends Node

signal session_started(mode: String)
signal session_cleared()

const MODE_NONE := "none"
const MODE_SINGLEPLAYER := "singleplayer"
const MODE_MULTIPLAYER_HOST := "multiplayer_host"
const MODE_MULTIPLAYER_CLIENT := "multiplayer_client"

const GAME_SCENE_PATH := "res://scenes/full_world/full_world.tscn"

var mode: String = MODE_NONE
var selected_scene_path: String = GAME_SCENE_PATH
var lobby_id: int = 0
var host_steam_id: int = 0
var local_steam_id: int = 0
var players: Array[Dictionary] = []
var match_settings: Dictionary = {}


func start_singleplayer(settings: Dictionary = {}) -> void:
	clear()

	mode = MODE_SINGLEPLAYER
	selected_scene_path = GAME_SCENE_PATH
	match_settings = settings.duplicate(true)
	players = [_make_player_info(0, "Player", true, true)]

	session_started.emit(mode)


func start_multiplayer_from_lobby(settings: Dictionary = {}) -> void:
	clear()

	mode = _get_multiplayer_mode_from_lobby()
	selected_scene_path = GAME_SCENE_PATH
	lobby_id = SteamManager.get_current_lobby_id()
	host_steam_id = SteamManager.get_lobby_owner_id()
	local_steam_id = _get_local_steam_id()
	match_settings = settings.duplicate(true)
	players = _build_players_from_lobby()

	session_started.emit(mode)


func clear() -> void:
	mode = MODE_NONE
	selected_scene_path = GAME_SCENE_PATH
	lobby_id = 0
	host_steam_id = 0
	local_steam_id = 0
	players.clear()
	match_settings.clear()

	session_cleared.emit()


func is_singleplayer() -> bool:
	return mode == MODE_SINGLEPLAYER


func is_multiplayer() -> bool:
	return mode == MODE_MULTIPLAYER_HOST or mode == MODE_MULTIPLAYER_CLIENT


func is_host() -> bool:
	if is_singleplayer():
		return true

	return mode == MODE_MULTIPLAYER_HOST


func has_active_session() -> bool:
	return mode != MODE_NONE


func get_players() -> Array[Dictionary]:
	return players.duplicate(true)


func get_local_player() -> Dictionary:
	for player in players:
		if bool(player.get("is_local", false)):
			return player.duplicate(true)

	return {}


func get_player_by_steam_id(steam_id: int) -> Dictionary:
	for player in players:
		if int(player.get("steam_id", 0)) == steam_id:
			return player.duplicate(true)

	return {}


func get_match_setting(key: String, default_value: Variant = null) -> Variant:
	return match_settings.get(key, default_value)


func set_match_setting(key: String, value: Variant) -> void:
	match_settings[key] = value


func go_to_selected_scene() -> void:
	get_tree().change_scene_to_file(selected_scene_path)


func _get_multiplayer_mode_from_lobby() -> String:
	if SteamManager.is_lobby_owner():
		return MODE_MULTIPLAYER_HOST

	return MODE_MULTIPLAYER_CLIENT


func _build_players_from_lobby() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var members := SteamManager.get_current_lobby_members()

	for member in members:
		var steam_id := int(member.get("id", 0))
		var player_name := str(member.get("name", "Player"))
		var is_host_player := bool(member.get("is_owner", false))
		var is_local_player := bool(member.get("is_me", false))

		result.append(_make_player_info(
			steam_id,
			player_name,
			is_host_player,
			is_local_player
		))

	if result.is_empty():
		result.append(_make_player_info(local_steam_id, "Player", is_host(), true))

	return result


func _make_player_info(
	steam_id: int,
	player_name: String,
	is_host_player: bool,
	is_local_player: bool
) -> Dictionary:
	return {
		"steam_id": steam_id,
		"name": player_name,
		"is_host": is_host_player,
		"is_local": is_local_player
	}


func _get_local_steam_id() -> int:
	if not SteamManager.is_steam_initialized:
		return 0

	return Steam.getSteamID()
