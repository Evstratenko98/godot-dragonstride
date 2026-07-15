class_name WorldActionStream
extends Node

signal action_started(action: WorldActionRecord)
signal action_completed(action: WorldActionRecord)
signal action_cancelled(action: WorldActionRecord, reason_code: String)
signal stream_idle_changed(is_idle: bool)

const MAX_QUEUED_ACTIONS := 100
const REJECTION_QUEUE_FULL := "queue_full"
const REJECTION_DUPLICATE_REQUEST := "duplicate_request"
const REJECTION_INVALID_ACTION := "invalid_action"
const REJECTION_ACTOR_UNAVAILABLE := "actor_unavailable"
const REJECTION_PRESENTATION_TIMEOUT := "presentation_timeout"
const REJECTION_STREAM_BUSY := "stream_busy"

var runtime: WorldRuntime = null
var level: WorldLevel = null
var queued_actions: Array[WorldActionRecord] = []
var processed_request_keys: Dictionary[String, bool] = {}
var completed_remote_sequences: Dictionary[int, bool] = {}
var cancelled_remote_sequences: Dictionary[int, String] = {}
var remote_action_buffer: Dictionary[int, WorldActionRecord] = {}
var remote_payload_buffer: Dictionary[int, Dictionary] = {}
var current_action: WorldActionRecord = null
var next_sequence_id: int = 1
var next_remote_sequence_id: int = 1
var next_local_request_id: int = 1
var is_processing_authority: bool = false
var is_processing_remote: bool = false
var is_remote_snapshot_ready: bool = true
var pending_snapshot_peer_ids: Dictionary[int, bool] = {}
var current_subsequence_id: int = 0


func _ready() -> void:
	_connect_network_signals()


func _exit_tree() -> void:
	_disconnect_network_signals()


func configure_context(new_runtime: WorldRuntime, new_level: WorldLevel) -> void:
	runtime = new_runtime
	level = new_level
	is_remote_snapshot_ready = not GameSession.is_multiplayer() or GameSession.is_host()
	if not is_remote_snapshot_ready:
		call_deferred("_request_initial_snapshot")


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
	)


func get_next_sequence_id() -> int:
	return next_sequence_id


func get_current_sequence_id() -> int:
	return 0 if current_action == null else current_action.sequence_id


func claim_current_subsequence_id() -> int:
	if current_action == null:
		return 0
	current_subsequence_id += 1
	return current_subsequence_id


func request_peer_snapshot(peer_id: int) -> void:
	if not _is_authority() or peer_id <= 0:
		return
	pending_snapshot_peer_ids[peer_id] = true
	if current_action == null:
		_send_pending_snapshots()


func receive_profile_payload(sequence_id: int, payload: Dictionary) -> void:
	if _is_authority() or sequence_id <= 0:
		return
	remote_payload_buffer[sequence_id] = payload.duplicate(true)
	_process_remote_queue()


func enqueue_external_action(action: WorldActionRecord, requester_peer_id: int) -> bool:
	if action == null or not _is_authority():
		_reject_request(requester_peer_id, 0 if action == null else action.request_id, REJECTION_INVALID_ACTION)
		return false
	var schema_rejection: String = runtime.get_action_schema_rejection_reason(action)
	if not schema_rejection.is_empty():
		_reject_request(requester_peer_id, action.request_id, schema_rejection)
		return false
	if queued_actions.size() >= MAX_QUEUED_ACTIONS:
		_reject_request(requester_peer_id, action.request_id, REJECTION_QUEUE_FULL)
		return false
	if action.action_type == WorldActionRecord.ActionType.END_PLAYER_TURN and not is_idle():
		_reject_request(requester_peer_id, action.request_id, REJECTION_STREAM_BUSY)
		return false
	if action.action_type == WorldActionRecord.ActionType.MOVE and has_pending_move(action.actor_entity_id):
		_reject_request(requester_peer_id, action.request_id, "movement_pending")
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

	var request_key: String = _make_request_key(action)
	if processed_request_keys.has(request_key):
		_reject_request(requester_peer_id, action.request_id, REJECTION_DUPLICATE_REQUEST)
		return false

	processed_request_keys[request_key] = true
	var reservation_rejection: String = runtime.reserve_action_on_accept(action)
	if not reservation_rejection.is_empty():
		processed_request_keys.erase(request_key)
		_reject_request(requester_peer_id, action.request_id, reservation_rejection)
		return false
	_assign_sequence(action)
	queued_actions.append(action)
	_accept_request(requester_peer_id, action.request_id, action.sequence_id)
	stream_idle_changed.emit(false)
	_process_authority_queue()
	return true


func enqueue_internal_action(action: WorldActionRecord) -> bool:
	if action == null or not _is_authority():
		return false
	_assign_sequence(action)
	queued_actions.append(action)
	stream_idle_changed.emit(false)
	_process_authority_queue()
	return true


func has_pending_move(actor_entity_id: String) -> bool:
	if current_action != null and current_action.actor_entity_id == actor_entity_id:
		if current_action.action_type == WorldActionRecord.ActionType.MOVE:
			return true
	for action: WorldActionRecord in queued_actions:
		if action.actor_entity_id == actor_entity_id and action.action_type == WorldActionRecord.ActionType.MOVE:
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
		var rejection_reason: String = runtime.get_action_rejection_reason(current_action)
		if not rejection_reason.is_empty():
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
			_broadcast_cancelled(current_action, failure_reason)
			action_cancelled.emit(current_action, failure_reason)
		current_action = null
		_send_pending_snapshots()

	is_processing_authority = false
	stream_idle_changed.emit(true)


func _process_remote_queue() -> void:
	if is_processing_remote or _is_authority() or not is_remote_snapshot_ready or not is_inside_tree():
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
			break
		remote_action_buffer.erase(next_remote_sequence_id)
		if remote_payload_buffer.has(action.sequence_id):
			action.payload = remote_payload_buffer[action.sequence_id]
			remote_payload_buffer.erase(action.sequence_id)
		next_remote_sequence_id += 1
		if cancelled_remote_sequences.has(action.sequence_id):
			var early_reason: String = cancelled_remote_sequences[action.sequence_id]
			cancelled_remote_sequences.erase(action.sequence_id)
			action_cancelled.emit(action, early_reason)
			continue

		current_action = action
		action_started.emit(action)
		await runtime.play_remote_action(action)
		if not is_inside_tree():
			break
		while not completed_remote_sequences.has(action.sequence_id) and not cancelled_remote_sequences.has(action.sequence_id):
			await scene_tree.process_frame
			if not is_inside_tree():
				break
		if not is_inside_tree():
			break

		if completed_remote_sequences.has(action.sequence_id):
			completed_remote_sequences.erase(action.sequence_id)
			action_completed.emit(action)
		else:
			var reason_code: String = cancelled_remote_sequences[action.sequence_id]
			cancelled_remote_sequences.erase(action.sequence_id)
			action_cancelled.emit(action, reason_code)
		current_action = null

	is_processing_remote = false
	stream_idle_changed.emit(remote_action_buffer.is_empty() and remote_payload_buffer.is_empty())


func _assign_sequence(action: WorldActionRecord) -> void:
	action.sequence_id = next_sequence_id
	next_sequence_id += 1


func _make_request_key(action: WorldActionRecord) -> String:
	return "%d:%d" % [action.requester_steam_id, action.request_id]


func _accept_request(peer_id: int, request_id: int, sequence_id: int) -> void:
	if GameSession.is_multiplayer() and GameSession.is_host() and peer_id > 0:
		NetworkManager.actions.send_action_accepted(peer_id, request_id, sequence_id)


func _reject_request(peer_id: int, request_id: int, reason_code: String) -> void:
	if GameSession.is_multiplayer() and GameSession.is_host() and peer_id > 0:
		NetworkManager.actions.send_action_rejected(peer_id, request_id, reason_code)


func _broadcast_started(action: WorldActionRecord) -> void:
	if GameSession.is_multiplayer() and GameSession.is_host():
		runtime.broadcast_action_profile_payload(action)
		NetworkManager.actions.broadcast_action_started(action.to_lifecycle_dictionary())


func _broadcast_completed(sequence_id: int) -> void:
	if GameSession.is_multiplayer() and GameSession.is_host():
		NetworkManager.actions.broadcast_action_completed(sequence_id)


func _broadcast_cancelled(action: WorldActionRecord, reason_code: String) -> void:
	if GameSession.is_multiplayer() and GameSession.is_host():
		NetworkManager.actions.broadcast_action_cancelled(action.to_lifecycle_dictionary(), reason_code)


func _send_pending_snapshots() -> void:
	if pending_snapshot_peer_ids.is_empty() or current_action != null:
		return
	var boundary_sequence_id: int = next_sequence_id
	if not queued_actions.is_empty():
		boundary_sequence_id = queued_actions[0].sequence_id
	var snapshot: Dictionary = runtime.create_action_stream_snapshot(boundary_sequence_id)
	for peer_id: int in pending_snapshot_peer_ids.keys():
		NetworkManager.actions.send_stream_snapshot(peer_id, snapshot)
	pending_snapshot_peer_ids.clear()


func _on_action_started(record: Dictionary) -> void:
	if _is_authority():
		return
	var action: WorldActionRecord = WorldActionRecord.from_dictionary(record)
	if action == null:
		return
	if action.sequence_id < next_remote_sequence_id:
		return
	remote_action_buffer[action.sequence_id] = action
	stream_idle_changed.emit(false)
	_process_remote_queue()


func _on_action_completed(sequence_id: int) -> void:
	if not _is_authority() and sequence_id > 0:
		completed_remote_sequences[sequence_id] = true


func _on_action_cancelled(record: Dictionary, reason_code: String) -> void:
	if _is_authority():
		return
	var action: WorldActionRecord = WorldActionRecord.from_dictionary(record)
	if action == null:
		return
	cancelled_remote_sequences[action.sequence_id] = reason_code
	if action.sequence_id >= next_remote_sequence_id and not remote_action_buffer.has(action.sequence_id):
		remote_action_buffer[action.sequence_id] = action
	_process_remote_queue()


func _on_stream_snapshot_received(snapshot: Dictionary) -> void:
	if _is_authority():
		return
	var snapshot_next_sequence_id: int = int(snapshot.get("next_sequence_id", 0))
	if snapshot_next_sequence_id <= 0 or not runtime.apply_action_stream_snapshot(snapshot):
		return
	next_remote_sequence_id = snapshot_next_sequence_id
	for sequence_id: int in remote_action_buffer.keys():
		if sequence_id < next_remote_sequence_id:
			remote_action_buffer.erase(sequence_id)
	for sequence_id: int in remote_payload_buffer.keys():
		if sequence_id < next_remote_sequence_id:
			remote_payload_buffer.erase(sequence_id)
	for sequence_id: int in completed_remote_sequences.keys():
		if sequence_id < next_remote_sequence_id:
			completed_remote_sequences.erase(sequence_id)
	for sequence_id: int in cancelled_remote_sequences.keys():
		if sequence_id < next_remote_sequence_id:
			cancelled_remote_sequences.erase(sequence_id)
	is_remote_snapshot_ready = true
	_process_remote_queue()


func _on_stream_snapshot_requested(requester_peer_id: int) -> void:
	request_peer_snapshot(requester_peer_id)


func _request_initial_snapshot() -> void:
	if not is_inside_tree():
		return
	var scene_tree: SceneTree = get_tree()
	while (
		is_inside_tree()
		and GameSession.is_multiplayer()
		and not GameSession.is_host()
		and not is_remote_snapshot_ready
	):
		NetworkManager.actions.request_stream_snapshot()
		await scene_tree.create_timer(0.5).timeout


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
	if NetworkManager.actions.stream_snapshot_requested.is_connected(_on_stream_snapshot_requested):
		NetworkManager.actions.stream_snapshot_requested.disconnect(_on_stream_snapshot_requested)


func _is_authority() -> bool:
	return not GameSession.is_multiplayer() or GameSession.is_host()
