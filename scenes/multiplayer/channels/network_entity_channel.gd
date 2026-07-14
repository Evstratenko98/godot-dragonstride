class_name NetworkEntityChannel
extends NetworkChannel

signal object_state_received(object_id: String, object_state: int)
signal entity_ai_state_received(entity_id: String, state: String, target_entity_id: String, reason: String)
signal entity_respawn_received(entity_id: String, cell: Vector2i, health: int)
signal entity_removed_received(entity_id: String)


func broadcast_object_state(object_id: String, object_state: int) -> void:
	if not _can_host_send():
		return
	store.cache_object_state(object_id, object_state)
	rpc("_receive_object_state", object_id, object_state)


func broadcast_entity_ai_state(entity_id: String, state: String, target_entity_id: String, reason: String) -> void:
	if not _can_host_send():
		return
	store.cache_entity_ai_state(entity_id, state, target_entity_id, reason)
	rpc("_receive_entity_ai_state", entity_id, state, target_entity_id, reason)


func broadcast_entity_respawn(entity_id: String, cell: Vector2i, health: int) -> void:
	if _can_host_send():
		rpc("_receive_entity_respawn", entity_id, cell, health)


func broadcast_entity_removed(entity_id: String) -> void:
	if _can_host_send():
		rpc("_receive_entity_removed", entity_id)


func send_entity_ai_states_to_peer(peer_id: int) -> void:
	if not _can_host_send() or peer_id == 0:
		return
	var entity_ai_states: Dictionary = store.get_entity_ai_states()
	for entity_id_variant: Variant in entity_ai_states.keys():
		var entity_id: String = str(entity_id_variant)
		var state: Dictionary = entity_ai_states[entity_id_variant]
		rpc_id(
			peer_id,
			"_receive_entity_ai_state",
			entity_id,
			str(state.get("state", "")),
			str(state.get("target_entity_id", "")),
			str(state.get("reason", ""))
		)


@rpc("authority", "reliable")
func _receive_object_state(object_id: String, object_state: int) -> void:
	store.cache_object_state(object_id, object_state)
	object_state_received.emit(object_id, object_state)


@rpc("authority", "reliable")
func _receive_entity_ai_state(entity_id: String, state: String, target_entity_id: String, reason: String) -> void:
	store.cache_entity_ai_state(entity_id, state, target_entity_id, reason)
	entity_ai_state_received.emit(entity_id, state, target_entity_id, reason)


@rpc("authority", "reliable")
func _receive_entity_respawn(entity_id: String, cell: Vector2i, health: int) -> void:
	entity_respawn_received.emit(entity_id, cell, health)


@rpc("authority", "reliable")
func _receive_entity_removed(entity_id: String) -> void:
	entity_removed_received.emit(entity_id)
