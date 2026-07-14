class_name NetworkCombatChannel
extends NetworkChannel

signal attack_requested(target_cell: Vector2i, requester_peer_id: int)
signal entity_attack_received(entity_id: String, target_cell: Vector2i)
signal entity_attack_result_received(
	attacker_entity_id: String,
	target_entity_id: String,
	damage: int,
	target_health: int,
	target_max_health: int
)
signal entity_health_received(entity_id: String, health: int)
signal entity_vitality_received(entity_id: String, health: int, max_health: int, damage: int)


func request_attack(target_cell: Vector2i) -> void:
	if not _can_send():
		return
	if connection.is_host:
		attack_requested.emit(target_cell, 0)
		return
	rpc_id(1, "_submit_attack", target_cell)


func broadcast_entity_attack(entity_id: String, target_cell: Vector2i) -> void:
	if _can_host_send():
		rpc("_receive_entity_attack", entity_id, target_cell)


func broadcast_entity_attack_result(
	attacker_entity_id: String,
	target_entity_id: String,
	damage: int,
	target_health: int,
	target_max_health: int
) -> void:
	if _can_host_send():
		rpc("_receive_entity_attack_result", attacker_entity_id, target_entity_id, damage, target_health, target_max_health)


func broadcast_entity_health(entity_id: String, health: int) -> void:
	if _can_host_send():
		rpc("_receive_entity_health", entity_id, health)


func broadcast_entity_vitality(entity_id: String, health: int, max_health: int, damage: int) -> void:
	if not _can_host_send():
		return
	store.cache_entity_vitality(entity_id, health, max_health, damage)
	rpc("_receive_entity_vitality", entity_id, health, max_health, damage)


func send_entity_vitality_to_peer(
	peer_id: int,
	entity_id: String,
	health: int,
	max_health: int,
	damage: int
) -> void:
	if not _can_host_send() or peer_id == 0:
		return
	if peer_id == multiplayer.get_unique_id():
		store.cache_entity_vitality(entity_id, health, max_health, damage)
		entity_vitality_received.emit(entity_id, health, max_health, damage)
		return
	rpc_id(peer_id, "_receive_entity_vitality", entity_id, health, max_health, damage)


@rpc("any_peer", "reliable")
func _submit_attack(target_cell: Vector2i) -> void:
	var requester_peer_id: int = _get_registered_sender_peer_id()
	if requester_peer_id != 0:
		attack_requested.emit(target_cell, requester_peer_id)


@rpc("authority", "reliable")
func _receive_entity_attack(entity_id: String, target_cell: Vector2i) -> void:
	entity_attack_received.emit(entity_id, target_cell)


@rpc("authority", "reliable")
func _receive_entity_attack_result(
	attacker_entity_id: String,
	target_entity_id: String,
	damage: int,
	target_health: int,
	target_max_health: int
) -> void:
	entity_attack_result_received.emit(attacker_entity_id, target_entity_id, damage, target_health, target_max_health)


@rpc("authority", "reliable")
func _receive_entity_health(entity_id: String, health: int) -> void:
	entity_health_received.emit(entity_id, health)


@rpc("authority", "reliable")
func _receive_entity_vitality(entity_id: String, health: int, max_health: int, damage: int) -> void:
	store.cache_entity_vitality(entity_id, health, max_health, damage)
	entity_vitality_received.emit(entity_id, health, max_health, damage)
