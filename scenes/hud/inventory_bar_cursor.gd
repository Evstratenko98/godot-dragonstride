class_name InventoryBarCursor
extends RefCounted

const MOVE_CURSOR_HOTSPOT := Vector2(8.0, 22.0)
const ATTACK_CURSOR_HOTSPOT := Vector2(3.0, 3.0)
const INTERACTION_CURSOR_HOTSPOT := Vector2(18.0, 20.0)
const INACTIVE_ACTION_CURSOR_HOTSPOT := Vector2(15.0, 4.0)
const METEOR_TARGET_CURSOR_HOTSPOT := Vector2(16.0, 16.0)
const ABILITY_CURSOR_HOTSPOT := Vector2(16.0, 16.0)
const MOVE_CURSOR_TEXTURE: Texture2D = preload("res://art/pointers/boot.svg")
const ATTACK_CURSOR_TEXTURE: Texture2D = preload("res://art/pointers/tool_sword_a.svg")
const INTERACTION_CURSOR_TEXTURE: Texture2D = preload("res://art/pointers/hand_open.svg")
const INACTIVE_ACTION_CURSOR_TEXTURE: Texture2D = preload("res://art/pointers/hand_small_point_n.svg")
const METEOR_TARGET_CURSOR_TEXTURE: Texture2D = preload("res://art/pointers/target_round_a.svg")
const ABILITY_CURSOR_TEXTURE: Texture2D = preload("res://art/pointers/knight_taunt.svg")


static func apply(action_mode: int, has_available_action: bool = true) -> void:
	if not has_available_action:
		Input.set_custom_mouse_cursor(INACTIVE_ACTION_CURSOR_TEXTURE, Input.CURSOR_ARROW, INACTIVE_ACTION_CURSOR_HOTSPOT)
		return
	if action_mode == PlayerCharacter.ActionMode.MOVE:
		Input.set_custom_mouse_cursor(MOVE_CURSOR_TEXTURE, Input.CURSOR_ARROW, MOVE_CURSOR_HOTSPOT)
		return
	if action_mode == PlayerCharacter.ActionMode.INTERACT:
		Input.set_custom_mouse_cursor(INTERACTION_CURSOR_TEXTURE, Input.CURSOR_ARROW, INTERACTION_CURSOR_HOTSPOT)
		return
	if action_mode == PlayerCharacter.ActionMode.SPECIAL_ABILITY:
		Input.set_custom_mouse_cursor(ABILITY_CURSOR_TEXTURE, Input.CURSOR_ARROW, ABILITY_CURSOR_HOTSPOT)
		return
	Input.set_custom_mouse_cursor(ATTACK_CURSOR_TEXTURE, Input.CURSOR_ARROW, ATTACK_CURSOR_HOTSPOT)


static func get_action_texture(action_mode: int) -> Texture2D:
	if action_mode == PlayerCharacter.ActionMode.MOVE:
		return MOVE_CURSOR_TEXTURE
	if action_mode == PlayerCharacter.ActionMode.INTERACT:
		return INTERACTION_CURSOR_TEXTURE
	if action_mode == PlayerCharacter.ActionMode.SPECIAL_ABILITY:
		return ABILITY_CURSOR_TEXTURE
	return ATTACK_CURSOR_TEXTURE


static func apply_meteor_targeting() -> void:
	Input.set_custom_mouse_cursor(
		METEOR_TARGET_CURSOR_TEXTURE,
		Input.CURSOR_ARROW,
		METEOR_TARGET_CURSOR_HOTSPOT
	)


static func clear_action_cursor() -> void:
	GameCursor.restore_default_cursor()
