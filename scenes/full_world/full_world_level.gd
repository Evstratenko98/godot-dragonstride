class_name FullWorldLevel
extends WorldLevel

const LEVEL_DEFINITION: LevelDefinition = preload("res://scenes/full_world/full_world_definition.tres")


func _init() -> void:
	definition = LEVEL_DEFINITION
