class_name SandboxLevel
extends WorldLevel

const LEVEL_DEFINITION: LevelDefinition = preload("res://scenes/sandbox/sandbox_definition.tres")


func _init() -> void:
	definition = LEVEL_DEFINITION
