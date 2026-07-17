extends Control

@onready var lobbies_list: VBoxContainer = $LobbiesList
@onready var status_label: Label = $StatusLabel

func _ready() -> void:
	SteamManager.lobby_list_received.connect(_on_lobby_list_received)
	SteamManager.lobby_joined.connect(_on_lobby_joined)
	SteamManager.lobby_join_failed.connect(_on_lobby_join_failed)

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
		var empty_label := Label.new()
		empty_label.text = "No lobbies found"
		lobbies_list.add_child(empty_label)
		return

	for lobby in lobbies:
		var row := HBoxContainer.new()

		var label := Label.new()
		label.text = str(lobby["name"]) + " | Players: " + str(lobby["member_count"])

		var join_button := Button.new()
		join_button.text = "Join"
		join_button.pressed.connect(func():
			SteamManager.join_lobby(lobby["id"])
		)

		row.add_child(label)
		row.add_child(join_button)

		lobbies_list.add_child(row)


func _on_lobby_joined(_lobby_id: int) -> void:
	get_tree().change_scene_to_file("res://scenes/menu/lobby/lobby_host.tscn")


func _on_lobby_join_failed(response: int) -> void:
	if response == -1:
		status_label.text = "This lobby uses an incompatible network protocol version."
		return
	status_label.text = "Failed to join the selected lobby."
	push_warning("Failed to join lobby. Steam response: %d" % response)
