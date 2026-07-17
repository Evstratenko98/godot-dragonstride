extends Control

@onready var lobby_title_label: Label = $LobbyTitleLabel
@onready var members_list: VBoxContainer = $MembersList
@onready var start_game_button: Button = $VBoxContainer/StartGameButton
@onready var status_label: Label = $StatusLabel

const STATUS_MESSAGES := {
	"relay_unavailable": "Steam relay is unavailable.",
	"invalid_roster": "The lobby roster is invalid.",
	"lobby_update_failed": "Could not lock the lobby for the match.",
	"lobby_message_failed": "Could not send match preparation to the lobby.",
	"transport_failed": "Could not establish the match connection.",
	"transport_timeout": "A player did not connect in time.",
	"world_timeout": "A player did not finish loading in time.",
	"roster_changed": "The roster changed. Match start was cancelled.",
	"invalid_spawn_snapshot": "Player placement could not be synchronized.",
	"spawn_unavailable": "There are not enough valid spawn cells.",
	"spawn_registration_failed": "A player could not be registered in the world.",
	"spawn_snapshot_timeout": "The player spawn snapshot was not received in time.",
	"session_commit_failed": "The prepared match could not be committed.",
	"protocol_mismatch": "The lobby uses an incompatible network protocol version.",
	"state_sync_timeout": "Authoritative world synchronization timed out.",
	"state_sync_invalid": "Authoritative world synchronization was rejected.",
}

func _ready() -> void:
	SteamManager.lobby_members_updated.connect(_on_lobby_members_updated)
	SteamManager.lobby_left.connect(_on_lobby_left)
	NetworkManager.connection.network_failed.connect(_on_network_failed)
	LobbyMatchCoordinator.status_changed.connect(_on_match_status_changed)
	LobbyMatchCoordinator.coordinator_state_changed.connect(_on_coordinator_state_changed)

	lobby_title_label.text = "Lobby ID: " + str(SteamManager.get_current_lobby_id())

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
		var label: Label = Label.new()
		var member_text: String = str(member["name"])

		if member["is_owner"]:
			member_text += " [HOST]"

		if int(member["id"]) == Steam.getSteamID():
			member_text += " [YOU]"

		label.text = member_text
		members_list.add_child(label)


func _update_host_controls() -> void:
	var is_host: bool = SteamManager.is_lobby_owner()

	start_game_button.visible = is_host
	start_game_button.disabled = not is_host or LobbyMatchCoordinator.is_starting_match()


func _on_start_game_button_pressed() -> void:
	if not SteamManager.is_lobby_owner():
		return

	start_game_button.disabled = true
	status_label.text = "Preparing match..."
	LobbyMatchCoordinator.request_start_match()
	_update_host_controls()


func _on_back_button_pressed() -> void:
	SteamManager.leave_lobby()


func _on_lobby_left() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/main_menu/main_menu.tscn")


func _on_network_failed(reason: String) -> void:
	print("Network failed: ", reason)
	_update_host_controls()


func _on_match_status_changed(reason_code: String) -> void:
	LobbyMatchCoordinator.consume_lobby_status()
	status_label.text = str(STATUS_MESSAGES.get(reason_code, "Match start failed: " + reason_code))
	_update_host_controls()


func _on_coordinator_state_changed(_state: LobbyMatchCoordinator.State) -> void:
	_update_host_controls()
