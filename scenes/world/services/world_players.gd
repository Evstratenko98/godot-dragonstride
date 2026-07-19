class_name WorldPlayers
extends Node

signal player_connection_changed(steam_id: int, is_connected: bool)

enum ConnectionState {
	CONNECTED,
	DISCONNECTED,
}

const CHARACTER_SCENE := preload("res://scenes/entities/character/character.tscn")
const CAMERA_SCENE := preload("res://scenes/camera/camera.tscn")
const KILL_COMMAND_NAME := "game_character_kill"
const INVENTORY_ADD_COMMAND_NAME := "game_inventory_add"
const SINGLEPLAYER_WARRIOR_COLOR := "Purple"
const MULTIPLAYER_WARRIOR_COLORS := ["Blue", "Purple", "Red", "Yellow"]
const PLAYER_SNAPSHOT_RETRY_MSEC := 500
const PLAYER_COMMIT_TIMEOUT_MSEC := 10000
const INVALID_SPAWN_CELL := Vector2i(-1, -1)

@export var spawn_cells: Array[Vector2i] = [
	Vector2i(8, 0),
	Vector2i(10, 0),
	Vector2i(8, 2),
	Vector2i(10, 2),
]
@export var players_root_path: NodePath = ^"../WorldRuntime/Players"

@onready var players_root: Node2D = get_node(players_root_path) as Node2D

var runtime: WorldRuntime = null
var level: WorldLevel = null
var players_by_steam_id: Dictionary = {}
var local_player: PlayerCharacter = null
var local_camera: GameCamera = null
var authoritative_spawn_snapshot: Dictionary = {}
var received_spawn_snapshot: Dictionary = {}
var are_players_committed: bool = false
var pending_respawn_players: Dictionary[String, PlayerCharacter] = {}
var connection_state_by_steam_id: Dictionary[int, ConnectionState] = {}


func _ready() -> void:
	_connect_network_signals()
	_connect_player_channel_signals()
	set_process(true)


func _process(_delta: float) -> void:
	if runtime == null or pending_respawn_players.is_empty() or (GameSession.is_multiplayer() and not GameSession.is_host()):
		return
	for entity_id: String in pending_respawn_players.keys():
		var player: PlayerCharacter = pending_respawn_players.get(entity_id, null) as PlayerCharacter
		if player == null or not is_instance_valid(player):
			pending_respawn_players.erase(entity_id)
			continue
		var target_cell: Vector2i = _find_available_spawn_cell(player.spawn_cell, true, {}, player)
		if target_cell == INVALID_SPAWN_CELL:
			continue
		if player.respawn_at_cell(target_cell):
			pending_respawn_players.erase(entity_id)
			player.can_receive_input = player.is_local_player
			_broadcast_player_respawn(player)


func _exit_tree() -> void:
	_unregister_console_commands()
	_disconnect_network_signals()
	_disconnect_player_channel_signals()


func configure_context(new_runtime: WorldRuntime, new_level: WorldLevel) -> void:
	runtime = new_runtime
	level = new_level
	if _can_use_debug_commands():
		_register_console_commands()


func configure(new_spawn_cells: Array[Vector2i]) -> void:
	spawn_cells = new_spawn_cells


func prepare_players_root() -> void:
	for child in players_root.get_children():
		child.queue_free()

	if local_camera != null:
		local_camera.queue_free()

	players_by_steam_id.clear()
	connection_state_by_steam_id.clear()
	pending_respawn_players.clear()
	local_player = null
	local_camera = null
	runtime.clear_registered_entities()


func start_singleplayer() -> void:
	_spawn_player({
		"steam_id": 0,
		"name": "Player",
		"is_host": true,
		"is_local": true,
	}, _get_spawn_cell(0), SINGLEPLAYER_WARRIOR_COLOR, "patrick")
	connection_state_by_steam_id[0] = ConnectionState.CONNECTED


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

	authoritative_spawn_snapshot.clear()
	received_spawn_snapshot.clear()
	are_players_committed = false
	if GameSession.is_host():
		var host_error: String = _spawn_authoritative_players(session_players)
		if not host_error.is_empty():
			return host_error
		NetworkManager.players.broadcast_player_spawn_snapshot(authoritative_spawn_snapshot)
	else:
		var snapshot_error: String = await _wait_for_spawn_snapshot()
		if not snapshot_error.is_empty():
			return snapshot_error
		if not _spawn_players_from_snapshot(session_players, received_spawn_snapshot):
			return "invalid_spawn_snapshot"

	update_player_authorities()
	return ""


func report_world_ready_and_wait_for_commit() -> String:
	NetworkManager.players.report_player_world_ready(GameSession.get_match_id())
	var deadline_msec: int = Time.get_ticks_msec() + PLAYER_COMMIT_TIMEOUT_MSEC
	while is_inside_tree() and not are_players_committed and Time.get_ticks_msec() < deadline_msec:
		await get_tree().process_frame
	if not are_players_committed:
		return "world_timeout"
	if local_player != null:
		local_player.can_receive_input = true
	return ""


func update_player_authorities() -> void:
	for steam_id in players_by_steam_id.keys():
		var peer_id: int = NetworkManager.peers.get_peer_id_for_steam_id(int(steam_id))

		if peer_id == 0:
			continue

		var player: Node = players_by_steam_id[steam_id]
		player.set_multiplayer_authority(peer_id)


func get_player_by_steam_id(steam_id: int) -> PlayerCharacter:
	return players_by_steam_id.get(steam_id, null) as PlayerCharacter


func is_player_connected(steam_id: int) -> bool:
	if not GameSession.is_multiplayer():
		return true
	return connection_state_by_steam_id.get(steam_id, ConnectionState.DISCONNECTED) == ConnectionState.CONNECTED


func mark_player_disconnected(steam_id: int, should_broadcast: bool) -> bool:
	if steam_id <= 0 or not connection_state_by_steam_id.has(steam_id):
		return false
	if connection_state_by_steam_id[steam_id] == ConnectionState.DISCONNECTED:
		return false
	connection_state_by_steam_id[steam_id] = ConnectionState.DISCONNECTED
	var player: PlayerCharacter = get_player_by_steam_id(steam_id)
	if player != null:
		player.can_receive_input = false
	if should_broadcast and GameSession.is_host():
		NetworkManager.players.broadcast_player_connection_state(
			GameSession.get_match_id(),
			steam_id,
			false
		)
	player_connection_changed.emit(steam_id, false)
	return true


func get_local_player() -> PlayerCharacter:
	return local_player


func get_player_by_entity_id(entity_id: String) -> PlayerCharacter:
	if entity_id.is_empty():
		return null
	for player_value: Variant in players_by_steam_id.values():
		var player: PlayerCharacter = player_value as PlayerCharacter
		if player != null and player.entity_id == entity_id:
			return player
	if local_player != null and local_player.entity_id == entity_id:
		return local_player
	return null


func get_players_root() -> Node2D:
	return players_root


func request_player_respawn(player: PlayerCharacter) -> bool:
	if player == null or runtime == null:
		return false
	var target_cell: Vector2i = _find_available_spawn_cell(player.spawn_cell, true, {}, player)
	if target_cell == INVALID_SPAWN_CELL:
		runtime.unregister_entity(player)
		player.can_receive_input = false
		player.hide()
		pending_respawn_players[player.entity_id] = player
		if GameSession.is_multiplayer() and GameSession.is_host():
			NetworkManager.players.broadcast_player_respawn_pending(
				GameSession.get_match_id(),
				player.entity_id
			)
		return false
	var was_respawned: bool = player.respawn_at_cell(target_cell)
	if was_respawned:
		player.can_receive_input = player.is_local_player
		_broadcast_player_respawn(player)
	return was_respawned


func console_kill_character() -> void:
	if not _can_use_debug_commands():
		ConsoleOutput.print_console("ERROR: Debug mutations are unavailable for this level.", runtime)
		return
	if local_player == null:
		ConsoleOutput.print_console("ERROR: Local character is not ready.", runtime)
		return
	if GameSession.is_multiplayer() and not NetworkManager.connection.is_ready():
		ConsoleOutput.print_console("ERROR: Cannot kill character: network is not ready.", runtime)
		return

	var request_id: int = runtime.create_action_request_id()
	if GameSession.is_multiplayer() and not GameSession.is_host():
		NetworkManager.character.request_character_kill(GameSession.get_match_id(), runtime.get_turn_revision(), request_id)
		return
	runtime.enqueue_player_action(
		WorldActionRecord.ActionType.CHARACTER_KILL,
		local_player,
		{},
		request_id,
		0
	)


func execute_character_kill_action(player: PlayerCharacter) -> bool:
	if player == null:
		return false
	_kill_and_respawn_player(player)
	return true


func console_inventory_add(item_id: String, amount_text: String) -> void:
	if not _can_use_debug_commands():
		ConsoleOutput.print_console("ERROR: Debug mutations are unavailable for this level.", runtime)
		return
	if local_player == null:
		ConsoleOutput.print_console("ERROR: Local character is not ready.", runtime)
		return
	if not local_player.character_inventory.has_item_id(item_id):
		ConsoleOutput.print_console("ERROR: Unknown inventory item: %s." % item_id, runtime)
		return
	if (
		not amount_text.is_valid_int()
		or amount_text.to_int() <= 0
		or amount_text.to_int() > CharacterInventory.ITEM_SLOT_COUNT * CharacterInventory.DEFAULT_MAX_STACK_SIZE
	):
		ConsoleOutput.print_console(
			"ERROR: Usage: %s <item_id> <positive_amount>." % INVENTORY_ADD_COMMAND_NAME,
			runtime
		)
		return
	if GameSession.is_multiplayer() and not NetworkManager.connection.is_ready():
		ConsoleOutput.print_console("ERROR: Cannot add inventory item: network is not ready.", runtime)
		return

	var amount: int = amount_text.to_int()
	runtime.request_inventory_add(item_id, amount)
	ConsoleOutput.print_console("Requested %d %s inventory item(s)." % [amount, item_id], runtime)


func _kill_and_respawn_player(player: PlayerCharacter) -> void:
	if player == null:
		return

	player.die()
	runtime.notify_entity_action_finished_in_turn(player)
	ConsoleOutput.print_console("Character killed and respawned at %s." % str(player.spawn_cell), runtime)


func _broadcast_player_respawn(player: PlayerCharacter) -> void:
	if not GameSession.is_multiplayer() or not GameSession.is_host():
		return
	NetworkManager.entity.broadcast_entity_respawn(
		player.entity_id,
		player.current_cell,
		player.health,
		runtime.get_current_action_sequence_id()
	)


func _can_use_debug_commands() -> bool:
	return level != null and level.allows_debug_commands()


func _register_console_commands() -> void:
	var console: Node = get_node_or_null("/root/Console")
	if console == null or not console.has_method("add_command"):
		return

	console.add_command(
		KILL_COMMAND_NAME,
		console_kill_character,
		0,
		0,
		"Kill and immediately respawn the local character."
	)
	console.add_command(
		INVENTORY_ADD_COMMAND_NAME,
		console_inventory_add,
		["item_id", "amount"],
		2,
		"Add a complete item amount to the local character inventory."
	)

	if console.has_method("add_command_autocomplete_list"):
		console.add_command_autocomplete_list(
			INVENTORY_ADD_COMMAND_NAME,
			CharacterInventory.KNOWN_ITEM_IDS
		)


func _unregister_console_commands() -> void:
	var console: Node = get_node_or_null("/root/Console")
	if console == null or not console.has_method("remove_command"):
		return

	console.remove_command(KILL_COMMAND_NAME)
	console.remove_command(INVENTORY_ADD_COMMAND_NAME)


func _connect_network_signals() -> void:
	if not NetworkManager.character.character_kill_requested.is_connected(_on_character_kill_requested):
		NetworkManager.character.character_kill_requested.connect(_on_character_kill_requested)
	if not NetworkManager.connection.steam_peer_disconnected.is_connected(_on_steam_peer_disconnected):
		NetworkManager.connection.steam_peer_disconnected.connect(_on_steam_peer_disconnected)


func _disconnect_network_signals() -> void:
	if NetworkManager.character.character_kill_requested.is_connected(_on_character_kill_requested):
		NetworkManager.character.character_kill_requested.disconnect(_on_character_kill_requested)
	if NetworkManager.connection.steam_peer_disconnected.is_connected(_on_steam_peer_disconnected):
		NetworkManager.connection.steam_peer_disconnected.disconnect(_on_steam_peer_disconnected)


func _connect_player_channel_signals() -> void:
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
	if GameSession.is_host() and not authoritative_spawn_snapshot.is_empty():
		NetworkManager.players.send_player_spawn_snapshot(requester_peer_id, authoritative_spawn_snapshot)


func _on_player_spawn_snapshot_received(snapshot: Dictionary) -> void:
	if not GameSession.is_host() and str(snapshot.get("match_id", "")) == GameSession.get_match_id():
		received_spawn_snapshot = snapshot.duplicate(true)


func _on_players_committed_received(match_id: String) -> void:
	if match_id == GameSession.get_match_id():
		are_players_committed = true


func _on_player_respawn_pending_received(match_id: String, entity_id: String) -> void:
	if GameSession.is_host() or match_id != GameSession.get_match_id():
		return
	var player: PlayerCharacter = get_player_by_entity_id(entity_id)
	if player == null:
		return
	runtime.unregister_entity(player)
	player.set_health(0)
	player.can_receive_input = false
	player.hide()


func _on_steam_peer_disconnected(steam_id: int) -> void:
	if GameSession.is_host():
		mark_player_disconnected(steam_id, true)


func _on_player_connection_state_received(match_id: String, steam_id: int, is_connected: bool) -> void:
	if GameSession.is_host() or match_id != GameSession.get_match_id() or is_connected:
		return
	mark_player_disconnected(steam_id, false)


func _on_character_kill_requested(
	match_id: String,
	turn_revision: int,
	request_id: int,
	requester_peer_id: int
) -> void:
	if not GameSession.is_host() or not _can_use_debug_commands():
		return

	var target_player: PlayerCharacter = local_player
	if requester_peer_id != 0:
		var requester_steam_id: int = NetworkManager.peers.get_steam_id_for_peer_id(requester_peer_id)
		target_player = get_player_by_steam_id(requester_steam_id)

	if target_player == null:
		return

	runtime.enqueue_player_action(
		WorldActionRecord.ActionType.CHARACTER_KILL,
		target_player,
		{},
		request_id,
		requester_peer_id,
		turn_revision,
		match_id
	)


func _spawn_player(
	player_info: Dictionary,
	spawn_cell: Vector2i,
	warrior_color: String,
	entity_id: String
) -> PlayerCharacter:
	var player: PlayerCharacter = CHARACTER_SCENE.instantiate() as PlayerCharacter
	if player == null:
		return null

	player.name = _get_player_node_name(player_info)
	players_root.add_child(player)
	player.setup_multiplayer_player(player_info)
	player.start(runtime.cell_to_world(spawn_cell), bool(player_info.get("is_local", false)), entity_id)
	if GameSession.is_multiplayer() and not GameSession.has_committed_match():
		player.can_receive_input = false
	player.configure_warrior_profile(warrior_color)
	var registration_result: int = runtime.register_entity(player)
	if registration_result != WorldRegistry.RegistrationError.NONE:
		player.queue_free()
		return null

	var steam_id: int = int(player_info.get("steam_id", 0))
	if steam_id != 0:
		players_by_steam_id[steam_id] = player

	if bool(player_info.get("is_local", false)):
		local_player = player
		_spawn_camera_for_player(player)

	return player


func _spawn_camera_for_player(player: Node2D) -> void:
	if level == null or player == null:
		return

	var camera: GameCamera = CAMERA_SCENE.instantiate() as GameCamera
	if camera == null:
		return

	camera.allows_console_commands = _can_use_debug_commands()
	local_camera = camera
	players_root.add_child.call_deferred(camera)
	call_deferred("_configure_camera_for_player", camera, player)


func _configure_camera_for_player(camera: GameCamera, player: Node2D) -> void:
	if camera == null or player == null:
		return

	if not is_instance_valid(camera) or not is_instance_valid(player):
		return

	if not camera.is_inside_tree() or not player.is_inside_tree():
		call_deferred("_configure_camera_for_player", camera, player)
		return

	camera.target_path = camera.get_path_to(player)
	camera.target = player
	camera.global_position = player.global_position
	camera.configure_world_bounds(runtime.get_grid_world_bounds())
	camera.make_current()


func _get_spawn_cell(index: int) -> Vector2i:
	if index < spawn_cells.size():
		return spawn_cells[index]

	var grid_size: Vector2i = runtime.get_grid_size()
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var cell: Vector2i = Vector2i(x, y)
			if runtime.is_cell_walkable_for_character(cell):
				return cell

	return Vector2i(1, 1)


func _spawn_authoritative_players(session_players: Array[Dictionary]) -> String:
	var spawn_records: Array[Dictionary] = []
	var assigned_cells: Dictionary[Vector2i, bool] = {}
	for index: int in range(session_players.size()):
		var player_info: Dictionary = session_players[index]
		var preferred_cell: Vector2i = INVALID_SPAWN_CELL
		var has_preferred_cell: bool = index < spawn_cells.size()
		if has_preferred_cell:
			preferred_cell = spawn_cells[index]
		var spawn_cell: Vector2i = _find_available_spawn_cell(preferred_cell, has_preferred_cell, assigned_cells)
		if spawn_cell == INVALID_SPAWN_CELL:
			return "spawn_unavailable"
		var entity_id: String = str(player_info.get("entity_id", ""))
		var warrior_color: String = _get_multiplayer_warrior_color(int(player_info.get("color_index", index)))
		var player: PlayerCharacter = _spawn_player(player_info, spawn_cell, warrior_color, entity_id)
		if player == null:
			return "spawn_registration_failed"
		assigned_cells[spawn_cell] = true
		spawn_records.append({
			"steam_id": int(player_info.get("steam_id", 0)),
			"entity_id": entity_id,
			"spawn_cell": spawn_cell,
			"warrior_color": warrior_color,
		})
	authoritative_spawn_snapshot = {
		"protocol_version": NetworkProtocol.PROTOCOL_VERSION,
		"match_id": GameSession.get_match_id(),
		"level_id": GameSession.selected_level_id,
		"roster_hash": GameSession.get_roster_hash(),
		"players": spawn_records,
	}
	return ""


func _wait_for_spawn_snapshot() -> String:
	var deadline_msec: int = Time.get_ticks_msec() + PLAYER_COMMIT_TIMEOUT_MSEC
	var next_request_msec: int = 0
	while is_inside_tree() and received_spawn_snapshot.is_empty() and Time.get_ticks_msec() < deadline_msec:
		if Time.get_ticks_msec() >= next_request_msec:
			NetworkManager.players.request_player_spawn_snapshot()
			next_request_msec = Time.get_ticks_msec() + PLAYER_SNAPSHOT_RETRY_MSEC
		await get_tree().process_frame
	return "" if not received_spawn_snapshot.is_empty() else "spawn_snapshot_timeout"


func _spawn_players_from_snapshot(session_players: Array[Dictionary], snapshot: Dictionary) -> bool:
	if (
		int(snapshot.get("protocol_version", 0)) != NetworkProtocol.PROTOCOL_VERSION
		or str(snapshot.get("match_id", "")) != GameSession.get_match_id()
		or str(snapshot.get("level_id", "")) != GameSession.selected_level_id
		or str(snapshot.get("roster_hash", "")) != GameSession.get_roster_hash()
	):
		return false
	var records_value: Variant = snapshot.get("players", [])
	if not (records_value is Array) or (records_value as Array).size() != session_players.size():
		return false
	var records_by_steam_id: Dictionary[int, Dictionary] = {}
	var used_cells: Dictionary[Vector2i, bool] = {}
	for record_value: Variant in records_value as Array:
		if not (record_value is Dictionary):
			return false
		var record: Dictionary = record_value as Dictionary
		var steam_id: int = int(record.get("steam_id", 0))
		var spawn_cell: Vector2i = record.get("spawn_cell", INVALID_SPAWN_CELL)
		if steam_id == 0 or records_by_steam_id.has(steam_id) or used_cells.has(spawn_cell):
			return false
		records_by_steam_id[steam_id] = record
		used_cells[spawn_cell] = true
	for player_info: Dictionary in session_players:
		var steam_id: int = int(player_info.get("steam_id", 0))
		var record: Dictionary = records_by_steam_id.get(steam_id, {})
		if record.is_empty() or str(record.get("entity_id", "")) != str(player_info.get("entity_id", "")):
			return false
		var entity_id: String = str(record.get("entity_id", ""))
		var player: PlayerCharacter = _spawn_player(
			player_info,
			record.get("spawn_cell", INVALID_SPAWN_CELL),
			str(record.get("warrior_color", "Blue")),
			entity_id
		)
		if player == null:
			return false
	return true


func _find_available_spawn_cell(
	preferred_cell: Vector2i,
	has_preferred_cell: bool,
	assigned_cells: Dictionary[Vector2i, bool],
	ignored_player: PlayerCharacter = null
) -> Vector2i:
	if has_preferred_cell and _is_spawn_cell_available(preferred_cell, assigned_cells, ignored_player):
		return preferred_cell
	var candidates: Array[Vector2i] = []
	var grid_size: Vector2i = runtime.get_grid_size()
	for y: int in range(grid_size.y):
		for x: int in range(grid_size.x):
			var cell: Vector2i = Vector2i(x, y)
			if _is_spawn_cell_available(cell, assigned_cells, ignored_player):
				candidates.append(cell)
	if has_preferred_cell:
		candidates.sort_custom(func(first: Vector2i, second: Vector2i) -> bool:
			var first_distance: int = absi(first.x - preferred_cell.x) + absi(first.y - preferred_cell.y)
			var second_distance: int = absi(second.x - preferred_cell.x) + absi(second.y - preferred_cell.y)
			if first_distance != second_distance:
				return first_distance < second_distance
			if first.y != second.y:
				return first.y < second.y
			return first.x < second.x
		)
	if candidates.is_empty():
		return INVALID_SPAWN_CELL
	return candidates[0]


func _is_spawn_cell_available(
	cell: Vector2i,
	assigned_cells: Dictionary[Vector2i, bool],
	ignored_player: PlayerCharacter = null
) -> bool:
	return (
		not assigned_cells.has(cell)
		and runtime.can_character_enter_cell(cell, ignored_player)
	)


func _get_multiplayer_warrior_color(player_index: int) -> String:
	if player_index >= 0 and player_index < MULTIPLAYER_WARRIOR_COLORS.size():
		return str(MULTIPLAYER_WARRIOR_COLORS[player_index])

	return str(MULTIPLAYER_WARRIOR_COLORS[0])


func _get_player_node_name(player_info: Dictionary) -> String:
	var steam_id: int = int(player_info.get("steam_id", 0))
	if steam_id == 0:
		return "Character"

	return "Character_%s" % steam_id
