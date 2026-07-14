class_name NetworkCharacterChannel
extends NetworkChannel

signal player_state_received(steam_id: int, player_position: Vector2, animation: String, is_moving: bool)
signal character_state_received(
	steam_id: int,
	player_position: Vector2,
	animation: String,
	is_moving: bool,
	facing_left: bool
)
signal interaction_requested(target_cell: Vector2i, requester_peer_id: int)
signal entity_move_requested(
	requester_steam_id: int,
	entity_id: String,
	from_cell: Vector2i,
	target_cell: Vector2i
)
signal entity_move_received(entity_id: String, from_cell: Vector2i, target_cell: Vector2i)
signal entity_move_completed_requested(
	requester_steam_id: int,
	entity_id: String,
	from_cell: Vector2i,
	target_cell: Vector2i
)
signal entity_move_completed_received(entity_id: String, from_cell: Vector2i, target_cell: Vector2i)
signal character_kill_requested(requester_peer_id: int)


func send_player_state(
	steam_id: int,
	player_position: Vector2,
	animation: String,
	is_moving_player: bool
) -> void:
	if not _can_send():
		return
	if connection.is_host:
		rpc("_receive_player_state", steam_id, player_position, animation, is_moving_player)
		return
	rpc_id(1, "_submit_player_state", steam_id, player_position, animation, is_moving_player)


func send_character_state(
	steam_id: int,
	player_position: Vector2,
	animation: String,
	is_moving_player: bool,
	facing_left_player: bool
) -> void:
	if not _can_send():
		return
	if connection.is_host:
		rpc("_receive_character_state", steam_id, player_position, animation, is_moving_player, facing_left_player)
		return
	rpc_id(1, "_submit_character_state", steam_id, player_position, animation, is_moving_player, facing_left_player)


func request_interaction(target_cell: Vector2i) -> void:
	if not _can_send():
		return
	if connection.is_host:
		interaction_requested.emit(target_cell, 0)
		return
	rpc_id(1, "_submit_interaction", target_cell)


func request_entity_move(entity_id: String, from_cell: Vector2i, target_cell: Vector2i) -> void:
	if not _can_send():
		return
	if connection.is_host:
		broadcast_entity_move(entity_id, from_cell, target_cell)
		return
	rpc_id(1, "_submit_entity_move", entity_id, from_cell, target_cell)


func broadcast_entity_move(entity_id: String, from_cell: Vector2i, target_cell: Vector2i) -> void:
	if _can_host_send():
		rpc("_receive_entity_move", entity_id, from_cell, target_cell)


func report_entity_move_completed(entity_id: String, from_cell: Vector2i, target_cell: Vector2i) -> void:
	if not _can_send():
		return
	if connection.is_host:
		broadcast_entity_move_completed(entity_id, from_cell, target_cell)
		return
	rpc_id(1, "_submit_entity_move_completed", entity_id, from_cell, target_cell)


func broadcast_entity_move_completed(entity_id: String, from_cell: Vector2i, target_cell: Vector2i) -> void:
	if _can_host_send():
		rpc("_receive_entity_move_completed", entity_id, from_cell, target_cell)


func request_character_kill() -> void:
	if not _can_send():
		return
	if connection.is_host:
		character_kill_requested.emit(0)
		return
	rpc_id(1, "_submit_character_kill")


@rpc("any_peer", "unreliable")
func _submit_player_state(
	steam_id: int,
	player_position: Vector2,
	animation: String,
	is_moving_player: bool
) -> void:
	if _get_registered_sender_steam_id() != steam_id:
		return
	player_state_received.emit(steam_id, player_position, animation, is_moving_player)
	rpc("_receive_player_state", steam_id, player_position, animation, is_moving_player)


@rpc("authority", "unreliable")
func _receive_player_state(
	steam_id: int,
	player_position: Vector2,
	animation: String,
	is_moving_player: bool
) -> void:
	if steam_id != connection.local_steam_id:
		player_state_received.emit(steam_id, player_position, animation, is_moving_player)


@rpc("any_peer", "unreliable")
func _submit_character_state(
	steam_id: int,
	player_position: Vector2,
	animation: String,
	is_moving_player: bool,
	facing_left_player: bool
) -> void:
	if _get_registered_sender_steam_id() != steam_id:
		return
	character_state_received.emit(steam_id, player_position, animation, is_moving_player, facing_left_player)
	rpc("_receive_character_state", steam_id, player_position, animation, is_moving_player, facing_left_player)


@rpc("authority", "unreliable")
func _receive_character_state(
	steam_id: int,
	player_position: Vector2,
	animation: String,
	is_moving_player: bool,
	facing_left_player: bool
) -> void:
	if steam_id != connection.local_steam_id:
		character_state_received.emit(steam_id, player_position, animation, is_moving_player, facing_left_player)


@rpc("any_peer", "reliable")
func _submit_interaction(target_cell: Vector2i) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id != 0:
		interaction_requested.emit(target_cell, requester_peer_id)


@rpc("any_peer", "reliable")
func _submit_entity_move(entity_id: String, from_cell: Vector2i, target_cell: Vector2i) -> void:
	var requester_steam_id: int = _get_registered_sender_steam_id()
	if requester_steam_id != 0:
		entity_move_requested.emit(requester_steam_id, entity_id, from_cell, target_cell)


@rpc("authority", "reliable")
func _receive_entity_move(entity_id: String, from_cell: Vector2i, target_cell: Vector2i) -> void:
	entity_move_received.emit(entity_id, from_cell, target_cell)


@rpc("any_peer", "reliable")
func _submit_entity_move_completed(entity_id: String, from_cell: Vector2i, target_cell: Vector2i) -> void:
	var requester_steam_id: int = _get_registered_sender_steam_id()
	if requester_steam_id != 0:
		entity_move_completed_requested.emit(requester_steam_id, entity_id, from_cell, target_cell)


@rpc("authority", "reliable")
func _receive_entity_move_completed(entity_id: String, from_cell: Vector2i, target_cell: Vector2i) -> void:
	entity_move_completed_received.emit(entity_id, from_cell, target_cell)


@rpc("any_peer", "reliable")
func _submit_character_kill() -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id != 0:
		character_kill_requested.emit(requester_peer_id)
