class_name PlayerCharacterCatalog
extends RefCounted

const TYPE_KNIGHT := "knight"
const DEFAULT_TYPE := TYPE_KNIGHT
const DEFAULT_APPEARANCE := "Blue"
const APPEARANCES: Dictionary[String, PackedStringArray] = {
	TYPE_KNIGHT: ["Blue", "Purple", "Red", "Yellow"],
}
const SCENES: Dictionary[String, PackedScene] = {
	TYPE_KNIGHT: preload("res://scenes/entities/characters/knight/knight.tscn"),
}
const ABILITIES: Dictionary[String, String] = {
	TYPE_KNIGHT: "knight_taunt",
}


static func has_type(character_type: String) -> bool:
	return SCENES.has(character_type)


static func instantiate(character_type: String) -> PlayerCharacter:
	var character_scene: PackedScene = SCENES.get(character_type) as PackedScene
	if character_scene == null:
		return null
	return character_scene.instantiate() as PlayerCharacter


static func is_valid_appearance(character_type: String, appearance_variant: String) -> bool:
	var allowed_appearances: PackedStringArray = APPEARANCES.get(character_type, PackedStringArray())
	return appearance_variant in allowed_appearances


static func get_ability_id(character_type: String) -> String:
	return str(ABILITIES.get(character_type, ""))


static func get_type_for_squad_slot(_squad_slot: int) -> String:
	return DEFAULT_TYPE
