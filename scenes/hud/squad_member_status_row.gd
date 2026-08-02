class_name SquadMemberStatusRow
extends PanelContainer

signal member_pressed(character: PlayerCharacter)

const SELECTED_COLOR := Color(1.0, 0.82, 0.20, 0.94)
const BORDER_COLOR := Color(0.34, 0.37, 0.43, 0.86)
const PANEL_COLOR := Color(0.055, 0.065, 0.085, 0.82)

var runtime: WorldRuntime = null
var character: PlayerCharacter = null
var is_selected: bool = false
var portrait: PlayerPortrait = null
var name_label: Label = null
var health_label: Label = null
var steps_label: Label = null
var action_label: Label = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(230.0, 58.0)
	_build_content()
	_refresh_style()


func _process(_delta: float) -> void:
	_refresh_content()


func _gui_input(event: InputEvent) -> void:
	var mouse_button_event: InputEventMouseButton = event as InputEventMouseButton
	if (
		mouse_button_event == null
		or not mouse_button_event.pressed
		or mouse_button_event.button_index != MOUSE_BUTTON_LEFT
		or character == null
		or not is_instance_valid(character)
	):
		return
	member_pressed.emit(character)
	accept_event()


func bind_member(new_runtime: WorldRuntime, new_character: PlayerCharacter) -> void:
	runtime = new_runtime
	character = new_character
	_refresh_content()


func set_selected(should_be_selected: bool) -> void:
	if is_selected == should_be_selected:
		return
	is_selected = should_be_selected
	_refresh_style()


func _build_content() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 7)
	add_child.call_deferred(row)
	portrait = PlayerPortrait.new()
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.set_diameter(36.0)
	row.add_child.call_deferred(portrait)
	var details: VBoxContainer = VBoxContainer.new()
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child.call_deferred(details)
	name_label = Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_size_override("font_size", 11)
	details.add_child.call_deferred(name_label)
	health_label = Label.new()
	health_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_label.add_theme_font_size_override("font_size", 9)
	details.add_child.call_deferred(health_label)
	steps_label = Label.new()
	steps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	steps_label.add_theme_font_size_override("font_size", 9)
	details.add_child.call_deferred(steps_label)
	action_label = Label.new()
	action_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_label.add_theme_font_size_override("font_size", 9)
	details.add_child.call_deferred(action_label)


func _refresh_content() -> void:
	if name_label == null:
		return
	visible = character != null and is_instance_valid(character)
	if not visible:
		return
	portrait.set_player(character)
	name_label.text = character.get_display_name()
	health_label.text = "Здоровье: %d/%d" % [character.health, character.max_health]
	var attacks_left: int = 0
	var interactions_left: int = 0
	var steps_left: int = 0
	var maximum_steps: int = WorldSquadTurnBudget.MAX_STEPS_PER_MEMBER
	if runtime != null and runtime.turn_manager != null:
		steps_left = runtime.turn_manager.get_steps_left(character.entity_id)
		maximum_steps = runtime.turn_manager.get_max_steps_per_member()
		attacks_left = runtime.turn_manager.get_attacks_left(character.entity_id)
		interactions_left = runtime.turn_manager.get_interactions_left(character.entity_id)
	steps_label.text = "Шаги: %d/%d" % [steps_left, maximum_steps]
	action_label.text = "Атака: %d  Схватить: %d" % [attacks_left, interactions_left]


func _refresh_style() -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.border_color = SELECTED_COLOR if is_selected else BORDER_COLOR
	style.set_border_width_all(2 if is_selected else 1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(5.0)
	add_theme_stylebox_override("panel", style)
