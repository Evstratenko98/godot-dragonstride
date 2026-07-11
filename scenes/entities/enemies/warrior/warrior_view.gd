extends "res://scenes/entities/non_player_entity/non_player_view.gd"

@export var sprite_path: NodePath = ^"../Sprite2D"
@export var animation_player_path: NodePath = ^"../AnimationPlayer"

@onready var sprite: Sprite2D = get_node(sprite_path) as Sprite2D
@onready var animation_player: AnimationPlayer = get_node(animation_player_path) as AnimationPlayer

var facing_left: bool = false


func face_direction(direction: Vector2i) -> void:
	if direction.x == 0:
		return

	facing_left = direction.x < 0
	sprite.flip_h = facing_left


func play_idle() -> void:
	play_animation(&"idle")


func play_walk() -> void:
	animation_player.stop()
	animation_player.play(&"run")


func play_guard() -> void:
	play_animation(&"guard")


func play_attack(attack_facing_left: bool, update_horizontal_facing: bool) -> void:
	if update_horizontal_facing:
		facing_left = attack_facing_left

	sprite.flip_h = facing_left
	animation_player.play(&"attack1")
	await animation_player.animation_finished
	animation_player.play(&"attack2")
	await animation_player.animation_finished
	sprite.flip_h = facing_left


func play_animation(animation_name: StringName) -> void:
	if animation_player.current_animation != animation_name:
		animation_player.play(animation_name)


func get_attack_duration() -> float:
	return animation_player.get_animation(&"attack1").length + animation_player.get_animation(&"attack2").length


func get_facing_left() -> bool:
	return facing_left
