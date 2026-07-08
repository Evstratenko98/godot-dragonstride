extends "res://scenes/objects/grid_object/grid_object.gd"


func _init() -> void:
	occupied_offsets = [Vector2i.ZERO]


func _ready() -> void:
	super._ready()
