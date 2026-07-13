class_name WorldItemUsage
extends Node

const EFFECT_ID_MEAT_HEALTH := "meat_health"

var runtime: WorldRuntime = null
var level: WorldLevel = null
var meat_use_effect: MeatUseEffect = MeatUseEffect.new()


func configure_context(new_runtime: WorldRuntime, new_level: WorldLevel) -> void:
	runtime = new_runtime
	level = new_level


func try_use_item(player: PlayerCharacter, slot_index: int) -> bool:
	if player == null or player.health <= 0 or runtime == null:
		return false
	if not runtime.can_entity_use_item_in_turn(player):
		return false

	var character_inventory: CharacterInventory = player.character_inventory
	if character_inventory == null or not character_inventory.is_item_usable(slot_index):
		return false

	var effect_id: String = character_inventory.get_item_use_effect_id(slot_index)
	var effect: ItemUseEffect = _get_effect(effect_id)
	if effect == null or not effect.can_apply(player):
		return false
	if not character_inventory.try_consume_one(slot_index):
		return false

	return effect.apply(player)


func _get_effect(effect_id: String) -> ItemUseEffect:
	if effect_id == EFFECT_ID_MEAT_HEALTH:
		return meat_use_effect

	return null
