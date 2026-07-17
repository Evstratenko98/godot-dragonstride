class_name LevelDefinition
extends Resource

@export var level_id: String = ""
@export var grid_size: Vector2i = Vector2i(19, 19)
@export var walkable_layer_names: PackedStringArray = ["Ground"]
@export var character_walkable_layer_names: PackedStringArray = ["Hay", "Bridge"]
@export var spawn_cells: Array[Vector2i] = []
@export var music_stream: AudioStream = null
@export var death_sound_stream: AudioStream = null
@export var allows_debug_commands: bool = false
