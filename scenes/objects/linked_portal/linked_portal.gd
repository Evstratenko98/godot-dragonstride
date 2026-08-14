class_name LinkedPortal
extends GridObject

@export var link_group_id: String = "primary"


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
		and not link_group_id.is_empty()
		and world_runtime.get_object_by_id(object_id) == self
	)


func interact(interactor: PlayerCharacter, world_runtime: WorldRuntime) -> bool:
	return can_interact(interactor, world_runtime)
