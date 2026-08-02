class_name Chest
extends GridObject

const OPEN_ANIMATION_NAME := &"open"

@onready var animation_player: AnimationPlayer = get_node("AnimationPlayer") as AnimationPlayer


func _init() -> void:
	occupied_offsets = [Vector2i.ZERO]


func can_open() -> bool:
	return object_state == ObjectState.NORMAL


func play_opening_animation() -> void:
	if animation_player == null:
		return

	animation_player.play(OPEN_ANIMATION_NAME)
	await animation_player.animation_finished


func set_opened() -> void:
	object_state = ObjectState.OPENED
	apply_state_visual()


func take_damage() -> bool:
	return false


func interact(_interactor: PlayerCharacter, _world_runtime: WorldRuntime) -> bool:
	return false


func can_interact(interactor: PlayerCharacter, world_runtime: WorldRuntime) -> bool:
	return interactor != null and world_runtime != null and can_open()


func apply_network_state(network_state: int) -> void:
	if network_state == ObjectState.OPENED:
		if animation_player != null and animation_player.is_playing():
			object_state = ObjectState.OPENED
			return
		set_opened()
		return

	super.apply_network_state(network_state)


func apply_state_visual() -> void:
	if sprite == null:
		return

	if object_state == ObjectState.OPENED:
		sprite.texture = destroyed_texture
		return

	sprite.texture = normal_texture
