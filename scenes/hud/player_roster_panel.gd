class_name PlayerRosterPanel
extends Control

const MAX_PLAYER_CARDS := 4
const DRAWER_WIDTH := 218.0
const TOGGLE_WIDTH := 28.0
const DRAWER_DURATION_SECONDS := 0.22
const PANEL_COLOR := Color(0.055, 0.065, 0.085, 0.62)
const BORDER_COLOR := Color(0.34, 0.37, 0.43, 0.84)
const TEXT_COLOR := Color(0.94, 0.96, 1.0, 1.0)

var runtime: WorldRuntime = null
var drawer_panel: PanelContainer = null
var cards_container: VBoxContainer = null
var toggle_button: Button = null
var player_cards: Array[PlayerStatusCard] = []
var is_expanded: bool = true
var drawer_tween: Tween = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_content()
	_apply_drawer_position()


func _exit_tree() -> void:
	_disconnect_turn_signal()


func configure_runtime(new_runtime: WorldRuntime) -> void:
	_disconnect_turn_signal()
	runtime = new_runtime
	if runtime != null and runtime.turn_manager != null:
		if not runtime.turn_manager.turn_state_changed.is_connected(_on_turn_state_changed):
			runtime.turn_manager.turn_state_changed.connect(_on_turn_state_changed)


func bind_session() -> void:
	_clear_cards()
	if runtime == null:
		return

	var session_players: Array[Dictionary] = GameSession.get_players()
	var card_count: int = mini(session_players.size(), MAX_PLAYER_CARDS)
	for player_index: int in range(card_count):
		var player_record: Dictionary = session_players[player_index]
		var player: PlayerCharacter = _resolve_player(player_record)
		if player == null:
			continue
		var steam_name: String = str(player_record.get("name", "")) if GameSession.is_multiplayer() else ""
		var card: PlayerStatusCard = PlayerStatusCard.new()
		card.set_layout_mode(PlayerStatusCard.LayoutMode.ROSTER)
		card.custom_minimum_size = Vector2(190.0, 60.0)
		card.bind_player(player, steam_name, bool(player_record.get("is_local", false)))
		player_cards.append(card)
		cards_container.add_child.call_deferred(card)
	_refresh_active_player()


func _build_content() -> void:
	toggle_button = Button.new()
	toggle_button.anchor_top = 0.5
	toggle_button.anchor_bottom = 0.5
	toggle_button.offset_right = TOGGLE_WIDTH
	toggle_button.offset_top = -25.0
	toggle_button.offset_bottom = 25.0
	toggle_button.text = "›"
	toggle_button.add_theme_font_size_override("font_size", 14)
	toggle_button.focus_mode = Control.FOCUS_NONE
	toggle_button.tooltip_text = "Свернуть список игроков"
	toggle_button.pressed.connect(_on_toggle_button_pressed)
	add_child.call_deferred(toggle_button)

	drawer_panel = PanelContainer.new()
	drawer_panel.anchor_left = 0.0
	drawer_panel.anchor_top = 0.0
	drawer_panel.anchor_right = 1.0
	drawer_panel.anchor_bottom = 1.0
	drawer_panel.offset_left = TOGGLE_WIDTH
	_apply_panel_style()
	add_child.call_deferred(drawer_panel)

	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	drawer_panel.add_child.call_deferred(content)

	var header: Label = Label.new()
	header.text = "Игроки"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", TEXT_COLOR)
	content.add_child.call_deferred(header)

	cards_container = VBoxContainer.new()
	cards_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards_container.add_theme_constant_override("separation", 6)
	content.add_child.call_deferred(cards_container)


func _apply_panel_style() -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(8.0)
	drawer_panel.add_theme_stylebox_override("panel", style)


func _apply_drawer_position() -> void:
	offset_left = -(DRAWER_WIDTH + TOGGLE_WIDTH) if is_expanded else -TOGGLE_WIDTH
	offset_right = 0.0 if is_expanded else DRAWER_WIDTH
	if drawer_panel != null:
		drawer_panel.visible = is_expanded
	if toggle_button != null:
		toggle_button.text = "›" if is_expanded else "‹"
		toggle_button.tooltip_text = "Свернуть список игроков" if is_expanded else "Развернуть список игроков"


func _set_expanded(should_be_expanded: bool) -> void:
	if is_expanded == should_be_expanded:
		return
	is_expanded = should_be_expanded
	if drawer_tween != null and drawer_tween.is_valid():
		drawer_tween.kill()
	if is_expanded:
		drawer_panel.visible = true
	toggle_button.text = "›" if is_expanded else "‹"
	toggle_button.tooltip_text = "Свернуть список игроков" if is_expanded else "Развернуть список игроков"

	var target_left: float = -(DRAWER_WIDTH + TOGGLE_WIDTH) if is_expanded else -TOGGLE_WIDTH
	var target_right: float = 0.0 if is_expanded else DRAWER_WIDTH
	drawer_tween = create_tween()
	drawer_tween.set_trans(Tween.TRANS_QUAD)
	drawer_tween.set_ease(Tween.EASE_OUT)
	drawer_tween.set_parallel(true)
	drawer_tween.tween_property(self, "offset_left", target_left, DRAWER_DURATION_SECONDS)
	drawer_tween.tween_property(self, "offset_right", target_right, DRAWER_DURATION_SECONDS)
	drawer_tween.finished.connect(_on_drawer_tween_finished)


func _clear_cards() -> void:
	for card: PlayerStatusCard in player_cards:
		card.queue_free()
	player_cards.clear()


func _resolve_player(player_record: Dictionary) -> PlayerCharacter:
	if GameSession.is_singleplayer():
		return runtime.get_local_player()
	return runtime.get_player_by_entity_id(str(player_record.get("entity_id", "")))


func _refresh_active_player() -> void:
	var active_entity_id: String = ""
	if runtime != null and runtime.turn_manager != null:
		active_entity_id = runtime.turn_manager.get_active_entity_id()
	for card: PlayerStatusCard in player_cards:
		var player: PlayerCharacter = card.get_bound_player()
		card.set_active_player(player != null and player.entity_id == active_entity_id)


func _disconnect_turn_signal() -> void:
	if runtime == null or runtime.turn_manager == null:
		return
	if runtime.turn_manager.turn_state_changed.is_connected(_on_turn_state_changed):
		runtime.turn_manager.turn_state_changed.disconnect(_on_turn_state_changed)


func _on_toggle_button_pressed() -> void:
	_set_expanded(not is_expanded)


func _on_drawer_tween_finished() -> void:
	if not is_expanded:
		drawer_panel.visible = false


func _on_turn_state_changed() -> void:
	_refresh_active_player()
