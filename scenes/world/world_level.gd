class_name WorldLevel
extends Node2D

@export var definition: LevelDefinition = null
@export var world_entities_root_path: NodePath = ^"WorldEntities"
@export var spawned_objects_root_path: NodePath = ^"SpawnedObjects"

var runtime: WorldRuntime = null


func configure_runtime(new_runtime: WorldRuntime) -> void:
	runtime = new_runtime


func get_runtime() -> WorldRuntime:
	return runtime


func get_definition() -> LevelDefinition:
	return definition


func get_grid_size() -> Vector2i:
	if definition == null:
		return Vector2i.ZERO

	return definition.grid_size


func get_walkable_layer_names() -> PackedStringArray:
	if definition == null:
		return PackedStringArray()

	return definition.walkable_layer_names


func get_character_walkable_layer_names() -> PackedStringArray:
	if definition == null:
		return PackedStringArray()

	return definition.character_walkable_layer_names


func get_spawn_cells() -> Array[Vector2i]:
	if definition == null:
		return []

	return definition.spawn_cells.duplicate()


func get_world_entities_root() -> Node2D:
	return get_node_or_null(world_entities_root_path) as Node2D


func get_spawned_objects_root() -> Node2D:
	return get_node_or_null(spawned_objects_root_path) as Node2D


func get_music_stream() -> AudioStream:
	if definition == null:
		return null

	return definition.music_stream


func get_death_sound_stream() -> AudioStream:
	if definition == null:
		return null

	return definition.death_sound_stream
