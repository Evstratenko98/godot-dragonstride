extends "res://scenes/entities/non_player_entity/non_player_entity.gd"

const SHEEP_MAX_HEALTH := 25

var move_direction := Vector2i.RIGHT


func _ready() -> void:
	max_health = SHEEP_MAX_HEALTH
	health = max_health
	super._ready()
	entity_type = EntityType.NEUTRAL
	if entity_name.is_empty():
		entity_name = "Sheep"


func start(
	start_position: Vector2,
	new_entity_id := "",
	new_entity_name := "Sheep"
) -> void:
	max_health = SHEEP_MAX_HEALTH
	start_non_player_entity(start_position, new_entity_id, new_entity_name, EntityType.NEUTRAL)


func behavior() -> void:
	if not can_act():
		_finish_behavior()
		return

	if request_behavior_move(move_direction):
		return

	move_direction = Vector2i(-move_direction.x, -move_direction.y)
	if request_behavior_move(move_direction):
		return

	_finish_behavior()
