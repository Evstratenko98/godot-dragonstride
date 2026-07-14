extends Control

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
