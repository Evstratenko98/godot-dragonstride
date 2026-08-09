class_name WorldVisibility
extends Node

signal local_visibility_changed
signal fog_enabled_changed(is_enabled: bool)

enum VisibilityMode {
	HIDDEN,
	EXPLORED,
	VISIBLE,
}

var runtime: WorldRuntime = null
var level: WorldLevel = null
var fog_enabled: bool = true
var solver: WorldVisionSolver = WorldVisionSolver.new()
var surface_order: Array[Vector3i] = []
var display_surfaces: Array[Vector3i] = []
var surface_index_by_surface: Dictionary[Vector3i, int] = {}
var visible_by_player: Dictionary[String, Dictionary] = {}
var explored_by_player: Dictionary[String, Dictionary] = {}
var object_memories_by_player: Dictionary[String, Dictionary] = {}
var blocker_cells: Dictionary[Vector2i, bool] = {}
var recompute_pending: bool = false
var bound_characters: Array[PlayerCharacter] = []


func configure_context(new_runtime: WorldRuntime, new_level: WorldLevel) -> void:
	_disconnect_runtime_signals()
	runtime = new_runtime
	level = new_level
	fog_enabled = bool(GameSession.get_match_setting(GameSession.MATCH_SETTING_FOG_OF_WAR, true))
	surface_order = _build_visibility_surface_order()
	surface_index_by_surface.clear()
	display_surfaces.clear()
	var display_surface_by_cell: Dictionary[Vector2i, Vector3i] = {}
	for index: int in range(surface_order.size()):
		var surface: Vector3i = surface_order[index]
		surface_index_by_surface[surface] = index
		var cell: Vector2i = Vector2i(surface.x, surface.y)
		if not display_surface_by_cell.has(cell) or surface.z > (display_surface_by_cell[cell] as Vector3i).z:
			display_surface_by_cell[cell] = surface
	for surface: Vector3i in display_surface_by_cell.values():
		display_surfaces.append(surface)
	display_surfaces.sort_custom(func(first: Vector3i, second: Vector3i) -> bool:
		return first.y < second.y if first.y != second.y else first.x < second.x
	)
	visible_by_player.clear()
	explored_by_player.clear()
	object_memories_by_player.clear()
	solver.configure(runtime.grid if runtime != null else null)
	_connect_runtime_signals()
	request_recompute()


func _build_visibility_surface_order() -> Array[Vector3i]:
	var result: Array[Vector3i] = [] if runtime == null else runtime.get_all_surfaces()
	var known_surfaces: Dictionary[Vector3i, bool] = {}
	for surface: Vector3i in result:
		known_surfaces[surface] = true
	if runtime != null:
		var grid_size: Vector2i = runtime.get_grid_size()
		for y: int in range(grid_size.y):
			for x: int in range(grid_size.x):
				var base_surface: Vector3i = Vector3i(x, y, WorldGridTopology.MIN_ELEVATION)
				if not known_surfaces.has(base_surface):
					known_surfaces[base_surface] = true
					result.append(base_surface)
	result.sort_custom(func(first: Vector3i, second: Vector3i) -> bool:
		if first.y != second.y:
			return first.y < second.y
		if first.x != second.x:
			return first.x < second.x
		return first.z < second.z
	)
	if result.size() > WorldGridTopology.MAX_SURFACES:
		push_error("Visibility surface limit exceeded: %d" % result.size())
		result.clear()
	return result


func _exit_tree() -> void:
	_disconnect_runtime_signals()


func request_recompute() -> void:
	if recompute_pending or runtime == null:
		return
	recompute_pending = true
	call_deferred("_recompute_visibility", true)


func execute_set_fog_enabled(is_enabled: bool) -> bool:
	if fog_enabled == is_enabled:
		return true
	fog_enabled = is_enabled
	GameSession.set_match_setting(GameSession.MATCH_SETTING_FOG_OF_WAR, fog_enabled)
	if not fog_enabled:
		_mark_everything_explored()
	_recompute_visibility()
	fog_enabled_changed.emit(fog_enabled)
	return true


func get_visibility_mode(player_id: String, surface: Vector3i) -> VisibilityMode:
	if not fog_enabled:
		return VisibilityMode.VISIBLE
	var visible: Dictionary = visible_by_player.get(player_id, {}) as Dictionary
	if visible.has(surface):
		return VisibilityMode.VISIBLE
	var explored: Dictionary = explored_by_player.get(player_id, {}) as Dictionary
	return VisibilityMode.EXPLORED if explored.has(surface) else VisibilityMode.HIDDEN


func get_local_visibility_mode(surface: Vector3i) -> VisibilityMode:
	return get_visibility_mode(get_local_player_id(), surface)


func is_surface_visible_for_player(player_id: String, surface: Vector3i) -> bool:
	return not fog_enabled or (visible_by_player.get(player_id, {}) as Dictionary).has(surface)


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
	return (object_memories_by_player.get(player_id, {}) as Dictionary).duplicate(true)


func is_surface_blocked_on_known_map(player_id: String, surface: Vector3i) -> bool:
	if is_surface_visible_for_player(player_id, surface):
		return runtime.get_object_at_surface(surface) != null
	var memories: Dictionary = object_memories_by_player.get(player_id, {}) as Dictionary
	for memory_value: Variant in memories.values():
		if not (memory_value is Dictionary):
			continue
		var memory: Dictionary = memory_value as Dictionary
		if surface in (memory.get("occupied_surfaces", [memory.get("surface")]) as Array):
			return true
	return false


func capture_tower(tower: VisionTower, interactor: PlayerCharacter) -> bool:
	if tower == null or interactor == null or interactor.owner_player_id.is_empty():
		return false
	if tower.owner_player_id == interactor.owner_player_id:
		return false
	tower.apply_owner_player_id(interactor.owner_player_id)
	_recompute_visibility()
	return true


func create_snapshot() -> Dictionary:
	return WorldVisibilitySnapshotCodec.create_snapshot(self)


func is_valid_snapshot(snapshot: Dictionary, additional_tower_ids: Dictionary[String, bool] = {}) -> bool:
	return WorldVisibilitySnapshotCodec.is_valid_snapshot(self, snapshot, additional_tower_ids)


func apply_snapshot(snapshot: Dictionary) -> bool:
	return WorldVisibilitySnapshotCodec.apply_snapshot(self, snapshot)


func _recompute_visibility(from_deferred: bool = false) -> void:
	if from_deferred and not recompute_pending:
		return
	recompute_pending = false
	if runtime == null or not is_instance_valid(runtime):
		return
	_rebind_character_signals()
	_rebuild_blocker_cache()
	var next_visible: Dictionary[String, Dictionary] = {}
	for player_id: String in get_valid_player_ids().keys():
		var player_visible: Dictionary[Vector3i, bool] = {}
		if not fog_enabled:
			for surface: Vector3i in surface_order:
				player_visible[surface] = true
		else:
			for character: PlayerCharacter in runtime.get_squad_members(player_id):
				if character.health > 0:
					_merge_surface_set(player_visible, solver.calculate_visible_surfaces(
						character.current_surface,
						character.vision_radius,
						blocker_cells
					))
			for object_value: Variant in runtime.get_registered_objects():
				var tower: VisionTower = object_value as VisionTower
				if tower != null and tower.owner_player_id == player_id:
					var tower_surface: Vector3i = runtime.spatial.get_object_anchor_surface(tower)
					_merge_surface_set(player_visible, solver.calculate_visible_surfaces(
						tower_surface,
						tower.vision_radius,
						blocker_cells,
						true
					))
		next_visible[player_id] = player_visible
		var explored: Dictionary = explored_by_player.get(player_id, {}) as Dictionary
		_merge_surface_set(explored, player_visible)
		explored_by_player[player_id] = explored
		_update_object_memories(player_id, player_visible)
	visible_by_player = next_visible
	local_visibility_changed.emit()


func _rebuild_blocker_cache() -> void:
	blocker_cells.clear()
	for object_value: Variant in runtime.get_registered_objects():
		var grid_object: GridObject = object_value as GridObject
		if grid_object == null or not grid_object.blocks_vision:
			continue
		var anchor: Vector3i = runtime.spatial.get_object_anchor_surface(grid_object)
		for surface: Vector3i in grid_object.get_occupied_surfaces(anchor):
			blocker_cells[Vector2i(surface.x, surface.y)] = true


func _update_object_memories(player_id: String, player_visible: Dictionary) -> void:
	var memories: Dictionary = object_memories_by_player.get(player_id, {}) as Dictionary
	var live_object_ids: Dictionary[String, bool] = {}
	for object_value: Variant in runtime.get_registered_objects():
		var grid_object: GridObject = object_value as GridObject
		if grid_object == null or grid_object.object_id.is_empty():
			continue
		live_object_ids[grid_object.object_id] = true
		var surface: Vector3i = runtime.spatial.get_object_anchor_surface(grid_object)
		var is_any_surface_visible: bool = false
		for occupied_surface: Vector3i in grid_object.get_occupied_surfaces(surface):
			if player_visible.has(occupied_surface):
				is_any_surface_visible = true
				break
		if not is_any_surface_visible:
			continue
		var owner_player_id: String = ""
		if grid_object is VisionTower:
			owner_player_id = (grid_object as VisionTower).owner_player_id
		memories[grid_object.object_id] = {
			"surface": surface,
			"occupied_surfaces": grid_object.get_occupied_surfaces(surface),
			"object_state": int(grid_object.object_state),
			"owner_player_id": owner_player_id,
			"texture_path": "" if grid_object.sprite == null or grid_object.sprite.texture == null else grid_object.sprite.texture.resource_path,
			"sprite_position": Vector2.ZERO if grid_object.sprite == null else grid_object.sprite.position,
			"sprite_scale": Vector2.ONE if grid_object.sprite == null else grid_object.sprite.scale,
			"sprite_offset": Vector2.ZERO if grid_object.sprite == null else grid_object.sprite.offset,
			"sprite_modulate": Color.WHITE if grid_object.sprite == null else grid_object.sprite.modulate,
			"sprite_centered": true if grid_object.sprite == null else grid_object.sprite.centered,
		}
	for object_id_value: Variant in memories.keys():
		var object_id: String = str(object_id_value)
		if live_object_ids.has(object_id):
			continue
		var memory: Dictionary = memories[object_id_value] as Dictionary
		for remembered_surface_value: Variant in memory.get("occupied_surfaces", [memory.get("surface")]) as Array:
			if remembered_surface_value is Vector3i and player_visible.has(remembered_surface_value as Vector3i):
				memories.erase(object_id_value)
				break
	object_memories_by_player[player_id] = memories


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


func _connect_runtime_signals() -> void:
	if runtime != null and not runtime.world_occupancy_changed.is_connected(request_recompute):
		runtime.world_occupancy_changed.connect(request_recompute)
	if not GameSession.session_cleared.is_connected(_on_session_cleared):
		GameSession.session_cleared.connect(_on_session_cleared)


func _disconnect_runtime_signals() -> void:
	if runtime != null and runtime.world_occupancy_changed.is_connected(request_recompute):
		runtime.world_occupancy_changed.disconnect(request_recompute)
	if GameSession.session_cleared.is_connected(_on_session_cleared):
		GameSession.session_cleared.disconnect(_on_session_cleared)
	for character: PlayerCharacter in bound_characters:
		if is_instance_valid(character) and character.vision_radius_changed.is_connected(_on_vision_radius_changed):
			character.vision_radius_changed.disconnect(_on_vision_radius_changed)
		if is_instance_valid(character) and character.vitality_changed.is_connected(_on_vitality_changed):
			character.vitality_changed.disconnect(_on_vitality_changed)
	bound_characters.clear()


func _rebind_character_signals() -> void:
	for character: PlayerCharacter in bound_characters:
		if is_instance_valid(character) and character.vision_radius_changed.is_connected(_on_vision_radius_changed):
			character.vision_radius_changed.disconnect(_on_vision_radius_changed)
		if is_instance_valid(character) and character.vitality_changed.is_connected(_on_vitality_changed):
			character.vitality_changed.disconnect(_on_vitality_changed)
	bound_characters.clear()
	for player: Dictionary in GameSession.get_players():
		for character: PlayerCharacter in runtime.get_squad_members(str(player.get("player_id", ""))):
			bound_characters.append(character)
			if not character.vision_radius_changed.is_connected(_on_vision_radius_changed):
				character.vision_radius_changed.connect(_on_vision_radius_changed)
			if not character.vitality_changed.is_connected(_on_vitality_changed):
				character.vitality_changed.connect(_on_vitality_changed)


func _on_vision_radius_changed(_current_radius: int) -> void:
	request_recompute()


func _on_vitality_changed(_current_health: int, _maximum_health: int) -> void:
	request_recompute()


func _on_session_cleared() -> void:
	_disconnect_runtime_signals()
	recompute_pending = false
	visible_by_player.clear()
	explored_by_player.clear()
	object_memories_by_player.clear()
	blocker_cells.clear()
	surface_order.clear()
	display_surfaces.clear()
	surface_index_by_surface.clear()
	solver.configure(null)
	runtime = null
	level = null
