class_name CharacterView
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

@onready var sprite: Sprite2D = get_node(sprite_path) as Sprite2D
@onready var animation_player: AnimationPlayer = get_node(animation_player_path) as AnimationPlayer

var facing_left: bool = false


func set_warrior_color(color_name: String) -> void:
	var texture: Texture2D = WARRIOR_TEXTURES.get(color_name, WARRIOR_TEXTURES[WARRIOR_COLOR_BLUE]) as Texture2D
	var target_sprite: Sprite2D = _get_sprite()
	if target_sprite != null:
		target_sprite.texture = texture


func apply_remote_visual_state(animation: String, remote_facing_left: bool) -> void:
	facing_left = remote_facing_left
	var target_sprite: Sprite2D = _get_sprite()
	if target_sprite != null:
		target_sprite.flip_h = facing_left
	play_animation(StringName(animation))


func face_direction(direction: Vector2i) -> void:
	if direction.x == 0:
		return

	facing_left = direction.x < 0
	var target_sprite: Sprite2D = _get_sprite()
	if target_sprite != null:
		target_sprite.flip_h = facing_left


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

	var target_sprite: Sprite2D = _get_sprite()
	if target_sprite != null:
		target_sprite.flip_h = attack_facing_left

	var player: AnimationPlayer = _get_animation_player()
	if player == null:
		return

	player.play(animation_name)
	await player.animation_finished
	target_sprite = _get_sprite()
	if target_sprite != null:
		target_sprite.flip_h = facing_left


func play_animation(animation_name: StringName) -> void:
	var player: AnimationPlayer = _get_animation_player()
	if player == null:
		return

	if player.current_animation != animation_name:
		player.play(animation_name)


func get_current_animation() -> StringName:
	var player: AnimationPlayer = _get_animation_player()
	if player == null:
		return &""

	return StringName(player.current_animation)


func get_animation_length(animation_name: StringName) -> float:
	var player: AnimationPlayer = _get_animation_player()
	if player == null:
		return 0.0

	var animation: Animation = player.get_animation(animation_name)
	if animation == null:
		return 0.0

	return animation.length


func get_facing_left() -> bool:
	return facing_left


func get_portrait_texture() -> Texture2D:
	var target_sprite: Sprite2D = _get_sprite()
	if target_sprite == null or target_sprite.texture == null:
		return null
	if target_sprite.hframes <= 1 and target_sprite.vframes <= 1:
		return target_sprite.texture

	var frame_width: float = float(target_sprite.texture.get_width()) / float(target_sprite.hframes)
	var frame_height: float = float(target_sprite.texture.get_height()) / float(target_sprite.vframes)
	var portrait_texture: AtlasTexture = AtlasTexture.new()
	portrait_texture.atlas = target_sprite.texture
	portrait_texture.region = Rect2(Vector2.ZERO, Vector2(frame_width, frame_height))
	return portrait_texture


func _get_sprite() -> Sprite2D:
	if sprite == null:
		sprite = get_node_or_null(sprite_path) as Sprite2D

	return sprite


func _get_animation_player() -> AnimationPlayer:
	if animation_player == null:
		animation_player = get_node_or_null(animation_player_path) as AnimationPlayer

	return animation_player
