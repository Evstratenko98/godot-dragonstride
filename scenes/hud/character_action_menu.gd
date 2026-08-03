class_name CharacterActionMenu
extends Control

const FALLBACK_PANEL_SIZE := Vector2(104.0, 40.0)
const VIEWPORT_MARGIN := 8.0
const HEAD_OFFSET := 62.0
const CLOSE_BUTTON_OFFSET := Vector2(-3.0, -6.0)
const CLOSE_BUTTON_RIGHT_OVERHANG := 9.0
const CLOSE_BUTTON_TOP_OVERHANG := 6.0

@onready var popup_panel: PanelContainer = get_node("PopupPanel") as PanelContainer
@onready var close_button: Button = get_node("CloseButton") as Button
@onready var action_mode_bar: ActionModeBar = get_node("PopupPanel/Content/ActionModeBar") as ActionModeBar

var runtime: WorldRuntime = null
var cell_hover: CellHover = null
var bound_player: PlayerCharacter = null
var is_input_blocked: bool = false
var pending_turn_start_character_id: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hide_popup()
	if not close_button.pressed.is_connected(close):
		close_button.pressed.connect(close)
	set_process(true)


func _exit_tree() -> void:
	_disconnect_context_signals()


func _process(_delta: float) -> void:
	if not pending_turn_start_character_id.is_empty():
		_try_open_pending_turn_start()
	if not is_open():
		return
	if not _can_remain_open():
		close()
		return
	_update_popup_position()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open() or is_input_blocked:
		return
	var mouse_button_event: InputEventMouseButton = event as InputEventMouseButton
	if (
		mouse_button_event == null
		or not mouse_button_event.pressed
		or mouse_button_event.button_index != MOUSE_BUTTON_LEFT
	):
		return
	var hovered_character: PlayerCharacter = null
	if cell_hover != null:
		hovered_character = cell_hover.get_hovered_entity() as PlayerCharacter
	if hovered_character == bound_player:
		return
	close()


func configure_context(new_runtime: WorldRuntime, new_cell_hover: CellHover) -> void:
	_disconnect_context_signals()
	pending_turn_start_character_id = ""
	bound_player = null
	runtime = new_runtime
	cell_hover = new_cell_hover
	action_mode_bar.configure_runtime(runtime)
	if runtime != null:
		if not runtime.selected_local_character_changed.is_connected(_on_selected_local_character_changed):
			runtime.selected_local_character_changed.connect(_on_selected_local_character_changed)
		if runtime.turn_manager != null and not runtime.turn_manager.player_turn_started.is_connected(_on_player_turn_started):
			runtime.turn_manager.player_turn_started.connect(_on_player_turn_started)
		if runtime.spells != null and not runtime.spells.targeting_changed.is_connected(_on_spell_targeting_changed):
			runtime.spells.targeting_changed.connect(_on_spell_targeting_changed)
	if cell_hover != null and not cell_hover.selected_local_character_clicked.is_connected(_on_selected_local_character_clicked):
		cell_hover.selected_local_character_clicked.connect(_on_selected_local_character_clicked)
	bind_character(null if runtime == null else runtime.get_selected_local_character())


func bind_character(character: PlayerCharacter) -> void:
	if character == bound_player:
		action_mode_bar.bind_character(character)
		return
	close()
	_disconnect_player_signals()
	bound_player = character
	action_mode_bar.bind_character(bound_player)
	if bound_player == null:
		return
	if not bound_player.movement_started.is_connected(_on_player_movement_started):
		bound_player.movement_started.connect(_on_player_movement_started)
	if not bound_player.vitality_changed.is_connected(_on_player_vitality_changed):
		bound_player.vitality_changed.connect(_on_player_vitality_changed)


func open_for_character(character: PlayerCharacter) -> bool:
	pending_turn_start_character_id = ""
	return _show_for_character(character)


func _show_for_character(character: PlayerCharacter) -> bool:
	if character == null or character != bound_player or is_input_blocked:
		return false
	if not _can_open():
		return false
	popup_panel.visible = true
	close_button.visible = true
	_update_popup_position()
	return true


func close() -> void:
	pending_turn_start_character_id = ""
	_hide_popup()


func is_open() -> bool:
	return popup_panel != null and popup_panel.visible


func handle_cancel() -> bool:
	if not is_open():
		return false
	close()
	return true


func set_input_blocked(should_block: bool) -> void:
	is_input_blocked = should_block
	action_mode_bar.set_cursor_suspended(should_block)
	if should_block:
		_hide_popup()
	elif not pending_turn_start_character_id.is_empty():
		_try_open_pending_turn_start.call_deferred()


func _can_open() -> bool:
	return (
		runtime != null
		and bound_player != null
		and is_instance_valid(bound_player)
		and bound_player.is_locally_owned
		and bound_player == runtime.get_selected_local_character()
		and bound_player.health > 0
		and not bound_player.is_moving
		and not bound_player.is_attacking
		and not bound_player.is_executing_move_path
		and not runtime.is_entity_casting(bound_player)
	)


func _can_remain_open() -> bool:
	return not is_input_blocked and _can_open() and bound_player.visible


func _update_popup_position() -> void:
	if bound_player == null or not is_instance_valid(bound_player):
		return
	var character_screen_position: Vector2 = bound_player.get_global_transform_with_canvas().origin
	var panel_size: Vector2 = popup_panel.size
	if panel_size.x <= 0.0 or panel_size.y <= 0.0:
		panel_size = FALLBACK_PANEL_SIZE
	var viewport_size: Vector2 = get_viewport_rect().size
	var desired_position: Vector2 = Vector2(
		character_screen_position.x - panel_size.x * 0.5,
		character_screen_position.y - panel_size.y - HEAD_OFFSET
	)
	popup_panel.position = Vector2(
		clampf(
			desired_position.x,
			VIEWPORT_MARGIN,
			maxf(
				VIEWPORT_MARGIN,
				viewport_size.x - panel_size.x - VIEWPORT_MARGIN - CLOSE_BUTTON_RIGHT_OVERHANG
			)
		),
		clampf(
			desired_position.y,
			VIEWPORT_MARGIN + CLOSE_BUTTON_TOP_OVERHANG,
			maxf(
				VIEWPORT_MARGIN + CLOSE_BUTTON_TOP_OVERHANG,
				viewport_size.y - panel_size.y - VIEWPORT_MARGIN
			)
		)
	)
	close_button.position = popup_panel.position + Vector2(panel_size.x, 0.0) + CLOSE_BUTTON_OFFSET


func _hide_popup() -> void:
	popup_panel.visible = false
	close_button.visible = false


func _try_open_pending_turn_start() -> void:
	if pending_turn_start_character_id.is_empty() or is_input_blocked or runtime == null:
		return
	var selected_character: PlayerCharacter = runtime.get_selected_local_character()
	if (
		selected_character == null
		or selected_character.entity_id != pending_turn_start_character_id
		or runtime.turn_manager == null
		or not runtime.turn_manager.is_entity_active_in_turn(selected_character)
	):
		pending_turn_start_character_id = ""
		return
	if _show_for_character(selected_character):
		pending_turn_start_character_id = ""


func _disconnect_context_signals() -> void:
	_disconnect_player_signals()
	if runtime != null:
		if runtime.selected_local_character_changed.is_connected(_on_selected_local_character_changed):
			runtime.selected_local_character_changed.disconnect(_on_selected_local_character_changed)
		if runtime.turn_manager != null and runtime.turn_manager.player_turn_started.is_connected(_on_player_turn_started):
			runtime.turn_manager.player_turn_started.disconnect(_on_player_turn_started)
		if runtime.spells != null and runtime.spells.targeting_changed.is_connected(_on_spell_targeting_changed):
			runtime.spells.targeting_changed.disconnect(_on_spell_targeting_changed)
	if cell_hover != null and cell_hover.selected_local_character_clicked.is_connected(_on_selected_local_character_clicked):
		cell_hover.selected_local_character_clicked.disconnect(_on_selected_local_character_clicked)


func _disconnect_player_signals() -> void:
	if bound_player == null or not is_instance_valid(bound_player):
		return
	if bound_player.movement_started.is_connected(_on_player_movement_started):
		bound_player.movement_started.disconnect(_on_player_movement_started)
	if bound_player.vitality_changed.is_connected(_on_player_vitality_changed):
		bound_player.vitality_changed.disconnect(_on_player_vitality_changed)


func _on_selected_local_character_clicked(character: PlayerCharacter) -> void:
	open_for_character(character)


func _on_selected_local_character_changed(character: PlayerCharacter) -> void:
	bind_character(character)
	open_for_character(character)


func _on_player_turn_started(player_id: String) -> void:
	if runtime == null:
		return
	var selected_character: PlayerCharacter = runtime.get_selected_local_character()
	if selected_character == null or selected_character.owner_player_id != player_id:
		pending_turn_start_character_id = ""
		return
	pending_turn_start_character_id = selected_character.entity_id
	_try_open_pending_turn_start.call_deferred()


func _on_player_movement_started(_from_cell: Vector2i, _target_cell: Vector2i) -> void:
	close()


func _on_player_vitality_changed(current_health: int, _maximum_health: int) -> void:
	if current_health <= 0:
		close()


func _on_spell_targeting_changed(is_targeting: bool, _spell_slot_index: int) -> void:
	if is_targeting:
		close()
