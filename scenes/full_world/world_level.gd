class_name WorldLevel
extends Node2D

@export var grid_size: Vector2i = Vector2i(18, 18)
@export var walkable_layer_names: PackedStringArray = ["Ground"]
@export var spawn_cells: Array[Vector2i] = [
	Vector2i(5, 5),
	Vector2i(6, 5),
	Vector2i(5, 6),
	Vector2i(6, 6),
]


func get_runtime() -> WorldRuntime:
	var runtime: WorldRuntime = get_node_or_null("WorldRuntime") as WorldRuntime
	if runtime != null and not runtime.is_configured_for(self):
		runtime.configure_for_level(self)
	return runtime


func get_match_controller() -> MatchController:
	return get_node_or_null("MatchController") as MatchController


func get_world_entities_root() -> Node:
	return get_node_or_null("WorldEntities")


func get_players_root() -> Node:
	return get_node_or_null("Players")


func get_music_player() -> AudioStreamPlayer:
	return get_node_or_null("Music") as AudioStreamPlayer


func get_death_sound_player() -> AudioStreamPlayer:
	return get_node_or_null("DeathSound") as AudioStreamPlayer
