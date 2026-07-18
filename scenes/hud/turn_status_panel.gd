class_name TurnStatusPanel
extends PanelContainer

const PANEL_COLOR := Color(0.055, 0.065, 0.085, 0.72)
const BORDER_COLOR := Color(0.34, 0.37, 0.43, 0.86)
const TEXT_COLOR := Color(0.94, 0.96, 1.0, 1.0)
const MUTED_TEXT_COLOR := Color(0.68, 0.72, 0.78, 1.0)
const ACTIVE_COLOR := Color(1.0, 0.82, 0.20, 1.0)
const EMPTY_STEP_COLOR := Color(0.25, 0.28, 0.34, 1.0)
const WORLD_MESSAGES := [
	"Мир действует",
	"Мир действует.",
	"Мир действует..",
	"Мир действует...",
]

var runtime: WorldRuntime = null
var day_label: Label = null
var player_row: HBoxContainer = null
var active_portrait: PlayerPortrait = null
var steps_row: VBoxContainer = null
var steps_label: Label = null
var steps_container: HBoxContainer = null
var step_segments: Array[ColorRect] = []
var world_label: Label = null
var world_animation_timer: Timer = null
var world_message_index: int = 0


func _ready() -> void:
	custom_minimum_size = Vector2(328.0, 82.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_style()
	_build_content()
	visible = false


func _exit_tree() -> void:
	_disconnect_turn_signal()


func configure_runtime(new_runtime: WorldRuntime) -> void:
	_disconnect_turn_signal()
	runtime = new_runtime
	if runtime != null and runtime.turn_manager != null:
		if not runtime.turn_manager.turn_state_changed.is_connected(_on_turn_state_changed):
			runtime.turn_manager.turn_state_changed.connect(_on_turn_state_changed)
	_refresh()


func bind_session() -> void:
	_refresh()


func _apply_style() -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(5.0)
	add_theme_stylebox_override("panel", style)


func _build_content() -> void:
	var content: VBoxContainer = VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 2)
	add_child.call_deferred(content)

	day_label = Label.new()
	day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	day_label.add_theme_font_size_override("font_size", 12)
	day_label.add_theme_color_override("font_color", MUTED_TEXT_COLOR)
	content.add_child.call_deferred(day_label)

	player_row = HBoxContainer.new()
	player_row.alignment = BoxContainer.ALIGNMENT_CENTER
	player_row.add_theme_constant_override("separation", 6)
	content.add_child.call_deferred(player_row)

	var turn_label: Label = Label.new()
	turn_label.text = "Ход совершает"
	turn_label.add_theme_font_size_override("font_size", 14)
	turn_label.add_theme_color_override("font_color", TEXT_COLOR)
	player_row.add_child.call_deferred(turn_label)

	active_portrait = PlayerPortrait.new()
	active_portrait.set_diameter(30.0)
	player_row.add_child.call_deferred(active_portrait)

	world_label = Label.new()
	world_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	world_label.add_theme_font_size_override("font_size", 14)
	world_label.add_theme_color_override("font_color", TEXT_COLOR)
	content.add_child.call_deferred(world_label)

	steps_row = VBoxContainer.new()
	steps_row.alignment = BoxContainer.ALIGNMENT_CENTER
	steps_row.add_theme_constant_override("separation", 2)
	content.add_child.call_deferred(steps_row)

	steps_label = Label.new()
	steps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	steps_label.add_theme_font_size_override("font_size", 10)
	steps_label.add_theme_color_override("font_color", TEXT_COLOR)
	steps_row.add_child.call_deferred(steps_label)

	steps_container = HBoxContainer.new()
	steps_container.alignment = BoxContainer.ALIGNMENT_CENTER
	steps_container.add_theme_constant_override("separation", 3)
	steps_row.add_child.call_deferred(steps_container)

	world_animation_timer = Timer.new()
	world_animation_timer.wait_time = 0.35
	world_animation_timer.timeout.connect(_on_world_animation_timer_timeout)
	add_child.call_deferred(world_animation_timer)


func _refresh() -> void:
	if runtime == null or runtime.turn_manager == null or day_label == null:
		visible = false
		return

	var turn_manager: WorldTurns = runtime.turn_manager
	var turn_state: String = turn_manager.get_state()
	visible = turn_state != WorldTurns.STATE_FREE
	if not visible:
		_stop_world_animation()
		return

	day_label.text = "День %d" % turn_manager.get_round_number()
	var is_world_turn: bool = turn_state == WorldTurns.STATE_WORLD_TURN
	var active_entity_id: String = turn_manager.get_active_entity_id()
	var is_player_turn: bool = turn_state == WorldTurns.STATE_PLAYER_TURN and not active_entity_id.is_empty()
	player_row.visible = is_player_turn
	steps_row.visible = is_player_turn
	world_label.visible = is_world_turn

	if is_world_turn:
		_start_world_animation()
		return
	_stop_world_animation()
	if not is_player_turn:
		return

	var active_player: PlayerCharacter = runtime.get_player_by_entity_id(active_entity_id)
	active_portrait.set_player(active_player)
	var steps_left: int = turn_manager.get_steps_left()
	var maximum_steps: int = turn_manager.get_max_steps_per_turn()
	steps_label.text = "Шаги: %d/%d" % [steps_left, maximum_steps]
	_refresh_step_segments(steps_left, maximum_steps)


func _refresh_step_segments(steps_left: int, maximum_steps: int) -> void:
	if step_segments.size() != maximum_steps:
		for segment: ColorRect in step_segments:
			segment.queue_free()
		step_segments.clear()
		for _segment_index: int in range(maximum_steps):
			var segment: ColorRect = ColorRect.new()
			segment.custom_minimum_size = Vector2(16.0, 5.0)
			segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
			step_segments.append(segment)
			steps_container.add_child.call_deferred(segment)

	for segment_index: int in range(step_segments.size()):
		step_segments[segment_index].color = ACTIVE_COLOR if segment_index < steps_left else EMPTY_STEP_COLOR


func _start_world_animation() -> void:
	if world_animation_timer == null:
		return
	if world_animation_timer.is_stopped():
		world_message_index = 0
		world_label.text = WORLD_MESSAGES[world_message_index]
		world_animation_timer.start.call_deferred()


func _stop_world_animation() -> void:
	if world_animation_timer != null:
		world_animation_timer.stop()
	world_message_index = 0
	if world_label != null:
		world_label.text = WORLD_MESSAGES[world_message_index]


func _disconnect_turn_signal() -> void:
	if runtime == null or runtime.turn_manager == null:
		return
	if runtime.turn_manager.turn_state_changed.is_connected(_on_turn_state_changed):
		runtime.turn_manager.turn_state_changed.disconnect(_on_turn_state_changed)


func _on_turn_state_changed() -> void:
	_refresh()


func _on_world_animation_timer_timeout() -> void:
	world_message_index = (world_message_index + 1) % WORLD_MESSAGES.size()
	world_label.text = WORLD_MESSAGES[world_message_index]
