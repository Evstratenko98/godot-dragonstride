class_name CellHover
extends Node2D

@export var hover_color: Color = Color(1.0, 0.85, 0.2, 0.28)
@export var spell_target_color: Color = Color(1.0, 0.3, 0.08, 0.38)

var runtime: WorldRuntime = null
var hover_cell: Vector2i = Vector2i.ZERO
var has_hover_cell: bool = false
var is_spell_targeting: bool = false


func _process(_delta: float) -> void:
	if runtime == null:
		return

	var next_cell: Vector2i = runtime.world_to_cell(get_global_mouse_position())
	var local_player: PlayerCharacter = runtime.get_local_player()
	var next_is_spell_targeting: bool = runtime.has_selected_spell(local_player)
	var next_has_hover_cell: bool = runtime.is_cell_inside(next_cell) if next_is_spell_targeting else runtime.is_cell_interactable(next_cell)
	if (
		hover_cell == next_cell
		and has_hover_cell == next_has_hover_cell
		and is_spell_targeting == next_is_spell_targeting
	):
		return

	hover_cell = next_cell
	has_hover_cell = next_has_hover_cell
	is_spell_targeting = next_is_spell_targeting
	queue_redraw()


func _draw() -> void:
	if runtime == null or not has_hover_cell:
		return

	var cell_size: int = runtime.get_cell_size()
	var rect: Rect2 = Rect2(Vector2(hover_cell) * cell_size, Vector2(cell_size, cell_size))
	var color: Color = spell_target_color if is_spell_targeting else hover_color
	draw_rect(rect, color, true)


func configure_context(new_runtime: WorldRuntime) -> void:
	runtime = new_runtime
