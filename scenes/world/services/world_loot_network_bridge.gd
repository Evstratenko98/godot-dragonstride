class_name WorldLootNetworkBridge
extends RefCounted

var loot: WorldLoot = null
var runtime: WorldRuntime = null


func configure(owner: WorldLoot, new_runtime: WorldRuntime) -> void:
	disconnect_signals()
	loot = owner
	runtime = new_runtime
	connect_signals()


func request_claim(
	chest_id: String,
	inventory_kind: String,
	target_slot_index: int,
	expected_inventory_revision: int,
	request_id: int
) -> void:
	NetworkManager.loot.request_loot_claim(
		chest_id,
		inventory_kind,
		target_slot_index,
		expected_inventory_revision,
		GameSession.get_match_id(),
		runtime.get_turn_revision(),
		request_id
	)


func request_discard(chest_id: String, request_id: int) -> void:
	NetworkManager.loot.request_loot_discard(chest_id, GameSession.get_match_id(), request_id)


func broadcast_discarded(chest_id: String, opener_entity_id: String) -> void:
	NetworkManager.loot.broadcast_loot_discarded(chest_id, opener_entity_id)


func connect_signals() -> void:
	if loot == null or runtime == null or runtime.action_stream == null:
		return
	if not NetworkManager.loot.loot_claim_requested.is_connected(_on_loot_claim_requested):
		NetworkManager.loot.loot_claim_requested.connect(_on_loot_claim_requested)
	if not NetworkManager.loot.loot_discard_requested.is_connected(_on_loot_discard_requested):
		NetworkManager.loot.loot_discard_requested.connect(_on_loot_discard_requested)
	if not NetworkManager.loot.loot_discarded_received.is_connected(_on_loot_discarded_received):
		NetworkManager.loot.loot_discarded_received.connect(_on_loot_discarded_received)
	if not NetworkManager.loot.loot_discard_rejected.is_connected(_on_loot_discard_rejected):
		NetworkManager.loot.loot_discard_rejected.connect(_on_loot_discard_rejected)
	if not runtime.action_stream.action_completed.is_connected(_on_action_completed):
		runtime.action_stream.action_completed.connect(_on_action_completed)
	if not runtime.action_stream.action_cancelled.is_connected(_on_action_cancelled):
		runtime.action_stream.action_cancelled.connect(_on_action_cancelled)
	if not runtime.action_rejected.is_connected(_on_runtime_action_rejected):
		runtime.action_rejected.connect(_on_runtime_action_rejected)
	if not GameSession.session_cleared.is_connected(_on_session_cleared):
		GameSession.session_cleared.connect(_on_session_cleared)


func disconnect_signals() -> void:
	if NetworkManager.loot.loot_claim_requested.is_connected(_on_loot_claim_requested):
		NetworkManager.loot.loot_claim_requested.disconnect(_on_loot_claim_requested)
	if NetworkManager.loot.loot_discard_requested.is_connected(_on_loot_discard_requested):
		NetworkManager.loot.loot_discard_requested.disconnect(_on_loot_discard_requested)
	if NetworkManager.loot.loot_discarded_received.is_connected(_on_loot_discarded_received):
		NetworkManager.loot.loot_discarded_received.disconnect(_on_loot_discarded_received)
	if NetworkManager.loot.loot_discard_rejected.is_connected(_on_loot_discard_rejected):
		NetworkManager.loot.loot_discard_rejected.disconnect(_on_loot_discard_rejected)
	if runtime != null and runtime.action_stream != null:
		if runtime.action_stream.action_completed.is_connected(_on_action_completed):
			runtime.action_stream.action_completed.disconnect(_on_action_completed)
		if runtime.action_stream.action_cancelled.is_connected(_on_action_cancelled):
			runtime.action_stream.action_cancelled.disconnect(_on_action_cancelled)
	if runtime != null and runtime.action_rejected.is_connected(_on_runtime_action_rejected):
		runtime.action_rejected.disconnect(_on_runtime_action_rejected)
	if GameSession.session_cleared.is_connected(_on_session_cleared):
		GameSession.session_cleared.disconnect(_on_session_cleared)


func _get_requesting_player(requester_peer_id: int) -> PlayerCharacter:
	if requester_peer_id == 0:
		return runtime.get_local_player()
	var steam_id: int = NetworkManager.peers.get_steam_id_for_peer_id(requester_peer_id)
	return runtime.get_player_by_steam_id(steam_id) if steam_id > 0 else null


func _on_loot_claim_requested(
	chest_id: String,
	inventory_kind: String,
	target_slot_index: int,
	expected_inventory_revision: int,
	match_id: String,
	turn_revision: int,
	request_id: int,
	requester_peer_id: int
) -> void:
	if not GameSession.is_host():
		return
	var player: PlayerCharacter = _get_requesting_player(requester_peer_id)
	if player != null:
		loot.enqueue_claim_request(
			player,
			chest_id,
			inventory_kind,
			target_slot_index,
			expected_inventory_revision,
			request_id,
			requester_peer_id,
			turn_revision,
			match_id
		)


func _on_loot_discard_requested(
	chest_id: String,
	_match_id: String,
	_request_id: int,
	requester_peer_id: int
) -> void:
	if not GameSession.is_host():
		return
	var player: PlayerCharacter = _get_requesting_player(requester_peer_id)
	if player != null and loot.discard_authoritative(chest_id, player):
		return
	if requester_peer_id > 0:
		NetworkManager.loot.send_loot_discard_rejected(requester_peer_id, chest_id, "invalid_target")


func _on_loot_discarded_received(chest_id: String, opener_entity_id: String) -> void:
	loot.apply_discarded(chest_id, opener_entity_id)


func _on_loot_discard_rejected(chest_id: String, reason_code: String) -> void:
	loot.notify_request_failed(chest_id, reason_code)


func _on_action_completed(action: WorldActionRecord) -> void:
	loot.handle_action_completed(action)


func _on_action_cancelled(action: WorldActionRecord, reason_code: String) -> void:
	loot.handle_action_cancelled(action, reason_code)


func _on_runtime_action_rejected(reason_code: String) -> void:
	loot.handle_local_action_rejected(reason_code)


func _on_session_cleared() -> void:
	loot.clear_state()
