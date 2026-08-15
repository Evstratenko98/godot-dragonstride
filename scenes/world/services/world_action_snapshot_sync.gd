class_name WorldActionSnapshotSync
extends RefCounted

signal snapshot_ready(snapshot: Dictionary)
signal synchronization_changed(is_synchronizing: bool)
signal runtime_failed(reason_code: String)
signal diagnostic_increment_requested(counter_name: String)

const SNAPSHOT_RETRY_MSEC: int = 500
const INITIAL_SYNC_TIMEOUT_MSEC: int = 8_000
const RUNTIME_SYNC_TIMEOUT_MSEC: int = 35_000

var runtime: WorldRuntime = null
var expected_sequence_provider: Callable = Callable()
var is_remote_snapshot_ready: bool = true
var active_sync_id: String = ""
var sync_deadline_msec: int = 0
var next_snapshot_request_msec: int = 0
var is_initial_sync: bool = false
var has_sync_failed: bool = false
var last_sync_failure_reason: String = ""


func configure_context(
	new_runtime: WorldRuntime,
	new_expected_sequence_provider: Callable
) -> void:
	disconnect_network_signals()
	runtime = new_runtime
	expected_sequence_provider = new_expected_sequence_provider
	reset(not GameSession.is_multiplayer() or GameSession.is_host())
	connect_network_signals()


func process() -> void:
	if _is_authority() or is_remote_snapshot_ready or has_sync_failed or active_sync_id.is_empty():
		return
	var now_msec: int = Time.get_ticks_msec()
	if now_msec >= sync_deadline_msec:
		fail("state_sync_timeout")
		return
	if now_msec < next_snapshot_request_msec:
		return
	var expected_sequence_id: int = 1
	if expected_sequence_provider.is_valid():
		expected_sequence_id = maxi(int(expected_sequence_provider.call()), 1)
	NetworkManager.actions.request_stream_snapshot(
		GameSession.get_match_id(),
		active_sync_id,
		expected_sequence_id
	)
	next_snapshot_request_msec = now_msec + SNAPSHOT_RETRY_MSEC


func synchronize_initial_state(owner: Node) -> String:
	if _is_authority():
		is_remote_snapshot_ready = true
		return ""
	_begin_sync(true)
	while owner != null and owner.is_inside_tree() and not is_remote_snapshot_ready and not has_sync_failed:
		await owner.get_tree().process_frame
	if is_remote_snapshot_ready:
		return ""
	return last_sync_failure_reason if not last_sync_failure_reason.is_empty() else "state_sync_timeout"


func request_runtime_resync() -> bool:
	if _is_authority() or not is_remote_snapshot_ready or has_sync_failed:
		return false
	_begin_sync(false)
	return true


func is_synchronizing() -> bool:
	return not is_remote_snapshot_ready


func is_ready() -> bool:
	return is_remote_snapshot_ready


func complete() -> void:
	active_sync_id = ""
	has_sync_failed = false
	last_sync_failure_reason = ""
	is_remote_snapshot_ready = true
	is_initial_sync = false
	sync_deadline_msec = 0
	next_snapshot_request_msec = 0
	diagnostic_increment_requested.emit("resync_successes")
	synchronization_changed.emit(false)


func fail(reason_code: String) -> void:
	if has_sync_failed:
		return
	has_sync_failed = true
	last_sync_failure_reason = reason_code
	active_sync_id = ""
	sync_deadline_msec = 0
	next_snapshot_request_msec = 0
	diagnostic_increment_requested.emit("resync_failures")
	synchronization_changed.emit(false)
	if not is_initial_sync:
		runtime_failed.emit(reason_code)


func reset(should_be_ready: bool) -> void:
	is_remote_snapshot_ready = should_be_ready
	active_sync_id = ""
	sync_deadline_msec = 0
	next_snapshot_request_msec = 0
	is_initial_sync = false
	has_sync_failed = false
	last_sync_failure_reason = ""


func connect_network_signals() -> void:
	if not NetworkManager.actions.stream_snapshot_received.is_connected(_on_stream_snapshot_received):
		NetworkManager.actions.stream_snapshot_received.connect(_on_stream_snapshot_received)
	if not NetworkManager.actions.stream_snapshot_pending.is_connected(_on_stream_snapshot_pending):
		NetworkManager.actions.stream_snapshot_pending.connect(_on_stream_snapshot_pending)
	if not NetworkManager.actions.stream_snapshot_invalid.is_connected(_on_stream_snapshot_invalid):
		NetworkManager.actions.stream_snapshot_invalid.connect(_on_stream_snapshot_invalid)
	if not NetworkManager.actions.stream_snapshot_rejected.is_connected(_on_stream_snapshot_rejected):
		NetworkManager.actions.stream_snapshot_rejected.connect(_on_stream_snapshot_rejected)


func disconnect_network_signals() -> void:
	if NetworkManager.actions.stream_snapshot_received.is_connected(_on_stream_snapshot_received):
		NetworkManager.actions.stream_snapshot_received.disconnect(_on_stream_snapshot_received)
	if NetworkManager.actions.stream_snapshot_pending.is_connected(_on_stream_snapshot_pending):
		NetworkManager.actions.stream_snapshot_pending.disconnect(_on_stream_snapshot_pending)
	if NetworkManager.actions.stream_snapshot_invalid.is_connected(_on_stream_snapshot_invalid):
		NetworkManager.actions.stream_snapshot_invalid.disconnect(_on_stream_snapshot_invalid)
	if NetworkManager.actions.stream_snapshot_rejected.is_connected(_on_stream_snapshot_rejected):
		NetworkManager.actions.stream_snapshot_rejected.disconnect(_on_stream_snapshot_rejected)


func _begin_sync(should_be_initial: bool) -> void:
	is_initial_sync = should_be_initial
	is_remote_snapshot_ready = false
	has_sync_failed = false
	last_sync_failure_reason = ""
	active_sync_id = "sync-%d-%d" % [GameSession.local_steam_id, Time.get_ticks_usec()]
	var timeout_msec: int = INITIAL_SYNC_TIMEOUT_MSEC if should_be_initial else RUNTIME_SYNC_TIMEOUT_MSEC
	sync_deadline_msec = Time.get_ticks_msec() + timeout_msec
	next_snapshot_request_msec = 0
	diagnostic_increment_requested.emit("resync_attempts")
	synchronization_changed.emit(true)


func _on_stream_snapshot_received(sync_id: String, snapshot: Dictionary) -> void:
	if _is_authority() or sync_id != active_sync_id:
		return
	if not _is_valid_snapshot(snapshot, sync_id):
		fail("state_sync_invalid")
		return
	snapshot_ready.emit(snapshot)


func _on_stream_snapshot_pending(sync_id: String, _active_sequence_id: int) -> void:
	if sync_id == active_sync_id:
		next_snapshot_request_msec = Time.get_ticks_msec() + SNAPSHOT_RETRY_MSEC


func _on_stream_snapshot_invalid(sync_id: String) -> void:
	if sync_id == active_sync_id:
		fail("state_sync_invalid")


func _on_stream_snapshot_rejected(sync_id: String, reason_code: String) -> void:
	if sync_id == active_sync_id:
		fail(reason_code)


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


func _is_authority() -> bool:
	return not GameSession.is_multiplayer() or GameSession.is_host()
