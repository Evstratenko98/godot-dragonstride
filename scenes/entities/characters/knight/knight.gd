class_name Knight
extends "res://scenes/entities/characters/player_character.gd"

const CHARACTER_TYPE_KEY := "knight"
const DEFAULT_APPEARANCE_VARIANT := "Blue"
const NAMES_BY_APPEARANCE: Dictionary[String, String] = {
	"Purple": "Patrick",
	"Blue": "Arnoldo",
	"Yellow": "Huan",
	"Red": "Dick",
}


func get_character_type_key() -> String:
	return CHARACTER_TYPE_KEY


func get_special_ability_id() -> String:
	return PlayerCharacterCatalog.get_ability_id(CHARACTER_TYPE_KEY)


func configure_character_profile(new_appearance_variant: String, display_name: String = "") -> void:
	appearance_variant = (
		new_appearance_variant
		if NAMES_BY_APPEARANCE.has(new_appearance_variant)
		else DEFAULT_APPEARANCE_VARIANT
	)
	entity_name = (
		display_name
		if not display_name.is_empty()
		else str(NAMES_BY_APPEARANCE.get(appearance_variant, NAMES_BY_APPEARANCE[DEFAULT_APPEARANCE_VARIANT]))
	)
	var knight_view: KnightView = _get_view() as KnightView
	if knight_view != null:
		knight_view.configure_appearance(appearance_variant)
		knight_view.set_display_name(entity_name)
