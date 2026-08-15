class_name WorldVisibilityTowerSourceCoordinator
extends RefCounted

const SOURCE_PREFIX: String = "tower:"

var runtime: WorldRuntime = null
var source_ledger: WorldVisibilitySourceLedger = null
var world_surfaces: Array[Vector3i] = []
var surfaces_by_object_id: Dictionary[String, Dictionary] = {}


func configure(
	new_runtime: WorldRuntime,
	new_source_ledger: WorldVisibilitySourceLedger
) -> void:
	runtime = new_runtime
	source_ledger = new_source_ledger
	world_surfaces = [] if runtime == null else runtime.get_all_surfaces()
	surfaces_by_object_id.clear()


func clear() -> void:
	runtime = null
	source_ledger = null
	world_surfaces.clear()
	surfaces_by_object_id.clear()


func add_registered_sources() -> void:
	if runtime == null or source_ledger == null:
		return
	for object_value: Variant in runtime.get_registered_objects():
		var tower: VisionTower = object_value as VisionTower
		if tower != null and not tower.owner_player_id.is_empty():
			source_ledger.replace_source(
				_get_source_id(tower),
				tower.owner_player_id,
				_get_surfaces(tower)
			)


func transfer_source(tower: VisionTower, interactor: PlayerCharacter) -> Dictionary:
	if tower == null or interactor == null or interactor.owner_player_id.is_empty():
		return {}
	if tower.owner_player_id == interactor.owner_player_id or source_ledger == null:
		return {}
	var previous_player_id: String = tower.owner_player_id
	var source_id: String = _get_source_id(tower)
	var previous_dirty_surfaces: Array[Vector3i] = source_ledger.remove_source(source_id)
	tower.apply_owner_player_id(interactor.owner_player_id)
	var next_dirty_surfaces: Array[Vector3i] = source_ledger.replace_source(
		source_id,
		tower.owner_player_id,
		_get_surfaces(tower)
	)
	return {
		"previous_player_id": previous_player_id,
		"previous_dirty_surfaces": previous_dirty_surfaces,
		"next_player_id": tower.owner_player_id,
		"next_dirty_surfaces": next_dirty_surfaces,
	}


func _get_surfaces(tower: VisionTower) -> Dictionary[Vector3i, bool]:
	if tower == null or tower.object_id.is_empty() or runtime == null:
		return {}
	if surfaces_by_object_id.has(tower.object_id):
		return surfaces_by_object_id[tower.object_id] as Dictionary
	var result: Dictionary[Vector3i, bool] = {}
	var grid_size: Vector2i = runtime.get_grid_size()
	for region: VisionRevealRegion in tower.reveal_regions:
		if region == null or not region.is_valid_for_grid(grid_size):
			continue
		for surface: Vector3i in world_surfaces:
			if region.contains_surface(surface):
				result[surface] = true
	surfaces_by_object_id[tower.object_id] = result
	return result


func _get_source_id(tower: VisionTower) -> String:
	return SOURCE_PREFIX + tower.object_id
