class_name WorldMapDocument
extends RefCounted

var schema_version: int = 0
var level_id: String = ""
var generator_id: String = ""
var generator_version: int = 0
var seed: int = 0
var grid_size: Vector2i = Vector2i.ZERO
var layers: Array[Dictionary] = []
var surface_layers: Array[Dictionary] = []
var ramps: Array[Dictionary] = []
var player_spawn_surfaces: Array[Vector3i] = []
var static_entities: Array[Dictionary] = []
var static_objects: Array[Dictionary] = []


func to_dictionary() -> Dictionary:
	var spawn_records: Array = []
	for surface: Vector3i in player_spawn_surfaces:
		spawn_records.append([surface.x, surface.y, surface.z])
	return {
		"schema_version": schema_version,
		"level_id": level_id,
		"generator_id": generator_id,
		"generator_version": generator_version,
		"seed": seed,
		"grid_size": [grid_size.x, grid_size.y],
		"layers": layers.duplicate(true),
		"surface_layers": surface_layers.duplicate(true),
		"ramps": ramps.duplicate(true),
		"player_spawn_surfaces": spawn_records,
		"static_entities": static_entities.duplicate(true),
		"static_objects": static_objects.duplicate(true),
	}
