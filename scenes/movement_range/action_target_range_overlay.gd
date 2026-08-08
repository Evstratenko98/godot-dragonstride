class_name ActionTargetRangeOverlay
extends Node2D

const ATTACK_OUTLINE_COLOR := Color(0.58, 0.08, 0.16, 0.96)
const ATTACK_FILL_COLOR := Color(0.42, 0.035, 0.09, 0.30)
const INTERACTION_OUTLINE_COLOR := Color(1.0, 0.82, 0.20, 0.98)
const INTERACTION_FILL_COLOR := Color(1.0, 0.72, 0.08, 0.26)
const OUTLINE_WIDTH := 3.0

var runtime: WorldRuntime = null
var displayed_mode: int = -1
var displayed_surfaces: Array[Vector3i] = []


func _process(_delta: float) -> void:
	_refresh_displayed_cells()


func _draw() -> void:
	if runtime == null or displayed_surfaces.is_empty():
		return
	var outline_color: Color = ATTACK_OUTLINE_COLOR
	var fill_color: Color = ATTACK_FILL_COLOR
	if displayed_mode == PlayerCharacter.ActionMode.INTERACT:
		outline_color = INTERACTION_OUTLINE_COLOR
		fill_color = INTERACTION_FILL_COLOR
	var cell_size: int = runtime.get_cell_size()
	var cell_dimensions: Vector2 = Vector2(cell_size, cell_size)
	var half_cell: Vector2 = cell_dimensions * 0.5
	for surface: Vector3i in displayed_surfaces:
		var local_center: Vector2 = to_local(runtime.surface_to_world(surface))
		var cell_rect: Rect2 = Rect2(local_center - half_cell, cell_dimensions)
		draw_rect(cell_rect, fill_color, true)
		draw_rect(cell_rect, outline_color, false, OUTLINE_WIDTH, false)


func configure_context(new_runtime: WorldRuntime) -> void:
	runtime = new_runtime
	_refresh_displayed_cells(true)


func _refresh_displayed_cells(should_force_redraw: bool = false) -> void:
	var next_mode: int = -1
	var next_surfaces: Array[Vector3i] = []
	var selected_character: PlayerCharacter = null if runtime == null else runtime.get_selected_local_character()
	if _can_show_for(selected_character):
		next_mode = selected_character.action_mode
		if next_mode == PlayerCharacter.ActionMode.ATTACK:
			next_surfaces = runtime.get_available_attack_surfaces(selected_character)
		elif next_mode == PlayerCharacter.ActionMode.INTERACT:
			next_surfaces = runtime.get_available_interaction_surfaces(selected_character)
	if not should_force_redraw and next_mode == displayed_mode and next_surfaces == displayed_surfaces:
		return
	displayed_mode = next_mode
	displayed_surfaces = next_surfaces
	if selected_character != null:
		z_index = selected_character.current_surface.z * 20 + 12
	queue_redraw()


func _can_show_for(character: PlayerCharacter) -> bool:
	return (
		character != null
		and is_instance_valid(character)
		and character.is_locally_owned
		and character.can_process_local_input()
		and character.health > 0
		and runtime != null
		and not runtime.has_selected_spell(character)
		and character.action_mode in [
			PlayerCharacter.ActionMode.ATTACK,
			PlayerCharacter.ActionMode.INTERACT,
		]
	)
