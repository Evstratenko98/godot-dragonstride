class_name WorldPlayers
extends Node

const CHARACTER_SCENE := preload("res://scenes/entities/character/character.tscn")
const CAMERA_SCENE := preload("res://scenes/camera/camera.tscn")
const KILL_COMMAND_NAME := "game_character_kill"
const INVENTORY_ADD_COMMAND_NAME := "game_inventory_add"
const SINGLEPLAYER_WARRIOR_COLOR := "Purple"
const MULTIPLAYER_WARRIOR_COLORS := ["Blue", "Purple", "Red", "Yellow"]

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
var local_camera: Camera2D = null


func _ready() -> void:
	_register_console_commands()
	_connect_network_signals()


func _exit_tree() -> void:
	_unregister_console_commands()
	_disconnect_network_signals()


func configure_context(new_runtime: WorldRuntime, new_level: WorldLevel) -> void:
	runtime = new_runtime
	level = new_level


func configure(new_spawn_cells: Array[Vector2i]) -> void:
	spawn_cells = new_spawn_cells


func prepare_players_root() -> void:
	for child in players_root.get_children():
		child.queue_free()

	if local_camera != null:
		local_camera.queue_free()

	players_by_steam_id.clear()
	local_player = null
	local_camera = null
	runtime.clear_registered_entities()


func start_singleplayer() -> void:
	_spawn_player({
		"steam_id": 0,
		"name": "Player",
		"is_host": true,
		"is_local": true,
	}, _get_spawn_cell(0), SINGLEPLAYER_WARRIOR_COLOR, "patrick", "Patrick")


func start_multiplayer() -> void:
	var session_players: Array = GameSession.get_players()

	if session_players.is_empty():
		start_singleplayer()
		return

	for i in range(session_players.size()):
		var player_entity_name: String = "player_%d" % [i + 1]
		_spawn_player(
			session_players[i],
			_get_spawn_cell(i),
			_get_multiplayer_warrior_color(i),
			player_entity_name,
			player_entity_name
		)

	update_player_authorities()


func update_player_authorities() -> void:
	for steam_id in players_by_steam_id.keys():
		var peer_id: int = NetworkManager.peers.get_peer_id_for_steam_id(int(steam_id))

		if peer_id == 0:
			continue

		var player: Node = players_by_steam_id[steam_id]
		player.set_multiplayer_authority(peer_id)


func get_player_by_steam_id(steam_id: int) -> PlayerCharacter:
	return players_by_steam_id.get(steam_id, null) as PlayerCharacter


func get_local_player() -> PlayerCharacter:
	return local_player


func get_players_root() -> Node2D:
	return players_root


func console_kill_character() -> void:
	if local_player == null:
		ConsoleOutput.print_console("ERROR: Local character is not ready.", runtime)
		return
	if GameSession.is_multiplayer() and not NetworkManager.connection.is_ready():
		ConsoleOutput.print_console("ERROR: Cannot kill character: network is not ready.", runtime)
		return

	var request_id: int = runtime.create_action_request_id()
	if GameSession.is_multiplayer() and not GameSession.is_host():
		NetworkManager.character.request_character_kill(request_id)
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
	if local_player == null:
		ConsoleOutput.print_console("ERROR: Local character is not ready.", runtime)
		return
	if not local_player.character_inventory.has_item_id(item_id):
		ConsoleOutput.print_console("ERROR: Unknown inventory item: %s." % item_id, runtime)
		return
	if not amount_text.is_valid_int() or amount_text.to_int() <= 0:
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
	if GameSession.is_multiplayer():
		NetworkManager.entity.broadcast_entity_respawn(
			player.entity_id,
			player.spawn_cell,
			player.health,
			runtime.get_current_action_sequence_id()
		)

	ConsoleOutput.print_console("Character killed and respawned at %s." % str(player.spawn_cell), runtime)


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


func _disconnect_network_signals() -> void:
	if NetworkManager.character.character_kill_requested.is_connected(_on_character_kill_requested):
		NetworkManager.character.character_kill_requested.disconnect(_on_character_kill_requested)


func _on_character_kill_requested(request_id: int, requester_peer_id: int) -> void:
	if not GameSession.is_host():
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
		requester_peer_id
	)


func _spawn_player(
	player_info: Dictionary,
	spawn_cell: Vector2i,
	warrior_color: String,
	entity_id: String,
	entity_name: String
) -> Node:
	var player: PlayerCharacter = CHARACTER_SCENE.instantiate() as PlayerCharacter
	if player == null:
		return null

	player.name = _get_player_node_name(player_info)
	players_root.add_child(player)
	player.setup_multiplayer_player(player_info)
	player.start(runtime.cell_to_world(spawn_cell), bool(player_info.get("is_local", false)), entity_id, entity_name)
	player.set_warrior_color(warrior_color)
	runtime.register_entity(player)

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

	var camera: Camera2D = CAMERA_SCENE.instantiate() as Camera2D
	if camera == null:
		return

	local_camera = camera
	players_root.add_child.call_deferred(camera)
	call_deferred("_configure_camera_for_player", camera, player)


func _configure_camera_for_player(camera: Camera2D, player: Node2D) -> void:
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


func _get_multiplayer_warrior_color(player_index: int) -> String:
	if player_index >= 0 and player_index < MULTIPLAYER_WARRIOR_COLORS.size():
		return str(MULTIPLAYER_WARRIOR_COLORS[player_index])

	return str(MULTIPLAYER_WARRIOR_COLORS[0])


func _get_player_node_name(player_info: Dictionary) -> String:
	var steam_id: int = int(player_info.get("steam_id", 0))
	if steam_id == 0:
		return "Character"

	return "Character_%s" % steam_id
