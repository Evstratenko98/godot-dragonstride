class_name CharacterView
extends Node


func set_display_name(_display_name: String) -> void:
	pass


func configure_appearance(_appearance_variant: String) -> void:
	pass


func apply_remote_visual_state(_animation: String, _remote_facing_left: bool) -> void:
	pass


func face_direction(_direction: Vector2i) -> void:
	pass


func play_idle() -> void:
	pass


func play_walk() -> void:
	pass


func play_attack(
	_animation_name: StringName,
	_attack_facing_left: bool,
	_update_horizontal_facing: bool
) -> void:
	pass


func play_animation(_animation_name: StringName) -> void:
	pass


func get_current_animation() -> StringName:
	return &""


func get_animation_length(_animation_name: StringName) -> float:
	return 0.0


func get_facing_left() -> bool:
	return false


func get_portrait_texture() -> Texture2D:
	return null
