class_name CharacterAbilityCatalog
extends RefCounted

const KNIGHT_TAUNT := "knight_taunt"
const KNIGHT_TAUNT_COOLDOWN_TURNS := 3


static func is_known(ability_id: String) -> bool:
	return ability_id == KNIGHT_TAUNT


static func get_cooldown_turns(ability_id: String) -> int:
	return KNIGHT_TAUNT_COOLDOWN_TURNS if ability_id == KNIGHT_TAUNT else 0


static func is_ability_available_to_character(ability_id: String, character: PlayerCharacter) -> bool:
	return (
		character != null
		and ability_id == KNIGHT_TAUNT
		and character.get_character_type_key() == PlayerCharacterCatalog.TYPE_KNIGHT
		and character.get_special_ability_id() == ability_id
	)
