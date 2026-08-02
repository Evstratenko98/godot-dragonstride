class_name LocalSquadPanel
extends PanelContainer

signal member_pressed(character: PlayerCharacter)

var runtime: WorldRuntime = null
var rows_container: VBoxContainer = null
var rows: Array[SquadMemberStatusRow] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_build_content()
	_apply_style()


func bind_squad(new_runtime: WorldRuntime, members: Array[PlayerCharacter]) -> void:
	runtime = new_runtime
	_clear_rows()
	for member: PlayerCharacter in members:
		var row: SquadMemberStatusRow = SquadMemberStatusRow.new()
		rows.append(row)
		rows_container.add_child.call_deferred(row)
		row.bind_member(runtime, member)
		row.member_pressed.connect(_on_member_pressed)
	visible = not members.is_empty()


func set_selected_character(character: PlayerCharacter) -> void:
	for row: SquadMemberStatusRow in rows:
		row.set_selected(row.character == character)


func _build_content() -> void:
	var content: VBoxContainer = VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 5)
	add_child.call_deferred(content)
	var title: Label = Label.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.text = "Последователи  •  Tab — переключить"
	title.add_theme_font_size_override("font_size", 11)
	content.add_child.call_deferred(title)
	rows_container = VBoxContainer.new()
	rows_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows_container.add_theme_constant_override("separation", 4)
	content.add_child.call_deferred(rows_container)


func _clear_rows() -> void:
	for row: SquadMemberStatusRow in rows:
		row.queue_free()
	rows.clear()


func _apply_style() -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.04, 0.055, 0.74)
	style.border_color = Color(0.28, 0.31, 0.38, 0.88)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(7.0)
	add_theme_stylebox_override("panel", style)


func _on_member_pressed(character: PlayerCharacter) -> void:
	member_pressed.emit(character)
	if runtime != null:
		runtime.select_local_character(character)
