class_name NonPlayerView
extends Node


func face_direction(_direction: Vector2i) -> void:
	pass


func play_idle() -> void:
	pass


func play_walk() -> void:
	pass


func play_guard() -> void:
	pass


func play_attack(_attack_facing_left: bool, _update_horizontal_facing: bool) -> void:
	pass


func get_attack_duration() -> float:
	return 0.0


func get_facing_left() -> bool:
	return false
