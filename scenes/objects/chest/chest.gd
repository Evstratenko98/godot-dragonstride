class_name Chest
extends GridObject

const OPEN_ANIMATION_NAME := &"open"
const OPEN_ANIMATION_TIMEOUT_MSEC: int = 3_000

@onready var animation_player: AnimationPlayer = get_node("AnimationPlayer") as AnimationPlayer


func _init() -> void:
	occupied_offsets = [Vector2i.ZERO]


func can_open() -> bool:
	return object_state == ObjectState.NORMAL


func play_opening_animation() -> bool:
	if animation_player == null:
		return false

	animation_player.play(OPEN_ANIMATION_NAME)
	var deadline_msec: int = Time.get_ticks_msec() + OPEN_ANIMATION_TIMEOUT_MSEC
	while (
		is_instance_valid(animation_player)
		and animation_player.is_playing()
		and Time.get_ticks_msec() < deadline_msec
	):
		await get_tree().process_frame
	var did_finish: bool = is_instance_valid(animation_player) and not animation_player.is_playing()
	if not did_finish and is_instance_valid(animation_player):
		animation_player.stop()
	return did_finish


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
