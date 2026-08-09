class_name WorldMapStartupCoordinator
extends Node

const MAP_REQUEST_RETRY_LIMIT: int = 1
const SANDBOX_SEED: int = 1

@export var builder_path: NodePath = ^"../MapBuilder"
@export var loading_screen_path: NodePath = ^"../LoadingScreen"

@onready var builder: WorldMapBuilder = get_node(builder_path) as WorldMapBuilder
@onready var loading_screen: WorldLoadingScreen = get_node(loading_screen_path) as WorldLoadingScreen

var host_payload: PackedByteArray = PackedByteArray()
var pending_peer_transfers: Dictionary[int, String] = {}
var active_transfer_id: String = ""
var received_payload: PackedByteArray = PackedByteArray()
var was_active_transfer_invalid: bool = false
var should_retry_active_transfer: bool = false


func _ready() -> void:
	_connect_signals()


func _exit_tree() -> void:
	_disconnect_signals()
	clear()


func prepare_level(level: WorldLevel, deadline_msec: int) -> String:
	if level == null or builder == null or loading_screen == null:
		return "map_build_failed"
	await get_tree().process_frame
	var payload: PackedByteArray = PackedByteArray()
	if GameSession.is_singleplayer() or GameSession.is_host():
		loading_screen.set_phase("Генерация карты")
		var generated_document: WorldMapDocument = level.generate_map_document(SANDBOX_SEED)
		if Time.get_ticks_msec() >= deadline_msec:
			return "map_sync_timeout"
		var validation_error: String = WorldMapDocumentCodec.get_validation_error(generated_document)
		if not validation_error.is_empty():
			return validation_error
		payload = WorldMapDocumentCodec.encode(generated_document)
		if payload.is_empty():
			return "map_invalid"
		if payload.size() > NetworkProtocol.MAX_LEVEL_MAP_BYTES:
			return "map_too_large"
		host_payload = payload.duplicate()
		_flush_pending_peer_transfers()
	else:
		payload = await _receive_host_payload(deadline_msec)
		if payload.is_empty():
			return "map_sync_timeout" if not was_active_transfer_invalid else "map_invalid"

	loading_screen.set_phase("Проверка карты")
	var decode_result: WorldMapDecodeResult = WorldMapDocumentCodec.decode(payload)
	if not decode_result.error_code.is_empty() or decode_result.document == null:
		return decode_result.error_code if not decode_result.error_code.is_empty() else "map_invalid"
	if decode_result.document.level_id != GameSession.selected_level_id:
		return "map_invalid"
	var document_hash: String = WorldMapDocumentCodec.get_sha256(payload)
	if document_hash.length() != 64:
		return "map_invalid"
	if Time.get_ticks_msec() >= deadline_msec:
		return "map_sync_timeout"

	loading_screen.set_progress(
		"Построение мира",
		0,
		builder.get_build_unit_count(decode_result.document)
	)
	var build_error: String = await builder.build(
		level,
		decode_result.document,
		document_hash,
		deadline_msec
	)
	if not build_error.is_empty():
		return build_error
	loading_screen.set_phase("Синхронизация участников")
	return ""


func clear() -> void:
	host_payload.clear()
	pending_peer_transfers.clear()
	active_transfer_id = ""
	received_payload.clear()
	was_active_transfer_invalid = false
	should_retry_active_transfer = false
	if NetworkManager.level_map != null:
		NetworkManager.level_map.reset_transfer()


func _receive_host_payload(deadline_msec: int) -> PackedByteArray:
	for attempt: int in range(MAP_REQUEST_RETRY_LIMIT + 1):
		active_transfer_id = _make_transfer_id(attempt)
		received_payload.clear()
		was_active_transfer_invalid = false
		should_retry_active_transfer = false
		NetworkManager.level_map.request_level_map(active_transfer_id)
		while (
			is_inside_tree()
			and received_payload.is_empty()
			and not was_active_transfer_invalid
			and Time.get_ticks_msec() < deadline_msec
		):
			await get_tree().process_frame
		if not received_payload.is_empty():
			return received_payload.duplicate()
		if Time.get_ticks_msec() >= deadline_msec:
			return PackedByteArray()
		if not should_retry_active_transfer:
			return PackedByteArray()
	return PackedByteArray()


func _make_transfer_id(attempt: int) -> String:
	return ("map-%d-%d" % [Time.get_ticks_usec(), attempt]).left(
		NetworkProtocol.MAX_IDENTIFIER_LENGTH
	)


func _connect_signals() -> void:
	if not NetworkManager.level_map.level_map_requested.is_connected(_on_level_map_requested):
		NetworkManager.level_map.level_map_requested.connect(_on_level_map_requested)
	if not NetworkManager.level_map.level_map_transfer_started.is_connected(_on_transfer_started):
		NetworkManager.level_map.level_map_transfer_started.connect(_on_transfer_started)
	if not NetworkManager.level_map.level_map_transfer_progress.is_connected(_on_transfer_progress):
		NetworkManager.level_map.level_map_transfer_progress.connect(_on_transfer_progress)
	if not NetworkManager.level_map.level_map_received.is_connected(_on_level_map_received):
		NetworkManager.level_map.level_map_received.connect(_on_level_map_received)
	if not NetworkManager.level_map.level_map_invalid.is_connected(_on_level_map_invalid):
		NetworkManager.level_map.level_map_invalid.connect(_on_level_map_invalid)
	if not builder.progress_changed.is_connected(_on_builder_progress_changed):
		builder.progress_changed.connect(_on_builder_progress_changed)


func _disconnect_signals() -> void:
	if NetworkManager.level_map.level_map_requested.is_connected(_on_level_map_requested):
		NetworkManager.level_map.level_map_requested.disconnect(_on_level_map_requested)
	if NetworkManager.level_map.level_map_transfer_started.is_connected(_on_transfer_started):
		NetworkManager.level_map.level_map_transfer_started.disconnect(_on_transfer_started)
	if NetworkManager.level_map.level_map_transfer_progress.is_connected(_on_transfer_progress):
		NetworkManager.level_map.level_map_transfer_progress.disconnect(_on_transfer_progress)
	if NetworkManager.level_map.level_map_received.is_connected(_on_level_map_received):
		NetworkManager.level_map.level_map_received.disconnect(_on_level_map_received)
	if NetworkManager.level_map.level_map_invalid.is_connected(_on_level_map_invalid):
		NetworkManager.level_map.level_map_invalid.disconnect(_on_level_map_invalid)
	if builder.progress_changed.is_connected(_on_builder_progress_changed):
		builder.progress_changed.disconnect(_on_builder_progress_changed)


func _on_level_map_requested(requester_peer_id: int, transfer_id: String) -> void:
	if not GameSession.is_host():
		return
	if host_payload.is_empty():
		if pending_peer_transfers.size() < NetworkProtocol.MAX_ROSTER_SIZE:
			pending_peer_transfers[requester_peer_id] = transfer_id
		return
	NetworkManager.level_map.send_level_map(requester_peer_id, transfer_id, host_payload)


func _flush_pending_peer_transfers() -> void:
	if not GameSession.is_host() or host_payload.is_empty():
		return
	for peer_id: int in pending_peer_transfers.keys():
		NetworkManager.level_map.send_level_map(
			peer_id,
			pending_peer_transfers[peer_id],
			host_payload
		)
	pending_peer_transfers.clear()


func _on_transfer_started(transfer_id: String, total_bytes: int) -> void:
	if transfer_id == active_transfer_id:
		loading_screen.set_progress("Получение карты", 0, total_bytes)


func _on_transfer_progress(transfer_id: String, received_bytes: int, total_bytes: int) -> void:
	if transfer_id == active_transfer_id:
		loading_screen.set_progress("Получение карты", received_bytes, total_bytes)


func _on_level_map_received(transfer_id: String, payload: PackedByteArray) -> void:
	if transfer_id == active_transfer_id:
		received_payload = payload.duplicate()


func _on_level_map_invalid(transfer_id: String, should_retry: bool) -> void:
	if transfer_id == active_transfer_id:
		was_active_transfer_invalid = true
		should_retry_active_transfer = should_retry


func _on_builder_progress_changed(completed_units: int, total_units: int) -> void:
	loading_screen.set_progress("Построение мира", completed_units, total_units)
