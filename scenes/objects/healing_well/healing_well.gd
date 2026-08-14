class_name HealingWell
extends GridObject

const HEAL_AMOUNT: int = 25


func _init() -> void:
	occupied_offsets = [Vector2i.ZERO]


func take_damage() -> bool:
	return false


func can_interact(interactor: PlayerCharacter, world_runtime: WorldRuntime) -> bool:
	return (
		interactor != null
		and interactor.health > 0
		and world_runtime != null
		and not object_id.is_empty()
		and world_runtime.get_object_by_id(object_id) == self
	)


func interact(interactor: PlayerCharacter, world_runtime: WorldRuntime) -> bool:
	if not can_interact(interactor, world_runtime):
		return false
	interactor.set_health(get_resulting_health(interactor))
	return true


func get_resulting_health(interactor: PlayerCharacter) -> int:
	if interactor == null:
		return 0
	return mini(interactor.health + HEAL_AMOUNT, interactor.max_health)


func apply_resulting_health(interactor: PlayerCharacter, resulting_health: int) -> bool:
	if interactor == null or interactor.health <= 0:
		return false
	if resulting_health < interactor.health or resulting_health > interactor.max_health:
		return false
	interactor.set_health(resulting_health)
	return true
