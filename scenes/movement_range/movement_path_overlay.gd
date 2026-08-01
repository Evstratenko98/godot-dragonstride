class_name MovementPathOverlay
extends Node2D

@export var available_outline_color: Color = Color(1.0, 0.82, 0.20, 1.0)
@export var available_fill_color: Color = Color(1.0, 0.82, 0.20, 0.30)
@export var distant_outline_color: Color = Color(0.56, 0.58, 0.62, 1.0)
@export var distant_fill_color: Color = Color(0.46, 0.48, 0.52, 0.34)
@export var outline_width: float = 3.0
@onready var step_label: Label = get_node("StepLabel") as Label

var runtime: WorldRuntime = null
var cell_hover: CellHover = null
var bound_player: PlayerCharacter = null
var preview_path: Array[Vector2i] = []
var is_path_available_this_turn: bool = false


func _process(_delta: float) -> void:
	if runtime == null:
		return
	var local_player: PlayerCharacter = runtime.get_local_player()
	if local_player != bound_player:
		_bind_player(local_player)


func _exit_tree() -> void:
	_disconnect_runtime_signals()
	_disconnect_player_signals()
	_disconnect_hover_signal()


func _draw() -> void:
	if runtime == null or preview_path.is_empty():
		return
	var cell_size: int = runtime.get_cell_size()
	var cell_dimensions: Vector2 = Vector2(cell_size, cell_size)
	var half_cell: Vector2 = cell_dimensions * 0.5
	var path_outline_color: Color = available_outline_color if is_path_available_this_turn else distant_outline_color
	var path_fill_color: Color = available_fill_color if is_path_available_this_turn else distant_fill_color
	for cell: Vector2i in preview_path:
		var local_center: Vector2 = to_local(runtime.cell_to_world(cell))
		var cell_rect: Rect2 = Rect2(local_center - half_cell, cell_dimensions)
		draw_rect(cell_rect, path_fill_color, true)
		draw_rect(cell_rect, path_outline_color, false, outline_width, false)


func configure_context(new_runtime: WorldRuntime, new_cell_hover: CellHover) -> void:
	_disconnect_runtime_signals()
	_disconnect_player_signals()
	_disconnect_hover_signal()
	runtime = new_runtime
	cell_hover = new_cell_hover
	if runtime != null:
		if not runtime.world_occupancy_changed.is_connected(_on_preview_context_changed):
			runtime.world_occupancy_changed.connect(_on_preview_context_changed)
		if runtime.turn_manager != null and not runtime.turn_manager.turn_state_changed.is_connected(_on_preview_context_changed):
			runtime.turn_manager.turn_state_changed.connect(_on_preview_context_changed)
		if runtime.spells != null and not runtime.spells.targeting_changed.is_connected(_on_spell_targeting_changed):
			runtime.spells.targeting_changed.connect(_on_spell_targeting_changed)
	if cell_hover != null and not cell_hover.hovered_cell_changed.is_connected(_on_hovered_cell_changed):
		cell_hover.hovered_cell_changed.connect(_on_hovered_cell_changed)
	_bind_player(null if runtime == null else runtime.get_local_player())
	_refresh_preview()


func _refresh_preview() -> void:
	preview_path.clear()
	is_path_available_this_turn = false
	step_label.visible = false
	if (
		runtime == null
		or cell_hover == null
		or bound_player == null
		or not is_instance_valid(bound_player)
		or bound_player.action_mode != PlayerCharacter.ActionMode.MOVE
		or not bound_player.can_process_local_input()
		or not runtime.can_entity_move_in_turn(bound_player)
		or runtime.has_selected_spell(bound_player)
		or not cell_hover.has_hovered_world_cell()
	):
		queue_redraw()
		return

	var start_cell: Vector2i = runtime.world_to_cell(bound_player.global_position)
	var target_cell: Vector2i = cell_hover.get_hovered_cell()
	preview_path = WorldGridPathfinder.find_path_to_cell(
		runtime,
		bound_player,
		start_cell,
		target_cell,
		true
	)
	if preview_path.is_empty():
		queue_redraw()
		return

	is_path_available_this_turn = true
	if runtime.turn_manager != null and runtime.turn_manager.is_turn_mode_enabled():
		is_path_available_this_turn = preview_path.size() <= runtime.turn_manager.get_steps_left()
	_update_step_label(target_cell)
	queue_redraw()


func _update_step_label(target_cell: Vector2i) -> void:
	var cell_size: int = runtime.get_cell_size()
	var label_size: Vector2 = Vector2(cell_size, cell_size)
	var local_center: Vector2 = to_local(runtime.cell_to_world(target_cell))
	step_label.position = local_center - label_size * 0.5
	step_label.size = label_size
	step_label.text = str(preview_path.size())
	step_label.visible = true


func _bind_player(player: PlayerCharacter) -> void:
	_disconnect_player_signals()
	bound_player = player
	if bound_player != null:
		if not bound_player.action_mode_changed.is_connected(_on_action_mode_changed):
			bound_player.action_mode_changed.connect(_on_action_mode_changed)
		if not bound_player.movement_started.is_connected(_on_player_movement_started):
			bound_player.movement_started.connect(_on_player_movement_started)
		if not bound_player.movement_finished.is_connected(_on_player_movement_finished):
			bound_player.movement_finished.connect(_on_player_movement_finished)
	_refresh_preview()


func _disconnect_player_signals() -> void:
	if bound_player == null or not is_instance_valid(bound_player):
		bound_player = null
		return
	if bound_player.action_mode_changed.is_connected(_on_action_mode_changed):
		bound_player.action_mode_changed.disconnect(_on_action_mode_changed)
	if bound_player.movement_started.is_connected(_on_player_movement_started):
		bound_player.movement_started.disconnect(_on_player_movement_started)
	if bound_player.movement_finished.is_connected(_on_player_movement_finished):
		bound_player.movement_finished.disconnect(_on_player_movement_finished)


func _disconnect_runtime_signals() -> void:
	if runtime == null:
		return
	if runtime.world_occupancy_changed.is_connected(_on_preview_context_changed):
		runtime.world_occupancy_changed.disconnect(_on_preview_context_changed)
	if runtime.turn_manager != null and runtime.turn_manager.turn_state_changed.is_connected(_on_preview_context_changed):
		runtime.turn_manager.turn_state_changed.disconnect(_on_preview_context_changed)
	if runtime.spells != null and runtime.spells.targeting_changed.is_connected(_on_spell_targeting_changed):
		runtime.spells.targeting_changed.disconnect(_on_spell_targeting_changed)


func _disconnect_hover_signal() -> void:
	if cell_hover != null and cell_hover.hovered_cell_changed.is_connected(_on_hovered_cell_changed):
		cell_hover.hovered_cell_changed.disconnect(_on_hovered_cell_changed)
	cell_hover = null


func _on_hovered_cell_changed(_cell: Vector2i, _is_inside_world: bool) -> void:
	_refresh_preview()


func _on_preview_context_changed() -> void:
	_refresh_preview()


func _on_action_mode_changed(_action_mode: int) -> void:
	_refresh_preview()


func _on_spell_targeting_changed(_is_targeting: bool, _spell_slot_index: int) -> void:
	_refresh_preview()


func _on_player_movement_started(_from_cell: Vector2i, _target_cell: Vector2i) -> void:
	preview_path.clear()
	step_label.visible = false
	queue_redraw()


func _on_player_movement_finished(_from_cell: Vector2i, _target_cell: Vector2i) -> void:
	_refresh_preview()
