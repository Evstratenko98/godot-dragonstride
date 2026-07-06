extends Control

var lobby_id: int = 0
var lobby_members: Array = []

func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/main_menu/main_menu.tscn")
	
func _on_host_button_pressed() -> void:
	SteamManager.create_lobby()
	
func _on_lobby_created(_lobby_id: int) -> void:
	get_tree().change_scene_to_file("res://scenes/menu/lobby/lobby_host.tscn")

func _ready() -> void:
	SteamManager.lobby_created.connect(_on_lobby_created)


func _on_join_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/lobby/lobby_join.tscn")
