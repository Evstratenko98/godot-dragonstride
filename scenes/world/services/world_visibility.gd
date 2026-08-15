class_name WorldVisibility
extends Node

signal local_visibility_changed(changed_surfaces: Array[Vector3i], full_refresh: bool)
signal fog_enabled_changed(is_enabled: bool)

enum VisibilityMode {
	HIDDEN,
	EXPLORED,
	VISIBLE,
}

const CHARACTER_SOURCE_PREFIX: String = "character:"

var runtime: WorldRuntime = null
var level: WorldLevel = null
var fog_enabled: bool = true
var solver: WorldVisionSolver = WorldVisionSolver.new()
var source_ledger: WorldVisibilitySourceLedger = WorldVisibilitySourceLedger.new()
var memory_store: WorldVisibilityObjectMemoryStore = WorldVisibilityObjectMemoryStore.new()
var character_sources: WorldVisibilityCharacterSourceCoordinator = WorldVisibilityCharacterSourceCoordinator.new()
var object_changes: WorldVisibilityObjectChangeCoordinator = WorldVisibilityObjectChangeCoordinator.new()
var surface_catalog: WorldVisibilitySurfaceCatalog = WorldVisibilitySurfaceCatalog.new()
var tower_sources: WorldVisibilityTowerSourceCoordinator = WorldVisibilityTowerSourceCoordinator.new()
var explored_by_player: Dictionary[String, Dictionary] = {}
var blocker_cells: Dictionary[Vector2i, bool] = {}
var recompute_pending: bool = false
var object_memories_by_player: Dictionary[String, Dictionary]:
	get:
		return memory_store.memories_by_player
	set(value):
		memory_store.replace_all(value)
var surface_order: Array[Vector3i]:
	get:
		return surface_catalog.surface_order
var display_surfaces: Array[Vector3i]:
	get:
		return surface_catalog.display_surfaces
var display_surface_by_cell: Dictionary[Vector2i, Vector3i]:
	get:
		return surface_catalog.display_surface_by_cell
var surface_index_by_surface: Dictionary[Vector3i, int]:
	get:
		return surface_catalog.surface_index_by_surface


func configure_context(new_runtime: WorldRuntime, new_level: WorldLevel) -> void:
	_disconnect_runtime_signals()
	runtime = new_runtime
	level = new_level
	fog_enabled = bool(GameSession.get_match_setting(GameSession.MATCH_SETTING_FOG_OF_WAR, true))
	surface_catalog.configure(runtime)
	explored_by_player.clear()
	source_ledger.configure(surface_index_by_surface, surface_order.size())
	tower_sources.configure(runtime, source_ledger)
	memory_store.configure(runtime)
	solver.configure(runtime.grid if runtime != null else null)
	_connect_runtime_signals()
	request_recompute()


func _exit_tree() -> void:
	_disconnect_runtime_signals()


func request_recompute() -> void:
	if recompute_pending or runtime == null:
		return
	recompute_pending = true
	_recompute_visibility.call_deferred(true)


func execute_set_fog_enabled(is_enabled: bool) -> bool:
	if fog_enabled == is_enabled:
		return true
	fog_enabled = is_enabled
	GameSession.set_match_setting(GameSession.MATCH_SETTING_FOG_OF_WAR, fog_enabled)
	_recompute_visibility()
	fog_enabled_changed.emit(fog_enabled)
	return true


func get_visibility_mode(player_id: String, surface: Vector3i) -> VisibilityMode:
	if not fog_enabled:
		return VisibilityMode.VISIBLE
	if source_ledger.get_visible_surfaces(player_id).has(surface):
		return VisibilityMode.VISIBLE
	var explored: Dictionary = explored_by_player.get(player_id, {}) as Dictionary
	return VisibilityMode.EXPLORED if explored.has(surface) else VisibilityMode.HIDDEN


func get_local_visibility_mode(surface: Vector3i) -> VisibilityMode:
	return get_visibility_mode(get_local_player_id(), surface)


func is_surface_visible_for_player(player_id: String, surface: Vector3i) -> bool:
	return not fog_enabled or source_ledger.get_visible_surfaces(player_id).has(surface)


func is_surface_visible_for_character(character: PlayerCharacter, surface: Vector3i) -> bool:
	return character != null and is_surface_visible_for_player(character.owner_player_id, surface)


func is_surface_visible_for_local_player(surface: Vector3i) -> bool:
	return is_surface_visible_for_player(get_local_player_id(), surface)


func get_object_visibility_mode(player_id: String, grid_object: GridObject) -> VisibilityMode:
	if grid_object == null:
		return VisibilityMode.HIDDEN
	var best_mode: VisibilityMode = VisibilityMode.HIDDEN
	var anchor: Vector3i = runtime.spatial.get_object_anchor_surface(grid_object)
	for surface: Vector3i in grid_object.get_occupied_surfaces(anchor):
		var mode: VisibilityMode = get_visibility_mode(player_id, surface)
		if mode == VisibilityMode.VISIBLE:
			return mode
		if mode == VisibilityMode.EXPLORED:
			best_mode = mode
	return best_mode


func get_local_player_id() -> String:
	return str(GameSession.get_local_player_record().get("player_id", ""))


func get_valid_player_ids() -> Dictionary[String, bool]:
	var result: Dictionary[String, bool] = {}
	for player: Dictionary in GameSession.get_players():
		var player_id: String = str(player.get("player_id", ""))
		if not player_id.is_empty():
			result[player_id] = true
	return result


func get_object_memories(player_id: String) -> Dictionary:
	return memory_store.get_player_memories(player_id)


func get_object_memories_for_surfaces(player_id: String, surfaces: Array[Vector3i]) -> Dictionary:
	return memory_store.get_player_memories_for_surfaces(player_id, surfaces)


func has_object_memory(player_id: String, object_id: String) -> bool:
	return memory_store.has_player_memory(player_id, object_id)


func notify_object_state_changed(grid_object: GridObject) -> void:
	if grid_object == null or runtime == null:
		return
	var anchor: Vector3i = runtime.spatial.get_object_anchor_surface(grid_object)
	notify_object_surfaces_changed(grid_object.get_occupied_surfaces(anchor))


func notify_object_surfaces_changed(affected_surfaces: Array[Vector3i]) -> void:
	if runtime == null or affected_surfaces.is_empty():
		return
	for player_id: String in get_valid_player_ids().keys():
		var memory_visible_surfaces: Dictionary = (
			source_ledger.get_visible_surfaces(player_id)
			if fog_enabled
			else explored_by_player.get(player_id, {}) as Dictionary
		)
		memory_store.update_player_for_surfaces(
			player_id,
			memory_visible_surfaces,
			affected_surfaces
		)
	_emit_local_changes(affected_surfaces, false)


func is_surface_blocked_on_known_map(player_id: String, surface: Vector3i) -> bool:
	if is_surface_visible_for_player(player_id, surface):
		return runtime.get_object_at_surface(surface) != null
	return memory_store.has_remembered_object_at_surface(player_id, surface)


func capture_tower(tower: VisionTower, interactor: PlayerCharacter) -> bool:
	var transfer: Dictionary = tower_sources.transfer_source(tower, interactor)
	if transfer.is_empty():
		return false
	var local_player_id: String = get_local_player_id()
	var local_dirty: Dictionary[Vector3i, bool] = {}
	var previous_owner_player_id: String = str(transfer.get("previous_player_id", ""))
	var removed_surfaces: Array[Vector3i] = transfer.get("previous_dirty_surfaces", []) as Array[Vector3i]
	_commit_player_changes(previous_owner_player_id, removed_surfaces, false)
	if previous_owner_player_id == local_player_id:
		_merge_dirty_surfaces(local_dirty, removed_surfaces)
	var next_owner_player_id: String = str(transfer.get("next_player_id", ""))
	var added_surfaces: Array[Vector3i] = transfer.get("next_dirty_surfaces", []) as Array[Vector3i]
	_commit_player_changes(next_owner_player_id, added_surfaces, false)
	if next_owner_player_id == local_player_id:
		_merge_dirty_surfaces(local_dirty, added_surfaces)
	_emit_local_changes(_get_surface_keys(local_dirty), false)
	return true


func create_snapshot() -> Dictionary:
	return WorldVisibilitySnapshotCodec.create_snapshot(self)


func is_valid_snapshot(
	snapshot: Dictionary,
	additional_tower_ids: Dictionary[String, bool] = {},
	should_require_exact_tower_count: bool = true
) -> bool:
	return WorldVisibilitySnapshotCodec.is_valid_snapshot(
		self,
		snapshot,
		additional_tower_ids,
		should_require_exact_tower_count
	)


func apply_snapshot(snapshot: Dictionary) -> bool:
	return WorldVisibilitySnapshotCodec.apply_snapshot(self, snapshot)


func _recompute_visibility(from_deferred: bool = false) -> void:
	if from_deferred and not recompute_pending:
		return
	recompute_pending = false
	if runtime == null or not is_instance_valid(runtime):
		return
	character_sources.configure(runtime)
	_rebuild_blocker_cache()
	source_ledger.configure(surface_index_by_surface, surface_order.size())
	tower_sources.configure(runtime, source_ledger)
	var player_ids: Dictionary[String, bool] = get_valid_player_ids()
	for player_id: String in player_ids.keys():
		source_ledger.ensure_player(player_id)
	if fog_enabled:
		for character: PlayerCharacter in character_sources.bound_characters:
			_add_character_source_without_notifications(character)
		tower_sources.add_registered_sources()
		for player_id: String in player_ids.keys():
			_merge_surface_set(
				explored_by_player.get_or_add(player_id, {}) as Dictionary,
				source_ledger.get_visible_surfaces(player_id)
			)
	else:
		_mark_everything_explored()
	for player_id: String in player_ids.keys():
		var memory_visible_surfaces: Dictionary = (
			source_ledger.get_visible_surfaces(player_id)
			if fog_enabled
			else explored_by_player.get(player_id, {}) as Dictionary
		)
		memory_store.rebuild_player(player_id, memory_visible_surfaces)
	_emit_local_changes([], true)


func _refresh_character_source(character: PlayerCharacter) -> void:
	if character == null or not is_instance_valid(character) or not fog_enabled:
		return
	var source_id: String = _get_character_source_id(character)
	var previous_player_id: String = source_ledger.get_source_player_id(source_id)
	if not previous_player_id.is_empty() and previous_player_id != character.owner_player_id:
		var previous_dirty_surfaces: Array[Vector3i] = source_ledger.remove_source(source_id)
		_commit_player_changes(previous_player_id, previous_dirty_surfaces, true)
	var dirty_surfaces: Array[Vector3i] = []
	if character.health <= 0 or character.owner_player_id.is_empty():
		dirty_surfaces = source_ledger.remove_source(source_id)
	else:
		dirty_surfaces = source_ledger.replace_source(
			source_id,
			character.owner_player_id,
			solver.calculate_visible_surfaces(character.current_surface, character.vision_radius, blocker_cells)
		)
	_commit_player_changes(character.owner_player_id, dirty_surfaces, true)


func _remove_character_source(character: PlayerCharacter) -> void:
	if character == null:
		return
	var source_id: String = _get_character_source_id(character)
	var player_id: String = source_ledger.get_source_player_id(source_id)
	var dirty_surfaces: Array[Vector3i] = source_ledger.remove_source(source_id)
	_commit_player_changes(player_id, dirty_surfaces, true)


func _add_character_source_without_notifications(character: PlayerCharacter) -> void:
	if character == null or character.health <= 0 or character.owner_player_id.is_empty():
		return
	source_ledger.replace_source(
		_get_character_source_id(character),
		character.owner_player_id,
		solver.calculate_visible_surfaces(character.current_surface, character.vision_radius, blocker_cells)
	)


func _commit_player_changes(
	player_id: String,
	dirty_surfaces: Array[Vector3i],
	should_emit: bool
) -> void:
	if player_id.is_empty() or dirty_surfaces.is_empty():
		return
	var visible_surfaces: Dictionary = source_ledger.get_visible_surfaces(player_id)
	var explored: Dictionary = explored_by_player.get_or_add(player_id, {}) as Dictionary
	for surface: Vector3i in dirty_surfaces:
		if visible_surfaces.has(surface):
			explored[surface] = true
	memory_store.update_player_for_surfaces(player_id, visible_surfaces, dirty_surfaces)
	if should_emit and player_id == get_local_player_id():
		_emit_local_changes(dirty_surfaces, false)


func _rebuild_blocker_cache() -> void:
	blocker_cells.clear()
	for object_value: Variant in runtime.get_registered_objects():
		var grid_object: GridObject = object_value as GridObject
		if grid_object == null or not grid_object.blocks_vision:
			continue
		var anchor: Vector3i = runtime.spatial.get_object_anchor_surface(grid_object)
		for surface: Vector3i in grid_object.get_occupied_surfaces(anchor):
			blocker_cells[Vector2i(surface.x, surface.y)] = true


func _mark_everything_explored() -> void:
	for player_id: String in get_valid_player_ids().keys():
		var explored: Dictionary[Vector3i, bool] = {}
		for surface: Vector3i in surface_order:
			explored[surface] = true
		explored_by_player[player_id] = explored


func _merge_surface_set(target: Dictionary, source: Dictionary) -> void:
	for surface_value: Variant in source.keys():
		if surface_value is Vector3i:
			target[surface_value as Vector3i] = true


func _merge_dirty_surfaces(target: Dictionary[Vector3i, bool], source: Array[Vector3i]) -> void:
	for surface: Vector3i in source:
		target[surface] = true


func _get_surface_keys(surfaces: Dictionary[Vector3i, bool]) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for surface: Vector3i in surfaces.keys():
		result.append(surface)
	return result


func _emit_local_changes(changed_surfaces: Array[Vector3i], full_refresh: bool) -> void:
	local_visibility_changed.emit(changed_surfaces, full_refresh)


func _get_character_source_id(character: PlayerCharacter) -> String:
	return CHARACTER_SOURCE_PREFIX + character.entity_id


func _connect_runtime_signals() -> void:
	if not character_sources.refresh_requested.is_connected(_refresh_character_source):
		character_sources.refresh_requested.connect(_refresh_character_source)
	if not character_sources.removal_requested.is_connected(_remove_character_source):
		character_sources.removal_requested.connect(_remove_character_source)
	if not object_changes.visibility_structure_changed.is_connected(request_recompute):
		object_changes.visibility_structure_changed.connect(request_recompute)
	if not object_changes.object_surfaces_changed.is_connected(notify_object_surfaces_changed):
		object_changes.object_surfaces_changed.connect(notify_object_surfaces_changed)
	character_sources.configure(runtime)
	object_changes.configure(runtime)
	if not GameSession.session_cleared.is_connected(_on_session_cleared):
		GameSession.session_cleared.connect(_on_session_cleared)


func _disconnect_runtime_signals() -> void:
	character_sources.disconnect_signals()
	object_changes.disconnect_signals()
	if GameSession.session_cleared.is_connected(_on_session_cleared):
		GameSession.session_cleared.disconnect(_on_session_cleared)


func _on_session_cleared() -> void:
	_disconnect_runtime_signals()
	recompute_pending = false
	explored_by_player.clear()
	blocker_cells.clear()
	tower_sources.clear()
	surface_catalog.clear()
	source_ledger.clear()
	memory_store.clear()
	solver.configure(null)
	runtime = null
	level = null
