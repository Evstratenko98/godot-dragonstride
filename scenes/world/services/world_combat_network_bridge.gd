class_name WorldCombatNetworkBridge
extends RefCounted

var network: WorldNetwork = null


func configure(owner: WorldNetwork) -> void:
	network = owner


func request_attack(attacker: PlayerCharacter, target_surface: Vector3i) -> bool:
	if network == null or attacker == null or attacker != network.runtime.get_selected_local_character():
		return false
	if attacker.health <= 0 or not attacker.can_attack_surface(target_surface):
		return false
	if not network.runtime.can_entity_attack_in_turn(attacker, target_surface):
		return false
	var request_id: int = network.runtime.create_action_request_id()
	if GameSession.is_singleplayer():
		return network.runtime.enqueue_player_action(
			WorldActionRecord.ActionType.ATTACK,
			attacker,
			{"target_surface": target_surface},
			request_id,
			0
		)
	if not NetworkManager.connection.is_ready():
		return false
	NetworkManager.combat.request_attack(
		attacker.entity_id,
		target_surface,
		GameSession.get_match_id(),
		network.runtime.get_turn_revision(),
		request_id
	)
	return true


func on_attack_requested(
	actor_entity_id: String,
	target_surface: Vector3i,
	match_id: String,
	turn_revision: int,
	request_id: int,
	requester_peer_id: int
) -> void:
	if network == null or not GameSession.is_host():
		return
	var player: PlayerCharacter = network.get_requesting_player(requester_peer_id, actor_entity_id)
	if player == null:
		return
	network.runtime.enqueue_player_action(
		WorldActionRecord.ActionType.ATTACK,
		player,
		{"target_surface": target_surface},
		request_id,
		requester_peer_id,
		turn_revision,
		match_id
	)


func on_entity_attack_received(
	parent_sequence_id: int,
	subsequence_id: int,
	entity_id: String,
	target_surface: Vector3i
) -> void:
	if network.message_buffer.buffer_npc_action(parent_sequence_id, {
		"kind": "attack",
		"subsequence_id": subsequence_id,
		"entity_id": entity_id,
		"target_surface": target_surface,
	}):
		return
	apply_npc_attack(entity_id, target_surface)


func apply_npc_attack(entity_id: String, target_surface: Vector3i) -> void:
	var attacker: Entity = network.runtime.get_entity_by_id(entity_id) as Entity
	if attacker == null:
		return
	if GameSession.is_host() and (
		not attacker.can_attack_surface(target_surface)
		or not network.runtime.can_entity_attack_in_turn(attacker, target_surface)
	):
		return
	if attacker is PlayerCharacter:
		(attacker as PlayerCharacter).play_remote_attack(target_surface, false)
	elif attacker is NonPlayerEntity:
		(attacker as NonPlayerEntity).play_remote_attack(target_surface, false)
	else:
		attacker.request_attack_surface(target_surface, false, false)
	if GameSession.is_host():
		network.runtime.notify_entity_attacked_in_turn(attacker, target_surface)
		network.runtime.apply_attack_to_surface(attacker, target_surface, true, false)
	else:
		network.runtime.print_non_entity_attack_result(attacker, target_surface)


func on_attack_result_received(
	sequence_id: int,
	attacker_entity_id: String,
	target_entity_id: String,
	damage_amount: int,
	target_health: int,
	target_max_health: int
) -> void:
	if network.message_buffer.buffer_combat(sequence_id, {
		"kind": "attack_result",
		"attacker_entity_id": attacker_entity_id,
		"target_entity_id": target_entity_id,
		"damage_amount": damage_amount,
		"target_health": target_health,
		"target_max_health": target_max_health,
	}):
		return
	apply_attack_result(attacker_entity_id, target_entity_id, damage_amount, target_health, target_max_health)


func apply_attack_result(
	attacker_entity_id: String,
	target_entity_id: String,
	damage_amount: int,
	target_health: int,
	target_max_health: int
) -> void:
	var attacker: PlayerCharacter = network.runtime.get_player_by_entity_id(attacker_entity_id)
	if attacker != null and attacker.is_locally_owned:
		return
	network.runtime.print_entity_attack_result(
		attacker_entity_id,
		target_entity_id,
		damage_amount,
		target_health,
		target_max_health
	)


func on_health_received(sequence_id: int, entity_id: String, new_health: int) -> void:
	if network.message_buffer.buffer_combat(sequence_id, {
		"kind": "health",
		"entity_id": entity_id,
		"health": new_health,
	}):
		return
	apply_health(entity_id, new_health)


func apply_health(entity_id: String, new_health: int) -> void:
	var entity: Entity = network.runtime.get_entity_by_id(entity_id) as Entity
	if entity != null:
		entity.set_health(new_health)


func on_vitality_received(
	sequence_id: int,
	entity_id: String,
	new_health: int,
	new_max_health: int,
	new_damage: int
) -> void:
	if network.message_buffer.buffer_combat(sequence_id, {
		"kind": "vitality",
		"entity_id": entity_id,
		"health": new_health,
		"max_health": new_max_health,
		"damage": new_damage,
	}):
		return
	apply_vitality(entity_id, new_health, new_max_health, new_damage)


func apply_vitality(entity_id: String, health: int, max_health: int, damage: int) -> void:
	var player: PlayerCharacter = network.runtime.get_entity_by_id(entity_id) as PlayerCharacter
	if player == null:
		return
	player.apply_vitality_state(health, max_health)
	player.apply_attack_damage_state(damage)


func apply_cached_vitality_states() -> void:
	for entity_id_value: Variant in NetworkManager.store.get_entity_vitality_states().keys():
		var entity_id: String = str(entity_id_value)
		var state: Dictionary = NetworkManager.store.get_entity_vitality_states()[entity_id_value]
		apply_vitality(
			entity_id,
			int(state.get("health", 0)),
			int(state.get("max_health", 1)),
			int(state.get("damage", 0))
		)


func send_vitality_states_to_peer(peer_id: int) -> void:
	if peer_id == 0 or not GameSession.is_host():
		return
	for entity_value: Variant in network.runtime.get_registered_entities():
		var player: PlayerCharacter = entity_value as PlayerCharacter
		if player != null:
			NetworkManager.combat.send_entity_vitality_to_peer(
				peer_id,
				player.entity_id,
				player.health,
				player.max_health,
				player.damage
			)


func send_vitality_states_to_mapped_peers() -> void:
	if not GameSession.is_host():
		return
	var peer_map: Dictionary = NetworkManager.peers.get_peer_map()
	for peer_id_value: Variant in peer_map.keys():
		send_vitality_states_to_peer(int(peer_id_value))
