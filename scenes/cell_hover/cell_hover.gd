class_name CellHover
extends Node2D

signal hovered_entity_changed(entity: Entity)

@export var hover_color: Color = Color(1.0, 0.85, 0.2, 0.28)
@export var spell_target_color: Color = Color(1.0, 0.3, 0.08, 0.38)

var runtime: WorldRuntime = null
var hover_cell: Vector2i = Vector2i.ZERO
var has_hover_cell: bool = false
var is_spell_targeting: bool = false
var hovered_entity: Entity = null


func _process(_delta: float) -> void:
	if runtime == null:
		return

	var next_cell: Vector2i = runtime.world_to_cell(get_global_mouse_position())
	var local_player: PlayerCharacter = runtime.get_local_player()
	var next_is_spell_targeting: bool = runtime.has_selected_spell(local_player)
	var next_has_hover_cell: bool = runtime.is_cell_inside(next_cell) if next_is_spell_targeting else runtime.is_cell_interactable(next_cell)
	var next_hovered_entity: Entity = null
	if runtime.is_cell_inside(next_cell):
		next_hovered_entity = runtime.get_entity_at_cell(next_cell) as Entity
	if hovered_entity != null and not is_instance_valid(hovered_entity):
		hovered_entity = null
	if (
		hover_cell == next_cell
		and has_hover_cell == next_has_hover_cell
		and is_spell_targeting == next_is_spell_targeting
		and hovered_entity == next_hovered_entity
	):
		return

	hover_cell = next_cell
	has_hover_cell = next_has_hover_cell
	is_spell_targeting = next_is_spell_targeting
	if hovered_entity != next_hovered_entity:
		hovered_entity = next_hovered_entity
		hovered_entity_changed.emit(hovered_entity)
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


func get_hovered_entity() -> Entity:
	if hovered_entity == null or not is_instance_valid(hovered_entity):
		return null
	return hovered_entity
