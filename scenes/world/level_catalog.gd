class_name LevelCatalog
extends RefCounted

const DEFAULT_LEVEL_ID := "full_world"
const LEVEL_SCENE_PATHS := {
	"full_world": "res://scenes/full_world/full_world.tscn",
	"level_1": "res://scenes/levels/level_1/level_1.tscn",
}


static func has_level(level_id: String) -> bool:
	return LEVEL_SCENE_PATHS.has(level_id)


static func get_level_scene(level_id: String) -> PackedScene:
	var level_scene_path: String = str(LEVEL_SCENE_PATHS.get(level_id, ""))
	if level_scene_path.is_empty() or not ResourceLoader.exists(level_scene_path, "PackedScene"):
		return null

	return load(level_scene_path) as PackedScene


static func get_level_ids() -> PackedStringArray:
	var level_ids: PackedStringArray = PackedStringArray()
	for level_id: String in LEVEL_SCENE_PATHS.keys():
		level_ids.append(level_id)

	return level_ids
