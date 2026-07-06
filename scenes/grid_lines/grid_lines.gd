@tool
extends Node2D

@export var line_color := Color(1.0, 1.0, 1.0, 0.8)
@export var line_width := 1.0

var world = null


func _ready() -> void:
	world = _find_world()
	_register_console_commands()
	queue_redraw()


func _exit_tree() -> void:
	var console := get_node_or_null("/root/Console")
	if console == null or not console.has_method("remove_command"):
		return

	console.remove_command("game_grid_lines_show")
	console.remove_command("game_grid_lines_hide")


func _draw() -> void:
	if world == null:
		world = _find_world()

	if world == null:
		return

	var grid_size := _get_world_grid_size()
	var cell_size := _get_world_cell_size()
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var cell := Vector2i(x, y)
			if _is_cell_walkable(cell):
				var rect := Rect2(Vector2(cell) * cell_size, Vector2(cell_size, cell_size))
				draw_rect(rect, line_color, false, line_width, false)


func show_lines() -> void:
	visible = true
	queue_redraw()
	_print_console("Game grid lines: shown")


func hide_lines() -> void:
	visible = false
	_print_console("Game grid lines: hidden")


func _find_world() -> Node:
	var node := get_parent()
	while node != null:
		if node.has_method("is_cell_walkable") or node.get("walkable_layer_names") != null:
			return node
		node = node.get_parent()

	return null


func _get_world_grid_size() -> Vector2i:
	if not Engine.is_editor_hint() and world.has_method("get_grid_size"):
		return world.get_grid_size()

	var value = world.get("grid_size")
	if value is Vector2i:
		return value

	return Vector2i(8, 8)


func _get_world_cell_size() -> int:
	if not Engine.is_editor_hint() and world.has_method("get_cell_size"):
		return world.get_cell_size()

	return 64


func _is_cell_walkable(cell: Vector2i) -> bool:
	if not Engine.is_editor_hint() and world.has_method("is_cell_walkable"):
		return world.is_cell_walkable(cell)

	var layer_names = world.get("walkable_layer_names")
	if layer_names == null:
		layer_names = PackedStringArray(["Ground"])

	for layer_name in layer_names:
		var layer: Node = world.get_node_or_null(NodePath(str(layer_name)))
		if layer is TileMapLayer and layer.get_cell_source_id(cell) != -1:
			return true

	return false


func _register_console_commands() -> void:
	var console := get_node_or_null("/root/Console")
	if console == null or not console.has_method("add_command"):
		return

	console.add_command("game_grid_lines_show", show_lines, 0, 0, "Show game grid lines.")
	console.add_command("game_grid_lines_hide", hide_lines, 0, 0, "Hide game grid lines.")


func _print_console(text: String) -> void:
	var console := get_node_or_null("/root/Console")
	if console != null and console.has_method("print_line"):
		console.print_line(text)
