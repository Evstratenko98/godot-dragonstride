class_name WorldSpawner
extends Node

const SPAWN_KIND_ENTITY := WorldSpawnCatalog.KIND_ENTITY
const SPAWN_KIND_OBJECT := WorldSpawnCatalog.KIND_OBJECT
const CATALOG := WorldSpawnCatalog.DEFINITIONS

var runtime: WorldRuntime = null
var level: WorldLevel = null
var spawned_counter: int = 0
var debug_commands: WorldSpawnerDebugCommands = WorldSpawnerDebugCommands.new()
var snapshot_transaction: WorldSpawnSnapshotTransaction = WorldSpawnSnapshotTransaction.new()
var batch_operator: WorldSpawnBatchOperator = WorldSpawnBatchOperator.new()
var network_bridge: WorldSpawnerNetworkBridge = WorldSpawnerNetworkBridge.new()


func _ready() -> void:
	network_bridge.configure(self)
	network_bridge.connect_signals()
	if not GameSession.session_cleared.is_connected(_on_session_cleared):
		GameSession.session_cleared.connect(_on_session_cleared)


func configure_context(new_runtime: WorldRuntime, new_level: WorldLevel) -> void:
	runtime = new_runtime
	level = new_level
	snapshot_transaction.configure(self)
	batch_operator.configure(self)
	debug_commands.configure(self, _can_use_debug_commands(), CATALOG.keys())
	network_bridge.connect_action_stream()
	call_deferred("_apply_cached_world_spawns")


func _exit_tree() -> void:
	debug_commands.unregister_commands()
	network_bridge.disconnect_signals()
	if GameSession.session_cleared.is_connected(_on_session_cleared):
		GameSession.session_cleared.disconnect(_on_session_cleared)


func _on_session_cleared() -> void:
	network_bridge.clear()
	snapshot_transaction.commit()


func console_create(type_key: String, x_text: String, y_text: String, height_text: String) -> void:
	if not _can_use_debug_commands():
		_print_spawn_error("Debug mutations are unavailable for this level.")
		return
	var normalized_type: String = _normalize_type_key(type_key)
	if not CATALOG.has(normalized_type):
		_print_spawn_error("Unknown create type: %s." % type_key)
		return

	if not x_text.is_valid_int() or not y_text.is_valid_int() or not height_text.is_valid_int():
		_print_spawn_error("Usage: %s <type> <x> <y> <height>. Coordinates must be integers." % WorldSpawnerDebugCommands.CREATE_COMMAND)
		return

	var surface: Vector3i = Vector3i(x_text.to_int(), y_text.to_int(), height_text.to_int())
	if not NetworkProtocol.is_valid_surface_value(surface) or not runtime.has_surface(surface):
		_print_spawn_error("The requested surface does not exist.")
		return
	if GameSession.is_multiplayer() and not GameSession.is_host():
		NetworkManager.world.request_world_spawn(normalized_type, surface)
		return

	_try_create_authoritative(normalized_type, surface, true, 0)


func console_create_full(type_key: String) -> void:
	if not _can_use_debug_commands():
		_print_spawn_error("Debug mutations are unavailable for this level.")
		return
	var normalized_type: String = _normalize_type_key(type_key)
	if not CATALOG.has(normalized_type):
		_print_spawn_error("Unknown create type: %s." % type_key)
		return
	if GameSession.is_multiplayer() and not NetworkManager.connection.is_ready():
		_print_spawn_error("Cannot fill world: network is not ready.")
		return

	if GameSession.is_multiplayer() and not GameSession.is_host():
		NetworkManager.world.request_world_fill(normalized_type)
		return

	batch_operator.fill(normalized_type, 0)


func console_clear_full(type_key: String = "") -> void:
	if not _can_use_debug_commands():
		_print_spawn_error("Debug mutations are unavailable for this level.")
		return
	var normalized_type: String = _normalize_type_key(type_key)
	if not normalized_type.is_empty() and not CATALOG.has(normalized_type):
		_print_spawn_error("Unknown clear type: %s." % type_key)
		return
	if GameSession.is_multiplayer() and not NetworkManager.connection.is_ready():
		_print_spawn_error("Cannot clear world: network is not ready.")
		return

	if GameSession.is_multiplayer() and not GameSession.is_host():
		NetworkManager.world.request_world_clear(normalized_type)
		return

	batch_operator.clear(normalized_type, 0)


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
		NetworkManager.world.broadcast_world_items_removed(
			removal_records,
			runtime.get_current_action_sequence_id()
		)

	return true


func remove_defeated_non_player(target_entity: NonPlayerEntity) -> bool:
	if target_entity == null:
		return false
	if GameSession.is_multiplayer() and not GameSession.is_host():
		return false

	var removal_record: Dictionary = _remove_world_item(target_entity)
	if removal_record.is_empty():
		return false

	if GameSession.is_multiplayer():
		var removal_records: Array[Dictionary] = [removal_record]
		NetworkManager.world.broadcast_world_items_removed(
			removal_records,
			runtime.get_current_action_sequence_id()
		)

	return true


func spawn_world_object(type_key: String, surface: Vector3i) -> bool:
	var normalized_type: String = _normalize_type_key(type_key)
	if not CATALOG.has(normalized_type):
		return false
	var definition: Dictionary = CATALOG[normalized_type]
	if str(definition.get("kind", "")) != SPAWN_KIND_OBJECT:
		return false
	if GameSession.is_multiplayer() and not GameSession.is_host():
		return false

	return _try_create_authoritative(normalized_type, surface, true, 0)


func _try_create_authoritative(type_key: String, surface: Vector3i, should_broadcast: bool, requester_peer_id: int) -> bool:
	if not CATALOG.has(type_key):
		_report_spawn_error("Unknown create type: %s." % type_key, requester_peer_id, "unknown_type")
		return false

	var spawn_id: String = _make_spawn_id(type_key)
	var record: Dictionary = {
		"type_key": type_key,
		"spawn_id": spawn_id,
		"surface": surface,
	}

	var error: String = _spawn_from_record(record, true)
	if not error.is_empty():
		_report_spawn_error("Cannot create %s at %d %d: %s" % [
			type_key,
			surface.x,
			surface.y,
			error,
		], requester_peer_id, "invalid_placement")
		return false

	if should_broadcast and GameSession.is_multiplayer():
		NetworkManager.world.broadcast_world_spawn(record)

	_print_created(record)
	return true


func _try_fill_surface(type_key: String, surface: Vector3i) -> Dictionary:
	var spawn_id: String = _make_spawn_id(type_key)
	var record: Dictionary = {
		"type_key": type_key,
		"spawn_id": spawn_id,
		"surface": surface,
	}
	var error: String = _spawn_from_record(record, true)
	if not error.is_empty():
		return {}

	return record


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

	var surface: Vector3i = record.get("surface", Vector3i.ZERO)
	var definition: Dictionary = CATALOG[type_key]
	var scene: PackedScene = definition.get("scene") as PackedScene
	if scene == null:
		return "Scene is missing for type: %s." % type_key

	var instance: Node = scene.instantiate()
	_assign_spawn_id(instance, str(definition.get("kind", "")), spawn_id)

	if should_validate:
		var placement_error: String = runtime.get_placement_error(instance, surface)
		if not placement_error.is_empty():
			instance.free()
			return placement_error

	return _spawn_instance(instance, definition, type_key, spawn_id, surface)


func _spawn_instance(instance: Node, definition: Dictionary, type_key: String, spawn_id: String, surface: Vector3i) -> String:
	var kind: String = str(definition.get("kind", ""))
	var display_name: String = str(definition.get("display_name", type_key.capitalize()))
	var world_position: Vector2 = runtime.surface_to_world(surface)

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
		var spawned_entity: Entity = instance as Entity
		if spawned_entity != null:
			spawned_entity.current_surface = surface
			spawned_entity.spawn_surface = surface
			spawned_entity.global_position = world_position
			spawned_entity.z_index = surface.z * 20 + 10
		var entity_registration_result: int = runtime.register_entity(instance)
		if entity_registration_result != WorldRegistry.RegistrationError.NONE:
			instance.queue_free()
			return "Entity registration failed with code %d." % entity_registration_result
		_apply_cached_entity_ai_state(instance, spawn_id)
		return ""

	if kind == SPAWN_KIND_OBJECT:
		var objects_root: Node2D = _get_spawned_objects_root()
		instance.name = spawn_id
		if not instance.is_in_group("game_blocker"):
			instance.add_to_group("game_blocker")
		if instance is Node2D:
			instance.global_position = world_position
		objects_root.add_child(instance)
		var object_registration_result: int = runtime.register_object(instance, surface)
		if object_registration_result != WorldRegistry.RegistrationError.NONE:
			instance.queue_free()
			return "Object registration failed with code %d." % object_registration_result
		_apply_cached_object_state(instance, spawn_id)
		return ""

	instance.free()
	return "Unsupported spawn kind."


func _assign_spawn_id(instance: Node, kind: String, spawn_id: String) -> void:
	if kind == SPAWN_KIND_ENTITY and instance.get("entity_id") != null:
		instance.set("entity_id", spawn_id)
		return

	if kind == SPAWN_KIND_OBJECT and instance.get("object_id") != null:
		instance.set("object_id", spawn_id)


func _apply_cached_object_state(instance: Node, spawn_id: String) -> void:
	if not (instance is GridObject):
		return

	var cached_states: Dictionary = NetworkManager.store.get_object_states()
	if not cached_states.has(spawn_id):
		return

	(instance as GridObject).apply_network_state(int(cached_states[spawn_id]))


func _apply_cached_entity_ai_state(instance: Node, spawn_id: String) -> void:
	if not (instance is NonPlayerEntity):
		return

	var cached_states: Dictionary = NetworkManager.store.get_entity_ai_states()
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

	_apply_world_removals(NetworkManager.store.get_removed_world_items())


func apply_action_stream_snapshot(
	dynamic_spawn_records: Array[Dictionary],
	removal_records: Array[Dictionary]
) -> bool:
	return snapshot_transaction.apply(dynamic_spawn_records, removal_records)


func rollback_action_stream_snapshot_spawns() -> void:
	snapshot_transaction.rollback()


func commit_action_stream_snapshot_spawns() -> void:
	snapshot_transaction.commit()


func normalize_type_key(type_key: String) -> String:
	return _normalize_type_key(type_key)


func has_spawn_id(spawn_id: String) -> bool:
	return _has_spawn_id(spawn_id)


func assign_spawn_id(instance: Node, kind: String, spawn_id: String) -> void:
	_assign_spawn_id(instance, kind, spawn_id)


func apply_world_removals(records: Array[Dictionary]) -> void:
	_apply_world_removals(records)


func spawn_staged_instance(record: Dictionary) -> String:
	return _spawn_instance(
		record.get("instance") as Node,
		record.get("definition", {}) as Dictionary,
		str(record.get("type_key", "")),
		str(record.get("spawn_id", "")),
		record.get("surface", Vector3i.ZERO)
	)


func remove_spawn_by_id(spawn_id: String) -> void:
	var instance: Node = runtime.get_entity_by_id(spawn_id)
	if instance == null:
		instance = runtime.get_object_by_id(spawn_id)
	if instance != null:
		_remove_world_item(instance)


func _apply_cached_world_spawns() -> void:
	if not GameSession.is_multiplayer() or GameSession.is_host():
		return

	var spawn_records: Array[Dictionary] = NetworkManager.store.get_world_spawn_records()
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
	return WorldSpawnCatalog.normalize_type_key(type_key)


func _can_use_debug_commands() -> bool:
	return level != null and level.allows_debug_commands()


func _print_created(record: Dictionary) -> void:
	var surface: Vector3i = record.get("surface", Vector3i.ZERO)
	ConsoleOutput.print_console("Created %s at %d %d." % [
		str(record.get("type_key", "")),
		surface.x,
		surface.y,
	], runtime)


func _print_spawn_error(message: String) -> void:
	ConsoleOutput.print_console("ERROR: %s" % message, runtime)


func _report_spawn_error(message: String, requester_peer_id: int, reason_code: String) -> void:
	if requester_peer_id != 0 and GameSession.is_multiplayer() and GameSession.is_host():
		NetworkManager.world.send_world_spawn_failed(requester_peer_id, reason_code)
		_print_spawn_error(message)
		return

	_print_spawn_error(message)
