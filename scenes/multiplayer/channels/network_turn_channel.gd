class_name NetworkTurnChannel
extends NetworkChannel

signal turn_state_received(snapshot: Dictionary)
signal turn_end_requested(steam_id: int)


func broadcast_turn_state(snapshot: Dictionary) -> void:
	if _can_host_send():
		rpc("_receive_turn_state", snapshot)


func request_turn_end(steam_id: int) -> void:
	if not GameSession.is_multiplayer():
		turn_end_requested.emit(steam_id)
		return
	if not _can_send():
		return
	if connection.is_host:
		turn_end_requested.emit(steam_id)
		return
	rpc_id(1, "_submit_turn_end", steam_id)


@rpc("authority", "reliable")
func _receive_turn_state(snapshot: Dictionary) -> void:
	turn_state_received.emit(snapshot)


@rpc("any_peer", "reliable")
func _submit_turn_end(steam_id: int) -> void:
	if _get_registered_sender_steam_id() == steam_id:
		turn_end_requested.emit(steam_id)
