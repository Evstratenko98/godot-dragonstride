extends "res://scenes/objects/grid_object/grid_object.gd"


func _ready() -> void:
	occupied_offsets = [Vector2i.ZERO]
	super._ready()
