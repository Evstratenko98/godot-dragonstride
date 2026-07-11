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
	animation_player.play(&"walk")


func play_animation(animation_name: StringName) -> void:
	if animation_player.current_animation != animation_name:
		animation_player.play(animation_name)
