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
var active_player: PlayerCharacter = null
var hovered_entity: Entity = null
var reachable_cells: Array[Vector2i] = []
var hovered_reachable_cells: Array[Vector2i] = []


func _exit_tree() -> void:
	_disconnect_runtime_signals()
	_disconnect_active_player_signals()
	_disconnect_hover_signal()


func _draw() -> void:
	if runtime == null:
		return
	if not _is_foreign_entity_hovered():
		_draw_cell_range(reachable_cells, outline_color, fill_color)
		return
	_draw_cell_range(
		hovered_reachable_cells,
		_get_hover_outline_color(hovered_entity),
		_get_hover_fill_color(hovered_entity)
	)


func _draw_cell_range(cells: Array[Vector2i], range_outline_color: Color, range_fill_color: Color) -> void:
	var cell_size: int = runtime.get_cell_size()
	var cell_dimensions: Vector2 = Vector2(cell_size, cell_size)
	var half_cell: Vector2 = cell_dimensions * 0.5
	for cell: Vector2i in cells:
		var local_center: Vector2 = to_local(runtime.cell_to_world(cell))
		var cell_rect: Rect2 = Rect2(local_center - half_cell, cell_dimensions)
		draw_rect(cell_rect, range_fill_color, true)
		draw_rect(cell_rect, range_outline_color, false, outline_width, false)


func configure_context(new_runtime: WorldRuntime, new_cell_hover: CellHover) -> void:
	_disconnect_runtime_signals()
	_disconnect_active_player_signals()
	_disconnect_hover_signal()
	runtime = new_runtime
	cell_hover = new_cell_hover
	if runtime != null:
		if not runtime.world_occupancy_changed.is_connected(_on_world_occupancy_changed):
			runtime.world_occupancy_changed.connect(_on_world_occupancy_changed)
		if runtime.turn_manager != null and not runtime.turn_manager.turn_state_changed.is_connected(_on_turn_state_changed):
			runtime.turn_manager.turn_state_changed.connect(_on_turn_state_changed)
	if cell_hover != null:
		hovered_entity = cell_hover.get_hovered_entity()
		if not cell_hover.hovered_entity_changed.is_connected(_on_cell_hover_hovered_entity_changed):
			cell_hover.hovered_entity_changed.connect(_on_cell_hover_hovered_entity_changed)
	_refresh_ranges()


func _refresh_ranges() -> void:
	reachable_cells.clear()
	hovered_reachable_cells.clear()
	_bind_active_player()
	if runtime != null and runtime.turn_manager != null and active_player != null:
		if runtime.turn_manager.get_state() == WorldTurns.STATE_PLAYER_TURN and not active_player.is_moving:
			var steps_left: int = runtime.turn_manager.get_steps_left()
			reachable_cells = runtime.get_reachable_cells_for_entity(active_player, steps_left)
	_refresh_hovered_range()
	queue_redraw()


func _refresh_hovered_range() -> void:
	hovered_reachable_cells.clear()
	if not _is_foreign_entity_hovered():
		return
	if hovered_entity.health <= 0 or hovered_entity.is_moving:
		return

	var maximum_steps: int = hovered_entity.get_max_movement_steps_per_turn()
	if runtime.turn_manager != null and runtime.turn_manager.is_entity_active_in_turn(hovered_entity):
		maximum_steps = runtime.turn_manager.get_steps_left()
	hovered_reachable_cells = runtime.get_reachable_cells_for_entity(hovered_entity, maximum_steps)


func _is_foreign_entity_hovered() -> bool:
	if runtime == null or hovered_entity == null or not is_instance_valid(hovered_entity):
		return false
	var local_player: PlayerCharacter = runtime.get_local_player()
	return hovered_entity != local_player


func _bind_active_player() -> void:
	var next_player: PlayerCharacter = null
	if runtime != null and runtime.turn_manager != null:
		next_player = runtime.get_player_by_entity_id(runtime.turn_manager.get_active_entity_id())
	if active_player == next_player:
		return
	_disconnect_active_player_signals()
	active_player = next_player
	if active_player == null:
		return
	if not active_player.movement_started.is_connected(_on_active_player_movement_started):
		active_player.movement_started.connect(_on_active_player_movement_started)
	if not active_player.movement_finished.is_connected(_on_active_player_movement_finished):
		active_player.movement_finished.connect(_on_active_player_movement_finished)


func _disconnect_runtime_signals() -> void:
	if runtime == null:
		return
	if runtime.world_occupancy_changed.is_connected(_on_world_occupancy_changed):
		runtime.world_occupancy_changed.disconnect(_on_world_occupancy_changed)
	if runtime.turn_manager != null and runtime.turn_manager.turn_state_changed.is_connected(_on_turn_state_changed):
		runtime.turn_manager.turn_state_changed.disconnect(_on_turn_state_changed)


func _disconnect_active_player_signals() -> void:
	if active_player == null or not is_instance_valid(active_player):
		active_player = null
		return
	if active_player.movement_started.is_connected(_on_active_player_movement_started):
		active_player.movement_started.disconnect(_on_active_player_movement_started)
	if active_player.movement_finished.is_connected(_on_active_player_movement_finished):
		active_player.movement_finished.disconnect(_on_active_player_movement_finished)
	active_player = null


func _disconnect_hover_signal() -> void:
	if cell_hover != null and cell_hover.hovered_entity_changed.is_connected(_on_cell_hover_hovered_entity_changed):
		cell_hover.hovered_entity_changed.disconnect(_on_cell_hover_hovered_entity_changed)
	cell_hover = null
	hovered_entity = null
	hovered_reachable_cells.clear()


func _get_hover_outline_color(entity: Entity) -> Color:
	if entity.entity_type == Entity.EntityType.NEUTRAL:
		return neutral_outline_color
	if entity.entity_type == Entity.EntityType.NPC:
		return npc_outline_color
	return hostile_outline_color


func _get_hover_fill_color(entity: Entity) -> Color:
	if entity.entity_type == Entity.EntityType.NEUTRAL:
		return neutral_fill_color
	if entity.entity_type == Entity.EntityType.NPC:
		return npc_fill_color
	return hostile_fill_color


func _on_turn_state_changed() -> void:
	_refresh_ranges()


func _on_world_occupancy_changed() -> void:
	_refresh_ranges()


func _on_active_player_movement_started(_from_cell: Vector2i, _target_cell: Vector2i) -> void:
	reachable_cells.clear()
	if hovered_entity == active_player:
		hovered_reachable_cells.clear()
	queue_redraw()


func _on_active_player_movement_finished(_from_cell: Vector2i, _target_cell: Vector2i) -> void:
	_refresh_ranges()


func _on_cell_hover_hovered_entity_changed(entity: Entity) -> void:
	hovered_entity = entity
	_refresh_hovered_range()
	queue_redraw()
