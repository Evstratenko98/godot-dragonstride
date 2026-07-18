class_name PlayerStatusCard
extends PanelContainer

const SWORD_TEXTURE: Texture2D = preload("res://art/pointers/tool_sword_a.svg")
const PANEL_COLOR := Color(0.055, 0.065, 0.085, 0.72)
const BORDER_COLOR := Color(0.34, 0.37, 0.43, 0.86)
const ACTIVE_COLOR := Color(1.0, 0.82, 0.20, 0.94)
const TEXT_COLOR := Color(0.94, 0.96, 1.0, 1.0)
const MUTED_TEXT_COLOR := Color(0.68, 0.72, 0.78, 1.0)
const HEALTH_COLOR := Color(0.86, 0.20, 0.23, 1.0)
const HEALTH_BACKGROUND_COLOR := Color(0.18, 0.08, 0.09, 0.78)

enum LayoutMode {
	LOCAL,
	ROSTER,
}

var player: PlayerCharacter = null
var display_name: String = ""
var should_show_local_tag: bool = false
var is_active_player: bool = false
var status_layout_mode: int = LayoutMode.LOCAL

var portrait: PlayerPortrait = null
var name_label: Label = null
var local_tag_label: Label = null
var active_tag_label: Label = null
var health_label: Label = null
var health_bar: ProgressBar = null
var damage_label: Label = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_content()
	_refresh_style()
	_refresh_content()


func _exit_tree() -> void:
	_disconnect_player_signals()


func bind_player(new_player: PlayerCharacter, new_display_name: String, show_local_tag: bool) -> void:
	if player != new_player:
		_disconnect_player_signals()
		player = new_player
		_connect_player_signals()
	display_name = new_display_name
	should_show_local_tag = show_local_tag
	visible = player != null
	_refresh_content()


func set_layout_mode(new_layout_mode: int) -> void:
	if is_node_ready():
		return
	status_layout_mode = new_layout_mode


func set_active_player(should_be_active: bool) -> void:
	if is_active_player == should_be_active:
		return
	is_active_player = should_be_active
	_refresh_style()
	_refresh_content()


func get_bound_player() -> PlayerCharacter:
	if player == null or not is_instance_valid(player):
		return null
	return player


func _build_content() -> void:
	var content: HBoxContainer = HBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	add_child.call_deferred(content)

	portrait = PlayerPortrait.new()
	portrait.set_diameter(34.0 if status_layout_mode == LayoutMode.ROSTER else 38.0)
	content.add_child.call_deferred(portrait)

	var details: VBoxContainer = VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 2)
	content.add_child.call_deferred(details)
	_build_name_row(details)
	if status_layout_mode == LayoutMode.ROSTER:
		_build_roster_stats(details)
	else:
		_build_local_stats(details)


func _build_name_row(details: VBoxContainer) -> void:
	var name_row: HBoxContainer = HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 4)
	details.add_child.call_deferred(name_row)

	name_label = Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", TEXT_COLOR)
	name_row.add_child.call_deferred(name_label)

	local_tag_label = _create_tag_label("Вы", MUTED_TEXT_COLOR)
	name_row.add_child.call_deferred(local_tag_label)

	active_tag_label = _create_tag_label("Ход", ACTIVE_COLOR)
	name_row.add_child.call_deferred(active_tag_label)


func _build_local_stats(details: VBoxContainer) -> void:
	var health_row: HBoxContainer = HBoxContainer.new()
	health_row.add_theme_constant_override("separation", 5)
	details.add_child.call_deferred(health_row)

	health_label = _create_health_label()
	health_label.custom_minimum_size = Vector2(62.0, 0.0)
	health_row.add_child.call_deferred(health_label)

	health_bar = _create_health_bar()
	health_bar.custom_minimum_size = Vector2(44.0, 7.0)
	health_row.add_child.call_deferred(health_bar)

	var damage_row: HBoxContainer = HBoxContainer.new()
	damage_row.add_theme_constant_override("separation", 3)
	details.add_child.call_deferred(damage_row)
	_add_damage_content(damage_row)


func _build_roster_stats(details: VBoxContainer) -> void:
	health_bar = _create_health_bar()
	health_bar.custom_minimum_size = Vector2(96.0, 6.0)
	details.add_child.call_deferred(health_bar)

	var stats_row: HBoxContainer = HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 4)
	details.add_child.call_deferred(stats_row)

	health_label = _create_health_label()
	health_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_row.add_child.call_deferred(health_label)
	_add_damage_content(stats_row)


func _create_health_label() -> Label:
	var label: Label = Label.new()
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	return label


func _create_health_bar() -> ProgressBar:
	var bar: ProgressBar = ProgressBar.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.show_percentage = false
	_apply_health_bar_style(bar)
	return bar


func _add_damage_content(target_row: HBoxContainer) -> void:
	var damage_icon: TextureRect = TextureRect.new()
	damage_icon.custom_minimum_size = Vector2(11.0, 11.0)
	damage_icon.texture = SWORD_TEXTURE
	damage_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	damage_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	damage_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_row.add_child.call_deferred(damage_icon)

	damage_label = Label.new()
	damage_label.add_theme_font_size_override("font_size", 9)
	damage_label.add_theme_color_override("font_color", TEXT_COLOR)
	target_row.add_child.call_deferred(damage_label)


func _create_tag_label(tag_text: String, tag_color: Color) -> Label:
	var tag: Label = Label.new()
	tag.text = tag_text
	tag.add_theme_font_size_override("font_size", 9)
	tag.add_theme_color_override("font_color", tag_color)
	return tag


func _apply_health_bar_style(target_health_bar: ProgressBar) -> void:
	var background_style: StyleBoxFlat = StyleBoxFlat.new()
	background_style.bg_color = HEALTH_BACKGROUND_COLOR
	background_style.set_corner_radius_all(3)
	target_health_bar.add_theme_stylebox_override("background", background_style)

	var fill_style: StyleBoxFlat = StyleBoxFlat.new()
	fill_style.bg_color = HEALTH_COLOR
	fill_style.set_corner_radius_all(3)
	target_health_bar.add_theme_stylebox_override("fill", fill_style)


func _refresh_style() -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.border_color = ACTIVE_COLOR if is_active_player else BORDER_COLOR
	style.set_border_width_all(2 if is_active_player else 1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(4.0)
	add_theme_stylebox_override("panel", style)


func _refresh_content() -> void:
	if name_label == null:
		return
	name_label.text = display_name
	local_tag_label.visible = should_show_local_tag
	active_tag_label.visible = is_active_player
	if portrait != null and player != null and is_instance_valid(player):
		portrait.set_player(player)
	if player == null or not is_instance_valid(player):
		if not visible:
			health_label.text = "HP —"
			health_bar.max_value = 1.0
			health_bar.value = 0.0
			damage_label.text = "Урон —"
		return

	var maximum_health: int = maxi(player.max_health, 1)
	health_label.text = "HP %d/%d" % [player.health, maximum_health]
	health_bar.max_value = maximum_health
	health_bar.value = clampi(player.health, 0, maximum_health)
	damage_label.text = "Урон %d" % player.damage


func _connect_player_signals() -> void:
	if player == null:
		return
	if not player.vitality_changed.is_connected(_on_player_vitality_changed):
		player.vitality_changed.connect(_on_player_vitality_changed)
	if not player.damage_changed.is_connected(_on_player_damage_changed):
		player.damage_changed.connect(_on_player_damage_changed)


func _disconnect_player_signals() -> void:
	if player == null or not is_instance_valid(player):
		return
	if player.vitality_changed.is_connected(_on_player_vitality_changed):
		player.vitality_changed.disconnect(_on_player_vitality_changed)
	if player.damage_changed.is_connected(_on_player_damage_changed):
		player.damage_changed.disconnect(_on_player_damage_changed)


func _on_player_vitality_changed(_current_health: int, _maximum_health: int) -> void:
	_refresh_content()


func _on_player_damage_changed(_current_damage: int) -> void:
	_refresh_content()
