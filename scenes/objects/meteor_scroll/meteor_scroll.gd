class_name MeteorScroll
extends ItemObject

const INVENTORY_ITEM_ID := "meteor_scroll"


func _init() -> void:
	occupied_offsets = [Vector2i.ZERO]


func interact(interactor: PlayerCharacter, world_runtime: WorldRuntime) -> bool:
	if interactor == null or world_runtime == null:
		return false
	if interactor.character_inventory.get_available_capacity(INVENTORY_ITEM_ID) < 1:
		return false
	if object_id.is_empty() or world_runtime.get_object_by_id(object_id) != self:
		return false
	if not interactor.character_inventory.try_add_item(INVENTORY_ITEM_ID, 1):
		return false

	return world_runtime.remove_world_object(self)
