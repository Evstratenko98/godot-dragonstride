class_name PlayerSquadRosterCard
extends PanelContainer

const ACTIVE_COLOR := Color(1.0, 0.82, 0.20, 0.94)
const BORDER_COLOR := Color(0.34, 0.37, 0.43, 0.86)

var player_id: String = ""
var display_name: String = ""
var runtime: WorldRuntime = null
var members: Array[PlayerCharacter] = []
var is_active: bool = false
var is_local_squad: bool = false
var title_label: Label = null
var health_container: VBoxContainer = null
var health_labels: Array[Label] = []


func _ready() -> void:
	custom_minimum_size = Vector2(252.0, 54.0)
	_build_content()
	_refresh_style()


func _process(_delta: float) -> void:
	for member_index: int in range(mini(members.size(), health_labels.size())):
		var member: PlayerCharacter = members[member_index]
		_refresh_member_label(health_labels[member_index], member)


func bind_squad(
	new_runtime: WorldRuntime,
	new_player_id: String,
	new_display_name: String,
	new_members: Array[PlayerCharacter],
	is_local: bool
) -> void:
	runtime = new_runtime
	player_id = new_player_id
	display_name = new_display_name
	members = new_members
	is_local_squad = is_local
	if title_label != null:
		title_label.text = "%s%s" % [display_name, "  • Вы" if is_local_squad else ""]
	_rebuild_health_rows()


func set_active(should_be_active: bool) -> void:
	is_active = should_be_active
	_refresh_style()
	_refresh_member_labels()


func _build_content() -> void:
	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 3)
	add_child.call_deferred(content)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 11)
	title_label.text = "%s%s" % [display_name, "  • Вы" if is_local_squad else ""]
	content.add_child.call_deferred(title_label)
	health_container = VBoxContainer.new()
	health_container.add_theme_constant_override("separation", 1)
	content.add_child.call_deferred(health_container)
	_rebuild_health_rows()


func _rebuild_health_rows() -> void:
	if health_container == null:
		return
	for label: Label in health_labels:
		label.queue_free()
	health_labels.clear()
	for member: PlayerCharacter in members:
		var label: Label = Label.new()
		label.add_theme_font_size_override("font_size", 9)
		_refresh_member_label(label, member)
		health_labels.append(label)
		health_container.add_child.call_deferred(label)


func _refresh_member_labels() -> void:
	for member_index: int in range(mini(members.size(), health_labels.size())):
		_refresh_member_label(health_labels[member_index], members[member_index])


func _refresh_member_label(label: Label, member: PlayerCharacter) -> void:
	var maximum_steps: int = WorldSquadTurnBudget.MAX_STEPS_PER_MEMBER
	var steps_text: String = "—"
	if is_active and runtime != null and runtime.turn_manager != null:
		maximum_steps = runtime.turn_manager.get_max_steps_per_member()
		steps_text = str(runtime.turn_manager.get_steps_left(member.entity_id))
	label.text = "%s  %d/%d  Урон: %d  Шаги: %s/%d" % [
		member.get_display_name(),
		member.health,
		member.max_health,
		member.damage,
		steps_text,
		maximum_steps,
	]


func _refresh_style() -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.065, 0.085, 0.72)
	style.border_color = ACTIVE_COLOR if is_active else BORDER_COLOR
	style.set_border_width_all(2 if is_active else 1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(5.0)
	add_theme_stylebox_override("panel", style)
