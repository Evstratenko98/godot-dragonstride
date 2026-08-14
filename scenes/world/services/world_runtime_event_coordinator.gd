class_name WorldRuntimeEventCoordinator
extends RefCounted

var runtime: WorldRuntime = null


func configure(owner: WorldRuntime) -> void:
	runtime = owner


func connect_service_signals() -> void:
	if runtime == null:
		return
	if runtime.registry != null and not runtime.registry.occupancy_changed.is_connected(on_registry_occupancy_changed):
		runtime.registry.occupancy_changed.connect(on_registry_occupancy_changed)
	if runtime.network != null and not runtime.network.match_end_requested.is_connected(on_network_match_end_requested):
		runtime.network.match_end_requested.connect(on_network_match_end_requested)
	if runtime.players_service != null and not runtime.players_service.player_connection_changed.is_connected(on_player_connection_changed):
		runtime.players_service.player_connection_changed.connect(on_player_connection_changed)
	if runtime.players_service != null and not runtime.players_service.selected_local_character_changed.is_connected(on_selected_local_character_changed):
		runtime.players_service.selected_local_character_changed.connect(on_selected_local_character_changed)


func connect_runtime_signals() -> void:
	if runtime == null:
		return
	if runtime.network != null:
		runtime.network.connect_signals()
	if runtime.action_stream != null and not runtime.action_stream.runtime_sync_failed.is_connected(on_action_stream_sync_failed):
		runtime.action_stream.runtime_sync_failed.connect(on_action_stream_sync_failed)
	if runtime.action_stream != null and not runtime.action_stream.sync_state_changed.is_connected(on_action_stream_sync_state_changed):
		runtime.action_stream.sync_state_changed.connect(on_action_stream_sync_state_changed)


func disconnect_runtime_signals() -> void:
	if runtime == null:
		return
	if runtime.network != null:
		runtime.network.disconnect_signals()
	if runtime.action_stream != null and runtime.action_stream.runtime_sync_failed.is_connected(on_action_stream_sync_failed):
		runtime.action_stream.runtime_sync_failed.disconnect(on_action_stream_sync_failed)
	if runtime.action_stream != null and runtime.action_stream.sync_state_changed.is_connected(on_action_stream_sync_state_changed):
		runtime.action_stream.sync_state_changed.disconnect(on_action_stream_sync_state_changed)


func register_level_entities() -> void:
	if runtime.level == null:
		return
	var world_entities_root: Node = runtime.level.get_world_entities_root()
	if world_entities_root != null:
		_register_world_entity_children(world_entities_root)


func on_network_match_end_requested() -> void:
	runtime.match_end_requested.emit()


func on_action_stream_sync_failed(reason_code: String) -> void:
	runtime.runtime_sync_failed.emit(reason_code)


func on_action_stream_sync_state_changed(is_synchronizing: bool) -> void:
	for player: PlayerCharacter in runtime.get_local_squad_members():
		player.can_receive_input = not is_synchronizing and GameSession.has_committed_match()


func on_selected_local_character_changed(_previous_character: PlayerCharacter, selected_character: PlayerCharacter) -> void:
	runtime.selected_local_character_changed.emit(selected_character)


func on_player_connection_changed(steam_id: int, is_connected: bool) -> void:
	if is_connected or not GameSession.is_host():
		return
	if runtime.action_stream != null:
		runtime.action_stream.cancel_actions_for_steam_id(steam_id)
		runtime.action_stream.prune_disconnected_snapshot_peers()
	if runtime.turn_manager != null:
		runtime.turn_manager.handle_player_disconnected(steam_id)


func on_registry_occupancy_changed() -> void:
	runtime.world_occupancy_changed.emit()


func _register_world_entity_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		if child.get("entity_type") != null and int(child.get("entity_type")) != Entity.EntityType.CHARACTER:
			_ensure_world_entity_id(child)
			runtime.register_entity(child)
		_register_world_entity_children(child)


func _ensure_world_entity_id(entity: Node) -> void:
	if entity.get("entity_id") != null and str(entity.get("entity_id")).is_empty():
		entity.set("entity_id", entity.name)
