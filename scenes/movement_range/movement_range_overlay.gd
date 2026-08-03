class_name MovementRangeOverlay
extends Node2D

@export var outline_color: Color = Color(1.0, 0.82, 0.20, 0.95)
@export var fill_color: Color = Color(1.0, 0.82, 0.20, 0.08)
@export var hostile_outline_color: Color = Color(0.95, 0.18, 0.20, 0.95)
@export var hostile_fill_color: Color = Color(0.95, 0.18, 0.20, 0.10)
@export var neutral_outline_color: Color = Color(0.62, 0.64, 0.68, 0.92)
@export var neutral_fill_color: Color = Color(0.62, 0.64, 0.68, 0.10)
@export var npc_outline_color: Color = Color(0.22, 0.78, 0.36, 0.95)
@export var npc_fill_color: Color = Color(0.22, 0.78, 0.36, 0.10)
@export var outline_width: float = 3.0

var runtime: WorldRuntime = null
var cell_hover: CellHover = null
var hovered_entity: Entity = null
var reachable_cells: Array[Vector2i] = []


func _exit_tree() -> void:
	_disconnect_runtime_signals()
	_disconnect_hovered_entity_signals()
	_disconnect_hover_signal()


func _draw() -> void:
	if runtime == null or hovered_entity == null or not is_instance_valid(hovered_entity):
		return
	_draw_cell_range(
		reachable_cells,
		_get_hover_outline_color(hovered_entity),
		_get_hover_fill_color(hovered_entity)
	)


func configure_context(new_runtime: WorldRuntime, new_cell_hover: CellHover) -> void:
	_disconnect_runtime_signals()
	_disconnect_hovered_entity_signals()
	_disconnect_hover_signal()
	runtime = new_runtime
	cell_hover = new_cell_hover
	if runtime != null:
		if not runtime.world_occupancy_changed.is_connected(_on_world_occupancy_changed):
			runtime.world_occupancy_changed.connect(_on_world_occupancy_changed)
		if runtime.turn_manager != null and not runtime.turn_manager.turn_state_changed.is_connected(_on_turn_state_changed):
			runtime.turn_manager.turn_state_changed.connect(_on_turn_state_changed)
		if runtime.spells != null and not runtime.spells.targeting_changed.is_connected(_on_spell_targeting_changed):
			runtime.spells.targeting_changed.connect(_on_spell_targeting_changed)
	if cell_hover != null:
		hovered_entity = cell_hover.get_hovered_entity()
		if not cell_hover.hovered_entity_changed.is_connected(_on_cell_hover_hovered_entity_changed):
			cell_hover.hovered_entity_changed.connect(_on_cell_hover_hovered_entity_changed)
	_connect_hovered_entity_signals()
	_refresh_range()


func _draw_cell_range(cells: Array[Vector2i], range_outline_color: Color, range_fill_color: Color) -> void:
	var cell_size: int = runtime.get_cell_size()
	var cell_dimensions: Vector2 = Vector2(cell_size, cell_size)
	var half_cell: Vector2 = cell_dimensions * 0.5
	for cell: Vector2i in cells:
		var local_center: Vector2 = to_local(runtime.cell_to_world(cell))
		var cell_rect: Rect2 = Rect2(local_center - half_cell, cell_dimensions)
		draw_rect(cell_rect, range_fill_color, true)
		draw_rect(cell_rect, range_outline_color, false, outline_width, false)


func _refresh_range() -> void:
	reachable_cells.clear()
	if (
		runtime == null
		or hovered_entity == null
		or not is_instance_valid(hovered_entity)
		or hovered_entity.health <= 0
		or hovered_entity.is_moving
		or _is_local_spell_targeting()
	):
		queue_redraw()
		return

	var maximum_steps: int = hovered_entity.get_max_movement_steps_per_turn()
	if runtime.turn_manager != null and runtime.turn_manager.is_entity_active_in_turn(hovered_entity):
		maximum_steps = runtime.turn_manager.get_steps_left(hovered_entity.entity_id)
	reachable_cells = runtime.get_reachable_cells_for_entity(hovered_entity, maximum_steps)
	queue_redraw()


func _connect_hovered_entity_signals() -> void:
	if hovered_entity == null or not is_instance_valid(hovered_entity):
		return
	if not hovered_entity.movement_started.is_connected(_on_hovered_entity_movement_started):
		hovered_entity.movement_started.connect(_on_hovered_entity_movement_started)
	if not hovered_entity.movement_finished.is_connected(_on_hovered_entity_movement_finished):
		hovered_entity.movement_finished.connect(_on_hovered_entity_movement_finished)


func _disconnect_hovered_entity_signals() -> void:
	if hovered_entity == null or not is_instance_valid(hovered_entity):
		return
	if hovered_entity.movement_started.is_connected(_on_hovered_entity_movement_started):
		hovered_entity.movement_started.disconnect(_on_hovered_entity_movement_started)
	if hovered_entity.movement_finished.is_connected(_on_hovered_entity_movement_finished):
		hovered_entity.movement_finished.disconnect(_on_hovered_entity_movement_finished)


func _disconnect_runtime_signals() -> void:
	if runtime == null:
		return
	if runtime.world_occupancy_changed.is_connected(_on_world_occupancy_changed):
		runtime.world_occupancy_changed.disconnect(_on_world_occupancy_changed)
	if runtime.turn_manager != null and runtime.turn_manager.turn_state_changed.is_connected(_on_turn_state_changed):
		runtime.turn_manager.turn_state_changed.disconnect(_on_turn_state_changed)
	if runtime.spells != null and runtime.spells.targeting_changed.is_connected(_on_spell_targeting_changed):
		runtime.spells.targeting_changed.disconnect(_on_spell_targeting_changed)


func _disconnect_hover_signal() -> void:
	if cell_hover != null and cell_hover.hovered_entity_changed.is_connected(_on_cell_hover_hovered_entity_changed):
		cell_hover.hovered_entity_changed.disconnect(_on_cell_hover_hovered_entity_changed)
	cell_hover = null
	hovered_entity = null
	reachable_cells.clear()


func _get_hover_outline_color(entity: Entity) -> Color:
	var player_character: PlayerCharacter = entity as PlayerCharacter
	if player_character != null and player_character.is_locally_owned:
		return outline_color
	if entity.entity_type == Entity.EntityType.NEUTRAL:
		return neutral_outline_color
	if entity.entity_type == Entity.EntityType.NPC:
		return npc_outline_color
	return hostile_outline_color


func _get_hover_fill_color(entity: Entity) -> Color:
	var player_character: PlayerCharacter = entity as PlayerCharacter
	if player_character != null and player_character.is_locally_owned:
		return fill_color
	if entity.entity_type == Entity.EntityType.NEUTRAL:
		return neutral_fill_color
	if entity.entity_type == Entity.EntityType.NPC:
		return npc_fill_color
	return hostile_fill_color


func _is_local_spell_targeting() -> bool:
	if runtime == null:
		return false
	var selected_character: PlayerCharacter = runtime.get_selected_local_character()
	return selected_character != null and runtime.has_selected_spell(selected_character)


func _on_turn_state_changed() -> void:
	_refresh_range()


func _on_world_occupancy_changed() -> void:
	_refresh_range()


func _on_spell_targeting_changed(_is_targeting: bool, _selected_slot_index: int) -> void:
	_refresh_range()


func _on_hovered_entity_movement_started(_from_cell: Vector2i, _target_cell: Vector2i) -> void:
	reachable_cells.clear()
	queue_redraw()


func _on_hovered_entity_movement_finished(_from_cell: Vector2i, _target_cell: Vector2i) -> void:
	_refresh_range()


func _on_cell_hover_hovered_entity_changed(entity: Entity) -> void:
	_disconnect_hovered_entity_signals()
	hovered_entity = entity
	_connect_hovered_entity_signals()
	_refresh_range()
