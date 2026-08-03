class_name WorldSpellSignalBridge
extends RefCounted

var spells: WorldSpells = null
var pending_local_request_ids: Dictionary[int, int] = {}


func configure(owner: WorldSpells) -> void:
	spells = owner


func connect_network_signals() -> void:
	if not NetworkManager.spells.spell_cast_requested.is_connected(_on_spell_cast_requested):
		NetworkManager.spells.spell_cast_requested.connect(_on_spell_cast_requested)
	if not NetworkManager.spells.spell_action_payload_received.is_connected(_on_spell_action_payload_received):
		NetworkManager.spells.spell_action_payload_received.connect(_on_spell_action_payload_received)
	if not NetworkManager.actions.action_accepted.is_connected(_on_action_accepted):
		NetworkManager.actions.action_accepted.connect(_on_action_accepted)
	if not NetworkManager.actions.action_rejected.is_connected(_on_action_rejected):
		NetworkManager.actions.action_rejected.connect(_on_action_rejected)


func connect_runtime_signals() -> void:
	if spells.runtime == null:
		return
	if spells.runtime.turn_manager != null:
		if not spells.runtime.turn_manager.player_turn_started.is_connected(_on_player_turn_started):
			spells.runtime.turn_manager.player_turn_started.connect(_on_player_turn_started)
		if not spells.runtime.turn_manager.round_started.is_connected(_on_round_started):
			spells.runtime.turn_manager.round_started.connect(_on_round_started)
		if not spells.runtime.turn_manager.turn_mode_changed.is_connected(_on_turn_mode_changed):
			spells.runtime.turn_manager.turn_mode_changed.connect(_on_turn_mode_changed)
	if spells.runtime.action_stream != null:
		if not spells.runtime.action_stream.action_completed.is_connected(_on_stream_action_completed):
			spells.runtime.action_stream.action_completed.connect(_on_stream_action_completed)
		if not spells.runtime.action_stream.action_cancelled.is_connected(_on_stream_action_cancelled):
			spells.runtime.action_stream.action_cancelled.connect(_on_stream_action_cancelled)
		if not spells.runtime.action_stream.remote_snapshot_committed.is_connected(_on_remote_snapshot_committed):
			spells.runtime.action_stream.remote_snapshot_committed.connect(_on_remote_snapshot_committed)


func disconnect_signals() -> void:
	if NetworkManager.spells.spell_cast_requested.is_connected(_on_spell_cast_requested):
		NetworkManager.spells.spell_cast_requested.disconnect(_on_spell_cast_requested)
	if NetworkManager.spells.spell_action_payload_received.is_connected(_on_spell_action_payload_received):
		NetworkManager.spells.spell_action_payload_received.disconnect(_on_spell_action_payload_received)
	if NetworkManager.actions.action_accepted.is_connected(_on_action_accepted):
		NetworkManager.actions.action_accepted.disconnect(_on_action_accepted)
	if NetworkManager.actions.action_rejected.is_connected(_on_action_rejected):
		NetworkManager.actions.action_rejected.disconnect(_on_action_rejected)
	if spells.runtime == null:
		return
	if spells.runtime.turn_manager != null:
		if spells.runtime.turn_manager.player_turn_started.is_connected(_on_player_turn_started):
			spells.runtime.turn_manager.player_turn_started.disconnect(_on_player_turn_started)
		if spells.runtime.turn_manager.round_started.is_connected(_on_round_started):
			spells.runtime.turn_manager.round_started.disconnect(_on_round_started)
		if spells.runtime.turn_manager.turn_mode_changed.is_connected(_on_turn_mode_changed):
			spells.runtime.turn_manager.turn_mode_changed.disconnect(_on_turn_mode_changed)
	if spells.runtime.action_stream != null:
		if spells.runtime.action_stream.action_completed.is_connected(_on_stream_action_completed):
			spells.runtime.action_stream.action_completed.disconnect(_on_stream_action_completed)
		if spells.runtime.action_stream.action_cancelled.is_connected(_on_stream_action_cancelled):
			spells.runtime.action_stream.action_cancelled.disconnect(_on_stream_action_cancelled)
		if spells.runtime.action_stream.remote_snapshot_committed.is_connected(_on_remote_snapshot_committed):
			spells.runtime.action_stream.remote_snapshot_committed.disconnect(_on_remote_snapshot_committed)


func track_local_request(request_id: int) -> void:
	pending_local_request_ids[request_id] = 0


func clear() -> void:
	pending_local_request_ids.clear()


func _on_spell_cast_requested(actor_entity_id: String, spell_slot_index: int, target_cell: Vector2i, match_id: String, turn_revision: int, request_id: int, requester_peer_id: int) -> void:
	if not GameSession.is_host():
		return
	var player: PlayerCharacter = spells._get_requesting_player(requester_peer_id, actor_entity_id)
	if player != null:
		spells.runtime.enqueue_player_action(WorldActionRecord.ActionType.SPELL_CAST, player, {"spell_slot_index": spell_slot_index, "target_cell": target_cell, "target_kind": "cell"}, request_id, requester_peer_id, turn_revision, match_id)


func _on_player_turn_started(_player_id: String) -> void:
	spells._clear_targeting()


func _on_round_started(_round_number: int) -> void:
	spells.usage_ledger.clear()
	spells.spell_usage_changed.emit()


func _on_turn_mode_changed(_is_enabled: bool) -> void:
	spells.usage_ledger.clear()
	spells.spell_usage_changed.emit()


func _on_spell_action_payload_received(match_id: String, sequence_id: int, payload: Dictionary) -> void:
	if not GameSession.is_host() and spells.runtime != null and match_id == GameSession.get_match_id():
		spells.runtime.receive_action_profile_payload(sequence_id, payload)


func _on_stream_action_completed(action: WorldActionRecord) -> void:
	if action != null and action.action_type == WorldActionRecord.ActionType.SPELL_CAST:
		pending_local_request_ids.erase(action.request_id)


func _on_stream_action_cancelled(action: WorldActionRecord, reason_code: String) -> void:
	if action != null and pending_local_request_ids.has(action.request_id):
		pending_local_request_ids.erase(action.request_id)
		spells._print_rejection(reason_code)


func _on_action_rejected(request_id: int, reason_code: String) -> void:
	if pending_local_request_ids.has(request_id):
		pending_local_request_ids.erase(request_id)
		spells._print_rejection(reason_code)


func _on_action_accepted(request_id: int, sequence_id: int) -> void:
	if pending_local_request_ids.has(request_id):
		pending_local_request_ids[request_id] = sequence_id


func _on_remote_snapshot_committed(boundary_sequence_id: int) -> void:
	for request_id: int in pending_local_request_ids.keys():
		var sequence_id: int = pending_local_request_ids[request_id]
		if sequence_id > 0 and sequence_id < boundary_sequence_id:
			pending_local_request_ids.erase(request_id)
