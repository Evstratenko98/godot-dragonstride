class_name MeteorEffect
extends SpellCastEffect

const FLY_DURATION := 0.8

@onready var animation_player: AnimationPlayer = get_node("AnimationPlayer") as AnimationPlayer

var movement_tween: Tween = null


func play_effect(start_position: Vector2, target_position: Vector2) -> void:
	global_position = start_position
	animation_player.play(&"fly")
	movement_tween = create_tween()
	movement_tween.set_trans(Tween.TRANS_LINEAR)
	movement_tween.set_ease(Tween.EASE_IN_OUT)
	movement_tween.tween_property(self, "global_position", target_position, FLY_DURATION)
	await movement_tween.finished

	global_position = target_position
	impact.emit()
	animation_player.play(&"burst")
	var finished_animation: StringName = await animation_player.animation_finished
	while finished_animation != &"burst":
		finished_animation = await animation_player.animation_finished

	finished.emit()
	queue_free()
