class_name ItemObject
extends GridObject

@export var is_destructible: bool = true


func take_damage() -> bool:
	return is_destructible
