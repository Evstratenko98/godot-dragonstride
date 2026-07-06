extends Node

const CHARACTER_SCENE := preload("res://scenes/entities/character/character.tscn")
const CAMERA_SCENE := preload("res://scenes/camera/camera.tscn")
const SINGLEPLAYER_WARRIOR_COLOR := "Purple"
const MULTIPLAYER_WARRIOR_COLORS := ["Blue", "Purple", "Red", "Yellow"]

@export var spawn_cells: Array[Vector2i] = [
	Vector2i(5, 5),
	Vector2i(6, 5),
	Vector2i(5, 6),
	Vector2i(6, 6),
]

@onready var players_root: Node2D = $"../Players"

var world = null
var players_by_steam_id: Dictionary = {}
var local_player: Node = null
var local_camera: Camera2D = null


func _ready() -> void:
	world = get_parent()


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
	world.clear_registered_entities()


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
		var peer_id: int = NetworkManager.get_peer_id_for_steam_id(int(steam_id))

		if peer_id == 0:
			continue

		var player: Node = players_by_steam_id[steam_id]
		player.set_multiplayer_authority(peer_id)


func get_player_by_steam_id(steam_id: int) -> Node:
	return players_by_steam_id.get(steam_id, null) as Node


func get_local_player() -> Node:
	return local_player


func _spawn_player(
	player_info: Dictionary,
	spawn_cell: Vector2i,
	warrior_color: String,
	entity_id: String,
	entity_name: String
) -> Node:
	var player: Node = CHARACTER_SCENE.instantiate()
	player.name = _get_player_node_name(player_info)
	players_root.add_child(player)
	player.setup_multiplayer_player(player_info)
	player.start(world.cell_to_world(spawn_cell), bool(player_info.get("is_local", false)), entity_id, entity_name)
	if player.has_method("set_warrior_color"):
		player.set_warrior_color(warrior_color)
	world.register_entity(player)

	var steam_id: int = int(player_info.get("steam_id", 0))
	if steam_id != 0:
		players_by_steam_id[steam_id] = player

	if bool(player_info.get("is_local", false)):
		local_player = player
		_spawn_camera_for_player(player)

	return player


func _spawn_camera_for_player(player: Node2D) -> void:
	local_camera = CAMERA_SCENE.instantiate()
	world.add_child(local_camera)
	local_camera.target_path = local_camera.get_path_to(player)
	local_camera.target = player
	local_camera.global_position = player.global_position
	local_camera.make_current()


func _get_spawn_cell(index: int) -> Vector2i:
	if index < spawn_cells.size():
		return spawn_cells[index]

	var grid_size: Vector2i = world.get_grid_size()
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var cell: Vector2i = Vector2i(x, y)
			if world.is_cell_walkable(cell):
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
