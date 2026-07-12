class_name Level1Level
extends WorldLevel

const LEVEL_DEFINITION: LevelDefinition = preload("res://scenes/levels/level_1/level_1_definition.tres")


func _init() -> void:
	definition = LEVEL_DEFINITION
