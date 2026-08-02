class_name HudCursorController
extends Node

const POINTING_HAND_CURSOR_TEXTURE: Texture2D = preload("res://art/pointers/hand_small_point_n.svg")
const POINTING_HAND_CURSOR_HOTSPOT := Vector2(15.0, 4.0)

var hud_root: Node = null


func _exit_tree() -> void:
	if get_tree() != null and get_tree().node_added.is_connected(_on_scene_tree_node_added):
		get_tree().node_added.disconnect(_on_scene_tree_node_added)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_POINTING_HAND)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_DRAG)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_CAN_DROP)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_FORBIDDEN)


func configure(new_hud_root: Node) -> void:
	hud_root = new_hud_root
	_register_global_cursors()
	_configure_interactive_cursor(hud_root)
	if not get_tree().node_added.is_connected(_on_scene_tree_node_added):
		get_tree().node_added.connect(_on_scene_tree_node_added)


func _register_global_cursors() -> void:
	for cursor_shape: int in [
		Input.CURSOR_POINTING_HAND,
		Input.CURSOR_DRAG,
		Input.CURSOR_CAN_DROP,
		Input.CURSOR_FORBIDDEN,
	]:
		Input.set_custom_mouse_cursor(
			POINTING_HAND_CURSOR_TEXTURE,
			cursor_shape,
			POINTING_HAND_CURSOR_HOTSPOT
		)


func _configure_interactive_cursor(node: Node) -> void:
	if node == null:
		return
	var control: Control = node as Control
	if control is BaseButton or control is InventorySlotControl:
		control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for child: Node in node.get_children():
		_configure_interactive_cursor(child)


func _on_scene_tree_node_added(node: Node) -> void:
	if hud_root != null and hud_root.is_ancestor_of(node):
		_configure_interactive_cursor(node)
