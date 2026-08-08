class_name WorldSpawnSnapshotTransaction
extends RefCounted

var spawner: WorldSpawner = null
var committed_spawn_ids: Array[String] = []


func configure(owner: WorldSpawner) -> void:
	spawner = owner


func apply(
	dynamic_spawn_records: Array[Dictionary],
	removal_records: Array[Dictionary]
) -> bool:
	committed_spawn_ids.clear()
	if dynamic_spawn_records.size() > NetworkProtocol.MAX_WORLD_RECORDS or removal_records.size() > NetworkProtocol.MAX_WORLD_RECORDS:
		return false
	var seen_spawn_ids: Dictionary[String, bool] = {}
	for record: Dictionary in dynamic_spawn_records:
		var type_key: String = spawner.normalize_type_key(str(record.get("type_key", "")))
		var spawn_id: String = str(record.get("spawn_id", ""))
		var surface_value: Variant = record.get("surface")
		if (
			not WorldSpawnCatalog.DEFINITIONS.has(type_key)
			or not NetworkProtocol.is_valid_identifier(spawn_id)
			or seen_spawn_ids.has(spawn_id)
			or not (surface_value is Vector3i)
			or not spawner.runtime.is_surface_inside(surface_value as Vector3i)
		):
			return false
		seen_spawn_ids[spawn_id] = true
	for record: Dictionary in removal_records:
		var kind: String = str(record.get("kind", ""))
		var removed_id: String = str(record.get("id", ""))
		if not NetworkProtocol.is_valid_identifier(removed_id) or kind not in [WorldSpawnCatalog.KIND_ENTITY, WorldSpawnCatalog.KIND_OBJECT] or seen_spawn_ids.has(removed_id):
			return false

	var effective_removals: Array[Dictionary] = removal_records.duplicate(true)
	for cached_record: Dictionary in NetworkManager.store.get_world_spawn_records():
		var cached_spawn_id: String = str(cached_record.get("spawn_id", ""))
		if seen_spawn_ids.has(cached_spawn_id):
			continue
		var cached_type_key: String = spawner.normalize_type_key(str(cached_record.get("type_key", "")))
		if not WorldSpawnCatalog.DEFINITIONS.has(cached_type_key):
			continue
		var cached_definition: Dictionary = WorldSpawnCatalog.DEFINITIONS[cached_type_key]
		effective_removals.append({
			"kind": str(cached_definition.get("kind", "")),
			"id": cached_spawn_id,
		})

	var staged_records: Array[Dictionary] = []
	var staged_surfaces: Dictionary[Vector3i, bool] = {}
	for record: Dictionary in dynamic_spawn_records:
		var spawn_id: String = str(record.get("spawn_id", ""))
		if spawner.has_spawn_id(spawn_id):
			continue
		var type_key: String = spawner.normalize_type_key(str(record.get("type_key", "")))
		var definition: Dictionary = WorldSpawnCatalog.DEFINITIONS[type_key]
		var scene: PackedScene = definition.get("scene") as PackedScene
		if scene == null:
			_free_staged(staged_records)
			return false
		var instance: Node = scene.instantiate()
		spawner.assign_spawn_id(instance, str(definition.get("kind", "")), spawn_id)
		var surface: Vector3i = record.get("surface", Vector3i.ZERO)
		for occupied_surface: Vector3i in _get_occupied_surfaces(instance, surface):
			if staged_surfaces.has(occupied_surface):
				instance.free()
				_free_staged(staged_records)
				return false
			staged_surfaces[occupied_surface] = true
		if not spawner.runtime.get_placement_error(instance, surface).is_empty():
			instance.free()
			_free_staged(staged_records)
			return false
		staged_records.append({
			"instance": instance,
			"definition": definition,
			"type_key": type_key,
			"spawn_id": spawn_id,
			"surface": surface,
		})

	spawner.apply_world_removals(effective_removals)
	for staged_record: Dictionary in staged_records:
		var spawn_error: String = spawner.spawn_staged_instance(staged_record)
		if not spawn_error.is_empty():
			_rollback(committed_spawn_ids)
			_free_staged(staged_records)
			return false
		committed_spawn_ids.append(str(staged_record.get("spawn_id", "")))
	for spawn_id: String in seen_spawn_ids.keys():
		if not spawner.has_spawn_id(spawn_id):
			rollback()
			return false
	return true


func rollback() -> void:
	_rollback(committed_spawn_ids)
	committed_spawn_ids.clear()


func commit() -> void:
	committed_spawn_ids.clear()


func _get_occupied_surfaces(instance: Node, anchor_surface: Vector3i) -> Array[Vector3i]:
	if instance is Entity:
		return (instance as Entity).get_occupied_surfaces(anchor_surface)
	if instance is GridObject:
		return (instance as GridObject).get_occupied_surfaces(anchor_surface)
	return [anchor_surface]


func _free_staged(records: Array[Dictionary]) -> void:
	for record: Dictionary in records:
		var instance: Node = record.get("instance") as Node
		if instance != null and not instance.is_inside_tree():
			instance.free()


func _rollback(spawn_ids: Array[String]) -> void:
	for spawn_id: String in spawn_ids:
		spawner.remove_spawn_by_id(spawn_id)
