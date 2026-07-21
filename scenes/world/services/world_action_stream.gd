class_name WorldActionStream
extends Node

signal action_started(action: WorldActionRecord)
signal action_completed(action: WorldActionRecord)
signal action_cancelled(action: WorldActionRecord, reason_code: String)
signal stream_idle_changed(is_idle: bool)
signal sync_state_changed(is_synchronizing: bool)
signal runtime_sync_failed(reason_code: String)
signal remote_snapshot_committed(boundary_sequence_id: int)

const MAX_QUEUED_ACTIONS := 64
const MAX_INTERNAL_QUEUED_ACTIONS := 256
const MAX_PROCESSED_REQUESTS_PER_PLAYER := 256
const INTENT_RATE_PER_SECOND := 8.0
const INTENT_RATE_BURST := 12.0
const REJECTION_QUEUE_FULL := "queue_full"
const REJECTION_DUPLICATE_REQUEST := "duplicate_request"
const REJECTION_INVALID_ACTION := "invalid_action"
const REJECTION_ACTOR_UNAVAILABLE := "actor_unavailable"
const REJECTION_PRESENTATION_TIMEOUT := "presentation_timeout"
const REJECTION_WRONG_MATCH := "wrong_match"
const REJECTION_STALE_TURN := "stale_turn"
const REJECTION_NOT_ACTIVE_PLAYER := "not_active_player"
const REJECTION_ACTOR_BUSY := "actor_busy"
const REJECTION_RATE_LIMITED := "rate_limited"
const REJECTION_WORLD_TURN := "world_turn"
const REJECTION_ACTOR_DISCONNECTED := "actor_disconnected"
const REJECTION_SEQUENCE_GAP := "sequence_gap"
const REJECTION_STATE_SYNC_FAILED := "state_sync_failed"
const SNAPSHOT_RETRY_MSEC := 500
const INITIAL_SYNC_TIMEOUT_MSEC := 8000
const RUNTIME_SYNC_TIMEOUT_MSEC := 35000
const GAP_TIMEOUT_MSEC := 2000
const TERMINAL_TIMEOUT_MSEC := 5000

var runtime: WorldRuntime = null
var level: WorldLevel = null
var queued_actions: Array[WorldActionRecord] = []
var processed_request_keys: Dictionary[String, bool] = {}
var processed_request_order_by_steam_id: Dictionary[int, Array] = {}
var intent_tokens_by_steam_id: Dictionary[int, float] = {}
var intent_refill_msec_by_steam_id: Dictionary[int, int] = {}
var completed_remote_sequences: Dictionary[int, bool] = {}
var cancelled_remote_sequences: Dictionary[int, String] = {}
var remote_action_buffer: Dictionary[int, WorldActionRecord] = {}
var remote_payload_buffer: Dictionary[int, Dictionary] = {}
var remote_auxiliary_profiles: Dictionary[int, Dictionary] = {}
var current_action: WorldActionRecord = null
var next_sequence_id: int = 1
var next_remote_sequence_id: int = 1
var presenting_sequence_id: int = 0
var next_local_request_id: int = 1
var is_processing_authority: bool = false
var is_processing_remote: bool = false
var has_pending_remote_process_request: bool = false
var is_remote_snapshot_ready: bool = true
var pending_snapshot_peer_ids: Dictionary[int, Dictionary] = {}
var current_subsequence_id: int = 0
var active_sync_id: String = ""
var sync_deadline_msec: int = 0
var next_snapshot_request_msec: int = 0
var gap_started_msec: int = 0
var terminal_deadline_msec: int = 0
var is_initial_sync: bool = false
var has_sync_failed: bool = false
var last_sync_failure_reason: String = ""
var diagnostics: WorldActionStreamDiagnostics = WorldActionStreamDiagnostics.new()


func _ready() -> void:
	_connect_network_signals()
	if not GameSession.session_cleared.is_connected(_on_session_cleared):
		GameSession.session_cleared.connect(_on_session_cleared)


func _exit_tree() -> void:
	_disconnect_network_signals()
	if GameSession.session_cleared.is_connected(_on_session_cleared):
		GameSession.session_cleared.disconnect(_on_session_cleared)


func configure_context(new_runtime: WorldRuntime, new_level: WorldLevel) -> void:
	runtime = new_runtime
	level = new_level
	is_remote_snapshot_ready = not GameSession.is_multiplayer() or GameSession.is_host()


func _process(_delta: float) -> void:
	if _is_authority() or is_remote_snapshot_ready or has_sync_failed:
		return
	if active_sync_id.is_empty():
		return
	var now_msec: int = Time.get_ticks_msec()
	if now_msec >= sync_deadline_msec:
		_fail_sync("state_sync_timeout")
		return
	if now_msec >= next_snapshot_request_msec:
		NetworkManager.actions.request_stream_snapshot(
			GameSession.get_match_id(),
			active_sync_id,
			next_remote_sequence_id
		)
		next_snapshot_request_msec = now_msec + SNAPSHOT_RETRY_MSEC


func synchronize_initial_state() -> String:
	if _is_authority():
		is_remote_snapshot_ready = true
		return ""
	_begin_sync(true, "initial")
	while is_inside_tree() and not is_remote_snapshot_ready and not has_sync_failed:
		await get_tree().process_frame
	if is_remote_snapshot_ready:
		return ""
	return last_sync_failure_reason if not last_sync_failure_reason.is_empty() else "state_sync_timeout"


func request_runtime_resync(reason_code: String) -> void:
	if _is_authority() or not is_remote_snapshot_ready or has_sync_failed:
		return
	_begin_sync(false, reason_code)


func is_synchronizing() -> bool:
	return not is_remote_snapshot_ready


func get_diagnostic_counters() -> Dictionary:
	return diagnostics.create_snapshot(
		remote_action_buffer.size(),
		remote_payload_buffer.size(),
		remote_auxiliary_profiles.size()
	)


func create_local_request_id() -> int:
	var request_id: int = next_local_request_id
	next_local_request_id += 1
	return request_id


func is_idle() -> bool:
	return (
		current_action == null
		and queued_actions.is_empty()
		and remote_action_buffer.is_empty()
		and remote_payload_buffer.is_empty()
		and remote_auxiliary_profiles.is_empty()
		and completed_remote_sequences.is_empty()
		and cancelled_remote_sequences.is_empty()
	)


func get_next_sequence_id() -> int:
	return next_sequence_id


func get_current_sequence_id() -> int:
	return 0 if current_action == null else current_action.sequence_id


func get_expected_remote_sequence_id() -> int:
	return next_remote_sequence_id


func claim_current_subsequence_id() -> int:
	if current_action == null:
		return 0
	current_subsequence_id += 1
	return current_subsequence_id


func request_peer_snapshot(peer_id: int) -> void:
	if not _is_authority() or peer_id <= 0:
		return
	pending_snapshot_peer_ids[peer_id] = {
		"match_id": GameSession.get_match_id(),
		"sync_id": "%s-sync-%d" % [GameSession.get_match_id(), Time.get_ticks_usec()],
		"expected_sequence_id": next_sequence_id,
	}
	if current_action == null:
		_send_pending_snapshots()


func cancel_peer_snapshot(peer_id: int) -> void:
	pending_snapshot_peer_ids.erase(peer_id)


func prune_disconnected_snapshot_peers() -> void:
	for peer_id: int in pending_snapshot_peer_ids.keys():
		if not NetworkManager.peers.has_steam_id_for_peer(peer_id):
			pending_snapshot_peer_ids.erase(peer_id)


func receive_profile_payload(sequence_id: int, payload: Dictionary) -> void:
	if _is_authority() or sequence_id <= 0:
		return
	if sequence_id == presenting_sequence_id:
		return
	if _is_stale_remote_sequence(sequence_id):
		_increment_diagnostic("stale_packets")
		return
	if not _can_buffer_sequence(sequence_id) or remote_payload_buffer.size() >= NetworkProtocol.MAX_BUFFERED_SEQUENCES:
		_increment_diagnostic("buffer_rejections")
		request_runtime_resync(REJECTION_SEQUENCE_GAP)
		return
	remote_payload_buffer[sequence_id] = payload.duplicate(true)
	if _should_watch_remote_gap(sequence_id):
		_start_gap_watchdog()
	_process_remote_queue()


func receive_auxiliary_profile(sequence_id: int, profile_kind: String) -> void:
	if _is_authority() or sequence_id <= 0 or not NetworkProtocol.is_valid_identifier(profile_kind):
		return
	if sequence_id == presenting_sequence_id:
		return
	if _is_stale_remote_sequence(sequence_id):
		_increment_diagnostic("stale_packets")
		return
	if (
		not _can_buffer_sequence(sequence_id)
		or remote_auxiliary_profiles.size() >= NetworkProtocol.MAX_BUFFERED_SEQUENCES
		or _get_buffered_auxiliary_profile_count() >= NetworkProtocol.MAX_BUFFERED_MESSAGES
	):
		_increment_diagnostic("buffer_rejections")
		request_runtime_resync(REJECTION_SEQUENCE_GAP)
		return
	var profiles: Dictionary = remote_auxiliary_profiles.get(sequence_id, {}) as Dictionary
	if profiles.size() >= NetworkProtocol.MAX_MESSAGES_PER_SEQUENCE and not profiles.has(profile_kind):
		_increment_diagnostic("buffer_rejections")
		request_runtime_resync(REJECTION_SEQUENCE_GAP)
		return
	profiles[profile_kind] = true
	remote_auxiliary_profiles[sequence_id] = profiles
	if _should_watch_remote_gap(sequence_id):
		_start_gap_watchdog()
	_process_remote_queue()


func cancel_actions_for_steam_id(steam_id: int) -> void:
	if not _is_authority() or steam_id <= 0:
		return
	var retained_actions: Array[WorldActionRecord] = []
	for action: WorldActionRecord in queued_actions:
		if action.request_id > 0 and action.requester_steam_id == steam_id:
			runtime.release_action_reservation(action)
			_broadcast_cancelled(action, REJECTION_ACTOR_DISCONNECTED)
			action_cancelled.emit(action, REJECTION_ACTOR_DISCONNECTED)
		else:
			retained_actions.append(action)
	queued_actions = retained_actions
	stream_idle_changed.emit(is_idle())


func enqueue_external_action(action: WorldActionRecord, requester_peer_id: int) -> bool:
	if action == null or not _is_authority():
		_reject_request(requester_peer_id, 0 if action == null else action.request_id, REJECTION_INVALID_ACTION)
		return false
	var schema_rejection: String = runtime.get_action_schema_rejection_reason(action)
	if not schema_rejection.is_empty():
		_reject_request(requester_peer_id, action.request_id, schema_rejection)
		return false
	var request_key: String = _make_request_key(action)
	if processed_request_keys.has(request_key):
		_reject_request(requester_peer_id, action.request_id, REJECTION_DUPLICATE_REQUEST)
		return false
	if not _consume_intent_token(action.requester_steam_id):
		_reject_request(requester_peer_id, action.request_id, REJECTION_RATE_LIMITED)
		return false
	var acceptance_rejection: String = runtime.get_action_acceptance_rejection_reason(action)
	if not acceptance_rejection.is_empty():
		_reject_request(requester_peer_id, action.request_id, acceptance_rejection)
		return false
	if _get_queued_external_action_count() >= MAX_QUEUED_ACTIONS:
		_reject_request(requester_peer_id, action.request_id, REJECTION_QUEUE_FULL)
		return false
	if action.action_type == WorldActionRecord.ActionType.END_PLAYER_TURN and not is_idle():
		_reject_request(requester_peer_id, action.request_id, REJECTION_ACTOR_BUSY)
		return false
	if (
		_is_external_player_action(action.action_type)
		and (
			runtime.is_world_turn_active()
			or _has_queued_action_type(WorldActionRecord.ActionType.WORLD_TURN_STARTED)
		)
	):
		_reject_request(requester_peer_id, action.request_id, "world_turn")
		return false
	if action.action_type == WorldActionRecord.ActionType.SPELL_CAST and not allows_spell_intents():
		_reject_request(requester_peer_id, action.request_id, "world_turn")
		return false

	if _has_pending_external_action_for_actor(action.actor_entity_id):
		_reject_request(requester_peer_id, action.request_id, REJECTION_ACTOR_BUSY)
		return false

	var reservation_rejection: String = runtime.reserve_action_on_accept(action)
	if not reservation_rejection.is_empty():
		_reject_request(requester_peer_id, action.request_id, reservation_rejection)
		return false
	_record_processed_request(action, request_key)
	_assign_sequence(action)
	queued_actions.append(action)
	_accept_request(requester_peer_id, action.request_id, action.sequence_id)
	stream_idle_changed.emit(false)
	_process_authority_queue()
	return true


func enqueue_internal_action(action: WorldActionRecord) -> bool:
	if (
		action == null
		or not _is_authority()
		or action.request_id != 0
		or action.requester_steam_id != 0
	):
		return false
	if _get_queued_internal_action_count() >= MAX_INTERNAL_QUEUED_ACTIONS:
		push_error("Internal action queue capacity was exceeded")
		return false
	_assign_sequence(action)
	queued_actions.append(action)
	stream_idle_changed.emit(false)
	_process_authority_queue()
	return true


func has_pending_move(actor_entity_id: String) -> bool:
	return has_pending_action(actor_entity_id, WorldActionRecord.ActionType.MOVE)


func has_pending_action(actor_entity_id: String, action_type: WorldActionRecord.ActionType) -> bool:
	if actor_entity_id.is_empty():
		return false
	if (
		current_action != null
		and current_action.actor_entity_id == actor_entity_id
		and current_action.action_type == action_type
	):
		return true
	for action: WorldActionRecord in queued_actions:
		if action.actor_entity_id == actor_entity_id and action.action_type == action_type:
			return true
	return false


func allows_spell_intents() -> bool:
	return (
		not _has_queued_action_type(WorldActionRecord.ActionType.WORLD_TURN_STARTED)
		and not _has_queued_action_type(WorldActionRecord.ActionType.BLOCKING_EVENT)
	)


func _has_queued_action_type(action_type: WorldActionRecord.ActionType) -> bool:
	if current_action != null and current_action.action_type == action_type:
		return true
	for action: WorldActionRecord in queued_actions:
		if action.action_type == action_type:
			return true
	return false


func _process_authority_queue() -> void:
	if is_processing_authority or not _is_authority():
		return

	is_processing_authority = true
	while not queued_actions.is_empty():
		current_action = queued_actions.pop_front()
		current_subsequence_id = 0
		var rejection_reason: String = runtime.get_action_acceptance_rejection_reason(current_action)
		if rejection_reason.is_empty():
			rejection_reason = runtime.get_action_rejection_reason(current_action)
		if not rejection_reason.is_empty():
			if not NetworkProtocol.is_safe_reason_code(rejection_reason):
				rejection_reason = REJECTION_INVALID_ACTION
			runtime.release_action_reservation(current_action)
			_broadcast_cancelled(current_action, rejection_reason)
			action_cancelled.emit(current_action, rejection_reason)
			current_action = null
			_send_pending_snapshots()
			continue

		_broadcast_started(current_action)
		action_started.emit(current_action)
		var was_successful: bool = await runtime.execute_authoritative_action(current_action)
		if not is_inside_tree() or not is_instance_valid(runtime) or not runtime.is_inside_tree():
			current_action = null
			break
		if was_successful:
			runtime.finalize_authoritative_action(current_action)
			_broadcast_completed(current_action.sequence_id)
			action_completed.emit(current_action)
		else:
			runtime.release_action_reservation(current_action)
			var failure_reason: String = str(current_action.payload.get("cancellation_reason", REJECTION_INVALID_ACTION))
			current_action.payload.erase("cancellation_reason")
			if not NetworkProtocol.is_safe_reason_code(failure_reason):
				failure_reason = REJECTION_INVALID_ACTION
			_broadcast_cancelled(current_action, failure_reason)
			action_cancelled.emit(current_action, failure_reason)
		current_action = null
		_send_pending_snapshots()

	is_processing_authority = false
	stream_idle_changed.emit(true)


func _process_remote_queue() -> void:
	if is_processing_remote:
		has_pending_remote_process_request = true
		return
	if _is_authority() or not is_remote_snapshot_ready or not is_inside_tree():
		return

	var scene_tree: SceneTree = get_tree()
	is_processing_remote = true
	while remote_action_buffer.has(next_remote_sequence_id):
		var action: WorldActionRecord = remote_action_buffer[next_remote_sequence_id]
		if (
			_requires_profile_payload(action.action_type)
			and not cancelled_remote_sequences.has(action.sequence_id)
			and not remote_payload_buffer.has(action.sequence_id)
		):
			_start_gap_watchdog()
			break
		if not cancelled_remote_sequences.has(action.sequence_id) and not _has_required_auxiliary_profiles(action):
			_start_gap_watchdog()
			break
		gap_started_msec = 0
		remote_action_buffer.erase(next_remote_sequence_id)
		remote_auxiliary_profiles.erase(action.sequence_id)
		if remote_payload_buffer.has(action.sequence_id):
			action.payload = remote_payload_buffer[action.sequence_id]
			remote_payload_buffer.erase(action.sequence_id)
		if cancelled_remote_sequences.has(action.sequence_id):
			var early_reason: String = cancelled_remote_sequences[action.sequence_id]
			action_cancelled.emit(action, early_reason)
			_finish_remote_sequence(action.sequence_id)
			continue

		current_action = action
		presenting_sequence_id = action.sequence_id
		action_started.emit(action)
		await runtime.play_remote_action(action)
		if not is_inside_tree():
			break
		terminal_deadline_msec = Time.get_ticks_msec() + TERMINAL_TIMEOUT_MSEC
		while not completed_remote_sequences.has(action.sequence_id) and not cancelled_remote_sequences.has(action.sequence_id):
			await scene_tree.process_frame
			if not is_inside_tree() or not is_remote_snapshot_ready or current_action != action:
				break
			if Time.get_ticks_msec() >= terminal_deadline_msec:
				_increment_diagnostic("watchdog_activations")
				request_runtime_resync(REJECTION_SEQUENCE_GAP)
				break
		terminal_deadline_msec = 0
		if not is_inside_tree() or not is_remote_snapshot_ready or current_action != action:
			if current_action == action:
				current_action = null
			if presenting_sequence_id == action.sequence_id:
				presenting_sequence_id = 0
			break

		if completed_remote_sequences.has(action.sequence_id):
			action_completed.emit(action)
		else:
			var reason_code: String = cancelled_remote_sequences[action.sequence_id]
			action_cancelled.emit(action, reason_code)
		_finish_remote_sequence(action.sequence_id)

	is_processing_remote = false
	var should_process_again: bool = has_pending_remote_process_request
	has_pending_remote_process_request = false
	stream_idle_changed.emit(
		remote_action_buffer.is_empty()
		and remote_payload_buffer.is_empty()
		and remote_auxiliary_profiles.is_empty()
		and completed_remote_sequences.is_empty()
		and cancelled_remote_sequences.is_empty()
	)
	if is_remote_snapshot_ready and should_process_again:
		call_deferred("_process_remote_queue")
	if is_remote_snapshot_ready and _has_future_remote_sequence():
		_start_gap_watchdog()


func _assign_sequence(action: WorldActionRecord) -> void:
	action.sequence_id = next_sequence_id
	next_sequence_id += 1


func _make_request_key(action: WorldActionRecord) -> String:
	return "%s:%d:%d" % [action.match_id, action.requester_steam_id, action.request_id]


func _has_pending_external_action_for_actor(actor_entity_id: String) -> bool:
	if actor_entity_id.is_empty():
		return false
	if current_action != null and current_action.request_id > 0 and current_action.actor_entity_id == actor_entity_id:
		return true
	for queued_action: WorldActionRecord in queued_actions:
		if queued_action.request_id > 0 and queued_action.actor_entity_id == actor_entity_id:
			return true
	return false


func _get_queued_external_action_count() -> int:
	var action_count: int = 0
	for action: WorldActionRecord in queued_actions:
		if action.request_id > 0:
			action_count += 1
	return action_count


func _get_queued_internal_action_count() -> int:
	var action_count: int = 0
	for action: WorldActionRecord in queued_actions:
		if action.request_id == 0:
			action_count += 1
	return action_count


func _consume_intent_token(steam_id: int) -> bool:
	var now_msec: int = Time.get_ticks_msec()
	var previous_msec: int = int(intent_refill_msec_by_steam_id.get(steam_id, now_msec))
	var elapsed_seconds: float = float(maxi(now_msec - previous_msec, 0)) / 1000.0
	var available_tokens: float = float(intent_tokens_by_steam_id.get(steam_id, INTENT_RATE_BURST))
	available_tokens = minf(INTENT_RATE_BURST, available_tokens + elapsed_seconds * INTENT_RATE_PER_SECOND)
	intent_refill_msec_by_steam_id[steam_id] = now_msec
	if available_tokens < 1.0:
		intent_tokens_by_steam_id[steam_id] = available_tokens
		return false
	intent_tokens_by_steam_id[steam_id] = available_tokens - 1.0
	return true


func _record_processed_request(action: WorldActionRecord, request_key: String) -> void:
	processed_request_keys[request_key] = true
	var request_order: Array = processed_request_order_by_steam_id.get(action.requester_steam_id, []) as Array
	request_order.append(request_key)
	while request_order.size() > MAX_PROCESSED_REQUESTS_PER_PLAYER:
		var expired_key: String = str(request_order.pop_front())
		processed_request_keys.erase(expired_key)
	processed_request_order_by_steam_id[action.requester_steam_id] = request_order


func _on_session_cleared() -> void:
	processed_request_keys.clear()
	processed_request_order_by_steam_id.clear()
	intent_tokens_by_steam_id.clear()
	intent_refill_msec_by_steam_id.clear()
	_clear_remote_state()
	pending_snapshot_peer_ids.clear()
	diagnostics.reset()


func _accept_request(peer_id: int, request_id: int, sequence_id: int) -> void:
	if GameSession.is_multiplayer() and GameSession.is_host() and peer_id > 0:
		NetworkManager.actions.send_action_accepted(peer_id, request_id, sequence_id)


func _reject_request(peer_id: int, request_id: int, reason_code: String) -> void:
	var safe_reason_code: String = reason_code
	if not NetworkProtocol.is_safe_reason_code(safe_reason_code):
		safe_reason_code = REJECTION_INVALID_ACTION
	if GameSession.is_multiplayer() and GameSession.is_host() and peer_id > 0:
		NetworkManager.actions.send_action_rejected(peer_id, request_id, safe_reason_code)
		return
	if peer_id == 0:
		runtime.notify_local_action_rejected(safe_reason_code)


func _broadcast_started(action: WorldActionRecord) -> void:
	if GameSession.is_multiplayer() and GameSession.is_host():
		runtime.broadcast_action_profile_payload(action)
		NetworkManager.actions.broadcast_action_started(action.to_lifecycle_dictionary())


func _broadcast_completed(sequence_id: int) -> void:
	if GameSession.is_multiplayer() and GameSession.is_host():
		NetworkManager.actions.broadcast_action_completed(GameSession.get_match_id(), sequence_id)


func _broadcast_cancelled(action: WorldActionRecord, reason_code: String) -> void:
	var safe_reason_code: String = reason_code
	if not NetworkProtocol.is_safe_reason_code(safe_reason_code):
		safe_reason_code = REJECTION_INVALID_ACTION
	if GameSession.is_multiplayer() and GameSession.is_host():
		NetworkManager.actions.broadcast_action_cancelled(action.to_lifecycle_dictionary(), safe_reason_code)


func _send_pending_snapshots() -> void:
	if pending_snapshot_peer_ids.is_empty() or current_action != null:
		return
	var boundary_sequence_id: int = next_sequence_id
	if not queued_actions.is_empty():
		boundary_sequence_id = queued_actions[0].sequence_id
	var base_snapshot: Dictionary = runtime.create_action_stream_snapshot(boundary_sequence_id)
	for peer_id: int in pending_snapshot_peer_ids.keys():
		var request: Dictionary = pending_snapshot_peer_ids[peer_id]
		var snapshot: Dictionary = base_snapshot.duplicate(true)
		snapshot["protocol_version"] = NetworkProtocol.PROTOCOL_VERSION
		snapshot["snapshot_schema_version"] = NetworkProtocol.SNAPSHOT_SCHEMA_VERSION
		snapshot["match_id"] = str(request.get("match_id", ""))
		snapshot["sync_id"] = str(request.get("sync_id", ""))
		snapshot["boundary_sequence_id"] = boundary_sequence_id
		snapshot["roster_hash"] = GameSession.get_roster_hash()
		NetworkManager.actions.send_stream_snapshot(
			peer_id,
			str(request.get("match_id", "")),
			str(request.get("sync_id", "")),
			snapshot
		)
	pending_snapshot_peer_ids.clear()


func _on_action_started(record: Dictionary) -> void:
	if _is_authority():
		return
	var action: WorldActionRecord = WorldActionRecord.from_dictionary(record)
	if action == null or action.match_id != GameSession.get_match_id():
		return
	if action.sequence_id == presenting_sequence_id:
		return
	if _is_stale_remote_sequence(action.sequence_id):
		_increment_diagnostic("stale_packets")
		return
	if not _can_buffer_sequence(action.sequence_id) or remote_action_buffer.size() >= NetworkProtocol.MAX_BUFFERED_SEQUENCES:
		_increment_diagnostic("buffer_rejections")
		request_runtime_resync(REJECTION_SEQUENCE_GAP)
		return
	remote_action_buffer[action.sequence_id] = action
	stream_idle_changed.emit(false)
	_process_remote_queue()


func _on_action_completed(record: Dictionary) -> void:
	if _is_authority():
		return
	var sequence_id: int = int(record.get("sequence_id", 0))
	if sequence_id <= 0:
		return
	if _is_stale_remote_sequence(sequence_id):
		_increment_diagnostic("stale_packets")
		return
	if not _can_buffer_sequence(sequence_id):
		request_runtime_resync(REJECTION_SEQUENCE_GAP)
		return
	completed_remote_sequences[sequence_id] = true
	if _should_watch_remote_gap(sequence_id):
		_start_gap_watchdog()
	_process_remote_queue()


func _on_action_cancelled(record: Dictionary, reason_code: String) -> void:
	if _is_authority():
		return
	var action: WorldActionRecord = WorldActionRecord.from_dictionary(record)
	if action == null or action.match_id != GameSession.get_match_id():
		return
	if _is_stale_remote_sequence(action.sequence_id):
		_increment_diagnostic("stale_packets")
		return
	if not _can_buffer_sequence(action.sequence_id):
		request_runtime_resync(REJECTION_SEQUENCE_GAP)
		return
	cancelled_remote_sequences[action.sequence_id] = reason_code
	if action.sequence_id != presenting_sequence_id and not remote_action_buffer.has(action.sequence_id):
		remote_action_buffer[action.sequence_id] = action
	if _should_watch_remote_gap(action.sequence_id):
		_start_gap_watchdog()
	_process_remote_queue()


func _on_stream_snapshot_received(sync_id: String, snapshot: Dictionary) -> void:
	if _is_authority():
		return
	if sync_id != active_sync_id or not _is_valid_snapshot(snapshot, sync_id):
		return
	var snapshot_next_sequence_id: int = int(snapshot.get("boundary_sequence_id", 0))
	if not runtime.apply_action_stream_snapshot(snapshot):
		_fail_sync("state_sync_invalid")
		return
	next_remote_sequence_id = snapshot_next_sequence_id
	for sequence_id: int in remote_action_buffer.keys():
		if sequence_id < next_remote_sequence_id:
			remote_action_buffer.erase(sequence_id)
	for sequence_id: int in remote_payload_buffer.keys():
		if sequence_id < next_remote_sequence_id:
			remote_payload_buffer.erase(sequence_id)
	for sequence_id: int in remote_auxiliary_profiles.keys():
		if sequence_id < next_remote_sequence_id:
			remote_auxiliary_profiles.erase(sequence_id)
	for sequence_id: int in completed_remote_sequences.keys():
		if sequence_id < next_remote_sequence_id:
			completed_remote_sequences.erase(sequence_id)
	for sequence_id: int in cancelled_remote_sequences.keys():
		if sequence_id < next_remote_sequence_id:
			cancelled_remote_sequences.erase(sequence_id)
	current_action = null
	presenting_sequence_id = 0
	active_sync_id = ""
	has_sync_failed = false
	last_sync_failure_reason = ""
	is_remote_snapshot_ready = true
	is_initial_sync = false
	gap_started_msec = 0
	terminal_deadline_msec = 0
	_increment_diagnostic("resync_successes")
	remote_snapshot_committed.emit(next_remote_sequence_id)
	sync_state_changed.emit(false)
	_process_remote_queue()


func _on_stream_snapshot_pending(sync_id: String, _active_sequence_id: int) -> void:
	if sync_id == active_sync_id:
		next_snapshot_request_msec = Time.get_ticks_msec() + SNAPSHOT_RETRY_MSEC


func _on_stream_snapshot_invalid(sync_id: String) -> void:
	if sync_id == active_sync_id:
		_fail_sync("state_sync_invalid")


func _on_stream_snapshot_requested(
	requester_peer_id: int,
	match_id: String,
	sync_id: String,
	expected_sequence_id: int
) -> void:
	if not _is_authority() or match_id != GameSession.get_match_id():
		return
	pending_snapshot_peer_ids[requester_peer_id] = {
		"match_id": match_id,
		"sync_id": sync_id,
		"expected_sequence_id": expected_sequence_id,
	}
	if current_action == null:
		_send_pending_snapshots()
	else:
		NetworkManager.actions.send_stream_snapshot_pending(
			requester_peer_id,
			match_id,
			sync_id,
			current_action.sequence_id
		)


func _requires_profile_payload(action_type: WorldActionRecord.ActionType) -> bool:
	return action_type in [
		WorldActionRecord.ActionType.MOVE,
		WorldActionRecord.ActionType.ATTACK,
		WorldActionRecord.ActionType.INTERACTION,
		WorldActionRecord.ActionType.SPELL_CAST,
		WorldActionRecord.ActionType.INVENTORY_ADD,
		WorldActionRecord.ActionType.INVENTORY_MOVE,
		WorldActionRecord.ActionType.INVENTORY_DELETE,
		WorldActionRecord.ActionType.INVENTORY_USE,
	]


func _has_required_auxiliary_profiles(action: WorldActionRecord) -> bool:
	var requires_turn_profile: bool = action.action_type in [
		WorldActionRecord.ActionType.END_PLAYER_TURN,
		WorldActionRecord.ActionType.PLAYER_TURN_STARTED,
		WorldActionRecord.ActionType.PLAYER_TURN_SKIPPED,
		WorldActionRecord.ActionType.WORLD_TURN_STARTED,
		WorldActionRecord.ActionType.WORLD_TURN_ENDED,
		WorldActionRecord.ActionType.SET_TURN_MODE,
	]
	if runtime.is_turn_mode_enabled() and action.action_type in [
		WorldActionRecord.ActionType.MOVE,
		WorldActionRecord.ActionType.ATTACK,
		WorldActionRecord.ActionType.INTERACTION,
	]:
		requires_turn_profile = true
	if not requires_turn_profile:
		return true
	var profiles: Dictionary = remote_auxiliary_profiles.get(action.sequence_id, {}) as Dictionary
	return bool(profiles.get("turn_snapshot", false))


func _get_buffered_auxiliary_profile_count() -> int:
	var message_count: int = 0
	for profiles_value: Variant in remote_auxiliary_profiles.values():
		if profiles_value is Dictionary:
			message_count += (profiles_value as Dictionary).size()
	return message_count


func _begin_sync(should_be_initial: bool, _reason_code: String) -> void:
	is_initial_sync = should_be_initial
	is_remote_snapshot_ready = false
	has_sync_failed = false
	last_sync_failure_reason = ""
	active_sync_id = "sync-%d-%d" % [GameSession.local_steam_id, Time.get_ticks_usec()]
	var timeout_msec: int = INITIAL_SYNC_TIMEOUT_MSEC if should_be_initial else RUNTIME_SYNC_TIMEOUT_MSEC
	sync_deadline_msec = Time.get_ticks_msec() + timeout_msec
	next_snapshot_request_msec = 0
	gap_started_msec = 0
	terminal_deadline_msec = 0
	_increment_diagnostic("resync_attempts")
	sync_state_changed.emit(true)


func _fail_sync(reason_code: String) -> void:
	if has_sync_failed:
		return
	has_sync_failed = true
	last_sync_failure_reason = reason_code
	active_sync_id = ""
	_increment_diagnostic("resync_failures")
	sync_state_changed.emit(false)
	if not is_initial_sync:
		runtime_sync_failed.emit(reason_code)


func _is_valid_snapshot(snapshot: Dictionary, sync_id: String) -> bool:
	return (
		int(snapshot.get("protocol_version", 0)) == NetworkProtocol.PROTOCOL_VERSION
		and int(snapshot.get("snapshot_schema_version", 0)) == NetworkProtocol.SNAPSHOT_SCHEMA_VERSION
		and str(snapshot.get("match_id", "")) == GameSession.get_match_id()
		and str(snapshot.get("sync_id", "")) == sync_id
		and str(snapshot.get("roster_hash", "")) == GameSession.get_roster_hash()
		and int(snapshot.get("boundary_sequence_id", 0)) > 0
		and NetworkProtocol.get_payload_size(snapshot) <= NetworkProtocol.MAX_SNAPSHOT_BYTES
	)


func _can_buffer_sequence(sequence_id: int) -> bool:
	if sequence_id == presenting_sequence_id:
		return true
	return (
		sequence_id >= next_remote_sequence_id
		and sequence_id - next_remote_sequence_id <= NetworkProtocol.MAX_FUTURE_SEQUENCE_DISTANCE
	)


func _is_stale_remote_sequence(sequence_id: int) -> bool:
	return sequence_id < next_remote_sequence_id and sequence_id != presenting_sequence_id


func _should_watch_remote_gap(sequence_id: int) -> bool:
	if presenting_sequence_id != 0:
		return false
	return (
		sequence_id > next_remote_sequence_id
		or (
			sequence_id == next_remote_sequence_id
			and not remote_action_buffer.has(next_remote_sequence_id)
		)
	)


func _finish_remote_sequence(sequence_id: int) -> void:
	completed_remote_sequences.erase(sequence_id)
	cancelled_remote_sequences.erase(sequence_id)
	remote_action_buffer.erase(sequence_id)
	remote_payload_buffer.erase(sequence_id)
	remote_auxiliary_profiles.erase(sequence_id)
	if current_action != null and current_action.sequence_id == sequence_id:
		current_action = null
	if presenting_sequence_id == sequence_id:
		presenting_sequence_id = 0
	if next_remote_sequence_id == sequence_id:
		next_remote_sequence_id += 1


func _has_future_remote_sequence() -> bool:
	for sequence_id: int in remote_action_buffer.keys():
		if sequence_id > next_remote_sequence_id:
			return true
	for sequence_id: int in remote_payload_buffer.keys():
		if sequence_id > next_remote_sequence_id:
			return true
	for sequence_id: int in remote_auxiliary_profiles.keys():
		if sequence_id > next_remote_sequence_id:
			return true
	for sequence_id: int in completed_remote_sequences.keys():
		if sequence_id > next_remote_sequence_id:
			return true
	for sequence_id: int in cancelled_remote_sequences.keys():
		if sequence_id > next_remote_sequence_id:
			return true
	return false


func _start_gap_watchdog() -> void:
	if presenting_sequence_id != 0:
		return
	if gap_started_msec == 0:
		gap_started_msec = Time.get_ticks_msec()
		call_deferred("_watch_remote_gap")


func _watch_remote_gap() -> void:
	if not is_inside_tree() or gap_started_msec == 0 or not is_remote_snapshot_ready:
		return
	while (
		is_inside_tree()
		and gap_started_msec > 0
		and is_remote_snapshot_ready
		and presenting_sequence_id == 0
		and Time.get_ticks_msec() - gap_started_msec < GAP_TIMEOUT_MSEC
	):
		await get_tree().process_frame
	if (
		is_inside_tree()
		and gap_started_msec > 0
		and is_remote_snapshot_ready
		and presenting_sequence_id == 0
	):
		_increment_diagnostic("watchdog_activations")
		request_runtime_resync(REJECTION_SEQUENCE_GAP)


func _clear_remote_state() -> void:
	completed_remote_sequences.clear()
	cancelled_remote_sequences.clear()
	remote_action_buffer.clear()
	remote_payload_buffer.clear()
	remote_auxiliary_profiles.clear()
	current_action = null
	presenting_sequence_id = 0
	is_processing_remote = false
	has_pending_remote_process_request = false
	active_sync_id = ""
	sync_deadline_msec = 0
	next_snapshot_request_msec = 0
	gap_started_msec = 0
	terminal_deadline_msec = 0
	has_sync_failed = false
	last_sync_failure_reason = ""
	is_initial_sync = false


func _increment_diagnostic(counter_name: String) -> void:
	diagnostics.increment(counter_name)


func _is_external_player_action(action_type: WorldActionRecord.ActionType) -> bool:
	return action_type in [
		WorldActionRecord.ActionType.MOVE,
		WorldActionRecord.ActionType.ATTACK,
		WorldActionRecord.ActionType.INTERACTION,
		WorldActionRecord.ActionType.SPELL_CAST,
		WorldActionRecord.ActionType.INVENTORY_ADD,
		WorldActionRecord.ActionType.INVENTORY_MOVE,
		WorldActionRecord.ActionType.INVENTORY_DELETE,
		WorldActionRecord.ActionType.INVENTORY_USE,
		WorldActionRecord.ActionType.CHARACTER_KILL,
		WorldActionRecord.ActionType.END_PLAYER_TURN,
	]


func _connect_network_signals() -> void:
	if not NetworkManager.actions.action_started.is_connected(_on_action_started):
		NetworkManager.actions.action_started.connect(_on_action_started)
	if not NetworkManager.actions.action_completed.is_connected(_on_action_completed):
		NetworkManager.actions.action_completed.connect(_on_action_completed)
	if not NetworkManager.actions.action_cancelled.is_connected(_on_action_cancelled):
		NetworkManager.actions.action_cancelled.connect(_on_action_cancelled)
	if not NetworkManager.actions.stream_snapshot_received.is_connected(_on_stream_snapshot_received):
		NetworkManager.actions.stream_snapshot_received.connect(_on_stream_snapshot_received)
	if not NetworkManager.actions.stream_snapshot_pending.is_connected(_on_stream_snapshot_pending):
		NetworkManager.actions.stream_snapshot_pending.connect(_on_stream_snapshot_pending)
	if not NetworkManager.actions.stream_snapshot_invalid.is_connected(_on_stream_snapshot_invalid):
		NetworkManager.actions.stream_snapshot_invalid.connect(_on_stream_snapshot_invalid)
	if not NetworkManager.actions.stream_snapshot_requested.is_connected(_on_stream_snapshot_requested):
		NetworkManager.actions.stream_snapshot_requested.connect(_on_stream_snapshot_requested)


func _disconnect_network_signals() -> void:
	if NetworkManager.actions.action_started.is_connected(_on_action_started):
		NetworkManager.actions.action_started.disconnect(_on_action_started)
	if NetworkManager.actions.action_completed.is_connected(_on_action_completed):
		NetworkManager.actions.action_completed.disconnect(_on_action_completed)
	if NetworkManager.actions.action_cancelled.is_connected(_on_action_cancelled):
		NetworkManager.actions.action_cancelled.disconnect(_on_action_cancelled)
	if NetworkManager.actions.stream_snapshot_received.is_connected(_on_stream_snapshot_received):
		NetworkManager.actions.stream_snapshot_received.disconnect(_on_stream_snapshot_received)
	if NetworkManager.actions.stream_snapshot_pending.is_connected(_on_stream_snapshot_pending):
		NetworkManager.actions.stream_snapshot_pending.disconnect(_on_stream_snapshot_pending)
	if NetworkManager.actions.stream_snapshot_invalid.is_connected(_on_stream_snapshot_invalid):
		NetworkManager.actions.stream_snapshot_invalid.disconnect(_on_stream_snapshot_invalid)
	if NetworkManager.actions.stream_snapshot_requested.is_connected(_on_stream_snapshot_requested):
		NetworkManager.actions.stream_snapshot_requested.disconnect(_on_stream_snapshot_requested)


func _is_authority() -> bool:
	return not GameSession.is_multiplayer() or GameSession.is_host()
