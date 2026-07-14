class_name PrecisionStoneUseEffect
extends ItemUseEffect

const DAMAGE_INCREASE := 5


func can_apply(target: PlayerCharacter) -> bool:
	return target != null and target.health > 0


func apply(target: PlayerCharacter) -> bool:
	if not can_apply(target):
		return false

	return target.apply_attack_damage_bonus(DAMAGE_INCREASE)
