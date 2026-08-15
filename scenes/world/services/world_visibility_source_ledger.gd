class_name WorldVisibilitySourceLedger
extends RefCounted

const MAX_VISIBILITY_SOURCES: int = NetworkProtocol.MAX_PLAYER_CHARACTERS + NetworkProtocol.MAX_WORLD_RECORDS

var surface_count: int = 0
var surface_index_by_surface: Dictionary[Vector3i, int] = {}
var source_surfaces_by_id: Dictionary[String, Dictionary] = {}
var source_player_id_by_id: Dictionary[String, String] = {}
var visible_counts_by_player: Dictionary[String, PackedInt32Array] = {}
var visible_surfaces_by_player: Dictionary[String, Dictionary] = {}


func configure(new_surface_index_by_surface: Dictionary[Vector3i, int], new_surface_count: int) -> void:
	clear()
	surface_index_by_surface = new_surface_index_by_surface.duplicate()
	surface_count = maxi(new_surface_count, 0)


func clear() -> void:
	surface_count = 0
	surface_index_by_surface.clear()
	source_surfaces_by_id.clear()
	source_player_id_by_id.clear()
	visible_counts_by_player.clear()
	visible_surfaces_by_player.clear()


func ensure_player(player_id: String) -> void:
	if player_id.is_empty() or visible_counts_by_player.has(player_id):
		return
	var counts: PackedInt32Array = PackedInt32Array()
	counts.resize(surface_count)
	visible_counts_by_player[player_id] = counts
	visible_surfaces_by_player[player_id] = {}


func replace_source(
	source_id: String,
	player_id: String,
	next_surfaces: Dictionary[Vector3i, bool]
) -> Array[Vector3i]:
	var dirty_surfaces: Dictionary[Vector3i, bool] = {}
	if source_id.is_empty() or player_id.is_empty():
		return _get_surface_keys(dirty_surfaces)
	if not source_surfaces_by_id.has(source_id) and source_surfaces_by_id.size() >= MAX_VISIBILITY_SOURCES:
		push_error("Visibility source limit exceeded: %d" % source_surfaces_by_id.size())
		return _get_surface_keys(dirty_surfaces)

	var previous_player_id: String = source_player_id_by_id.get(source_id, "")
	var previous_surfaces: Dictionary = source_surfaces_by_id.get(source_id, {}) as Dictionary
	if not previous_player_id.is_empty() and previous_player_id != player_id:
		_remove_source_contribution(previous_player_id, previous_surfaces, dirty_surfaces)
		previous_surfaces = {}

	ensure_player(player_id)
	var counts: PackedInt32Array = visible_counts_by_player[player_id]
	var visible_surfaces: Dictionary = visible_surfaces_by_player[player_id] as Dictionary
	for surface_value: Variant in previous_surfaces.keys():
		if not (surface_value is Vector3i):
			continue
		var surface: Vector3i = surface_value as Vector3i
		if next_surfaces.has(surface):
			continue
		var surface_index: int = surface_index_by_surface.get(surface, -1)
		if surface_index < 0 or counts[surface_index] <= 0:
			continue
		counts[surface_index] -= 1
		if counts[surface_index] == 0:
			visible_surfaces.erase(surface)
			dirty_surfaces[surface] = true
	for surface: Vector3i in next_surfaces.keys():
		if previous_surfaces.has(surface):
			continue
		var surface_index: int = surface_index_by_surface.get(surface, -1)
		if surface_index < 0:
			continue
		var previous_count: int = counts[surface_index]
		counts[surface_index] = previous_count + 1
		if previous_count == 0:
			visible_surfaces[surface] = true
			dirty_surfaces[surface] = true
	visible_counts_by_player[player_id] = counts
	visible_surfaces_by_player[player_id] = visible_surfaces
	source_player_id_by_id[source_id] = player_id
	source_surfaces_by_id[source_id] = next_surfaces.duplicate()
	return _get_surface_keys(dirty_surfaces)


func remove_source(source_id: String) -> Array[Vector3i]:
	var dirty_surfaces: Dictionary[Vector3i, bool] = {}
	var player_id: String = source_player_id_by_id.get(source_id, "")
	var surfaces: Dictionary = source_surfaces_by_id.get(source_id, {}) as Dictionary
	if not player_id.is_empty():
		_remove_source_contribution(player_id, surfaces, dirty_surfaces)
	source_player_id_by_id.erase(source_id)
	source_surfaces_by_id.erase(source_id)
	return _get_surface_keys(dirty_surfaces)


func has_source(source_id: String) -> bool:
	return source_surfaces_by_id.has(source_id)


func get_source_player_id(source_id: String) -> String:
	return source_player_id_by_id.get(source_id, "")


func get_visible_surfaces(player_id: String) -> Dictionary:
	return visible_surfaces_by_player.get(player_id, {}) as Dictionary


func _remove_source_contribution(
	player_id: String,
	surfaces: Dictionary,
	dirty_surfaces: Dictionary[Vector3i, bool]
) -> void:
	if not visible_counts_by_player.has(player_id):
		return
	var counts: PackedInt32Array = visible_counts_by_player[player_id]
	var visible_surfaces: Dictionary = visible_surfaces_by_player.get(player_id, {}) as Dictionary
	for surface_value: Variant in surfaces.keys():
		if not (surface_value is Vector3i):
			continue
		var surface: Vector3i = surface_value as Vector3i
		var surface_index: int = surface_index_by_surface.get(surface, -1)
		if surface_index < 0 or counts[surface_index] <= 0:
			continue
		counts[surface_index] -= 1
		if counts[surface_index] == 0:
			visible_surfaces.erase(surface)
			dirty_surfaces[surface] = true
	visible_counts_by_player[player_id] = counts
	visible_surfaces_by_player[player_id] = visible_surfaces


func _get_surface_keys(surfaces: Dictionary[Vector3i, bool]) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for surface: Vector3i in surfaces.keys():
		result.append(surface)
	return result
