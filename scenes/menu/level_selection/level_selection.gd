extends Control

const MAIN_MENU_SCENE_PATH := "res://scenes/menu/main_menu/main_menu.tscn"


func _on_sandbox_button_pressed() -> void:
	_start_singleplayer_level(LevelCatalog.SANDBOX_LEVEL_ID)


func _on_level_1_button_pressed() -> void:
	_start_singleplayer_level(LevelCatalog.LEVEL_1_ID)


func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _start_singleplayer_level(level_id: String) -> void:
	NetworkManager.connection.stop_network()
	GameSession.start_singleplayer({"level_id": level_id})
	GameSession.go_to_selected_scene()
