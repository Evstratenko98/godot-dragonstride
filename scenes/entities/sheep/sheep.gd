extends "res://scenes/entities/non_player_entity/non_player_entity.gd"

const SHEEP_MAX_HEALTH := 25
const DEATH_DROP_TYPE := "meat"

var move_direction: Vector2i = Vector2i.RIGHT


func _ready() -> void:
	max_health = SHEEP_MAX_HEALTH
	health = max_health
	super._ready()
	entity_type = EntityType.NEUTRAL
	if entity_name.is_empty():
		entity_name = "Sheep"


func start(
	start_position: Vector2,
	new_entity_id: String = "",
	new_entity_name: String = "Sheep"
) -> void:
	max_health = SHEEP_MAX_HEALTH
	start_non_player_entity(start_position, new_entity_id, new_entity_name, EntityType.NEUTRAL)


func spawn_death_drop(death_cell: Vector2i) -> bool:
	if runtime == null:
		return false

	return runtime.spawn_world_object(DEATH_DROP_TYPE, death_cell)


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
