class_name MatchController
extends Node

const MAIN_MENU_SCENE_PATH := "res://scenes/menu/main_menu/main_menu.tscn"
const GAME_HUD_SCRIPT := preload("res://scenes/hud/hud.gd")

@export var runtime_path: NodePath = ^"../WorldRuntime"
@export var level_container_path: NodePath = ^"../LevelContainer"
@export var grid_lines_path: NodePath = ^"../GridLines"
@export var movement_range_overlay_path: NodePath = ^"../MovementRangeOverlay"
@export var cell_hover_path: NodePath = ^"../CellHover"
@export var hud_path: NodePath = ^"../HUD"
@export var music_player_path: NodePath = ^"../Music"
@export var death_sound_player_path: NodePath = ^"../DeathSound"

@onready var runtime: WorldRuntime = get_node(runtime_path) as WorldRuntime
@onready var level_container: Node2D = get_node(level_container_path) as Node2D
@onready var grid_lines: GridLines = get_node(grid_lines_path) as GridLines
@onready var movement_range_overlay: MovementRangeOverlay = get_node(movement_range_overlay_path) as MovementRangeOverlay
@onready var cell_hover: CellHover = get_node(cell_hover_path) as CellHover
@onready var hud: GAME_HUD_SCRIPT = get_node(hud_path) as GAME_HUD_SCRIPT
@onready var music_player: AudioStreamPlayer = get_node(music_player_path) as AudioStreamPlayer
@onready var death_sound_player: AudioStreamPlayer = get_node(death_sound_player_path) as AudioStreamPlayer

var level: WorldLevel = null
var is_ending_game: bool = false
var has_started_match: bool = false


func _ready() -> void:
	if not GameSession.has_active_session():
		GameSession.start_singleplayer()

	call_deferred("_initialize_match")


func _exit_tree() -> void:
	if runtime != null:
		if runtime.match_end_requested.is_connected(_on_runtime_match_end_requested):
			runtime.match_end_requested.disconnect(_on_runtime_match_end_requested)
		if runtime.runtime_sync_failed.is_connected(_on_runtime_sync_failed):
			runtime.runtime_sync_failed.disconnect(_on_runtime_sync_failed)
		runtime.disconnect_signals()


func start_match() -> void:
	if has_started_match or runtime == null or level == null:
		return

	has_started_match = true
	var start_error: String = await runtime.start_game()
	if not start_error.is_empty():
		has_started_match = false
		if GameSession.is_multiplayer():
			LobbyMatchCoordinator.cancel_runtime_start(start_error)
		return
	hud.bind_session()
	if level.has_welcome_modal():
		hud.show_level_welcome(level.get_welcome_modal_title(), level.get_welcome_modal_text())
	_play_level_music()


func game_over(should_broadcast: bool = true) -> void:
	if is_ending_game:
		return

	if should_broadcast and GameSession.is_multiplayer():
		NetworkManager.match_channel.request_end_game()
		return

	is_ending_game = true
	_stop_level_music()
	_play_level_death_sound()
	_leave_active_multiplayer_session()
	GameSession.clear()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _initialize_match() -> void:
	if not is_inside_tree():
		return

	var level_scene: PackedScene = GameSession.get_selected_level_scene()
	if level_scene == null:
		push_error("Selected level scene is not available: " + GameSession.selected_level_id)
		return

	var loaded_level: WorldLevel = level_scene.instantiate() as WorldLevel
	if loaded_level == null:
		push_error("Selected scene root must inherit WorldLevel: " + GameSession.selected_level_id)
		return

	level = loaded_level
	runtime.configure_for_level(level)
	if not runtime.match_end_requested.is_connected(_on_runtime_match_end_requested):
		runtime.match_end_requested.connect(_on_runtime_match_end_requested)
	if not runtime.runtime_sync_failed.is_connected(_on_runtime_sync_failed):
		runtime.runtime_sync_failed.connect(_on_runtime_sync_failed)
	level_container.add_child(level)
	grid_lines.configure_context(runtime, level)
	cell_hover.configure_context(runtime)
	movement_range_overlay.configure_context(runtime, cell_hover)
	hud.configure_runtime(runtime)
	_configure_level_audio()
	runtime.connect_signals()
	call_deferred("_start_match_deferred")


func _start_match_deferred() -> void:
	if not is_inside_tree():
		return

	start_match()


func _configure_level_audio() -> void:
	music_player.stream = level.get_music_stream()
	death_sound_player.stream = level.get_death_sound_stream()


func _play_level_music() -> void:
	if music_player.stream != null:
		music_player.play()


func _stop_level_music() -> void:
	music_player.stop()


func _play_level_death_sound() -> void:
	if death_sound_player.stream != null:
		death_sound_player.play()


func _leave_active_multiplayer_session() -> void:
	if SteamManager.get_current_lobby_id() != 0:
		SteamManager.leave_lobby()
		return

	NetworkManager.connection.stop_network()


func _on_runtime_match_end_requested() -> void:
	game_over(false)


func _on_runtime_sync_failed(reason_code: String) -> void:
	LobbyMatchCoordinator.handle_runtime_sync_failure(reason_code)
