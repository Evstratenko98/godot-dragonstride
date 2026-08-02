extends Control

@onready var lobbies_list: VBoxContainer = %LobbiesList
@onready var status_label: Label = %StatusLabel

func _ready() -> void:
	SteamManager.lobby_list_received.connect(_on_lobby_list_received)
	SteamManager.lobby_joined.connect(_on_lobby_joined)
	SteamManager.lobby_join_failed.connect(_on_lobby_join_failed)

	status_label.text = "Поиск доступных лобби..."
	SteamManager.request_lobbies()


func _exit_tree() -> void:
	if SteamManager.lobby_list_received.is_connected(_on_lobby_list_received):
		SteamManager.lobby_list_received.disconnect(_on_lobby_list_received)

	if SteamManager.lobby_joined.is_connected(_on_lobby_joined):
		SteamManager.lobby_joined.disconnect(_on_lobby_joined)

	if SteamManager.lobby_join_failed.is_connected(_on_lobby_join_failed):
		SteamManager.lobby_join_failed.disconnect(_on_lobby_join_failed)


func _on_refresh_button_pressed() -> void:
	status_label.text = ""
	SteamManager.request_lobbies()


func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/lobby/lobby_main.tscn")


func _on_lobby_list_received(lobbies: Array) -> void:
	_render_lobbies(lobbies)


func _render_lobbies(lobbies: Array) -> void:
	for child in lobbies_list.get_children():
		child.queue_free()

	if lobbies.is_empty():
		var empty_label: Label = Label.new()
		empty_label.text = "Совместимые лобби не найдены"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_color_override("font_color", Color(0.55, 0.61, 0.7, 1.0))
		lobbies_list.add_child.call_deferred(empty_label)
		status_label.text = ""
		return

	for lobby_value: Variant in lobbies:
		var lobby: Dictionary = lobby_value as Dictionary
		var lobby_panel: PanelContainer = PanelContainer.new()
		lobby_panel.theme_type_variation = &"CompactMenuPanel"
		lobby_panel.custom_minimum_size = Vector2(0.0, 72.0)
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		var label: Label = Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = "%s\nУчастники: %d / 4" % [
			str(lobby.get("name", "Steam lobby")),
			int(lobby.get("member_count", 0)),
		]
		var join_button: Button = Button.new()
		join_button.custom_minimum_size = Vector2(150.0, 46.0)
		join_button.focus_mode = Control.FOCUS_NONE
		join_button.text = "Присоединиться"
		join_button.pressed.connect(_on_join_lobby_pressed.bind(int(lobby.get("id", 0))))
		row.add_child.call_deferred(label)
		row.add_child.call_deferred(join_button)
		lobby_panel.add_child.call_deferred(row)
		lobbies_list.add_child.call_deferred(lobby_panel)
	status_label.text = "Найдено лобби: %d" % lobbies.size()


func _on_join_lobby_pressed(lobby_id: int) -> void:
	if lobby_id <= 0:
		return
	status_label.text = "Подключение к лобби..."
	SteamManager.join_lobby(lobby_id)


func _on_lobby_joined(_lobby_id: int) -> void:
	get_tree().change_scene_to_file("res://scenes/menu/lobby/lobby_host.tscn")


func _on_lobby_join_failed(response: int) -> void:
	if response == -1:
		status_label.text = "Это лобби использует несовместимую версию сетевого протокола."
		return
	status_label.text = "Не удалось присоединиться к выбранному лобби."
	push_warning("Failed to join lobby. Steam response: %d" % response)
