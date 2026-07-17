class_name WorldItemUsage
extends Node

const EFFECT_ID_MEAT_HEALTH := "meat_health"
const EFFECT_ID_PRECISION_STONE_DAMAGE := "precision_stone_damage"

var runtime: WorldRuntime = null
var level: WorldLevel = null
var meat_use_effect: MeatUseEffect = MeatUseEffect.new()
var precision_stone_use_effect: PrecisionStoneUseEffect = PrecisionStoneUseEffect.new()


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
	var rollback_inventory_snapshot: Dictionary = character_inventory.create_snapshot()
	var rollback_health: int = player.health
	var rollback_max_health: int = player.max_health
	var rollback_damage: int = player.damage
	if not character_inventory.try_consume_one(CharacterInventory.INVENTORY_KIND_ITEM, slot_index):
		return false
	if effect.apply(player):
		return true
	character_inventory.restore_snapshot(rollback_inventory_snapshot)
	player.max_health = rollback_max_health
	player.set_health(rollback_health)
	player.apply_attack_damage_state(rollback_damage)
	return false


func _get_effect(effect_id: String) -> ItemUseEffect:
	if effect_id == EFFECT_ID_MEAT_HEALTH:
		return meat_use_effect
	if effect_id == EFFECT_ID_PRECISION_STONE_DAMAGE:
		return precision_stone_use_effect

	return null
