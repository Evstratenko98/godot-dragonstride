extends Node

const WARRIOR_COLOR_BLUE := "Blue"
const WARRIOR_COLOR_PURPLE := "Purple"
const WARRIOR_COLOR_RED := "Red"
const WARRIOR_COLOR_YELLOW := "Yellow"
const WARRIOR_TEXTURES := {
	WARRIOR_COLOR_BLUE: preload("res://art/Tiny Swords (Update 010)/Factions/Knights/Troops/Warrior/Blue/Warrior_Blue.png"),
	WARRIOR_COLOR_PURPLE: preload("res://art/Tiny Swords (Update 010)/Factions/Knights/Troops/Warrior/Purple/Warrior_Purple.png"),
	WARRIOR_COLOR_RED: preload("res://art/Tiny Swords (Update 010)/Factions/Knights/Troops/Warrior/Red/Warrior_Red.png"),
	WARRIOR_COLOR_YELLOW: preload("res://art/Tiny Swords (Update 010)/Factions/Knights/Troops/Warrior/Yellow/Warrior_Yellow.png"),
}

@export var sprite_path: NodePath = ^"../Sprite2D"
@export var animation_player_path: NodePath = ^"../AnimationPlayer"

@onready var sprite := get_node(sprite_path) as Sprite2D
@onready var animation_player := get_node(animation_player_path) as AnimationPlayer

var facing_left: bool = false


func set_warrior_color(color_name: String) -> void:
	var texture := WARRIOR_TEXTURES.get(color_name, WARRIOR_TEXTURES[WARRIOR_COLOR_BLUE]) as Texture2D
	sprite.texture = texture


func apply_remote_visual_state(animation: String, remote_facing_left: bool) -> void:
	facing_left = remote_facing_left
	sprite.flip_h = facing_left
	play_animation(StringName(animation))


func face_direction(direction: Vector2i) -> void:
	if direction.x == 0:
		return

	facing_left = direction.x < 0
	sprite.flip_h = facing_left


func play_idle() -> void:
	play_animation(&"idle")


func play_walk() -> void:
	play_animation(&"walk")


func play_attack(
	animation_name: StringName,
	attack_facing_left: bool,
	update_horizontal_facing: bool
) -> void:
	if update_horizontal_facing:
		facing_left = attack_facing_left

	sprite.flip_h = attack_facing_left
	animation_player.play(animation_name)
	await animation_player.animation_finished
	sprite.flip_h = facing_left


func play_animation(animation_name: StringName) -> void:
	if animation_player.current_animation != animation_name:
		animation_player.play(animation_name)


func get_current_animation() -> StringName:
	return StringName(animation_player.current_animation)


func get_facing_left() -> bool:
	return facing_left
