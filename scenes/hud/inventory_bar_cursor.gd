class_name InventoryBarCursor
extends RefCounted

const ATTACK_CURSOR_HOTSPOT := Vector2(3.0, 3.0)
const INTERACTION_CURSOR_HOTSPOT := Vector2(18.0, 20.0)
const INACTIVE_ACTION_CURSOR_HOTSPOT := Vector2(15.0, 4.0)
const ATTACK_CURSOR_TEXTURE: Texture2D = preload("res://art/pointers/tool_sword_a.svg")
const INTERACTION_CURSOR_TEXTURE: Texture2D = preload("res://art/pointers/hand_open.svg")
const INACTIVE_ACTION_CURSOR_TEXTURE: Texture2D = preload("res://art/pointers/hand_small_point_n.svg")


static func apply(action_mode: int, has_available_action: bool = true) -> void:
	if not has_available_action:
		Input.set_custom_mouse_cursor(INACTIVE_ACTION_CURSOR_TEXTURE, Input.CURSOR_ARROW, INACTIVE_ACTION_CURSOR_HOTSPOT)
		return
	if action_mode == PlayerCharacter.ActionMode.INTERACT:
		Input.set_custom_mouse_cursor(INTERACTION_CURSOR_TEXTURE, Input.CURSOR_ARROW, INTERACTION_CURSOR_HOTSPOT)
		return
	Input.set_custom_mouse_cursor(ATTACK_CURSOR_TEXTURE, Input.CURSOR_ARROW, ATTACK_CURSOR_HOTSPOT)
