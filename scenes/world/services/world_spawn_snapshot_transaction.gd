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
		var cell_value: Variant = record.get("cell")
		if (
			not WorldSpawner.CATALOG.has(type_key)
			or not NetworkProtocol.is_valid_identifier(spawn_id)
			or seen_spawn_ids.has(spawn_id)
			or not (cell_value is Vector2i)
			or not spawner.runtime.is_cell_inside(cell_value as Vector2i)
		):
			return false
		seen_spawn_ids[spawn_id] = true
	for record: Dictionary in removal_records:
		var kind: String = str(record.get("kind", ""))
		var removed_id: String = str(record.get("id", ""))
		if not NetworkProtocol.is_valid_identifier(removed_id) or kind not in [WorldSpawner.SPAWN_KIND_ENTITY, WorldSpawner.SPAWN_KIND_OBJECT] or seen_spawn_ids.has(removed_id):
			return false

	var effective_removals: Array[Dictionary] = removal_records.duplicate(true)
	for cached_record: Dictionary in NetworkManager.store.get_world_spawn_records():
		var cached_spawn_id: String = str(cached_record.get("spawn_id", ""))
		if seen_spawn_ids.has(cached_spawn_id):
			continue
		var cached_type_key: String = spawner.normalize_type_key(str(cached_record.get("type_key", "")))
		if not WorldSpawner.CATALOG.has(cached_type_key):
			continue
		var cached_definition: Dictionary = WorldSpawner.CATALOG[cached_type_key]
		effective_removals.append({
			"kind": str(cached_definition.get("kind", "")),
			"id": cached_spawn_id,
		})

	var staged_records: Array[Dictionary] = []
	var staged_cells: Dictionary[Vector2i, bool] = {}
	for record: Dictionary in dynamic_spawn_records:
		var spawn_id: String = str(record.get("spawn_id", ""))
		if spawner.has_spawn_id(spawn_id):
			continue
		var type_key: String = spawner.normalize_type_key(str(record.get("type_key", "")))
		var definition: Dictionary = WorldSpawner.CATALOG[type_key]
		var scene: PackedScene = definition.get("scene") as PackedScene
		if scene == null:
			_free_staged(staged_records)
			return false
		var instance: Node = scene.instantiate()
		spawner.assign_spawn_id(instance, str(definition.get("kind", "")), spawn_id)
		var cell: Vector2i = record.get("cell", Vector2i.ZERO)
		for occupied_cell: Vector2i in _get_occupied_cells(instance, cell):
			if staged_cells.has(occupied_cell):
				instance.free()
				_free_staged(staged_records)
				return false
			staged_cells[occupied_cell] = true
		if not spawner.runtime.get_placement_error(instance, cell).is_empty():
			instance.free()
			_free_staged(staged_records)
			return false
		staged_records.append({
			"instance": instance,
			"definition": definition,
			"type_key": type_key,
			"spawn_id": spawn_id,
			"cell": cell,
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


func _get_occupied_cells(instance: Node, anchor_cell: Vector2i) -> Array[Vector2i]:
	if instance is Entity:
		return (instance as Entity).get_occupied_cells(anchor_cell)
	if instance is GridObject:
		return (instance as GridObject).get_occupied_cells(anchor_cell)
	return [anchor_cell]


func _free_staged(records: Array[Dictionary]) -> void:
	for record: Dictionary in records:
		var instance: Node = record.get("instance") as Node
		if instance != null and not instance.is_inside_tree():
			instance.free()


func _rollback(spawn_ids: Array[String]) -> void:
	for spawn_id: String in spawn_ids:
		spawner.remove_spawn_by_id(spawn_id)
