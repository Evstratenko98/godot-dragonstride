class_name GridLines
extends Node2D

@export var line_color: Color = Color(1.0, 1.0, 1.0, 0.8)
@export var line_width: float = 1.0

var runtime: WorldRuntime = null
var level: WorldLevel = null


func _ready() -> void:
	queue_redraw()


func _exit_tree() -> void:
	var console: Node = get_node_or_null("/root/Console")
	if console == null or not console.has_method("remove_command"):
		return

	console.remove_command("game_grid_lines_show")
	console.remove_command("game_grid_lines_hide")


func _draw() -> void:
	if level == null:
		return

	var grid_size: Vector2i = _get_world_grid_size()
	var cell_size: int = _get_world_cell_size()
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var cell: Vector2i = Vector2i(x, y)
			if _is_cell_walkable(cell):
				var rect: Rect2 = Rect2(Vector2(cell) * cell_size, Vector2(cell_size, cell_size))
				draw_rect(rect, line_color, false, line_width, false)


func show_lines() -> void:
	if level == null or not level.allows_debug_commands():
		return
	visible = true
	queue_redraw()
	ConsoleOutput.print_console("Game grid lines: shown")


func hide_lines() -> void:
	if level == null or not level.allows_debug_commands():
		return
	visible = false
	ConsoleOutput.print_console("Game grid lines: hidden")


func configure_context(new_runtime: WorldRuntime, new_level: WorldLevel) -> void:
	runtime = new_runtime
	level = new_level
	if level != null and level.allows_debug_commands():
		_register_console_commands()
	queue_redraw()


func _get_world_grid_size() -> Vector2i:
	if runtime != null:
		return runtime.get_grid_size()

	if level != null:
		return level.get_grid_size()

	return Vector2i(8, 8)


func _get_world_cell_size() -> int:
	if runtime != null:
		return runtime.get_cell_size()

	return 64


func _is_cell_walkable(cell: Vector2i) -> bool:
	if runtime != null:
		return runtime.is_cell_walkable_for_character(cell)

	if level == null:
		return false

	if _is_cell_in_layers(cell, level.get_walkable_layer_names()):
		return true

	return _is_cell_in_layers(cell, level.get_character_walkable_layer_names())


func _is_cell_in_layers(cell: Vector2i, layer_names: PackedStringArray) -> bool:
	for layer_name in layer_names:
		var layer: Node = level.get_node_or_null(NodePath(str(layer_name)))
		if layer is TileMapLayer and layer.get_cell_source_id(cell) != -1:
			return true

	return false


func _register_console_commands() -> void:
	var console: Node = get_node_or_null("/root/Console")
	if console == null or not console.has_method("add_command"):
		return

	console.add_command("game_grid_lines_show", show_lines, 0, 0, "Show game grid lines.")
	console.add_command("game_grid_lines_hide", hide_lines, 0, 0, "Hide game grid lines.")
