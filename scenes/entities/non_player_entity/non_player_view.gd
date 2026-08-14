class_name NonPlayerView
extends Node

var provoked_indicator_presenter: EntityProvokedIndicatorPresenter = EntityProvokedIndicatorPresenter.new()


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


func set_provoked_indicator_visible(is_visible: bool) -> void:
	provoked_indicator_presenter.configure(get_parent() as Entity)
	provoked_indicator_presenter.set_visible(is_visible)
