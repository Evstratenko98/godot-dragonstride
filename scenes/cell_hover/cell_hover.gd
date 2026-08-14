class_name CellHover
extends Node2D

signal hovered_entity_changed(entity: Entity)
signal hovered_surface_changed(surface: Vector3i, is_inside_world: bool)
signal inspection_requested(target: Node)

@export var hover_color: Color = Color(1.0, 0.85, 0.2, 0.28)
@export var spell_target_color: Color = Color(1.0, 0.3, 0.08, 0.38)

@onready var surface_label: Label = get_node("SurfaceLabel") as Label

var runtime: WorldRuntime = null
var hover_surface: Vector3i = Vector3i.ZERO
var hovered_cell: Vector2i = Vector2i(-1, -1)
var available_surfaces: Array[Vector3i] = []
var selected_surface_index: int = -1
var selected_elevation: int = WorldGridTopology.MIN_ELEVATION
var maximum_elevation: int = WorldGridTopology.MIN_ELEVATION
var has_hover_surface: bool = false
var is_hover_surface_inside: bool = false
var is_spell_targeting: bool = false
var hovered_entity: Entity = null
var is_hovering_local_character: bool = false
var bound_character: PlayerCharacter = null


func _exit_tree() -> void:
	if runtime != null and runtime.selected_local_character_changed.is_connected(_on_selected_character_changed):
		runtime.selected_local_character_changed.disconnect(_on_selected_character_changed)
	if runtime != null and runtime.visibility != null and runtime.visibility.local_visibility_changed.is_connected(_on_visibility_changed):
		runtime.visibility.local_visibility_changed.disconnect(_on_visibility_changed)
	_bind_character(null)
	GameCursor.restore_default_cursor()


func _process(_delta: float) -> void:
	if runtime == null:
		return
	var projected: Vector3i = runtime.world_to_surface(get_global_mouse_position())
	var next_cell: Vector2i = Vector2i(projected.x, projected.y)
	if next_cell != hovered_cell:
		hovered_cell = next_cell
		_rebuild_surface_choices()
	_refresh_hover_state()


func _unhandled_input(event: InputEvent) -> void:
	if runtime == null:
		return
	if event.is_action_pressed("cycle_surface_level"):
		_cycle_elevation()
		get_viewport().set_input_as_handled()
		return
	var mouse_button_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button_event == null or not mouse_button_event.pressed:
		return
	if mouse_button_event.button_index == MOUSE_BUTTON_RIGHT:
		_request_world_inspection()
		return
	if mouse_button_event.button_index != MOUSE_BUTTON_LEFT:
		return
	var local_character: PlayerCharacter = get_hovered_entity() as PlayerCharacter
	if local_character == null or not local_character.is_locally_owned:
		return
	if runtime.select_local_character(local_character):
		get_viewport().set_input_as_handled()


func _request_world_inspection() -> void:
	var fallback_surface: Vector3i = (
		hover_surface
		if is_hover_surface_inside
		else WorldGridTopology.INVALID_SURFACE
	)
	var target: Node = WorldInspectionHitTester.find_target(
		runtime,
		get_global_mouse_position(),
		fallback_surface
	)
	if target == null:
		return
	inspection_requested.emit(target)
	get_viewport().set_input_as_handled()


func _draw() -> void:
	if runtime == null or not has_hover_surface:
		return
	var cell_size: int = runtime.get_cell_size()
	var rect: Rect2 = Rect2(
		Vector2(hover_surface.x, hover_surface.y) * cell_size,
		Vector2(cell_size, cell_size)
	)
	var color: Color = spell_target_color if is_spell_targeting else hover_color
	draw_rect(rect, color, true)


func configure_context(new_runtime: WorldRuntime) -> void:
	if runtime != null and runtime.selected_local_character_changed.is_connected(_on_selected_character_changed):
		runtime.selected_local_character_changed.disconnect(_on_selected_character_changed)
	runtime = new_runtime
	runtime.set_selected_input_surface(WorldGridTopology.INVALID_SURFACE)
	selected_elevation = WorldGridTopology.MIN_ELEVATION
	maximum_elevation = _get_maximum_level_elevation()
	if not runtime.selected_local_character_changed.is_connected(_on_selected_character_changed):
		runtime.selected_local_character_changed.connect(_on_selected_character_changed)
	if runtime.visibility != null and not runtime.visibility.local_visibility_changed.is_connected(_on_visibility_changed):
		runtime.visibility.local_visibility_changed.connect(_on_visibility_changed)
	_bind_character(runtime.get_selected_local_character())
	hovered_cell = Vector2i(-1, -1)
	_rebuild_surface_choices()
	_refresh_hover_state()


func get_hovered_entity() -> Entity:
	if hovered_entity == null or not is_instance_valid(hovered_entity):
		return null
	return hovered_entity


func get_hovered_surface() -> Vector3i:
	return hover_surface


func has_hovered_world_surface() -> bool:
	return is_hover_surface_inside and not available_surfaces.is_empty()


func _rebuild_surface_choices() -> void:
	available_surfaces.clear()
	selected_surface_index = -1
	if runtime == null or hovered_cell.x < 0 or hovered_cell.y < 0:
		return
	available_surfaces = runtime.get_surfaces_at(hovered_cell)
	if available_surfaces.is_empty():
		return
	for index: int in range(available_surfaces.size()):
		if available_surfaces[index].z == selected_elevation:
			selected_surface_index = index
			break
	if selected_surface_index < 0:
		selected_surface_index = _get_closest_surface_index(selected_elevation)
	hover_surface = available_surfaces[selected_surface_index]


func _cycle_elevation() -> void:
	selected_elevation = (
		WorldGridTopology.MIN_ELEVATION
		if selected_elevation >= maximum_elevation
		else selected_elevation + 1
	)
	_rebuild_surface_choices()
	_refresh_hover_state(true)


func _get_maximum_level_elevation() -> int:
	var result: int = WorldGridTopology.MIN_ELEVATION
	if runtime == null:
		return result
	for surface: Vector3i in runtime.get_all_surfaces():
		result = maxi(result, surface.z)
	return result


func _get_closest_surface_index(target_elevation: int) -> int:
	var best_index: int = 0
	var best_distance: int = absi(available_surfaces[0].z - target_elevation)
	for index: int in range(1, available_surfaces.size()):
		var distance: int = absi(available_surfaces[index].z - target_elevation)
		if distance < best_distance or (
			distance == best_distance
			and available_surfaces[index].z < available_surfaces[best_index].z
		):
			best_index = index
			best_distance = distance
	return best_index


func _refresh_hover_state(force_change: bool = false) -> void:
	if runtime == null:
		return
	if not available_surfaces.is_empty() and selected_surface_index >= 0:
		hover_surface = available_surfaces[selected_surface_index]
	var local_player: PlayerCharacter = runtime.get_selected_local_character()
	var next_is_spell_targeting: bool = runtime.has_selected_spell(local_player)
	var next_is_inside: bool = (
		not available_surfaces.is_empty()
		and runtime.is_surface_inside(hover_surface)
		and runtime.has_surface(hover_surface)
	)
	var is_currently_visible: bool = (
		next_is_inside
		and (runtime.visibility == null or runtime.visibility.is_surface_visible_for_local_player(hover_surface))
	)
	var is_movement_mode: bool = bound_character != null and bound_character.action_mode == PlayerCharacter.ActionMode.MOVE
	var next_has_hover: bool = (
		next_is_inside
		if is_movement_mode
		else is_currently_visible and (next_is_spell_targeting or runtime.is_surface_interactable(hover_surface))
	)
	var next_hovered_entity: Entity = runtime.get_entity_at_surface(hover_surface) as Entity if is_currently_visible else null
	var next_is_hovering_local: bool = _is_locally_owned_character(next_hovered_entity)
	if hovered_entity != null and not is_instance_valid(hovered_entity):
		hovered_entity = null
	var did_surface_change: bool = force_change or hover_surface != get_meta("last_surface", Vector3i(-1, -1, -1))
	set_meta("last_surface", hover_surface)
	has_hover_surface = next_has_hover
	is_hover_surface_inside = next_is_inside
	is_spell_targeting = next_is_spell_targeting
	is_hovering_local_character = next_is_hovering_local
	Input.set_default_cursor_shape(
		Input.CURSOR_POINTING_HAND if is_hovering_local_character else Input.CURSOR_ARROW
	)
	_refresh_action_cursor_for_visibility(is_currently_visible)
	if hovered_entity != next_hovered_entity:
		hovered_entity = next_hovered_entity
		hovered_entity_changed.emit(hovered_entity)
	if did_surface_change:
		runtime.set_selected_input_surface(hover_surface if is_hover_surface_inside else WorldGridTopology.INVALID_SURFACE)
		hovered_surface_changed.emit(hover_surface, is_hover_surface_inside)
	_update_surface_label()
	z_index = 2011
	queue_redraw()


func _update_surface_label() -> void:
	if surface_label == null:
		return
	surface_label.visible = (
		has_hover_surface
		and bound_character != null
		and (bound_character.action_mode == PlayerCharacter.ActionMode.MOVE or is_spell_targeting)
		and (runtime.visibility == null or runtime.visibility.is_surface_visible_for_local_player(hover_surface))
	)
	if not surface_label.visible:
		return
	var cell_size: int = runtime.get_cell_size()
	surface_label.position = Vector2(hover_surface.x, hover_surface.y) * cell_size + Vector2(4, 3)
	surface_label.text = "Высота: %d  [Z]" % hover_surface.z


func _is_locally_owned_character(entity: Entity) -> bool:
	var player_character: PlayerCharacter = entity as PlayerCharacter
	return (
		player_character != null
		and is_instance_valid(player_character)
		and player_character.is_locally_owned
	)


func _refresh_action_cursor_for_visibility(is_currently_visible: bool) -> void:
	if bound_character == null:
		return
	if is_spell_targeting:
		if is_currently_visible:
			InventoryBarCursor.apply_meteor_targeting()
		else:
			InventoryBarCursor.apply(PlayerCharacter.ActionMode.ATTACK, false)
		return
	if bound_character.action_mode in [PlayerCharacter.ActionMode.ATTACK, PlayerCharacter.ActionMode.INTERACT, PlayerCharacter.ActionMode.SPECIAL_ABILITY]:
		InventoryBarCursor.apply(bound_character.action_mode, is_currently_visible)


func _on_selected_character_changed(character: PlayerCharacter) -> void:
	_bind_character(character)
	_rebuild_surface_choices()
	_refresh_hover_state(true)


func _bind_character(character: PlayerCharacter) -> void:
	if bound_character != null and bound_character.action_mode_changed.is_connected(_on_action_mode_changed):
		bound_character.action_mode_changed.disconnect(_on_action_mode_changed)
	bound_character = character
	if bound_character != null and not bound_character.action_mode_changed.is_connected(_on_action_mode_changed):
		bound_character.action_mode_changed.connect(_on_action_mode_changed)


func _on_action_mode_changed(_action_mode: int) -> void:
	_rebuild_surface_choices()
	_refresh_hover_state(true)


func _on_visibility_changed() -> void:
	_refresh_hover_state(true)
