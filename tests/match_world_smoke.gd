extends Node

const MATCH_SCENE := preload("res://scenes/world/match_world.tscn")
const LEVEL_IDS: PackedStringArray = ["full_world", "level_1"]

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for level_id: String in LEVEL_IDS:
		await _run_level(level_id)

	if failures.is_empty():
		print("Match world smoke test passed for: " + ", ".join(LEVEL_IDS))
		get_tree().quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	get_tree().quit(1)


func _run_level(level_id: String) -> void:
	GameSession.start_singleplayer({"level_id": level_id})
	var match_world: Node = MATCH_SCENE.instantiate()
	add_child(match_world)

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var controller: MatchController = match_world.get_node("MatchController") as MatchController
	var runtime: WorldRuntime = match_world.get_node("WorldRuntime") as WorldRuntime
	if controller == null or controller.level == null:
		failures.append("Level was not loaded: " + level_id)
	elif controller.level.get_definition() == null:
		failures.append("Level definition is missing: " + level_id)
	elif controller.level.get_definition().level_id != level_id:
		failures.append("Unexpected level definition for: " + level_id)

	if runtime == null or controller == null or not runtime.is_configured_for(controller.level):
		failures.append("Runtime was not configured for: " + level_id)
	elif runtime.get_local_player() == null:
		failures.append("Local player was not spawned for: " + level_id)
	else:
		_validate_level_runtime(level_id, runtime, controller.level)
		if level_id == "level_1":
			await _validate_level_movement(runtime)

	remove_child(match_world)
	match_world.free()
	GameSession.clear()
	await get_tree().process_frame


func _validate_level_runtime(level_id: String, runtime: WorldRuntime, level: WorldLevel) -> void:
	if runtime.get_grid_size() != level.get_grid_size():
		failures.append("Runtime grid size differs from level definition: " + level_id)

	var local_player: PlayerCharacter = runtime.get_local_player()
	if local_player != null and not runtime.is_cell_walkable_for_character(local_player.current_cell):
		var ground: TileMapLayer = level.get_node_or_null("Ground") as TileMapLayer
		var used_cells: Array[Vector2i] = ground.get_used_cells() if ground != null else []
		failures.append("Player spawned outside a walkable cell: %s at %s; configured spawns: %s; used cells: %s" % [
			level_id,
			str(local_player.current_cell),
			str(level.get_spawn_cells()),
			str(used_cells),
		])

	if level_id == "full_world":
		if runtime.get_object_by_id("house_1") == null or runtime.get_object_by_id("tree_2") == null:
			failures.append("Placed full_world objects were not registered")
		if runtime.get_entity_by_id("Sheep3") == null or runtime.get_entity_by_id("Warrior") == null:
			failures.append("Placed full_world NPCs were not registered")


func _validate_level_movement(runtime: WorldRuntime) -> void:
	var local_player: PlayerCharacter = runtime.get_local_player()
	if local_player == null:
		return

	if not local_player.request_move(Vector2i.RIGHT):
		failures.append("Player could not start moving on level_1")
		return

	await get_tree().create_timer(0.3).timeout
	if local_player.current_cell != Vector2i(9, 0):
		failures.append("Player did not complete movement on level_1")
