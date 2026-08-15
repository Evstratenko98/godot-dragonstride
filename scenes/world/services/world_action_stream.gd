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
const GAP_TIMEOUT_MSEC := 2000
const TERMINAL_TIMEOUT_MSEC := 5000

var runtime: WorldRuntime = null
var level: WorldLevel = null
var queued_actions: Array[WorldActionRecord] = []
var queued_action_head_index: int = 0
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
var current_subsequence_id: int = 0
var gap_started_msec: int = 0
var terminal_deadline_msec: int = 0
var diagnostics: WorldActionStreamDiagnostics = WorldActionStreamDiagnostics.new()
var intent_gate: WorldActionIntentGate = WorldActionIntentGate.new()
var snapshot_responder: WorldActionSnapshotResponder = WorldActionSnapshotResponder.new()
var snapshot_sync: WorldActionSnapshotSync = WorldActionSnapshotSync.new()


func _ready() -> void:
	_connect_snapshot_sync_signals()
	_connect_network_signals()
	if not GameSession.session_cleared.is_connected(_on_session_cleared):
		GameSession.session_cleared.connect(_on_session_cleared)


func _exit_tree() -> void:
	snapshot_responder.disconnect_signals()
	snapshot_sync.disconnect_network_signals()
	_disconnect_snapshot_sync_signals()
	_disconnect_network_signals()
	if GameSession.session_cleared.is_connected(_on_session_cleared):
		GameSession.session_cleared.disconnect(_on_session_cleared)


func configure_context(new_runtime: WorldRuntime, new_level: WorldLevel) -> void:
	runtime = new_runtime
	level = new_level
	snapshot_responder.configure_context(runtime, self)
	snapshot_sync.configure_context(runtime, get_expected_remote_sequence_id)


func _process(_delta: float) -> void:
	snapshot_sync.process()


func synchronize_initial_state() -> String:
	return await snapshot_sync.synchronize_initial_state(self)


func request_runtime_resync(_reason_code: String) -> void:
	if snapshot_sync.request_runtime_resync():
		gap_started_msec = 0
		terminal_deadline_msec = 0


func is_synchronizing() -> bool:
	return snapshot_sync.is_synchronizing()


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
		and not _has_queued_authority_actions()
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


func get_snapshot_boundary_sequence_id() -> int:
	if _has_queued_authority_actions():
		return queued_actions[queued_action_head_index].sequence_id
	return next_sequence_id


func claim_current_subsequence_id() -> int:
	if current_action == null:
		return 0
	current_subsequence_id += 1
	return current_subsequence_id


func request_peer_snapshot(peer_id: int) -> void:
	snapshot_responder.request_peer_snapshot(peer_id)


func cancel_peer_snapshot(peer_id: int) -> void:
	snapshot_responder.cancel_peer_snapshot(peer_id)


func prune_disconnected_snapshot_peers() -> void:
	snapshot_responder.prune_disconnected_peers()


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
	for action_index: int in range(queued_action_head_index, queued_actions.size()):
		var action: WorldActionRecord = queued_actions[action_index]
		if action.request_id > 0 and action.requester_steam_id == steam_id:
			runtime.release_action_reservation(action)
			_broadcast_cancelled(action, REJECTION_ACTOR_DISCONNECTED)
			action_cancelled.emit(action, REJECTION_ACTOR_DISCONNECTED)
		else:
			retained_actions.append(action)
	queued_actions = retained_actions
	queued_action_head_index = 0
	stream_idle_changed.emit(is_idle())


func enqueue_external_action(action: WorldActionRecord, requester_peer_id: int) -> bool:
	if action == null or not _is_authority():
		_reject_request(requester_peer_id, 0 if action == null else action.request_id, REJECTION_INVALID_ACTION)
		return false
	var schema_rejection: String = runtime.get_action_schema_rejection_reason(action)
	if not schema_rejection.is_empty():
		_reject_request(requester_peer_id, action.request_id, schema_rejection)
		return false
	if intent_gate.has_processed(action):
		_reject_request(requester_peer_id, action.request_id, REJECTION_DUPLICATE_REQUEST)
		return false
	if not intent_gate.consume_rate_limit_token(action.requester_steam_id):
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
		WorldActionCatalog.is_external(action.action_type)
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
	intent_gate.record_processed(action)
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


func has_pending_move_path(actor_entity_id: String) -> bool:
	return has_pending_action(actor_entity_id, WorldActionRecord.ActionType.MOVE_PATH)


func has_pending_action(actor_entity_id: String, action_type: WorldActionRecord.ActionType) -> bool:
	if actor_entity_id.is_empty():
		return false
	if (
		current_action != null
		and current_action.actor_entity_id == actor_entity_id
		and current_action.action_type == action_type
	):
		return true
	for action_index: int in range(queued_action_head_index, queued_actions.size()):
		var action: WorldActionRecord = queued_actions[action_index]
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
	for action_index: int in range(queued_action_head_index, queued_actions.size()):
		var action: WorldActionRecord = queued_actions[action_index]
		if action.action_type == action_type:
			return true
	return false


func _process_authority_queue() -> void:
	if is_processing_authority or not _is_authority():
		return

	is_processing_authority = true
	while _has_queued_authority_actions():
		current_action = queued_actions[queued_action_head_index]
		queued_action_head_index += 1
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
			snapshot_responder.try_send_pending()
			continue

		_broadcast_started(current_action)
		action_started.emit(current_action)
		var was_successful: bool = await runtime.execute_authoritative_action(current_action)
		if current_action == null or not is_inside_tree() or not is_instance_valid(runtime) or not runtime.is_inside_tree():
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
		snapshot_responder.try_send_pending()

	queued_actions.clear()
	queued_action_head_index = 0
	is_processing_authority = false
	stream_idle_changed.emit(true)


func _process_remote_queue() -> void:
	if is_processing_remote:
		has_pending_remote_process_request = true
		return
	if _is_authority() or not snapshot_sync.is_ready() or not is_inside_tree():
		return

	var scene_tree: SceneTree = get_tree()
	is_processing_remote = true
	while remote_action_buffer.has(next_remote_sequence_id):
		var action: WorldActionRecord = remote_action_buffer[next_remote_sequence_id]
		if (
			WorldActionCatalog.requires_profile_payload(action.action_type)
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
			if not is_inside_tree() or not snapshot_sync.is_ready() or current_action != action:
				break
			if Time.get_ticks_msec() >= terminal_deadline_msec:
				_increment_diagnostic("watchdog_activations")
				request_runtime_resync(REJECTION_SEQUENCE_GAP)
				break
		terminal_deadline_msec = 0
		if not is_inside_tree() or not snapshot_sync.is_ready() or current_action != action:
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
	if snapshot_sync.is_ready() and should_process_again:
		call_deferred("_process_remote_queue")
	if snapshot_sync.is_ready() and _has_future_remote_sequence():
		_start_gap_watchdog()


func _assign_sequence(action: WorldActionRecord) -> void:
	action.sequence_id = next_sequence_id
	next_sequence_id += 1


func _has_pending_external_action_for_actor(actor_entity_id: String) -> bool:
	if actor_entity_id.is_empty():
		return false
	if current_action != null and current_action.request_id > 0 and current_action.actor_entity_id == actor_entity_id:
		return true
	for action_index: int in range(queued_action_head_index, queued_actions.size()):
		var queued_action: WorldActionRecord = queued_actions[action_index]
		if queued_action.request_id > 0 and queued_action.actor_entity_id == actor_entity_id:
			return true
	return false


func _get_queued_external_action_count() -> int:
	var action_count: int = 0
	for action_index: int in range(queued_action_head_index, queued_actions.size()):
		var action: WorldActionRecord = queued_actions[action_index]
		if action.request_id > 0:
			action_count += 1
	return action_count


func _get_queued_internal_action_count() -> int:
	var action_count: int = 0
	for action_index: int in range(queued_action_head_index, queued_actions.size()):
		var action: WorldActionRecord = queued_actions[action_index]
		if action.request_id == 0:
			action_count += 1
	return action_count


func _has_queued_authority_actions() -> bool:
	return queued_action_head_index < queued_actions.size()


func _on_session_cleared() -> void:
	intent_gate.clear()
	queued_actions.clear()
	queued_action_head_index = 0
	is_processing_authority = false
	_clear_remote_state()
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


func _on_snapshot_sync_ready(snapshot: Dictionary) -> void:
	var snapshot_next_sequence_id: int = int(snapshot.get("boundary_sequence_id", 0))
	if not runtime.apply_action_stream_snapshot(snapshot):
		snapshot_sync.fail("state_sync_invalid")
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
	gap_started_msec = 0
	terminal_deadline_msec = 0
	remote_snapshot_committed.emit(next_remote_sequence_id)
	snapshot_sync.complete()
	_process_remote_queue()


func _on_snapshot_sync_state_changed(is_synchronizing_state: bool) -> void:
	sync_state_changed.emit(is_synchronizing_state)


func _on_snapshot_sync_runtime_failed(reason_code: String) -> void:
	runtime_sync_failed.emit(reason_code)


func _on_snapshot_sync_diagnostic_increment_requested(counter_name: String) -> void:
	_increment_diagnostic(counter_name)


func _has_required_auxiliary_profiles(action: WorldActionRecord) -> bool:
	var requires_turn_profile: bool = WorldActionCatalog.requires_turn_profile(
		action.action_type,
		runtime.is_turn_mode_enabled()
	)
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
	if not is_inside_tree() or gap_started_msec == 0 or not snapshot_sync.is_ready():
		return
	while (
		is_inside_tree()
		and gap_started_msec > 0
		and snapshot_sync.is_ready()
		and presenting_sequence_id == 0
		and Time.get_ticks_msec() - gap_started_msec < GAP_TIMEOUT_MSEC
	):
		await get_tree().process_frame
	if (
		is_inside_tree()
		and gap_started_msec > 0
		and snapshot_sync.is_ready()
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
	gap_started_msec = 0
	terminal_deadline_msec = 0
	snapshot_sync.reset(not GameSession.is_multiplayer() or GameSession.is_host())


func _increment_diagnostic(counter_name: String) -> void:
	diagnostics.increment(counter_name)


func _connect_network_signals() -> void:
	if not NetworkManager.actions.action_started.is_connected(_on_action_started):
		NetworkManager.actions.action_started.connect(_on_action_started)
	if not NetworkManager.actions.action_completed.is_connected(_on_action_completed):
		NetworkManager.actions.action_completed.connect(_on_action_completed)
	if not NetworkManager.actions.action_cancelled.is_connected(_on_action_cancelled):
		NetworkManager.actions.action_cancelled.connect(_on_action_cancelled)


func _disconnect_network_signals() -> void:
	if NetworkManager.actions.action_started.is_connected(_on_action_started):
		NetworkManager.actions.action_started.disconnect(_on_action_started)
	if NetworkManager.actions.action_completed.is_connected(_on_action_completed):
		NetworkManager.actions.action_completed.disconnect(_on_action_completed)
	if NetworkManager.actions.action_cancelled.is_connected(_on_action_cancelled):
		NetworkManager.actions.action_cancelled.disconnect(_on_action_cancelled)


func _connect_snapshot_sync_signals() -> void:
	if not snapshot_sync.snapshot_ready.is_connected(_on_snapshot_sync_ready):
		snapshot_sync.snapshot_ready.connect(_on_snapshot_sync_ready)
	if not snapshot_sync.synchronization_changed.is_connected(_on_snapshot_sync_state_changed):
		snapshot_sync.synchronization_changed.connect(_on_snapshot_sync_state_changed)
	if not snapshot_sync.runtime_failed.is_connected(_on_snapshot_sync_runtime_failed):
		snapshot_sync.runtime_failed.connect(_on_snapshot_sync_runtime_failed)
	if not snapshot_sync.diagnostic_increment_requested.is_connected(_on_snapshot_sync_diagnostic_increment_requested):
		snapshot_sync.diagnostic_increment_requested.connect(_on_snapshot_sync_diagnostic_increment_requested)


func _disconnect_snapshot_sync_signals() -> void:
	if snapshot_sync.snapshot_ready.is_connected(_on_snapshot_sync_ready):
		snapshot_sync.snapshot_ready.disconnect(_on_snapshot_sync_ready)
	if snapshot_sync.synchronization_changed.is_connected(_on_snapshot_sync_state_changed):
		snapshot_sync.synchronization_changed.disconnect(_on_snapshot_sync_state_changed)
	if snapshot_sync.runtime_failed.is_connected(_on_snapshot_sync_runtime_failed):
		snapshot_sync.runtime_failed.disconnect(_on_snapshot_sync_runtime_failed)
	if snapshot_sync.diagnostic_increment_requested.is_connected(_on_snapshot_sync_diagnostic_increment_requested):
		snapshot_sync.diagnostic_increment_requested.disconnect(_on_snapshot_sync_diagnostic_increment_requested)


func _is_authority() -> bool:
	return not GameSession.is_multiplayer() or GameSession.is_host()
