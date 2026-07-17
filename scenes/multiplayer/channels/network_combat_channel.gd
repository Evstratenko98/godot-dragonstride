class_name NetworkCombatChannel
extends NetworkChannel

signal attack_requested(target_cell: Vector2i, match_id: String, turn_revision: int, request_id: int, requester_peer_id: int)
signal entity_attack_received(
	parent_sequence_id: int,
	subsequence_id: int,
	entity_id: String,
	target_cell: Vector2i
)
signal entity_attack_result_received(
	sequence_id: int,
	attacker_entity_id: String,
	target_entity_id: String,
	damage: int,
	target_health: int,
	target_max_health: int
)
signal entity_health_received(sequence_id: int, entity_id: String, health: int)
signal entity_vitality_received(sequence_id: int, entity_id: String, health: int, max_health: int, damage: int)
signal combat_action_payload_received(match_id: String, sequence_id: int, payload: Dictionary)


func request_attack(target_cell: Vector2i, match_id: String, turn_revision: int, request_id: int) -> void:
	if not _can_send():
		return
	if connection.is_host:
		attack_requested.emit(target_cell, match_id, turn_revision, request_id, 0)
		return
	rpc_id(1, "_submit_attack", target_cell, match_id, turn_revision, request_id)


func broadcast_action_payload(match_id: String, sequence_id: int, payload: Dictionary) -> void:
	if _can_host_send() and _is_valid_match_message(match_id) and sequence_id > 0 and _is_payload_size_valid(payload):
		rpc("_receive_action_payload", match_id, sequence_id, payload)


func broadcast_entity_attack(
	parent_sequence_id: int,
	subsequence_id: int,
	entity_id: String,
	target_cell: Vector2i
) -> void:
	if _can_host_send() and parent_sequence_id > 0 and subsequence_id >= 0 and NetworkProtocol.is_valid_identifier(entity_id) and NetworkProtocol.is_valid_cell_value(target_cell):
		rpc("_receive_entity_attack", GameSession.get_match_id(), parent_sequence_id, subsequence_id, entity_id, target_cell)


func broadcast_entity_attack_result(
	sequence_id: int,
	attacker_entity_id: String,
	target_entity_id: String,
	damage: int,
	target_health: int,
	target_max_health: int
) -> void:
	if (
		_can_host_send()
		and sequence_id > 0
		and NetworkProtocol.is_valid_identifier(attacker_entity_id)
		and NetworkProtocol.is_valid_identifier(target_entity_id)
		and NetworkProtocol.is_valid_nonnegative_value(damage)
		and target_max_health > 0 and target_max_health <= NetworkProtocol.MAX_GAMEPLAY_VALUE
		and target_health >= 0 and target_health <= target_max_health
	):
		rpc("_receive_entity_attack_result", GameSession.get_match_id(), sequence_id, attacker_entity_id, target_entity_id, damage, target_health, target_max_health)


func broadcast_entity_health(sequence_id: int, entity_id: String, health: int) -> void:
	if _can_host_send() and sequence_id >= 0 and NetworkProtocol.is_valid_identifier(entity_id) and NetworkProtocol.is_valid_nonnegative_value(health):
		rpc("_receive_entity_health", GameSession.get_match_id(), sequence_id, entity_id, health)


func broadcast_entity_vitality(
	entity_id: String,
	health: int,
	max_health: int,
	damage: int,
	sequence_id: int = 0
) -> void:
	if not _can_host_send() or not _is_valid_vitality(entity_id, health, max_health, damage, sequence_id):
		return
	store.cache_entity_vitality(entity_id, health, max_health, damage)
	rpc("_receive_entity_vitality", GameSession.get_match_id(), sequence_id, entity_id, health, max_health, damage)


func send_entity_vitality_to_peer(
	peer_id: int,
	entity_id: String,
	health: int,
	max_health: int,
	damage: int
) -> void:
	if not _can_host_send() or peer_id == 0 or not _is_valid_vitality(entity_id, health, max_health, damage, 0):
		return
	if peer_id == multiplayer.get_unique_id():
		store.cache_entity_vitality(entity_id, health, max_health, damage)
		entity_vitality_received.emit(0, entity_id, health, max_health, damage)
		return
	rpc_id(peer_id, "_receive_entity_vitality", GameSession.get_match_id(), 0, entity_id, health, max_health, damage)


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_attack(target_cell: Vector2i, match_id: String, turn_revision: int, request_id: int) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id != 0 and NetworkProtocol.is_valid_cell_value(target_cell) and turn_revision >= 0 and _is_valid_intent(match_id, request_id, {"target_cell": target_cell, "turn_revision": turn_revision}):
		attack_requested.emit(target_cell, match_id, turn_revision, request_id, requester_peer_id)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_action_payload(match_id: String, sequence_id: int, payload: Dictionary) -> void:
	if _is_valid_match_message(match_id) and sequence_id > 0 and _is_payload_size_valid(payload):
		combat_action_payload_received.emit(match_id, sequence_id, payload)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_entity_attack(
	match_id: String,
	parent_sequence_id: int,
	subsequence_id: int,
	entity_id: String,
	target_cell: Vector2i
) -> void:
	if _is_valid_match_message(match_id) and parent_sequence_id > 0 and subsequence_id >= 0 and NetworkProtocol.is_valid_identifier(entity_id) and NetworkProtocol.is_valid_cell_value(target_cell):
		entity_attack_received.emit(parent_sequence_id, subsequence_id, entity_id, target_cell)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_entity_attack_result(
	match_id: String,
	sequence_id: int,
	attacker_entity_id: String,
	target_entity_id: String,
	damage: int,
	target_health: int,
	target_max_health: int
) -> void:
	if (
		_is_valid_match_message(match_id)
		and NetworkProtocol.is_valid_identifier(attacker_entity_id)
		and NetworkProtocol.is_valid_identifier(target_entity_id)
		and sequence_id > 0
		and NetworkProtocol.is_valid_nonnegative_value(damage)
		and target_max_health > 0 and target_max_health <= NetworkProtocol.MAX_GAMEPLAY_VALUE
		and target_health >= 0 and target_health <= target_max_health
	):
		entity_attack_result_received.emit(sequence_id, attacker_entity_id, target_entity_id, damage, target_health, target_max_health)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_entity_health(match_id: String, sequence_id: int, entity_id: String, health: int) -> void:
	if _is_valid_match_message(match_id) and sequence_id >= 0 and NetworkProtocol.is_valid_identifier(entity_id) and NetworkProtocol.is_valid_nonnegative_value(health):
		entity_health_received.emit(sequence_id, entity_id, health)


@rpc("authority", "call_remote", "reliable", 1)
func _receive_entity_vitality(match_id: String, sequence_id: int, entity_id: String, health: int, max_health: int, damage: int) -> void:
	if not _is_valid_match_message(match_id) or not _is_valid_vitality(entity_id, health, max_health, damage, sequence_id):
		return
	store.cache_entity_vitality(entity_id, health, max_health, damage)
	entity_vitality_received.emit(sequence_id, entity_id, health, max_health, damage)


func _is_valid_vitality(entity_id: String, health: int, max_health: int, damage: int, sequence_id: int) -> bool:
	return (
		NetworkProtocol.is_valid_identifier(entity_id)
		and sequence_id >= 0
		and max_health > 0 and max_health <= NetworkProtocol.MAX_GAMEPLAY_VALUE
		and health >= 0 and health <= max_health
		and NetworkProtocol.is_valid_nonnegative_value(damage)
	)
