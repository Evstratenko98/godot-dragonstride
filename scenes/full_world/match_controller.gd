class_name MatchController
extends Node

const MAIN_MENU_SCENE_PATH := "res://scenes/menu/main_menu/main_menu.tscn"

var level: WorldLevel = null
var runtime: WorldRuntime = null
var is_ending_game: bool = false
var has_started_match: bool = false


func _ready() -> void:
	level = get_parent() as WorldLevel
	if level != null:
		runtime = level.get_runtime()

	if runtime != null:
		runtime.configure_for_level(level)

	if not GameSession.has_active_session():
		GameSession.start_singleplayer()

	if runtime != null:
		runtime.connect_signals()
		call_deferred("_start_match_deferred")


func _exit_tree() -> void:
	if runtime != null:
		runtime.disconnect_signals()


func start_match() -> void:
	if has_started_match or runtime == null:
		return

	has_started_match = true
	runtime.start_game()
	_play_level_music()


func _start_match_deferred() -> void:
	if not is_inside_tree():
		return

	start_match()


func game_over(should_broadcast: bool = true) -> void:
	if is_ending_game:
		return

	if should_broadcast and GameSession.is_multiplayer():
		NetworkManager.request_end_game()
		return

	is_ending_game = true
	_stop_level_music()
	_play_level_death_sound()
	_leave_active_multiplayer_session()
	GameSession.clear()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _play_level_music() -> void:
	if level == null:
		return

	var music: AudioStreamPlayer = level.get_music_player()
	if music != null and music.stream != null:
		music.play()


func _stop_level_music() -> void:
	if level == null:
		return

	var music: AudioStreamPlayer = level.get_music_player()
	if music != null:
		music.stop()


func _play_level_death_sound() -> void:
	if level == null:
		return

	var death_sound: AudioStreamPlayer = level.get_death_sound_player()
	if death_sound != null and death_sound.stream != null:
		death_sound.play()


func _leave_active_multiplayer_session() -> void:
	if SteamManager.get_current_lobby_id() != 0:
		SteamManager.leave_lobby()
		return

	NetworkManager.stop_network()
