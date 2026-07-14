class_name NetworkMatchChannel
extends NetworkChannel

signal match_end_requested()


func request_end_game() -> void:
	if not GameSession.is_multiplayer() or not _can_send():
		match_end_requested.emit()
		return
	if not connection.is_host:
		match_end_requested.emit()
		return
	_broadcast_end_game()


func _broadcast_end_game() -> void:
	if not _can_host_send():
		return
	match_end_requested.emit()
	rpc("_receive_end_game")


@rpc("authority", "reliable")
func _receive_end_game() -> void:
	match_end_requested.emit()
