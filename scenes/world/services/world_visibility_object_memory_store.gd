class_name WorldVisibilityObjectMemoryStore
extends RefCounted

var runtime: WorldRuntime = null
var memories_by_player: Dictionary[String, Dictionary] = {}
var memory_ids_by_surface_by_player: Dictionary[String, Dictionary] = {}


func configure(new_runtime: WorldRuntime) -> void:
	runtime = new_runtime
	memories_by_player.clear()
	memory_ids_by_surface_by_player.clear()


func clear() -> void:
	memories_by_player.clear()
	memory_ids_by_surface_by_player.clear()
	runtime = null


func replace_all(next_memories: Dictionary) -> void:
	memories_by_player.clear()
	memory_ids_by_surface_by_player.clear()
	for player_id_value: Variant in next_memories.keys():
		if player_id_value is String and next_memories[player_id_value] is Dictionary:
			var player_id: String = player_id_value as String
			var memories: Dictionary = (next_memories[player_id_value] as Dictionary).duplicate(true)
			memories_by_player[player_id] = memories
			_rebuild_player_surface_index(player_id, memories)


func get_player_memories(player_id: String) -> Dictionary:
	return (memories_by_player.get(player_id, {}) as Dictionary).duplicate(true)


func get_player_memories_for_surfaces(player_id: String, surfaces: Array[Vector3i]) -> Dictionary:
	var result: Dictionary = {}
	var memories: Dictionary = memories_by_player.get(player_id, {}) as Dictionary
	var memory_ids_by_surface: Dictionary = memory_ids_by_surface_by_player.get(player_id, {}) as Dictionary
	for surface: Vector3i in surfaces:
		var object_ids: Dictionary = memory_ids_by_surface.get(surface, {}) as Dictionary
		for object_id_value: Variant in object_ids.keys():
			if memories.has(object_id_value):
				result[object_id_value] = (memories[object_id_value] as Dictionary).duplicate(true)
	return result


func has_player_memory(player_id: String, object_id: String) -> bool:
	return (memories_by_player.get(player_id, {}) as Dictionary).has(object_id)


func has_remembered_object_at_surface(player_id: String, surface: Vector3i) -> bool:
	var memory_ids_by_surface: Dictionary = memory_ids_by_surface_by_player.get(player_id, {}) as Dictionary
	return not (memory_ids_by_surface.get(surface, {}) as Dictionary).is_empty()


func rebuild_player(player_id: String, visible_surfaces: Dictionary) -> void:
	if runtime == null:
		return
	var memories: Dictionary = memories_by_player.get(player_id, {}) as Dictionary
	var live_object_ids: Dictionary[String, bool] = {}
	for object_value: Variant in runtime.get_registered_objects():
		var grid_object: GridObject = object_value as GridObject
		if grid_object == null or grid_object.object_id.is_empty():
			continue
		live_object_ids[grid_object.object_id] = true
		if _is_object_visible(grid_object, visible_surfaces):
			memories[grid_object.object_id] = _create_memory(grid_object)
	_remove_revealed_missing_memories(memories, live_object_ids, visible_surfaces)
	memories_by_player[player_id] = memories
	_rebuild_player_surface_index(player_id, memories)


func update_player_for_surfaces(
	player_id: String,
	visible_surfaces: Dictionary,
	dirty_surfaces: Array[Vector3i]
) -> void:
	if runtime == null or dirty_surfaces.is_empty():
		return
	var memories: Dictionary = memories_by_player.get(player_id, {}) as Dictionary
	var dirty_set: Dictionary[Vector3i, bool] = {}
	var touched_objects: Dictionary[String, GridObject] = {}
	for surface: Vector3i in dirty_surfaces:
		dirty_set[surface] = true
		var grid_object: GridObject = runtime.get_object_at_surface(surface) as GridObject
		if grid_object != null and not grid_object.object_id.is_empty():
			touched_objects[grid_object.object_id] = grid_object
	for grid_object: GridObject in touched_objects.values():
		if _is_object_visible(grid_object, visible_surfaces):
			_replace_memory(player_id, memories, grid_object.object_id, _create_memory(grid_object))
	var memory_ids: Array = memories.keys()
	for object_id_value: Variant in memory_ids:
		var object_id: String = str(object_id_value)
		if runtime.get_object_by_id(object_id) != null:
			continue
		var memory: Dictionary = memories[object_id_value] as Dictionary
		if _memory_intersects_visible_dirty_surfaces(memory, visible_surfaces, dirty_set):
			_remove_memory_from_surface_index(player_id, object_id, memory)
			memories.erase(object_id_value)
	memories_by_player[player_id] = memories


func _replace_memory(player_id: String, memories: Dictionary, object_id: String, memory: Dictionary) -> void:
	if memories.has(object_id):
		_remove_memory_from_surface_index(player_id, object_id, memories[object_id] as Dictionary)
	memories[object_id] = memory
	_add_memory_to_surface_index(player_id, object_id, memory)


func _rebuild_player_surface_index(player_id: String, memories: Dictionary) -> void:
	memory_ids_by_surface_by_player[player_id] = {}
	for object_id_value: Variant in memories.keys():
		if memories[object_id_value] is Dictionary:
			_add_memory_to_surface_index(player_id, str(object_id_value), memories[object_id_value] as Dictionary)


func _add_memory_to_surface_index(player_id: String, object_id: String, memory: Dictionary) -> void:
	var memory_ids_by_surface: Dictionary = memory_ids_by_surface_by_player.get(player_id, {}) as Dictionary
	for surface_value: Variant in memory.get("occupied_surfaces", [memory.get("surface")]) as Array:
		if not (surface_value is Vector3i):
			continue
		var surface: Vector3i = surface_value as Vector3i
		var object_ids: Dictionary = memory_ids_by_surface.get(surface, {}) as Dictionary
		object_ids[object_id] = true
		memory_ids_by_surface[surface] = object_ids
	memory_ids_by_surface_by_player[player_id] = memory_ids_by_surface


func _remove_memory_from_surface_index(player_id: String, object_id: String, memory: Dictionary) -> void:
	var memory_ids_by_surface: Dictionary = memory_ids_by_surface_by_player.get(player_id, {}) as Dictionary
	for surface_value: Variant in memory.get("occupied_surfaces", [memory.get("surface")]) as Array:
		if not (surface_value is Vector3i):
			continue
		var surface: Vector3i = surface_value as Vector3i
		var object_ids: Dictionary = memory_ids_by_surface.get(surface, {}) as Dictionary
		object_ids.erase(object_id)
		if object_ids.is_empty():
			memory_ids_by_surface.erase(surface)
		else:
			memory_ids_by_surface[surface] = object_ids
	memory_ids_by_surface_by_player[player_id] = memory_ids_by_surface


func _is_object_visible(grid_object: GridObject, visible_surfaces: Dictionary) -> bool:
	var anchor: Vector3i = runtime.spatial.get_object_anchor_surface(grid_object)
	for surface: Vector3i in grid_object.get_occupied_surfaces(anchor):
		if visible_surfaces.has(surface):
			return true
	return false


func _create_memory(grid_object: GridObject) -> Dictionary:
	var surface: Vector3i = runtime.spatial.get_object_anchor_surface(grid_object)
	var owner_player_id: String = ""
	if grid_object is VisionTower:
		owner_player_id = (grid_object as VisionTower).owner_player_id
	return {
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


func _remove_revealed_missing_memories(
	memories: Dictionary,
	live_object_ids: Dictionary[String, bool],
	visible_surfaces: Dictionary
) -> void:
	for object_id_value: Variant in memories.keys():
		var object_id: String = str(object_id_value)
		if live_object_ids.has(object_id):
			continue
		var memory: Dictionary = memories[object_id_value] as Dictionary
		for surface_value: Variant in memory.get("occupied_surfaces", [memory.get("surface")]) as Array:
			if surface_value is Vector3i and visible_surfaces.has(surface_value as Vector3i):
				memories.erase(object_id_value)
				break


func _memory_intersects_visible_dirty_surfaces(
	memory: Dictionary,
	visible_surfaces: Dictionary,
	dirty_surfaces: Dictionary[Vector3i, bool]
) -> bool:
	for surface_value: Variant in memory.get("occupied_surfaces", [memory.get("surface")]) as Array:
		if (
			surface_value is Vector3i
			and dirty_surfaces.has(surface_value as Vector3i)
			and visible_surfaces.has(surface_value as Vector3i)
		):
			return true
	return false
