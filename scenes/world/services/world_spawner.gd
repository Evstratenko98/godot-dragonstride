class_name WorldSpawner
extends Node

const COMMAND_NAME := "game_create"
const CREATE_FULL_COMMAND_NAME := "game_create_full"
const CLEAR_FULL_COMMAND_NAME := "game_clear_full"
const SPAWN_KIND_ENTITY := "entity"
const SPAWN_KIND_OBJECT := "object"

const SHEEP_SCENE := preload("res://scenes/entities/sheep/sheep.tscn")
const WARRIOR_SCENE := preload("res://scenes/entities/enemies/warrior/warrior.tscn")
const TREE_SCENE := preload("res://scenes/objects/tree/tree.tscn")
const HOUSE_SCENE := preload("res://scenes/objects/house/house.tscn")
const MEAT_SCENE := preload("res://scenes/objects/meat/meat.tscn")

const CATALOG := {
	"sheep": {
		"kind": SPAWN_KIND_ENTITY,
		"scene": SHEEP_SCENE,
		"display_name": "Sheep",
	},
	"warrior": {
		"kind": SPAWN_KIND_ENTITY,
		"scene": WARRIOR_SCENE,
		"display_name": "Warrior",
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
	"meat": {
		"kind": SPAWN_KIND_OBJECT,
		"scene": MEAT_SCENE,
		"display_name": "Meat",
	},
}

var runtime: WorldRuntime = null
var level: WorldLevel = null
var spawned_counter: int = 0


func _ready() -> void:
	_register_console_commands()
	_connect_network_signals()


func configure_context(new_runtime: WorldRuntime, new_level: WorldLevel) -> void:
	runtime = new_runtime
	level = new_level
	call_deferred("_apply_cached_world_spawns")


func _exit_tree() -> void:
	_unregister_console_commands()
	_disconnect_network_signals()


func console_create(type_key: String, x_text: String, y_text: String) -> void:
	var normalized_type: String = _normalize_type_key(type_key)
	if not CATALOG.has(normalized_type):
		_print_spawn_error("Unknown create type: %s." % type_key)
		return

	if not x_text.is_valid_int() or not y_text.is_valid_int():
		_print_spawn_error("Usage: %s <type> <x> <y>. Coordinates must be integers." % COMMAND_NAME)
		return

	var cell: Vector2i = Vector2i(x_text.to_int(), y_text.to_int())
	if GameSession.is_multiplayer() and not GameSession.is_host():
		NetworkManager.request_world_spawn(normalized_type, cell)
		return

	_try_create_authoritative(normalized_type, cell, true, 0)


func console_create_full(type_key: String) -> void:
	var normalized_type: String = _normalize_type_key(type_key)
	if not CATALOG.has(normalized_type):
		_print_spawn_error("Unknown create type: %s." % type_key)
		return
	if GameSession.is_multiplayer() and not NetworkManager.is_ready():
		_print_spawn_error("Cannot fill world: network is not ready.")
		return

	if GameSession.is_multiplayer() and not GameSession.is_host():
		NetworkManager.request_world_fill(normalized_type)
		return

	_fill_authoritative(normalized_type, 0)


func console_clear_full(type_key: String = "") -> void:
	var normalized_type: String = _normalize_type_key(type_key)
	if not normalized_type.is_empty() and not CATALOG.has(normalized_type):
		_print_spawn_error("Unknown clear type: %s." % type_key)
		return
	if GameSession.is_multiplayer() and not NetworkManager.is_ready():
		_print_spawn_error("Cannot clear world: network is not ready.")
		return

	if GameSession.is_multiplayer() and not GameSession.is_host():
		NetworkManager.request_world_clear(normalized_type)
		return

	_clear_authoritative(normalized_type, 0)


func remove_world_object(target_object: GridObject) -> bool:
	if target_object == null:
		return false
	if GameSession.is_multiplayer() and not GameSession.is_host():
		return false

	var removal_record: Dictionary = _remove_world_item(target_object)
	if removal_record.is_empty():
		return false

	if GameSession.is_multiplayer():
		var removal_records: Array[Dictionary] = [removal_record]
		NetworkManager.broadcast_world_items_removed(removal_records)

	return true


func _try_create_authoritative(type_key: String, cell: Vector2i, should_broadcast: bool, requester_peer_id: int) -> bool:
	if not CATALOG.has(type_key):
		_report_spawn_error("Unknown create type: %s." % type_key, requester_peer_id)
		return false

	var spawn_id: String = _make_spawn_id(type_key)
	var record: Dictionary = {
		"type_key": type_key,
		"spawn_id": spawn_id,
		"cell": cell,
	}

	var error: String = _spawn_from_record(record, true)
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


func _fill_authoritative(type_key: String, requester_peer_id: int) -> void:
	if not CATALOG.has(type_key):
		_report_spawn_error("Unknown create type: %s." % type_key, requester_peer_id)
		return

	var created_records: Array[Dictionary] = []
	var grid_size: Vector2i = runtime.get_grid_size()
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var cell: Vector2i = Vector2i(x, y)
			if not runtime.is_cell_walkable(cell):
				continue

			var record: Dictionary = _try_fill_cell(type_key, cell)
			if not record.is_empty():
				created_records.append(record)

	if GameSession.is_multiplayer() and not created_records.is_empty():
		NetworkManager.broadcast_world_spawns(created_records)

	ConsoleOutput.print_console("Created %d %s instance(s) on available cells." % [
		created_records.size(),
		type_key,
	], runtime)


func _try_fill_cell(type_key: String, cell: Vector2i) -> Dictionary:
	var spawn_id: String = _make_spawn_id(type_key)
	var record: Dictionary = {
		"type_key": type_key,
		"spawn_id": spawn_id,
		"cell": cell,
	}
	var error: String = _spawn_from_record(record, true)
	if not error.is_empty():
		return {}

	return record


func _clear_authoritative(type_key: String, requester_peer_id: int) -> void:
	if not type_key.is_empty() and not CATALOG.has(type_key):
		_report_spawn_error("Unknown clear type: %s." % type_key, requester_peer_id)
		return

	var removal_records: Array[Dictionary] = []
	for entity_variant in runtime.get_registered_entities():
		var entity: Node = entity_variant as Node
		if entity is NonPlayerEntity and _matches_catalog_type(entity, type_key):
			var entity_removal: Dictionary = _remove_world_item(entity)
			if not entity_removal.is_empty():
				removal_records.append(entity_removal)

	for object_variant in runtime.get_registered_objects():
		var target_object: Node = object_variant as Node
		if target_object is GridObject and _matches_catalog_type(target_object, type_key):
			var object_removal: Dictionary = _remove_world_item(target_object)
			if not object_removal.is_empty():
				removal_records.append(object_removal)

	if GameSession.is_multiplayer() and not removal_records.is_empty():
		NetworkManager.broadcast_world_items_removed(removal_records)

	var cleared_type: String = type_key if not type_key.is_empty() else "all world items"
	ConsoleOutput.print_console("Removed %d %s instance(s)." % [
		removal_records.size(),
		cleared_type,
	], runtime)


func _matches_catalog_type(instance: Node, type_key: String) -> bool:
	if type_key.is_empty():
		return true

	var definition: Dictionary = CATALOG[type_key]
	var scene: PackedScene = definition.get("scene") as PackedScene
	return scene != null and instance.scene_file_path == scene.resource_path


func _remove_world_item(instance: Node) -> Dictionary:
	if instance is NonPlayerEntity:
		var entity_id: String = runtime.get_entity_id(instance)
		if entity_id.is_empty():
			return {}

		runtime.unregister_entity(instance)
		instance.queue_free()
		return {
			"kind": SPAWN_KIND_ENTITY,
			"id": entity_id,
		}

	if instance is GridObject:
		var object_id: String = (instance as GridObject).object_id
		if object_id.is_empty():
			return {}

		runtime.unregister_object(instance)
		instance.queue_free()
		return {
			"kind": SPAWN_KIND_OBJECT,
			"id": object_id,
		}

	return {}


func _spawn_from_record(record: Dictionary, should_validate: bool) -> String:
	var type_key: String = _normalize_type_key(str(record.get("type_key", "")))
	if not CATALOG.has(type_key):
		return "Unknown create type: %s." % type_key

	var spawn_id: String = str(record.get("spawn_id", ""))
	if spawn_id.is_empty():
		return "Spawn id is empty."

	if _has_spawn_id(spawn_id):
		return ""

	var cell: Vector2i = record.get("cell", Vector2i.ZERO)
	var definition: Dictionary = CATALOG[type_key]
	var scene: PackedScene = definition.get("scene") as PackedScene
	if scene == null:
		return "Scene is missing for type: %s." % type_key

	var instance: Node = scene.instantiate()
	_assign_spawn_id(instance, str(definition.get("kind", "")), spawn_id)

	if should_validate:
		var placement_error: String = runtime.get_placement_error(instance, cell)
		if not placement_error.is_empty():
			instance.free()
			return placement_error

	_spawn_instance(instance, definition, type_key, spawn_id, cell)
	return ""


func _spawn_instance(instance: Node, definition: Dictionary, type_key: String, spawn_id: String, cell: Vector2i) -> void:
	var kind: String = str(definition.get("kind", ""))
	var display_name: String = str(definition.get("display_name", type_key.capitalize()))
	var world_position: Vector2 = runtime.cell_to_world(cell)

	if kind == SPAWN_KIND_ENTITY:
		var entities_root: Node2D = _get_world_entities_root()
		instance.name = spawn_id
		entities_root.add_child(instance)
		if instance is NonPlayerEntity:
			(instance as NonPlayerEntity).start(world_position, spawn_id, display_name)
		elif instance is Entity:
			(instance as Entity).start_entity(world_position, spawn_id, display_name)
		elif instance is Node2D:
			instance.global_position = world_position
		runtime.register_entity(instance)
		_apply_cached_entity_ai_state(instance, spawn_id)
		return

	if kind == SPAWN_KIND_OBJECT:
		var objects_root: Node2D = _get_spawned_objects_root()
		instance.name = spawn_id
		if not instance.is_in_group("game_blocker"):
			instance.add_to_group("game_blocker")
		if instance is Node2D:
			instance.global_position = world_position
		objects_root.add_child(instance)
		runtime.register_object(instance, cell)
		_apply_cached_object_state(instance, spawn_id)


func _assign_spawn_id(instance: Node, kind: String, spawn_id: String) -> void:
	if kind == SPAWN_KIND_ENTITY and instance.get("entity_id") != null:
		instance.set("entity_id", spawn_id)
		return

	if kind == SPAWN_KIND_OBJECT and instance.get("object_id") != null:
		instance.set("object_id", spawn_id)


func _apply_cached_object_state(instance: Node, spawn_id: String) -> void:
	if not (instance is GridObject):
		return

	var cached_states: Dictionary = NetworkManager.get_object_states()
	if not cached_states.has(spawn_id):
		return

	(instance as GridObject).apply_network_state(int(cached_states[spawn_id]))


func _apply_cached_entity_ai_state(instance: Node, spawn_id: String) -> void:
	if not (instance is NonPlayerEntity):
		return

	var cached_states: Dictionary = NetworkManager.get_entity_ai_states()
	if not cached_states.has(spawn_id):
		return

	var state: Dictionary = cached_states[spawn_id]
	(instance as NonPlayerEntity).apply_remote_ai_state(
		str(state.get("state", "")),
		str(state.get("target_entity_id", "")),
		str(state.get("reason", ""))
	)


func apply_cached_world_removals() -> void:
	if not GameSession.is_multiplayer() or GameSession.is_host():
		return

	_apply_world_removals(NetworkManager.get_removed_world_items())


func _apply_cached_world_spawns() -> void:
	if not GameSession.is_multiplayer() or GameSession.is_host():
		return

	var spawn_records: Array[Dictionary] = NetworkManager.get_world_spawn_records()
	_apply_world_spawns(spawn_records, "cached")


func _apply_world_spawns(records: Array[Dictionary], source_name: String) -> void:
	for record_variant in records:
		var record: Dictionary = record_variant
		if _has_spawn_id(str(record.get("spawn_id", ""))):
			continue

		var error: String = _spawn_from_record(record, false)
		if not error.is_empty():
			_print_spawn_error("Cannot apply %s spawn: %s" % [source_name, error])


func _apply_world_removals(records: Array[Dictionary]) -> void:
	for record_variant in records:
		var record: Dictionary = record_variant
		var kind: String = str(record.get("kind", ""))
		var item_id: String = str(record.get("id", ""))
		var instance: Node = null
		if kind == SPAWN_KIND_ENTITY:
			instance = runtime.get_entity_by_id(item_id)
		elif kind == SPAWN_KIND_OBJECT:
			instance = runtime.get_object_by_id(item_id)

		if instance != null:
			_remove_world_item(instance)


func _make_spawn_id(type_key: String) -> String:
	while true:
		spawned_counter += 1
		var spawn_id: String = "spawned_%s_%d" % [type_key, spawned_counter]
		if not _has_spawn_id(spawn_id):
			return spawn_id

	return ""


func _has_spawn_id(spawn_id: String) -> bool:
	return runtime.get_entity_by_id(spawn_id) != null or runtime.get_object_by_id(spawn_id) != null


func _get_world_entities_root() -> Node2D:
	var root: Node2D = level.get_world_entities_root()
	if root != null:
		return root

	root = Node2D.new()
	root.name = "WorldEntities"
	level.add_child(root)
	return root


func _get_spawned_objects_root() -> Node2D:
	var root: Node2D = level.get_spawned_objects_root()
	if root != null:
		return root

	root = Node2D.new()
	root.name = "SpawnedObjects"
	level.add_child(root)
	return root


func _normalize_type_key(type_key: String) -> String:
	return type_key.strip_edges().to_lower()


func _print_created(record: Dictionary) -> void:
	var cell: Vector2i = record.get("cell", Vector2i.ZERO)
	ConsoleOutput.print_console("Created %s at %d %d." % [
		str(record.get("type_key", "")),
		cell.x,
		cell.y,
	], runtime)


func _print_spawn_error(message: String) -> void:
	ConsoleOutput.print_console("ERROR: %s" % message, runtime)


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
	console.add_command(
		CREATE_FULL_COMMAND_NAME,
		console_create_full,
		["type"],
		1,
		"Fill available ground cells with an allowed entity or object. My thanks to Kirill."
	)
	console.add_command(
		CLEAR_FULL_COMMAND_NAME,
		console_clear_full,
		["type"],
		0,
		"Remove one allowed type, or all world items when type is omitted. My thanks to Kirill."
	)

	if console.has_method("add_command_autocomplete_list"):
		var type_keys: PackedStringArray = PackedStringArray()
		for type_key in CATALOG.keys():
			type_keys.append(str(type_key))
		console.add_command_autocomplete_list(COMMAND_NAME, type_keys)
		console.add_command_autocomplete_list(CREATE_FULL_COMMAND_NAME, type_keys)
		console.add_command_autocomplete_list(CLEAR_FULL_COMMAND_NAME, type_keys)


func _unregister_console_commands() -> void:
	var console: Node = get_node_or_null("/root/Console")
	if console == null or not console.has_method("remove_command"):
		return

	console.remove_command(COMMAND_NAME)
	console.remove_command(CREATE_FULL_COMMAND_NAME)
	console.remove_command(CLEAR_FULL_COMMAND_NAME)


func _connect_network_signals() -> void:
	if not NetworkManager.world_spawn_requested.is_connected(_on_world_spawn_requested):
		NetworkManager.world_spawn_requested.connect(_on_world_spawn_requested)

	if not NetworkManager.world_spawn_received.is_connected(_on_world_spawn_received):
		NetworkManager.world_spawn_received.connect(_on_world_spawn_received)

	if not NetworkManager.world_spawns_received.is_connected(_on_world_spawns_received):
		NetworkManager.world_spawns_received.connect(_on_world_spawns_received)

	if not NetworkManager.world_fill_requested.is_connected(_on_world_fill_requested):
		NetworkManager.world_fill_requested.connect(_on_world_fill_requested)

	if not NetworkManager.world_clear_requested.is_connected(_on_world_clear_requested):
		NetworkManager.world_clear_requested.connect(_on_world_clear_requested)

	if not NetworkManager.world_items_removed_received.is_connected(_on_world_items_removed_received):
		NetworkManager.world_items_removed_received.connect(_on_world_items_removed_received)

	if not NetworkManager.world_spawn_failed_received.is_connected(_on_world_spawn_failed_received):
		NetworkManager.world_spawn_failed_received.connect(_on_world_spawn_failed_received)


func _disconnect_network_signals() -> void:
	if NetworkManager.world_spawn_requested.is_connected(_on_world_spawn_requested):
		NetworkManager.world_spawn_requested.disconnect(_on_world_spawn_requested)

	if NetworkManager.world_spawn_received.is_connected(_on_world_spawn_received):
		NetworkManager.world_spawn_received.disconnect(_on_world_spawn_received)

	if NetworkManager.world_spawns_received.is_connected(_on_world_spawns_received):
		NetworkManager.world_spawns_received.disconnect(_on_world_spawns_received)

	if NetworkManager.world_fill_requested.is_connected(_on_world_fill_requested):
		NetworkManager.world_fill_requested.disconnect(_on_world_fill_requested)

	if NetworkManager.world_clear_requested.is_connected(_on_world_clear_requested):
		NetworkManager.world_clear_requested.disconnect(_on_world_clear_requested)

	if NetworkManager.world_items_removed_received.is_connected(_on_world_items_removed_received):
		NetworkManager.world_items_removed_received.disconnect(_on_world_items_removed_received)

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

	var error: String = _spawn_from_record(record, false)
	if not error.is_empty():
		_print_spawn_error("Cannot apply network spawn: %s" % error)
		return

	_print_created(record)


func _on_world_spawns_received(records: Array[Dictionary]) -> void:
	if GameSession.is_host():
		return

	_apply_world_spawns(records, "network")


func _on_world_fill_requested(type_key: String, requester_peer_id: int) -> void:
	if not GameSession.is_host():
		return

	_fill_authoritative(_normalize_type_key(type_key), requester_peer_id)


func _on_world_clear_requested(type_key: String, requester_peer_id: int) -> void:
	if not GameSession.is_host():
		return

	_clear_authoritative(_normalize_type_key(type_key), requester_peer_id)


func _on_world_items_removed_received(records: Array[Dictionary]) -> void:
	if GameSession.is_host():
		return

	_apply_world_removals(records)


func _on_world_spawn_failed_received(message: String) -> void:
	_print_spawn_error(message)
