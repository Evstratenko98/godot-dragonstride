extends Control

@onready var lobby_title_label: Label = $LobbyTitleLabel
@onready var members_list: VBoxContainer = $MembersList
@onready var start_game_button: Button = $VBoxContainer/StartGameButton

func _ready() -> void:
	SteamManager.lobby_members_updated.connect(_on_lobby_members_updated)
	SteamManager.lobby_left.connect(_on_lobby_left)
	NetworkManager.connection.network_failed.connect(_on_network_failed)

	lobby_title_label.text = "Lobby ID: " + str(SteamManager.get_current_lobby_id())

	_update_host_controls()
	_render_members(SteamManager.get_current_lobby_members())
	SteamManager.update_lobby_members()


func _exit_tree() -> void:
	if SteamManager.lobby_members_updated.is_connected(_on_lobby_members_updated):
		SteamManager.lobby_members_updated.disconnect(_on_lobby_members_updated)

	if SteamManager.lobby_left.is_connected(_on_lobby_left):
		SteamManager.lobby_left.disconnect(_on_lobby_left)

	if NetworkManager.connection.network_failed.is_connected(_on_network_failed):
		NetworkManager.connection.network_failed.disconnect(_on_network_failed)


func _on_lobby_members_updated(members: Array) -> void:
	_render_members(members)
	_update_host_controls()


func _render_members(members: Array) -> void:
	for child in members_list.get_children():
		child.queue_free()

	for member in members:
		var label := Label.new()
		var text := str(member["name"])

		if member["is_owner"]:
			text += " [HOST]"

		if int(member["id"]) == Steam.getSteamID():
			text += " [YOU]"

		label.text = text
		members_list.add_child(label)


func _update_host_controls() -> void:
	var is_host := SteamManager.is_lobby_owner()

	start_game_button.visible = is_host
	start_game_button.disabled = not is_host


func _on_start_game_button_pressed() -> void:
	if not SteamManager.is_lobby_owner():
		return

	start_game_button.disabled = true
	SteamManager.request_start_game_from_lobby()

	if not SteamManager.is_starting_game_from_lobby:
		start_game_button.disabled = false


func _on_back_button_pressed() -> void:
	SteamManager.leave_lobby()


func _on_lobby_left() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/main_menu/main_menu.tscn")


func _on_network_failed(reason: String) -> void:
	print("Network failed: ", reason)
	_update_host_controls()
