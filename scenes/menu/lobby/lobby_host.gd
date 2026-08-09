extends Control

@onready var lobby_title_label: Label = %LobbyTitleLabel
@onready var members_list: VBoxContainer = %MembersList
@onready var start_game_button: Button = %StartGameButton
@onready var status_label: Label = %StatusLabel

const STATUS_MESSAGES := {
	"relay_unavailable": "Ретранслятор Steam недоступен.",
	"invalid_roster": "Некорректный состав лобби.",
	"lobby_update_failed": "Не удалось заблокировать лобби перед матчем.",
	"lobby_message_failed": "Не удалось отправить участникам данные подготовки.",
	"transport_failed": "Не удалось установить соединение матча.",
	"transport_timeout": "Один из игроков не подключился вовремя.",
	"world_timeout": "Один из игроков не завершил загрузку мира вовремя.",
	"roster_changed": "Состав лобби изменился. Запуск матча отменён.",
	"invalid_spawn_snapshot": "Не удалось синхронизировать размещение игроков.",
	"spawn_unavailable": "На карте недостаточно доступных точек появления.",
	"spawn_registration_failed": "Не удалось зарегистрировать игрока в мире.",
	"spawn_snapshot_timeout": "Снимок размещения игроков не получен вовремя.",
	"session_commit_failed": "Не удалось подтвердить подготовленный матч.",
	"protocol_mismatch": "Версия сетевого протокола лобби несовместима.",
	"state_sync_timeout": "Истекло время синхронизации состояния мира.",
	"state_sync_invalid": "Синхронизация состояния мира была отклонена.",
	"snapshot_too_large": "Состояние мира слишком велико для сетевой синхронизации.",
}

func _ready() -> void:
	SteamManager.lobby_members_updated.connect(_on_lobby_members_updated)
	SteamManager.lobby_left.connect(_on_lobby_left)
	NetworkManager.connection.network_failed.connect(_on_network_failed)
	LobbyMatchCoordinator.status_changed.connect(_on_match_status_changed)
	LobbyMatchCoordinator.coordinator_state_changed.connect(_on_coordinator_state_changed)

	lobby_title_label.text = "Лобби Steam · ID %s" % SteamManager.get_current_lobby_id()

	_update_host_controls()
	_render_members(SteamManager.get_current_lobby_members())
	SteamManager.update_lobby_members()
	var pending_status_code: String = LobbyMatchCoordinator.consume_lobby_status()
	if not pending_status_code.is_empty():
		_on_match_status_changed(pending_status_code)


func _exit_tree() -> void:
	if SteamManager.lobby_members_updated.is_connected(_on_lobby_members_updated):
		SteamManager.lobby_members_updated.disconnect(_on_lobby_members_updated)

	if SteamManager.lobby_left.is_connected(_on_lobby_left):
		SteamManager.lobby_left.disconnect(_on_lobby_left)

	if NetworkManager.connection.network_failed.is_connected(_on_network_failed):
		NetworkManager.connection.network_failed.disconnect(_on_network_failed)

	if LobbyMatchCoordinator.status_changed.is_connected(_on_match_status_changed):
		LobbyMatchCoordinator.status_changed.disconnect(_on_match_status_changed)

	if LobbyMatchCoordinator.coordinator_state_changed.is_connected(_on_coordinator_state_changed):
		LobbyMatchCoordinator.coordinator_state_changed.disconnect(_on_coordinator_state_changed)


func _on_lobby_members_updated(members: Array) -> void:
	_render_members(members)
	_update_host_controls()


func _render_members(members: Array) -> void:
	for child: Node in members_list.get_children():
		child.queue_free()

	for member_value: Variant in members:
		var member: Dictionary = member_value as Dictionary
		var member_panel: PanelContainer = PanelContainer.new()
		member_panel.theme_type_variation = &"CompactMenuPanel"
		member_panel.custom_minimum_size = Vector2(0.0, 52.0)
		var member_row: HBoxContainer = HBoxContainer.new()
		member_row.add_theme_constant_override("separation", 10)
		var member_name_label: Label = Label.new()
		member_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		member_name_label.text = str(member.get("name", "Unknown player"))
		var role_label: Label = Label.new()
		role_label.add_theme_font_size_override("font_size", 12)
		role_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.20, 1.0))
		if bool(member.get("is_owner", false)):
			role_label.text = "ХОЗЯИН · ВЫ" if int(member.get("id", 0)) == Steam.getSteamID() else "ХОЗЯИН"
		elif int(member.get("id", 0)) == Steam.getSteamID():
			role_label.text = "ВЫ"
		else:
			role_label.text = "В ИГРЕ"
		member_row.add_child.call_deferred(member_name_label)
		member_row.add_child.call_deferred(role_label)
		member_panel.add_child.call_deferred(member_row)
		members_list.add_child.call_deferred(member_panel)


func _update_host_controls() -> void:
	var is_host: bool = SteamManager.is_lobby_owner()

	start_game_button.visible = is_host
	start_game_button.disabled = not is_host or LobbyMatchCoordinator.is_starting_match()


func _on_start_game_button_pressed() -> void:
	if not SteamManager.is_lobby_owner():
		return

	start_game_button.disabled = true
	status_label.text = "Подготовка матча..."
	LobbyMatchCoordinator.request_start_match()
	_update_host_controls()


func _on_back_button_pressed() -> void:
	SteamManager.leave_lobby()


func _on_lobby_left() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/main_menu/main_menu.tscn")


func _on_network_failed(reason: String) -> void:
	status_label.text = str(STATUS_MESSAGES.get(reason, "Сетевая ошибка: " + reason))
	_update_host_controls()


func _on_match_status_changed(reason_code: String) -> void:
	LobbyMatchCoordinator.consume_lobby_status()
	status_label.text = str(STATUS_MESSAGES.get(reason_code, "Не удалось запустить матч: " + reason_code))
	_update_host_controls()


func _on_coordinator_state_changed(_state: LobbyMatchCoordinator.State) -> void:
	_update_host_controls()
