extends Node

const COMMAND_NAME := "game_create"
const SPAWN_KIND_ENTITY := "entity"
const SPAWN_KIND_OBJECT := "object"

const SHEEP_SCENE := preload("res://scenes/entities/sheep/sheep.tscn")
const TREE_SCENE := preload("res://scenes/objects/tree/tree.tscn")
const HOUSE_SCENE := preload("res://scenes/objects/house/house.tscn")

const CATALOG := {
	"sheep": {
		"kind": SPAWN_KIND_ENTITY,
		"scene": SHEEP_SCENE,
		"display_name": "Sheep",
	},
	"tree": {
		"kind": SPAWN_KIND_OBJECT,
		"scene": TREE_SCENE,
		"display_name": "Tree",
	},
	"house": {
		"kind": SPAWN_KIND_OBJECT,
		"scene": HOUSE_SCENE,
		"display_name": "House",
	},
}

var world: Node = null
var spawned_counter := 0


func _ready() -> void:
	world = get_parent()
	_register_console_commands()
	_connect_network_signals()
	call_deferred("_apply_cached_world_spawns")


func _exit_tree() -> void:
	_unregister_console_commands()
	_disconnect_network_signals()


func console_create(type_key: String, x_text: String, y_text: String) -> void:
	var normalized_type := _normalize_type_key(type_key)
	if not CATALOG.has(normalized_type):
		_print_spawn_error("Unknown create type: %s." % type_key)
		return

	if not x_text.is_valid_int() or not y_text.is_valid_int():
		_print_spawn_error("Usage: %s <type> <x> <y>. Coordinates must be integers." % COMMAND_NAME)
		return

	var cell := Vector2i(x_text.to_int(), y_text.to_int())
	if GameSession.is_multiplayer() and not GameSession.is_host():
		NetworkManager.request_world_spawn(normalized_type, cell)
		return

	_try_create_authoritative(normalized_type, cell, true, 0)


func _try_create_authoritative(type_key: String, cell: Vector2i, should_broadcast: bool, requester_peer_id: int) -> bool:
	if not CATALOG.has(type_key):
		_report_spawn_error("Unknown create type: %s." % type_key, requester_peer_id)
		return false

	var spawn_id := _make_spawn_id(type_key)
	var record := {
		"type_key": type_key,
		"spawn_id": spawn_id,
		"cell": cell,
	}

	var error := _spawn_from_record(record, true)
	if not error.is_empty():
		_report_spawn_error("Cannot create %s at %d %d: %s" % [
			type_key,
			cell.x,
			cell.y,
			error,
		], requester_peer_id)
		return false

	if should_broadcast and GameSession.is_multiplayer():
		NetworkManager.broadcast_world_spawn(record)

	_print_created(record)
	return true


func _spawn_from_record(record: Dictionary, should_validate: bool) -> String:
	var type_key := _normalize_type_key(str(record.get("type_key", "")))
	if not CATALOG.has(type_key):
		return "Unknown create type: %s." % type_key

	var spawn_id := str(record.get("spawn_id", ""))
	if spawn_id.is_empty():
		return "Spawn id is empty."

	if _has_spawn_id(spawn_id):
		return ""

	var cell: Vector2i = record.get("cell", Vector2i.ZERO)
	var definition: Dictionary = CATALOG[type_key]
	var scene: PackedScene = definition.get("scene") as PackedScene
	if scene == null:
		return "Scene is missing for type: %s." % type_key

	var instance := scene.instantiate()
	_assign_spawn_id(instance, str(definition.get("kind", "")), spawn_id)

	if should_validate:
		var placement_error: String = world.get_placement_error(instance, cell)
		if not placement_error.is_empty():
			instance.free()
			return placement_error

	_spawn_instance(instance, definition, type_key, spawn_id, cell)
	return ""


func _spawn_instance(instance: Node, definition: Dictionary, type_key: String, spawn_id: String, cell: Vector2i) -> void:
	var kind := str(definition.get("kind", ""))
	var display_name := str(definition.get("display_name", type_key.capitalize()))
	var world_position: Vector2 = world.cell_to_world(cell)

	if kind == SPAWN_KIND_ENTITY:
		var entities_root := _get_world_entities_root()
		instance.name = spawn_id
		entities_root.add_child(instance)
		if instance.has_method("start"):
			instance.start(world_position, spawn_id, display_name)
		elif instance.has_method("start_entity"):
			instance.start_entity(world_position, spawn_id, display_name)
		elif instance is Node2D:
			instance.global_position = world_position
		world.register_entity(instance)
		return

	if kind == SPAWN_KIND_OBJECT:
		var objects_root := _get_spawned_objects_root()
		instance.name = spawn_id
		if not instance.is_in_group("game_blocker"):
			instance.add_to_group("game_blocker")
		if instance is Node2D:
			instance.global_position = world_position
		objects_root.add_child(instance)
		world.register_object(instance, cell)
		_apply_cached_object_state(instance, spawn_id)


func _assign_spawn_id(instance: Node, kind: String, spawn_id: String) -> void:
	if kind == SPAWN_KIND_ENTITY and instance.get("entity_id") != null:
		instance.set("entity_id", spawn_id)
		return

	if kind == SPAWN_KIND_OBJECT and instance.get("object_id") != null:
		instance.set("object_id", spawn_id)


func _apply_cached_object_state(instance: Node, spawn_id: String) -> void:
	if not instance.has_method("apply_network_state"):
		return

	var cached_states: Dictionary = NetworkManager.get_object_states()
	if not cached_states.has(spawn_id):
		return

	instance.apply_network_state(int(cached_states[spawn_id]))


func _apply_cached_world_spawns() -> void:
	if not GameSession.is_multiplayer() or GameSession.is_host():
		return

	var spawn_records: Array = NetworkManager.get_world_spawn_records()
	for record_variant in spawn_records:
		var record: Dictionary = record_variant
		if _has_spawn_id(str(record.get("spawn_id", ""))):
			continue

		var error := _spawn_from_record(record, false)
		if not error.is_empty():
			_print_spawn_error("Cannot apply cached spawn: %s" % error)


func _make_spawn_id(type_key: String) -> String:
	while true:
		spawned_counter += 1
		var spawn_id := "spawned_%s_%d" % [type_key, spawned_counter]
		if not _has_spawn_id(spawn_id):
			return spawn_id

	return ""


func _has_spawn_id(spawn_id: String) -> bool:
	return world.get_entity_by_id(spawn_id) != null or world.get_object_by_id(spawn_id) != null


func _get_world_entities_root() -> Node2D:
	var root := world.get_node_or_null("WorldEntities") as Node2D
	if root != null:
		return root

	root = Node2D.new()
	root.name = "WorldEntities"
	world.add_child(root)
	return root


func _get_spawned_objects_root() -> Node2D:
	var root := world.get_node_or_null("SpawnedObjects") as Node2D
	if root != null:
		return root

	root = Node2D.new()
	root.name = "SpawnedObjects"
	world.add_child(root)
	return root


func _normalize_type_key(type_key: String) -> String:
	return type_key.strip_edges().to_lower()


func _print_created(record: Dictionary) -> void:
	var cell: Vector2i = record.get("cell", Vector2i.ZERO)
	ConsoleOutput.print_console("Created %s at %d %d." % [
		str(record.get("type_key", "")),
		cell.x,
		cell.y,
	], world)


func _print_spawn_error(message: String) -> void:
	ConsoleOutput.print_console("ERROR: %s" % message, world)


func _report_spawn_error(message: String, requester_peer_id: int) -> void:
	if requester_peer_id != 0 and GameSession.is_multiplayer() and GameSession.is_host():
		NetworkManager.send_world_spawn_failed(requester_peer_id, message)
		return

	_print_spawn_error(message)


func _register_console_commands() -> void:
	var console: Node = get_node_or_null("/root/Console")
	if console == null or not console.has_method("add_command"):
		return

	console.add_command(
		COMMAND_NAME,
		console_create,
		["type", "x", "y"],
		3,
		"Create an allowed entity or object on a grid cell."
	)

	if console.has_method("add_command_autocomplete_list"):
		var type_keys := PackedStringArray()
		for type_key in CATALOG.keys():
			type_keys.append(str(type_key))
		console.add_command_autocomplete_list(COMMAND_NAME, type_keys)


func _unregister_console_commands() -> void:
	var console: Node = get_node_or_null("/root/Console")
	if console == null or not console.has_method("remove_command"):
		return

	console.remove_command(COMMAND_NAME)


func _connect_network_signals() -> void:
	if not NetworkManager.world_spawn_requested.is_connected(_on_world_spawn_requested):
		NetworkManager.world_spawn_requested.connect(_on_world_spawn_requested)

	if not NetworkManager.world_spawn_received.is_connected(_on_world_spawn_received):
		NetworkManager.world_spawn_received.connect(_on_world_spawn_received)

	if not NetworkManager.world_spawn_failed_received.is_connected(_on_world_spawn_failed_received):
		NetworkManager.world_spawn_failed_received.connect(_on_world_spawn_failed_received)


func _disconnect_network_signals() -> void:
	if NetworkManager.world_spawn_requested.is_connected(_on_world_spawn_requested):
		NetworkManager.world_spawn_requested.disconnect(_on_world_spawn_requested)

	if NetworkManager.world_spawn_received.is_connected(_on_world_spawn_received):
		NetworkManager.world_spawn_received.disconnect(_on_world_spawn_received)

	if NetworkManager.world_spawn_failed_received.is_connected(_on_world_spawn_failed_received):
		NetworkManager.world_spawn_failed_received.disconnect(_on_world_spawn_failed_received)


func _on_world_spawn_requested(type_key: String, cell: Vector2i, requester_peer_id: int) -> void:
	if not GameSession.is_host():
		return

	_try_create_authoritative(_normalize_type_key(type_key), cell, true, requester_peer_id)


func _on_world_spawn_received(record: Dictionary) -> void:
	if GameSession.is_host():
		return

	if _has_spawn_id(str(record.get("spawn_id", ""))):
		return

	var error := _spawn_from_record(record, false)
	if not error.is_empty():
		_print_spawn_error("Cannot apply network spawn: %s" % error)
		return

	_print_created(record)


func _on_world_spawn_failed_received(message: String) -> void:
	_print_spawn_error(message)
