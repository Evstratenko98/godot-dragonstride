extends "res://scenes/objects/grid_object/grid_object.gd"


func _ready() -> void:
	occupied_offsets = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(1, 1)
	]
	super._ready()
