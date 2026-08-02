class_name WorldPlayers
extends Node

signal player_connection_changed(steam_id: int, is_connected: bool)
signal selected_local_character_changed(previous_character: PlayerCharacter, selected_character: PlayerCharacter)

enum ConnectionState {
	CONNECTED,
	DISCONNECTED,
}

const CAMERA_SCENE := preload("res://scenes/camera/camera.tscn")
const PLAYER_SNAPSHOT_RETRY_MSEC := 500
const PLAYER_COMMIT_TIMEOUT_MSEC := 10000
const INVALID_SPAWN_CELL := Vector2i(-1, -1)

@export var spawn_cells: Array[Vector2i] = []
@export var players_root_path: NodePath = ^"../WorldRuntime/Players"

@onready var players_root: Node2D = get_node(players_root_path) as Node2D

var runtime: WorldRuntime = null
var level: WorldLevel = null
var local_camera: GameCamera = null
var received_spawn_snapshot: Dictionary = {}
var are_players_committed: bool = false
var pending_respawn_players: Dictionary[String, PlayerCharacter] = {}
var connection_state_by_steam_id: Dictionary[int, ConnectionState] = {}
var squad_registry: PlayerSquadRegistry = PlayerSquadRegistry.new()
var spawn_coordinator: WorldPlayerSpawnCoordinator = WorldPlayerSpawnCoordinator.new()
var selection_controller: LocalSquadSelectionController = null
var debug_commands: WorldPlayersDebugCommands = WorldPlayersDebugCommands.new()


func _ready() -> void:
	selection_controller = LocalSquadSelectionController.new()
	selection_controller.name = "LocalSquadSelectionController"
	add_child.call_deferred(selection_controller)
	selection_controller.selected_character_changed.connect(_on_selected_character_changed)
	_connect_network_signals()
	_connect_player_channel_signals()
	set_process(true)


func _process(_delta: float) -> void:
	if runtime == null or pending_respawn_players.is_empty() or (GameSession.is_multiplayer() and not GameSession.is_host()):
		return
	for entity_id: String in pending_respawn_players.keys():
		var member: PlayerCharacter = pending_respawn_players.get(entity_id, null) as PlayerCharacter
		if member == null or not is_instance_valid(member):
			pending_respawn_players.erase(entity_id)
			continue
		var target_cell: Vector2i = WorldPlayerSpawnPlanner.find_available_cell(runtime, member.spawn_cell, true, {}, member)
		if target_cell == INVALID_SPAWN_CELL:
			continue
		if member.respawn_at_cell(target_cell):
			pending_respawn_players.erase(entity_id)
			member.can_receive_input = member.is_locally_owned
			member.show()
			_broadcast_player_respawn(member)
			selection_controller.ensure_available_selection()


func _exit_tree() -> void:
	debug_commands.unregister_commands()
	_disconnect_network_signals()
	_disconnect_player_channel_signals()


func configure_context(new_runtime: WorldRuntime, new_level: WorldLevel) -> void:
	runtime = new_runtime
	level = new_level
	debug_commands.configure_context(self, runtime, level)
	_configure_helpers()


func configure(new_spawn_cells: Array[Vector2i]) -> void:
	spawn_cells = new_spawn_cells.duplicate()
	_configure_helpers()


func prepare_players_root() -> void:
	if selection_controller != null:
		selection_controller.clear_selection()
	for child: Node in players_root.get_children():
		child.queue_free()
	if local_camera != null:
		local_camera.queue_free()
	squad_registry.clear()
	connection_state_by_steam_id.clear()
	pending_respawn_players.clear()
	local_camera = null
	runtime.clear_registered_entities()
	_configure_helpers()


func start_singleplayer() -> void:
	var spawn_error: String = spawn_coordinator.spawn_singleplayer()
	if not spawn_error.is_empty():
		ConsoleOutput.print_console("Unable to spawn local squad: %s" % spawn_error, runtime)
		return
	connection_state_by_steam_id[0] = ConnectionState.CONNECTED
	_spawn_camera()
	selection_controller.ensure_available_selection()


func start_multiplayer() -> String:
	var prepare_error: String = await prepare_multiplayer_players()
	if not prepare_error.is_empty():
		return prepare_error
	return await report_world_ready_and_wait_for_commit()


func prepare_multiplayer_players() -> String:
	var session_players: Array[Dictionary] = GameSession.get_players()
	if session_players.is_empty():
		return "invalid_roster"
	connection_state_by_steam_id.clear()
	for player_record: Dictionary in session_players:
		connection_state_by_steam_id[int(player_record.get("steam_id", 0))] = ConnectionState.CONNECTED
	received_spawn_snapshot.clear()
	are_players_committed = false
	if GameSession.is_host():
		var host_error: String = spawn_coordinator.spawn_authoritative(session_players)
		if not host_error.is_empty():
			return host_error
		NetworkManager.players.broadcast_player_spawn_snapshot(spawn_coordinator.authoritative_snapshot)
	else:
		var snapshot_error: String = await _wait_for_spawn_snapshot()
		if not snapshot_error.is_empty():
			return snapshot_error
		if not spawn_coordinator.spawn_from_snapshot(session_players, received_spawn_snapshot):
			return "invalid_spawn_snapshot"
	update_player_authorities()
	_spawn_camera()
	selection_controller.ensure_available_selection()
	return ""


func report_world_ready_and_wait_for_commit() -> String:
	NetworkManager.players.report_player_world_ready(GameSession.get_match_id())
	var deadline_msec: int = Time.get_ticks_msec() + PLAYER_COMMIT_TIMEOUT_MSEC
	while is_inside_tree() and not are_players_committed and Time.get_ticks_msec() < deadline_msec:
		await get_tree().process_frame
	if not are_players_committed:
		return "world_timeout"
	for member: PlayerCharacter in squad_registry.get_local_members():
		member.can_receive_input = true
	selection_controller.ensure_available_selection()
	return ""


func update_player_authorities() -> void:
	for member: PlayerCharacter in squad_registry.get_all_members():
		var peer_id: int = NetworkManager.peers.get_peer_id_for_steam_id(member.steam_id)
		if peer_id != 0:
			member.set_multiplayer_authority(peer_id)


func get_squad_members(player_id: String) -> Array[PlayerCharacter]:
	return squad_registry.get_members_by_player_id(player_id)


func get_squad_members_by_steam_id(steam_id: int) -> Array[PlayerCharacter]:
	return squad_registry.get_members_by_steam_id(steam_id)


func get_local_squad_members() -> Array[PlayerCharacter]:
	return squad_registry.get_local_members()


func get_selected_local_character() -> PlayerCharacter:
	return selection_controller.get_selected_character() if selection_controller != null else null


func get_player_by_entity_id(entity_id: String) -> PlayerCharacter:
	return squad_registry.get_member_by_entity_id(entity_id)


func get_all_characters() -> Array[PlayerCharacter]:
	return squad_registry.get_all_members()


func get_player_id_by_steam_id(steam_id: int) -> String:
	return squad_registry.get_player_id_by_steam_id(steam_id)


func is_character_owned_by_steam_id(steam_id: int, entity_id: String) -> bool:
	return squad_registry.owns_member(steam_id, entity_id)


func request_select_local_character(character: PlayerCharacter) -> bool:
	return selection_controller != null and selection_controller.request_select_character(character)


func get_local_camera_mode() -> String:
	return GameCamera.MODE_FOLLOW if local_camera == null else local_camera.get_camera_mode()


func set_local_camera_mode(camera_mode: String) -> bool:
	if local_camera == null or not local_camera.set_camera_mode(camera_mode):
		return false
	if camera_mode == GameCamera.MODE_FOLLOW and selection_controller != null:
		selection_controller.focus_selected_character()
	return true


func set_local_camera_input_blocked(should_block: bool) -> void:
	if local_camera != null:
		local_camera.set_user_input_blocked(should_block)


func is_player_connected(steam_id: int) -> bool:
	return not GameSession.is_multiplayer() or connection_state_by_steam_id.get(steam_id, ConnectionState.DISCONNECTED) == ConnectionState.CONNECTED


func mark_player_disconnected(steam_id: int, should_broadcast: bool) -> bool:
	if steam_id <= 0 or not connection_state_by_steam_id.has(steam_id):
		return false
	if connection_state_by_steam_id[steam_id] == ConnectionState.DISCONNECTED:
		return false
	connection_state_by_steam_id[steam_id] = ConnectionState.DISCONNECTED
	for member: PlayerCharacter in get_squad_members_by_steam_id(steam_id):
		member.can_receive_input = false
	if should_broadcast and GameSession.is_host():
		NetworkManager.players.broadcast_player_connection_state(GameSession.get_match_id(), steam_id, false)
	player_connection_changed.emit(steam_id, false)
	return true


func get_players_root() -> Node2D:
	return players_root


func request_player_respawn(member: PlayerCharacter) -> bool:
	if member == null or runtime == null:
		return false
	var target_cell: Vector2i = WorldPlayerSpawnPlanner.find_available_cell(runtime, member.spawn_cell, true, {}, member)
	if target_cell == INVALID_SPAWN_CELL:
		runtime.unregister_entity(member)
		member.can_receive_input = false
		member.hide()
		pending_respawn_players[member.entity_id] = member
		if GameSession.is_multiplayer() and GameSession.is_host():
			NetworkManager.players.broadcast_player_respawn_pending(GameSession.get_match_id(), member.entity_id)
		selection_controller.ensure_available_selection()
		return false
	var was_respawned: bool = member.respawn_at_cell(target_cell)
	if was_respawned:
		member.can_receive_input = member.is_locally_owned
		_broadcast_player_respawn(member)
		selection_controller.ensure_available_selection()
	return was_respawned


func execute_character_kill_action(member: PlayerCharacter) -> bool:
	if member == null:
		return false
	member.die()
	runtime.notify_entity_action_finished_in_turn(member)
	return true


func _configure_helpers() -> void:
	if runtime == null or players_root == null:
		return
	spawn_coordinator.configure(runtime, players_root, squad_registry, spawn_cells)
	if selection_controller != null:
		selection_controller.configure(runtime, squad_registry, local_camera)


func _spawn_camera() -> void:
	if level == null or get_local_squad_members().is_empty():
		return
	local_camera = CAMERA_SCENE.instantiate() as GameCamera
	if local_camera == null:
		return
	local_camera.allows_console_commands = debug_commands.allows_commands()
	players_root.add_child.call_deferred(local_camera)
	call_deferred("_configure_camera")


func _configure_camera() -> void:
	if local_camera == null or not is_instance_valid(local_camera):
		return
	if not local_camera.is_inside_tree():
		call_deferred("_configure_camera")
		return
	local_camera.configure_world_bounds(runtime.get_grid_world_bounds())
	local_camera.make_current()
	selection_controller.set_camera(local_camera)


func _broadcast_player_respawn(member: PlayerCharacter) -> void:
	if GameSession.is_multiplayer() and GameSession.is_host():
		NetworkManager.entity.broadcast_entity_respawn(member.entity_id, member.current_cell, member.health, runtime.get_current_action_sequence_id())


func _wait_for_spawn_snapshot() -> String:
	var deadline_msec: int = Time.get_ticks_msec() + PLAYER_COMMIT_TIMEOUT_MSEC
	var next_request_msec: int = 0
	while is_inside_tree() and received_spawn_snapshot.is_empty() and Time.get_ticks_msec() < deadline_msec:
		if Time.get_ticks_msec() >= next_request_msec:
			NetworkManager.players.request_player_spawn_snapshot()
			next_request_msec = Time.get_ticks_msec() + PLAYER_SNAPSHOT_RETRY_MSEC
		await get_tree().process_frame
	return "" if not received_spawn_snapshot.is_empty() else "spawn_snapshot_timeout"


func _connect_network_signals() -> void:
	if not NetworkManager.connection.steam_peer_disconnected.is_connected(_on_steam_peer_disconnected):
		NetworkManager.connection.steam_peer_disconnected.connect(_on_steam_peer_disconnected)


func _disconnect_network_signals() -> void:
	if NetworkManager.connection.steam_peer_disconnected.is_connected(_on_steam_peer_disconnected):
		NetworkManager.connection.steam_peer_disconnected.disconnect(_on_steam_peer_disconnected)


func _connect_player_channel_signals() -> void:
	if not NetworkManager.character.character_kill_requested.is_connected(_on_character_kill_requested):
		NetworkManager.character.character_kill_requested.connect(_on_character_kill_requested)
	if not NetworkManager.players.player_spawn_snapshot_requested.is_connected(_on_player_spawn_snapshot_requested):
		NetworkManager.players.player_spawn_snapshot_requested.connect(_on_player_spawn_snapshot_requested)
	if not NetworkManager.players.player_spawn_snapshot_received.is_connected(_on_player_spawn_snapshot_received):
		NetworkManager.players.player_spawn_snapshot_received.connect(_on_player_spawn_snapshot_received)
	if not NetworkManager.players.players_committed_received.is_connected(_on_players_committed_received):
		NetworkManager.players.players_committed_received.connect(_on_players_committed_received)
	if not NetworkManager.players.player_respawn_pending_received.is_connected(_on_player_respawn_pending_received):
		NetworkManager.players.player_respawn_pending_received.connect(_on_player_respawn_pending_received)
	if not NetworkManager.players.player_connection_state_received.is_connected(_on_player_connection_state_received):
		NetworkManager.players.player_connection_state_received.connect(_on_player_connection_state_received)


func _disconnect_player_channel_signals() -> void:
	if NetworkManager.character.character_kill_requested.is_connected(_on_character_kill_requested):
		NetworkManager.character.character_kill_requested.disconnect(_on_character_kill_requested)
	if NetworkManager.players.player_spawn_snapshot_requested.is_connected(_on_player_spawn_snapshot_requested):
		NetworkManager.players.player_spawn_snapshot_requested.disconnect(_on_player_spawn_snapshot_requested)
	if NetworkManager.players.player_spawn_snapshot_received.is_connected(_on_player_spawn_snapshot_received):
		NetworkManager.players.player_spawn_snapshot_received.disconnect(_on_player_spawn_snapshot_received)
	if NetworkManager.players.players_committed_received.is_connected(_on_players_committed_received):
		NetworkManager.players.players_committed_received.disconnect(_on_players_committed_received)
	if NetworkManager.players.player_respawn_pending_received.is_connected(_on_player_respawn_pending_received):
		NetworkManager.players.player_respawn_pending_received.disconnect(_on_player_respawn_pending_received)
	if NetworkManager.players.player_connection_state_received.is_connected(_on_player_connection_state_received):
		NetworkManager.players.player_connection_state_received.disconnect(_on_player_connection_state_received)


func _on_player_spawn_snapshot_requested(requester_peer_id: int) -> void:
	if GameSession.is_host() and not spawn_coordinator.authoritative_snapshot.is_empty():
		NetworkManager.players.send_player_spawn_snapshot(requester_peer_id, spawn_coordinator.authoritative_snapshot)


func _on_player_spawn_snapshot_received(snapshot: Dictionary) -> void:
	if not GameSession.is_host() and str(snapshot.get("match_id", "")) == GameSession.get_match_id():
		received_spawn_snapshot = snapshot.duplicate(true)


func _on_players_committed_received(match_id: String) -> void:
	if match_id == GameSession.get_match_id():
		are_players_committed = true


func _on_player_respawn_pending_received(match_id: String, entity_id: String) -> void:
	if GameSession.is_host() or match_id != GameSession.get_match_id():
		return
	var member: PlayerCharacter = get_player_by_entity_id(entity_id)
	if member == null:
		return
	runtime.unregister_entity(member)
	member.set_health(0)
	member.can_receive_input = false
	member.hide()
	selection_controller.ensure_available_selection()


func _on_steam_peer_disconnected(steam_id: int) -> void:
	if GameSession.is_host():
		mark_player_disconnected(steam_id, true)


func _on_player_connection_state_received(match_id: String, steam_id: int, is_connected: bool) -> void:
	if not GameSession.is_host() and match_id == GameSession.get_match_id() and not is_connected:
		mark_player_disconnected(steam_id, false)


func _on_selected_character_changed(previous_character: PlayerCharacter, selected_character: PlayerCharacter) -> void:
	selected_local_character_changed.emit(previous_character, selected_character)


func _on_character_kill_requested(
	actor_entity_id: String,
	match_id: String,
	requested_turn_revision: int,
	request_id: int,
	requester_peer_id: int
) -> void:
	if not GameSession.is_host() or level == null or not level.allows_debug_commands():
		return
	var requester_steam_id: int = NetworkManager.peers.get_steam_id_for_peer_id(requester_peer_id)
	if requester_steam_id <= 0 or not is_character_owned_by_steam_id(requester_steam_id, actor_entity_id):
		return
	var member: PlayerCharacter = get_player_by_entity_id(actor_entity_id)
	if member != null:
		runtime.enqueue_player_action(
			WorldActionRecord.ActionType.CHARACTER_KILL,
			member,
			{},
			request_id,
			requester_peer_id,
			requested_turn_revision,
			match_id
		)
