class_name WorldCharacterMovementBridge
extends RefCounted

var network: WorldNetwork = null
var move_request_tracker: WorldMoveRequestTracker = WorldMoveRequestTracker.new()
var tracked_characters: Array[PlayerCharacter] = []
var held_state_by_entity_id: Dictionary[String, bool] = {}


func configure(owner: WorldNetwork) -> void:
	disconnect_signals()
	network = owner
	move_request_tracker.clear()
	held_state_by_entity_id.clear()


func connect_signals() -> void:
	if network == null or network.runtime == null:
		return
	if not NetworkManager.character.character_move_path_requested.is_connected(_on_character_move_path_requested):
		NetworkManager.character.character_move_path_requested.connect(_on_character_move_path_requested)
	if not NetworkManager.character.movement_input_state_requested.is_connected(_on_movement_input_state_requested):
		NetworkManager.character.movement_input_state_requested.connect(_on_movement_input_state_requested)
	if not NetworkManager.character.movement_input_state_received.is_connected(_on_movement_input_state_received):
		NetworkManager.character.movement_input_state_received.connect(_on_movement_input_state_received)
	if not NetworkManager.peers.peer_map_updated.is_connected(_on_peer_map_updated):
		NetworkManager.peers.peer_map_updated.connect(_on_peer_map_updated)
	if not network.runtime.get_tree().node_added.is_connected(_on_scene_tree_node_added):
		network.runtime.get_tree().node_added.connect(_on_scene_tree_node_added)
	if (
		network.runtime.players_service != null
		and not network.runtime.players_service.player_connection_changed.is_connected(_on_player_connection_changed)
	):
		network.runtime.players_service.player_connection_changed.connect(_on_player_connection_changed)
	if (
		network.runtime.turn_manager != null
		and not network.runtime.turn_manager.turn_state_changed.is_connected(_on_turn_state_changed)
	):
		network.runtime.turn_manager.turn_state_changed.connect(_on_turn_state_changed)
	for entity_variant: Variant in network.runtime.get_registered_entities():
		_track_character(entity_variant as PlayerCharacter)


func disconnect_signals() -> void:
	if NetworkManager.character != null:
		if NetworkManager.character.character_move_path_requested.is_connected(_on_character_move_path_requested):
			NetworkManager.character.character_move_path_requested.disconnect(_on_character_move_path_requested)
		if NetworkManager.character.movement_input_state_requested.is_connected(_on_movement_input_state_requested):
			NetworkManager.character.movement_input_state_requested.disconnect(_on_movement_input_state_requested)
		if NetworkManager.character.movement_input_state_received.is_connected(_on_movement_input_state_received):
			NetworkManager.character.movement_input_state_received.disconnect(_on_movement_input_state_received)
	if NetworkManager.peers != null and NetworkManager.peers.peer_map_updated.is_connected(_on_peer_map_updated):
		NetworkManager.peers.peer_map_updated.disconnect(_on_peer_map_updated)
	if network != null and network.runtime != null:
		if network.runtime.get_tree() != null and network.runtime.get_tree().node_added.is_connected(_on_scene_tree_node_added):
			network.runtime.get_tree().node_added.disconnect(_on_scene_tree_node_added)
		if (
			network.runtime.players_service != null
			and network.runtime.players_service.player_connection_changed.is_connected(_on_player_connection_changed)
		):
			network.runtime.players_service.player_connection_changed.disconnect(_on_player_connection_changed)
		if (
			network.runtime.turn_manager != null
			and network.runtime.turn_manager.turn_state_changed.is_connected(_on_turn_state_changed)
		):
			network.runtime.turn_manager.turn_state_changed.disconnect(_on_turn_state_changed)
	for character: PlayerCharacter in tracked_characters.duplicate():
		_untrack_character(character)
	held_state_by_entity_id.clear()
	move_request_tracker.clear()


func request_move_path(player: PlayerCharacter, requested_path: Array[Vector3i]) -> bool:
	if network == null or player == null or player != network.runtime.get_selected_local_character() or requested_path.is_empty():
		return false
	if network.runtime.has_pending_move_path(player) or move_request_tracker.is_pending():
		return false
	var request_id: int = network.runtime.create_action_request_id()
	if GameSession.is_singleplayer():
		return network.runtime.enqueue_player_action(
			WorldActionRecord.ActionType.MOVE_PATH,
			player,
			{WorldMovePathPolicy.REQUESTED_PATH_KEY: requested_path},
			request_id,
			0
		)
	if not NetworkManager.connection.is_ready():
		return false
	move_request_tracker.begin(request_id)
	NetworkManager.character.request_character_move_path(
		player.entity_id,
		requested_path,
		GameSession.get_match_id(),
		network.runtime.get_turn_revision(),
		request_id
	)
	return true


func request_entity_move_started(
	entity: Node,
	from_surface: Vector3i,
	target_surface: Vector3i,
	should_broadcast: bool = true
) -> void:
	if (
		network == null
		or not should_broadcast
		or not GameSession.is_multiplayer()
		or not GameSession.is_host()
	):
		return
	var entity_id: String = network.runtime.get_entity_id(entity)
	if entity_id.is_empty():
		return
	NetworkManager.character.broadcast_entity_move(
		network.runtime.get_current_action_sequence_id(),
		network.runtime.claim_current_action_subsequence_id(),
		entity_id,
		from_surface,
		target_surface
	)


func on_entity_move_received(
	parent_sequence_id: int,
	subsequence_id: int,
	entity_id: String,
	from_surface: Vector3i,
	target_surface: Vector3i
) -> void:
	if network.message_buffer.buffer_npc_action(parent_sequence_id, {
		"kind": "move",
		"subsequence_id": subsequence_id,
		"entity_id": entity_id,
		"from_surface": from_surface,
		"target_surface": target_surface,
	}):
		return
	apply_npc_move(entity_id, from_surface, target_surface)


func apply_npc_move(entity_id: String, from_surface: Vector3i, target_surface: Vector3i) -> void:
	var entity: Entity = network.runtime.get_entity_by_id(entity_id) as Entity
	if entity == null or (entity is PlayerCharacter and (entity as PlayerCharacter).is_locally_owned):
		return
	if not network.runtime.has_traversal_edge(from_surface, target_surface):
		return
	if entity is NonPlayerEntity:
		(entity as NonPlayerEntity).play_remote_move(from_surface, target_surface)
		return
	network.runtime.reserve_entity_surface(entity, from_surface, target_surface)


func handle_action_finished(action: WorldActionRecord) -> void:
	move_request_tracker.finish_action(action)


func handle_action_rejected(request_id: int) -> void:
	move_request_tracker.handle_rejected(request_id)


func handle_action_accepted(request_id: int, sequence_id: int) -> void:
	move_request_tracker.handle_accepted(request_id, sequence_id)


func handle_snapshot_committed(boundary_sequence_id: int) -> void:
	move_request_tracker.handle_snapshot_committed(boundary_sequence_id)


func process_pending_requests() -> void:
	move_request_tracker.expire_if_needed(Time.get_ticks_msec())


func clear() -> void:
	move_request_tracker.clear()
	held_state_by_entity_id.clear()
	for character: PlayerCharacter in tracked_characters:
		if character != null and is_instance_valid(character):
			character.apply_movement_input_state(false)


func _track_character(character: PlayerCharacter) -> void:
	if (
		character == null
		or tracked_characters.has(character)
		or tracked_characters.size() >= NetworkProtocol.MAX_PLAYER_CHARACTERS
	):
		return
	tracked_characters.append(character)
	if not character.movement_input_state_requested.is_connected(_on_character_movement_input_state_requested):
		character.movement_input_state_requested.connect(_on_character_movement_input_state_requested)
	if not character.vitality_changed.is_connected(_on_character_vitality_changed.bind(character)):
		character.vitality_changed.connect(_on_character_vitality_changed.bind(character))
	if not character.tree_exiting.is_connected(_on_character_tree_exiting.bind(character)):
		character.tree_exiting.connect(_on_character_tree_exiting.bind(character))
	if character.is_locally_owned and character.is_movement_input_held:
		_on_character_movement_input_state_requested(character, true)


func _untrack_character(character: PlayerCharacter) -> void:
	if character == null:
		return
	var vitality_callable: Callable = _on_character_vitality_changed.bind(character)
	var exiting_callable: Callable = _on_character_tree_exiting.bind(character)
	if character.movement_input_state_requested.is_connected(_on_character_movement_input_state_requested):
		character.movement_input_state_requested.disconnect(_on_character_movement_input_state_requested)
	if character.vitality_changed.is_connected(vitality_callable):
		character.vitality_changed.disconnect(vitality_callable)
	if character.tree_exiting.is_connected(exiting_callable):
		character.tree_exiting.disconnect(exiting_callable)
	tracked_characters.erase(character)
	held_state_by_entity_id.erase(character.entity_id)


func _set_authoritative_state(
	character: PlayerCharacter,
	is_held: bool,
	should_force_broadcast: bool = false
) -> void:
	if character == null or character.entity_id.is_empty():
		return
	var previous_state: bool = bool(held_state_by_entity_id.get(character.entity_id, false))
	held_state_by_entity_id[character.entity_id] = is_held
	character.apply_movement_input_state(is_held)
	if previous_state == is_held and not should_force_broadcast:
		return
	if GameSession.is_multiplayer() and GameSession.is_host():
		NetworkManager.character.broadcast_movement_input_state(character.entity_id, is_held)


func _can_hold_movement_input(character: PlayerCharacter, turn_revision: int) -> bool:
	return (
		character != null
		and character.health > 0
		and turn_revision == network.runtime.get_turn_revision()
		and network.runtime.is_player_connected(character.steam_id)
		and network.runtime.can_entity_move_in_turn(character)
	)


func _on_character_movement_input_state_requested(character: PlayerCharacter, is_held: bool) -> void:
	if network == null or character == null or not character.is_locally_owned:
		return
	if GameSession.is_singleplayer():
		held_state_by_entity_id[character.entity_id] = is_held
		return
	if not NetworkManager.connection.is_ready():
		return
	NetworkManager.character.request_movement_input_state(
		character.entity_id,
		is_held,
		GameSession.get_match_id(),
		network.runtime.get_turn_revision(),
		network.runtime.create_action_request_id()
	)


func _on_movement_input_state_requested(
	requester_steam_id: int,
	actor_entity_id: String,
	is_held: bool,
	match_id: String,
	turn_revision: int,
	_request_id: int
) -> void:
	if network == null or not GameSession.is_host() or match_id != GameSession.get_match_id():
		return
	if not network.runtime.is_character_owned_by_steam_id(actor_entity_id, requester_steam_id):
		return
	var character: PlayerCharacter = network.runtime.get_player_by_entity_id(actor_entity_id)
	if character == null:
		return
	if is_held and not _can_hold_movement_input(character, turn_revision):
		_set_authoritative_state(character, false, true)
		return
	_set_authoritative_state(character, is_held)


func _on_movement_input_state_received(actor_entity_id: String, is_held: bool) -> void:
	if network == null or GameSession.is_host():
		return
	var character: PlayerCharacter = network.runtime.get_player_by_entity_id(actor_entity_id)
	if character == null:
		return
	held_state_by_entity_id[actor_entity_id] = is_held
	character.apply_movement_input_state(is_held)


func _on_character_move_path_requested(
	requester_steam_id: int,
	actor_entity_id: String,
	requested_path: Array[Vector3i],
	match_id: String,
	turn_revision: int,
	request_id: int,
	requester_peer_id: int
) -> void:
	if network == null or not GameSession.is_host():
		return
	if not network.runtime.is_character_owned_by_steam_id(actor_entity_id, requester_steam_id):
		_reject_move_path_request(requester_peer_id, request_id)
		return
	var player: PlayerCharacter = network.runtime.get_player_by_entity_id(actor_entity_id)
	if player == null:
		_reject_move_path_request(requester_peer_id, request_id)
		return
	network.runtime.enqueue_player_action(
		WorldActionRecord.ActionType.MOVE_PATH,
		player,
		{WorldMovePathPolicy.REQUESTED_PATH_KEY: requested_path},
		request_id,
		requester_peer_id,
		turn_revision,
		match_id
	)


func _reject_move_path_request(requester_peer_id: int, request_id: int) -> void:
	if requester_peer_id > 0:
		NetworkManager.actions.send_action_rejected(
			requester_peer_id,
			request_id,
			WorldActionStream.REJECTION_ACTOR_UNAVAILABLE
		)
		return
	move_request_tracker.handle_rejected(request_id)


func _on_scene_tree_node_added(node: Node) -> void:
	_track_character(node as PlayerCharacter)


func _on_character_tree_exiting(character: PlayerCharacter) -> void:
	if GameSession.is_host() and bool(held_state_by_entity_id.get(character.entity_id, false)):
		_set_authoritative_state(character, false)
	_untrack_character(character)


func _on_character_vitality_changed(current_health: int, _maximum_health: int, character: PlayerCharacter) -> void:
	if current_health <= 0 and GameSession.is_host():
		_set_authoritative_state(character, false)


func _on_player_connection_changed(steam_id: int, is_connected: bool) -> void:
	if is_connected or network == null or not GameSession.is_host():
		return
	for character: PlayerCharacter in network.runtime.get_squad_members_by_steam_id(steam_id):
		_set_authoritative_state(character, false)


func _on_turn_state_changed() -> void:
	if network == null or not GameSession.is_host():
		return
	for entity_id: String in held_state_by_entity_id.keys():
		if not bool(held_state_by_entity_id.get(entity_id, false)):
			continue
		var character: PlayerCharacter = network.runtime.get_player_by_entity_id(entity_id)
		if character == null or not network.runtime.can_entity_move_in_turn(character):
			_set_authoritative_state(character, false)


func _on_peer_map_updated() -> void:
	if network == null or not GameSession.is_multiplayer() or not NetworkManager.connection.is_ready():
		return
	if GameSession.is_host():
		for entity_id: String in held_state_by_entity_id.keys():
			if bool(held_state_by_entity_id.get(entity_id, false)):
				NetworkManager.character.broadcast_movement_input_state(entity_id, true)
		return
	for character: PlayerCharacter in tracked_characters:
		if character.is_locally_owned and character.is_movement_input_held:
			_on_character_movement_input_state_requested(character, true)
