class_name PrecisionStone
extends ItemObject

const INVENTORY_ITEM_ID := "precision_stone"


func _init() -> void:
	occupied_offsets = [Vector2i.ZERO]


func interact(interactor: PlayerCharacter, world_runtime: WorldRuntime) -> bool:
	if not can_interact(interactor, world_runtime):
		return false
	if not interactor.character_inventory.try_add_item(INVENTORY_ITEM_ID, 1):
		return false

	return world_runtime.remove_world_object(self)


func can_interact(interactor: PlayerCharacter, world_runtime: WorldRuntime) -> bool:
	return (
		interactor != null
		and world_runtime != null
		and interactor.character_inventory != null
		and interactor.character_inventory.get_available_capacity(INVENTORY_ITEM_ID) >= 1
		and not object_id.is_empty()
		and world_runtime.get_object_by_id(object_id) == self
	)
