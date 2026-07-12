class_name CellHover
extends Node2D

@export var hover_color: Color = Color(1.0, 0.85, 0.2, 0.28)

var runtime: WorldRuntime = null
var hover_cell: Vector2i = Vector2i.ZERO
var has_hover_cell: bool = false


func _process(_delta: float) -> void:
	if runtime == null:
		return

	var next_cell: Vector2i = runtime.world_to_cell(get_global_mouse_position())
	var next_has_hover_cell: bool = runtime.is_cell_interactable(next_cell)
	if hover_cell == next_cell and has_hover_cell == next_has_hover_cell:
		return

	hover_cell = next_cell
	has_hover_cell = next_has_hover_cell
	queue_redraw()


func _draw() -> void:
	if runtime == null or not has_hover_cell:
		return

	var cell_size: int = runtime.get_cell_size()
	var rect: Rect2 = Rect2(Vector2(hover_cell) * cell_size, Vector2(cell_size, cell_size))
	draw_rect(rect, hover_color, true)


func configure_context(new_runtime: WorldRuntime) -> void:
	runtime = new_runtime
