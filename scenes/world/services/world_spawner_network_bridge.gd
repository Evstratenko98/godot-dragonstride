class_name WorldSpawnerNetworkBridge
extends RefCounted

var spawner: WorldSpawner = null
var pending_remote_removals: Dictionary[int, Array] = {}


func configure(owner: WorldSpawner) -> void:
	spawner = owner


func connect_signals() -> void:
	if not NetworkManager.world.world_spawn_requested.is_connected(_on_world_spawn_requested):
		NetworkManager.world.world_spawn_requested.connect(_on_world_spawn_requested)
	if not NetworkManager.world.world_spawn_received.is_connected(_on_world_spawn_received):
		NetworkManager.world.world_spawn_received.connect(_on_world_spawn_received)
	if not NetworkManager.world.world_spawns_received.is_connected(_on_world_spawns_received):
		NetworkManager.world.world_spawns_received.connect(_on_world_spawns_received)
	if not NetworkManager.world.world_fill_requested.is_connected(_on_world_fill_requested):
		NetworkManager.world.world_fill_requested.connect(_on_world_fill_requested)
	if not NetworkManager.world.world_clear_requested.is_connected(_on_world_clear_requested):
		NetworkManager.world.world_clear_requested.connect(_on_world_clear_requested)
	if not NetworkManager.world.world_items_removed_received.is_connected(_on_world_items_removed_received):
		NetworkManager.world.world_items_removed_received.connect(_on_world_items_removed_received)
	if not NetworkManager.world.world_spawn_failed_received.is_connected(_on_world_spawn_failed_received):
		NetworkManager.world.world_spawn_failed_received.connect(_on_world_spawn_failed_received)


func connect_action_stream() -> void:
	if spawner.runtime.action_stream != null and not spawner.runtime.action_stream.action_started.is_connected(_on_stream_action_started):
		spawner.runtime.action_stream.action_started.connect(_on_stream_action_started)


func disconnect_signals() -> void:
	if NetworkManager.world.world_spawn_requested.is_connected(_on_world_spawn_requested):
		NetworkManager.world.world_spawn_requested.disconnect(_on_world_spawn_requested)
	if NetworkManager.world.world_spawn_received.is_connected(_on_world_spawn_received):
		NetworkManager.world.world_spawn_received.disconnect(_on_world_spawn_received)
	if NetworkManager.world.world_spawns_received.is_connected(_on_world_spawns_received):
		NetworkManager.world.world_spawns_received.disconnect(_on_world_spawns_received)
	if NetworkManager.world.world_fill_requested.is_connected(_on_world_fill_requested):
		NetworkManager.world.world_fill_requested.disconnect(_on_world_fill_requested)
	if NetworkManager.world.world_clear_requested.is_connected(_on_world_clear_requested):
		NetworkManager.world.world_clear_requested.disconnect(_on_world_clear_requested)
	if NetworkManager.world.world_items_removed_received.is_connected(_on_world_items_removed_received):
		NetworkManager.world.world_items_removed_received.disconnect(_on_world_items_removed_received)
	if NetworkManager.world.world_spawn_failed_received.is_connected(_on_world_spawn_failed_received):
		NetworkManager.world.world_spawn_failed_received.disconnect(_on_world_spawn_failed_received)
	if spawner.runtime != null and spawner.runtime.action_stream != null and spawner.runtime.action_stream.action_started.is_connected(_on_stream_action_started):
		spawner.runtime.action_stream.action_started.disconnect(_on_stream_action_started)


func clear() -> void:
	pending_remote_removals.clear()


func _on_world_spawn_requested(type_key: String, cell: Vector2i, requester_peer_id: int) -> void:
	if GameSession.is_host() and spawner._can_use_debug_commands():
		spawner._try_create_authoritative(WorldSpawnCatalog.normalize_type_key(type_key), cell, true, requester_peer_id)


func _on_world_spawn_received(record: Dictionary) -> void:
	if GameSession.is_host() or spawner.has_spawn_id(str(record.get("spawn_id", ""))):
		return
	var error: String = spawner._spawn_from_record(record, false)
	if not error.is_empty():
		spawner._print_spawn_error("Cannot apply network spawn: %s" % error)
		return
	spawner._print_created(record)


func _on_world_spawns_received(records: Array[Dictionary]) -> void:
	if not GameSession.is_host():
		spawner._apply_world_spawns(records, "network")


func _on_world_fill_requested(type_key: String, requester_peer_id: int) -> void:
	if GameSession.is_host() and spawner._can_use_debug_commands():
		spawner.batch_operator.fill(WorldSpawnCatalog.normalize_type_key(type_key), requester_peer_id)


func _on_world_clear_requested(type_key: String, requester_peer_id: int) -> void:
	if GameSession.is_host() and spawner._can_use_debug_commands():
		spawner.batch_operator.clear(WorldSpawnCatalog.normalize_type_key(type_key), requester_peer_id)


func _on_world_items_removed_received(sequence_id: int, records: Array[Dictionary]) -> void:
	if GameSession.is_host():
		return
	if sequence_id > 0 and spawner.runtime.get_current_action_sequence_id() != sequence_id:
		var expected_sequence_id: int = spawner.runtime.get_expected_remote_action_sequence_id()
		if sequence_id < expected_sequence_id:
			return
		if sequence_id - expected_sequence_id > NetworkProtocol.MAX_FUTURE_SEQUENCE_DISTANCE or pending_remote_removals.size() >= NetworkProtocol.MAX_BUFFERED_SEQUENCES:
			spawner.runtime.action_stream.request_runtime_resync(WorldActionStream.REJECTION_SEQUENCE_GAP)
			return
		pending_remote_removals[sequence_id] = records.duplicate(true)
		return
	spawner._apply_world_removals(records)


func _on_stream_action_started(action: WorldActionRecord) -> void:
	if action == null or not pending_remote_removals.has(action.sequence_id):
		return
	var records: Array = pending_remote_removals[action.sequence_id]
	pending_remote_removals.erase(action.sequence_id)
	var typed_records: Array[Dictionary] = []
	for record_value: Variant in records:
		if record_value is Dictionary:
			typed_records.append(record_value as Dictionary)
	spawner._apply_world_removals(typed_records)


func _on_world_spawn_failed_received(reason_code: String) -> void:
	spawner._print_spawn_error(str(WorldSpawnCatalog.FAILURE_MESSAGES.get(reason_code, "Spawn operation failed.")))
