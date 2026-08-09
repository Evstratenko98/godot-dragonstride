extends Control

const NOTICE_MESSAGES := {
	"host_disconnected": "Связь с хозяином потеряна. Матч завершён.",
	"state_sync_failed": "Не удалось синхронизировать мир. Соединение с матчем закрыто.",
	"snapshot_too_large": "Состояние мира слишком велико для сетевой синхронизации.",
}

@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	var notice_code: String = LobbyMatchCoordinator.consume_last_notice()
	status_label.text = str(NOTICE_MESSAGES.get(notice_code, ""))


func _on_settings_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/settings/settings.tscn")


func _on_exit_button_pressed() -> void:
	get_tree().quit()


func _on_lobby_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/lobby/lobby_main.tscn")


func _on_start_button_pressed() -> void:
	NetworkManager.connection.stop_network()
	GameSession.start_singleplayer()
	GameSession.go_to_selected_scene()
