class_name CellHover
extends Node2D

signal hovered_entity_changed(entity: Entity)
signal hovered_cell_changed(cell: Vector2i, is_inside_world: bool)

@export var hover_color: Color = Color(1.0, 0.85, 0.2, 0.28)
@export var spell_target_color: Color = Color(1.0, 0.3, 0.08, 0.38)

var runtime: WorldRuntime = null
var hover_cell: Vector2i = Vector2i.ZERO
var has_hover_cell: bool = false
var is_hover_cell_inside: bool = false
var is_spell_targeting: bool = false
var hovered_entity: Entity = null
var is_hovering_local_character: bool = false


func _exit_tree() -> void:
	if is_hovering_local_character:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _process(_delta: float) -> void:
	if runtime == null:
		return

	var next_cell: Vector2i = runtime.world_to_cell(get_global_mouse_position())
	var local_player: PlayerCharacter = runtime.get_selected_local_character()
	var next_is_spell_targeting: bool = runtime.has_selected_spell(local_player)
	var next_is_hover_cell_inside: bool = runtime.is_cell_inside(next_cell)
	var next_has_hover_cell: bool = next_is_hover_cell_inside if next_is_spell_targeting else runtime.is_cell_interactable(next_cell)
	var next_hovered_entity: Entity = null
	if runtime.is_cell_inside(next_cell):
		next_hovered_entity = runtime.get_entity_at_cell(next_cell) as Entity
	var next_is_hovering_local_character: bool = _is_locally_owned_character(next_hovered_entity)
	if hovered_entity != null and not is_instance_valid(hovered_entity):
		hovered_entity = null
	if (
		hover_cell == next_cell
		and has_hover_cell == next_has_hover_cell
		and is_hover_cell_inside == next_is_hover_cell_inside
		and is_spell_targeting == next_is_spell_targeting
		and hovered_entity == next_hovered_entity
		and is_hovering_local_character == next_is_hovering_local_character
	):
		return

	var did_hovered_cell_change: bool = hover_cell != next_cell or is_hover_cell_inside != next_is_hover_cell_inside
	hover_cell = next_cell
	has_hover_cell = next_has_hover_cell
	is_hover_cell_inside = next_is_hover_cell_inside
	is_spell_targeting = next_is_spell_targeting
	is_hovering_local_character = next_is_hovering_local_character
	Input.set_default_cursor_shape(
		Input.CURSOR_POINTING_HAND if is_hovering_local_character else Input.CURSOR_ARROW
	)
	if hovered_entity != next_hovered_entity:
		hovered_entity = next_hovered_entity
		hovered_entity_changed.emit(hovered_entity)
	if did_hovered_cell_change:
		hovered_cell_changed.emit(hover_cell, is_hover_cell_inside)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	var mouse_button_event: InputEventMouseButton = event as InputEventMouseButton
	if (
		mouse_button_event == null
		or not mouse_button_event.pressed
		or mouse_button_event.button_index != MOUSE_BUTTON_LEFT
		or runtime == null
	):
		return
	var local_character: PlayerCharacter = get_hovered_entity() as PlayerCharacter
	if local_character == null or not local_character.is_locally_owned:
		return
	if runtime.select_local_character(local_character):
		get_viewport().set_input_as_handled()


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


func get_hovered_cell() -> Vector2i:
	return hover_cell


func has_hovered_world_cell() -> bool:
	return is_hover_cell_inside


func _is_locally_owned_character(entity: Entity) -> bool:
	var player_character: PlayerCharacter = entity as PlayerCharacter
	return (
		player_character != null
		and is_instance_valid(player_character)
		and player_character.is_locally_owned
	)
