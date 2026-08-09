class_name WorldLevel
extends Node2D

@export var definition: LevelDefinition = null
@export var world_entities_root_path: NodePath = ^"WorldEntities"
@export var spawned_objects_root_path: NodePath = ^"SpawnedObjects"
@export var terrain_topology_root_path: NodePath = ^"TerrainTopology"

var runtime: WorldRuntime = null
var map_grid_size: Vector2i = Vector2i.ZERO
var map_walkable_layer_names: PackedStringArray = PackedStringArray()
var map_character_walkable_layer_names: PackedStringArray = PackedStringArray()
var map_spawn_surfaces: Array[Vector3i] = []
var map_document_hash: String = ""
var has_committed_map: bool = false


func configure_runtime(new_runtime: WorldRuntime) -> void:
	runtime = new_runtime


func get_runtime() -> WorldRuntime:
	return runtime


func get_definition() -> LevelDefinition:
	return definition


func get_grid_size() -> Vector2i:
	return map_grid_size


func get_walkable_layer_names() -> PackedStringArray:
	return map_walkable_layer_names.duplicate()


func get_character_walkable_layer_names() -> PackedStringArray:
	return map_character_walkable_layer_names.duplicate()


func get_spawn_surfaces() -> Array[Vector3i]:
	return map_spawn_surfaces.duplicate()


func generate_map_document(_seed: int) -> WorldMapDocument:
	return null


func commit_map_document(document: WorldMapDocument, document_hash: String) -> void:
	map_grid_size = document.grid_size
	map_spawn_surfaces = document.player_spawn_surfaces.duplicate()
	map_document_hash = document_hash
	map_walkable_layer_names.clear()
	map_character_walkable_layer_names.clear()
	for record: Dictionary in document.surface_layers:
		var source_layer: String = str(record.get("source_layer", ""))
		if source_layer.is_empty():
			continue
		if bool(record.get("character_only", false)):
			map_character_walkable_layer_names.append(source_layer)
		else:
			map_walkable_layer_names.append(source_layer)
	has_committed_map = true


func has_runtime_map() -> bool:
	return has_committed_map


func get_map_document_hash() -> String:
	return map_document_hash


func get_terrain_topology_root() -> Node:
	return get_node_or_null(terrain_topology_root_path)


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


func has_welcome_modal() -> bool:
	return (
		definition != null
		and not definition.welcome_modal_title.is_empty()
		and not definition.welcome_modal_text.is_empty()
	)


func get_welcome_modal_title() -> String:
	if definition == null:
		return ""

	return definition.welcome_modal_title


func get_welcome_modal_text() -> String:
	if definition == null:
		return ""

	return definition.welcome_modal_text


func allows_debug_commands() -> bool:
	return definition != null and definition.allows_debug_commands
