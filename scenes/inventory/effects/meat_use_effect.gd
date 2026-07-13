class_name MeatUseEffect
extends ItemUseEffect

const MAX_HEALTH_INCREASE := 10
const HEALTH_RESTORE := 10


func can_apply(target: PlayerCharacter) -> bool:
	return target != null and target.health > 0


func apply(target: PlayerCharacter) -> bool:
	if not can_apply(target):
		return false

	return target.apply_health_capacity_bonus(MAX_HEALTH_INCREASE, HEALTH_RESTORE)
