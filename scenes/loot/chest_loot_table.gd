class_name ChestLootTable
extends Resource

@export var reward_item_ids: PackedStringArray = PackedStringArray([
	CharacterInventory.ITEM_ID_MEAT,
	CharacterInventory.ITEM_ID_PRECISION_STONE,
	CharacterInventory.ITEM_ID_METEOR_SCROLL,
])


func roll_reward_item_id(random_number_generator: RandomNumberGenerator) -> String:
	if random_number_generator == null or reward_item_ids.is_empty():
		return ""

	var reward_index: int = random_number_generator.randi_range(0, reward_item_ids.size() - 1)
	return reward_item_ids[reward_index]


func is_valid() -> bool:
	if reward_item_ids.is_empty():
		return false
	for item_id: String in reward_item_ids:
		if item_id.is_empty() or item_id not in CharacterInventory.KNOWN_ITEM_IDS:
			return false
	return true
