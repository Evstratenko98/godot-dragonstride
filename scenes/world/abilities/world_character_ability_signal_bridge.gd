class_name WorldCharacterAbilitySignalBridge
extends RefCounted

var abilities: WorldCharacterAbilities = null
var pending_local_request_ids: Dictionary[int, int] = {}


func configure(owner: WorldCharacterAbilities) -> void:
	abilities = owner


func connect_signals() -> void:
	if not NetworkManager.abilities.character_ability_requested.is_connected(_on_character_ability_requested):
		NetworkManager.abilities.character_ability_requested.connect(_on_character_ability_requested)
	if not NetworkManager.abilities.ability_action_payload_received.is_connected(_on_ability_action_payload_received):
		NetworkManager.abilities.ability_action_payload_received.connect(_on_ability_action_payload_received)
	if not NetworkManager.actions.action_accepted.is_connected(_on_action_accepted):
		NetworkManager.actions.action_accepted.connect(_on_action_accepted)
	if not NetworkManager.actions.action_rejected.is_connected(_on_action_rejected):
		NetworkManager.actions.action_rejected.connect(_on_action_rejected)
	if abilities.runtime != null and abilities.runtime.turn_manager != null:
		var turns: WorldTurns = abilities.runtime.turn_manager
		if not turns.player_turn_started.is_connected(_on_player_turn_started):
			turns.player_turn_started.connect(_on_player_turn_started)
		if not turns.round_started.is_connected(_on_round_started):
			turns.round_started.connect(_on_round_started)
		if not turns.turn_mode_changed.is_connected(_on_turn_mode_changed):
			turns.turn_mode_changed.connect(_on_turn_mode_changed)
		if not turns.turn_state_changed.is_connected(_on_turn_state_changed):
			turns.turn_state_changed.connect(_on_turn_state_changed)
	if abilities.runtime != null and abilities.runtime.action_stream != null:
		var stream: WorldActionStream = abilities.runtime.action_stream
		if not stream.action_completed.is_connected(_on_stream_action_completed):
			stream.action_completed.connect(_on_stream_action_completed)
		if not stream.action_cancelled.is_connected(_on_stream_action_cancelled):
			stream.action_cancelled.connect(_on_stream_action_cancelled)
		if not stream.remote_snapshot_committed.is_connected(_on_remote_snapshot_committed):
			stream.remote_snapshot_committed.connect(_on_remote_snapshot_committed)
	if not GameSession.session_cleared.is_connected(_on_session_cleared):
		GameSession.session_cleared.connect(_on_session_cleared)


func disconnect_signals() -> void:
	if NetworkManager.abilities.character_ability_requested.is_connected(_on_character_ability_requested):
		NetworkManager.abilities.character_ability_requested.disconnect(_on_character_ability_requested)
	if NetworkManager.abilities.ability_action_payload_received.is_connected(_on_ability_action_payload_received):
		NetworkManager.abilities.ability_action_payload_received.disconnect(_on_ability_action_payload_received)
	if NetworkManager.actions.action_accepted.is_connected(_on_action_accepted):
		NetworkManager.actions.action_accepted.disconnect(_on_action_accepted)
	if NetworkManager.actions.action_rejected.is_connected(_on_action_rejected):
		NetworkManager.actions.action_rejected.disconnect(_on_action_rejected)
	if abilities == null:
		return
	if abilities.runtime != null and abilities.runtime.turn_manager != null:
		var turns: WorldTurns = abilities.runtime.turn_manager
		if turns.player_turn_started.is_connected(_on_player_turn_started):
			turns.player_turn_started.disconnect(_on_player_turn_started)
		if turns.round_started.is_connected(_on_round_started):
			turns.round_started.disconnect(_on_round_started)
		if turns.turn_mode_changed.is_connected(_on_turn_mode_changed):
			turns.turn_mode_changed.disconnect(_on_turn_mode_changed)
		if turns.turn_state_changed.is_connected(_on_turn_state_changed):
			turns.turn_state_changed.disconnect(_on_turn_state_changed)
	if abilities.runtime != null and abilities.runtime.action_stream != null:
		var stream: WorldActionStream = abilities.runtime.action_stream
		if stream.action_completed.is_connected(_on_stream_action_completed):
			stream.action_completed.disconnect(_on_stream_action_completed)
		if stream.action_cancelled.is_connected(_on_stream_action_cancelled):
			stream.action_cancelled.disconnect(_on_stream_action_cancelled)
		if stream.remote_snapshot_committed.is_connected(_on_remote_snapshot_committed):
			stream.remote_snapshot_committed.disconnect(_on_remote_snapshot_committed)
	if GameSession.session_cleared.is_connected(_on_session_cleared):
		GameSession.session_cleared.disconnect(_on_session_cleared)


func track_local_request(request_id: int) -> void:
	pending_local_request_ids[request_id] = 0


func clear() -> void:
	pending_local_request_ids.clear()


func _on_character_ability_requested(
	actor_entity_id: String,
	ability_id: String,
	target_surface: Vector3i,
	match_id: String,
	turn_revision: int,
	request_id: int,
	requester_peer_id: int
) -> void:
	if not GameSession.is_host() or abilities.runtime == null:
		return
	var player: PlayerCharacter = abilities.get_requesting_player(requester_peer_id, actor_entity_id)
	if player == null:
		var requester_steam_id: int = NetworkManager.peers.get_steam_id_for_peer_id(requester_peer_id)
		var invalid_action: WorldActionRecord = WorldActionRecord.create(
			request_id,
			match_id,
			requester_steam_id,
			actor_entity_id,
			WorldActionRecord.ActionType.CHARACTER_ABILITY,
			turn_revision,
			{"ability_id": ability_id, "target_surface": target_surface}
		)
		abilities.runtime.action_stream.enqueue_external_action(invalid_action, requester_peer_id)
		return
	abilities.runtime.enqueue_player_action(
		WorldActionRecord.ActionType.CHARACTER_ABILITY,
		player,
		{"ability_id": ability_id, "target_surface": target_surface},
		request_id,
		requester_peer_id,
		turn_revision,
		match_id
	)


func _on_ability_action_payload_received(match_id: String, sequence_id: int, payload: Dictionary) -> void:
	if not GameSession.is_host() and abilities.runtime != null and match_id == GameSession.get_match_id():
		abilities.runtime.receive_action_profile_payload(sequence_id, payload)


func _on_player_turn_started(player_id: String) -> void:
	abilities.begin_player_turn(player_id)


func _on_round_started(_round_number: int) -> void:
	abilities.clear_non_player_provocations()


func _on_turn_mode_changed(_is_enabled: bool) -> void:
	abilities.reset_state()


func _on_turn_state_changed() -> void:
	abilities.sync_player_provocation_turn_state()


func _on_stream_action_completed(action: WorldActionRecord) -> void:
	abilities.handle_player_provocation_action_completed(action)
	if action != null and action.action_type == WorldActionRecord.ActionType.CHARACTER_ABILITY:
		pending_local_request_ids.erase(action.request_id)


func _on_stream_action_cancelled(action: WorldActionRecord, reason_code: String) -> void:
	abilities.handle_player_provocation_action_cancelled(action)
	if action != null and pending_local_request_ids.has(action.request_id):
		pending_local_request_ids.erase(action.request_id)
		abilities.notify_rejected(reason_code)


func _on_action_rejected(request_id: int, reason_code: String) -> void:
	if pending_local_request_ids.has(request_id):
		pending_local_request_ids.erase(request_id)
		abilities.notify_rejected(reason_code)


func _on_action_accepted(request_id: int, sequence_id: int) -> void:
	if pending_local_request_ids.has(request_id):
		pending_local_request_ids[request_id] = sequence_id


func _on_remote_snapshot_committed(boundary_sequence_id: int) -> void:
	for request_id: int in pending_local_request_ids.keys():
		var sequence_id: int = pending_local_request_ids[request_id]
		if sequence_id > 0 and sequence_id < boundary_sequence_id:
			pending_local_request_ids.erase(request_id)
	abilities.sync_player_provocation_turn_state()


func _on_session_cleared() -> void:
	abilities.reset_state()
