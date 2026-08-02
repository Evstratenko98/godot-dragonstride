class_name MenuBackdrop
extends Control

const BACKGROUND_COLOR := Color(0.025, 0.03, 0.045, 1.0)
const GRID_COLOR := Color(0.28, 0.34, 0.43, 0.08)
const GOLD_GLOW_COLOR := Color(1.0, 0.72, 0.12, 0.018)
const BLUE_GLOW_COLOR := Color(0.14, 0.48, 0.72, 0.025)
const GRID_STEP := 64.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND_COLOR)
	var horizontal_count: int = ceili(size.x / GRID_STEP)
	var vertical_count: int = ceili(size.y / GRID_STEP)
	for column_index: int in range(horizontal_count + 1):
		var x_position: float = float(column_index) * GRID_STEP
		draw_line(Vector2(x_position, 0.0), Vector2(x_position, size.y), GRID_COLOR, 1.0)
	for row_index: int in range(vertical_count + 1):
		var y_position: float = float(row_index) * GRID_STEP
		draw_line(Vector2(0.0, y_position), Vector2(size.x, y_position), GRID_COLOR, 1.0)
	var gold_center: Vector2 = Vector2(size.x * 0.82, size.y * 0.18)
	var blue_center: Vector2 = Vector2(size.x * 0.12, size.y * 0.86)
	for radius_index: int in range(7, 0, -1):
		var radius: float = float(radius_index) * 58.0
		draw_circle(gold_center, radius, GOLD_GLOW_COLOR)
		draw_circle(blue_center, radius * 0.78, BLUE_GLOW_COLOR)
	draw_arc(gold_center, 178.0, 0.0, TAU, 96, Color(1.0, 0.82, 0.20, 0.12), 2.0)
	draw_arc(gold_center, 206.0, 0.0, TAU, 96, Color(1.0, 0.82, 0.20, 0.055), 1.0)


func _on_resized() -> void:
	queue_redraw()
