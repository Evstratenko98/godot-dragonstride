class_name HudCursorController
extends Node

var hud_root: Node = null


func _exit_tree() -> void:
	if get_tree() != null and get_tree().node_added.is_connected(_on_scene_tree_node_added):
		get_tree().node_added.disconnect(_on_scene_tree_node_added)


func configure(new_hud_root: Node) -> void:
	hud_root = new_hud_root
	_configure_interactive_cursor(hud_root)
	if not get_tree().node_added.is_connected(_on_scene_tree_node_added):
		get_tree().node_added.connect(_on_scene_tree_node_added)


func _configure_interactive_cursor(node: Node) -> void:
	if node == null:
		return
	var control: Control = node as Control
	var is_action_button: bool = control is BaseButton and control.get_parent() is ActionModeBar
	if (control is BaseButton and not is_action_button) or control is InventorySlotControl:
		control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for child: Node in node.get_children():
		_configure_interactive_cursor(child)


func _on_scene_tree_node_added(node: Node) -> void:
	if hud_root != null and hud_root.is_ancestor_of(node):
		_configure_interactive_cursor(node)
