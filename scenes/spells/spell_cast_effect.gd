class_name SpellCastEffect
extends Node2D

signal impact()
signal finished()


func play_effect(_start_position: Vector2, _target_position: Vector2) -> void:
	pass


func _emit_impact() -> void:
	impact.emit()


func _emit_finished() -> void:
	finished.emit()


func get_expected_duration() -> float:
	return 0.0
