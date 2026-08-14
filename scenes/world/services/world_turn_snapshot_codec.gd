class_name WorldTurnSnapshotCodec
extends RefCounted

const PLAYER_TURN_TRANSITION_EVENTS: Array[String] = [
	WorldTurns.EVENT_ROUND_STARTED,
	WorldTurns.EVENT_PLAYER_TURN_ENDED,
	WorldTurns.EVENT_PLAYER_TURN_SKIPPED,
]


static func create_snapshot(turns: WorldTurns, event: String = WorldTurns.EVENT_NONE, event_payload: Dictionary = {}) -> Dictionary:
	var snapshot: Dictionary = {
		"state": turns.state,
		"round_number": turns.round_number,
		"turn_revision": turns.turn_revision,
		"world_turn_generation": turns.world_turn_generation,
		"active_player_id": turns.active_player_id,
		"current_turn_index": turns.current_turn_index,
		"pending_end_turn": turns.pending_end_turn,
		"turn_order": turns.turn_order.duplicate(),
		"event": event,
		"event_payload": event_payload,
	}
	snapshot.merge(turns.budget.create_snapshot(), true)
	return snapshot


static func apply_remote_snapshot(turns: WorldTurns, snapshot: Dictionary) -> void:
	if not is_valid_snapshot(turns, snapshot):
		return
	turns.state = str(snapshot.get("state", WorldTurns.STATE_FREE))
	turns.round_number = int(snapshot.get("round_number", 0))
	turns.turn_revision = int(snapshot.get("turn_revision", turns.turn_revision))
	turns.world_turn_generation = int(snapshot.get("world_turn_generation", turns.world_turn_generation))
	turns.active_player_id = str(snapshot.get("active_player_id", ""))
	turns.budget.apply_snapshot(snapshot)
	turns.current_turn_index = int(snapshot.get("current_turn_index", -1))
	turns.pending_end_turn = bool(snapshot.get("pending_end_turn", false))
	turns.turn_order.clear()
	for player_id_value: Variant in snapshot.get("turn_order", []):
		turns.turn_order.append(str(player_id_value))
	var event_payload: Dictionary = {}
	var snapshot_payload: Variant = snapshot.get("event_payload", {})
	if snapshot_payload is Dictionary:
		event_payload = snapshot_payload
	var event: String = str(snapshot.get("event", WorldTurns.EVENT_NONE))
	_print_remote_event(turns, event, event_payload)
	if event == WorldTurns.EVENT_TURN_MODE_ENABLED:
		turns.turn_mode_changed.emit(true)
	elif event == WorldTurns.EVENT_TURN_MODE_DISABLED:
		turns.turn_mode_changed.emit(false)
	elif event == WorldTurns.EVENT_PLAYER_TURN_STARTED:
		turns.player_turn_started.emit(turns.active_player_id)
	elif event == WorldTurns.EVENT_ROUND_STARTED:
		turns.round_started.emit(turns.round_number)
	turns.turn_state_changed.emit()


static func is_valid_snapshot(turns: WorldTurns, snapshot: Dictionary) -> bool:
	var snapshot_state: String = str(snapshot.get("state", ""))
	var snapshot_active_player_id: String = str(snapshot.get("active_player_id", ""))
	var turn_order_value: Variant = snapshot.get("turn_order")
	var event_payload_value: Variant = snapshot.get("event_payload", {})
	if snapshot_state not in [WorldTurns.STATE_FREE, WorldTurns.STATE_PLAYER_TURN, WorldTurns.STATE_WORLD_TURN] or int(snapshot.get("round_number", -1)) < 0 or int(snapshot.get("turn_revision", -1)) < 0 or int(snapshot.get("world_turn_generation", -1)) < 0 or not NetworkProtocol.is_valid_optional_identifier(snapshot_active_player_id) or not (turn_order_value is Array) or (turn_order_value as Array).size() > NetworkProtocol.MAX_ROSTER_SIZE or not (event_payload_value is Dictionary) or not NetworkProtocol.is_valid_bounded_text(str(snapshot.get("event", ""))):
		return false
	var seen_player_ids: Dictionary[String, bool] = {}
	for player_id_value: Variant in turn_order_value as Array:
		var player_id: String = str(player_id_value)
		if not NetworkProtocol.is_valid_identifier(player_id) or seen_player_ids.has(player_id):
			return false
		seen_player_ids[player_id] = true
	var valid_entity_ids: Array[String] = []
	if snapshot_state == WorldTurns.STATE_PLAYER_TURN:
		if snapshot_active_player_id.is_empty():
			if str(snapshot.get("event", "")) not in PLAYER_TURN_TRANSITION_EVENTS:
				return false
		elif not seen_player_ids.has(snapshot_active_player_id):
			return false
		else:
			for player: PlayerCharacter in turns.runtime.get_squad_members(snapshot_active_player_id):
				valid_entity_ids.append(player.entity_id)
	elif not snapshot_active_player_id.is_empty():
		return false
	if not turns.budget.is_valid_snapshot(snapshot, valid_entity_ids):
		return false
	var current_index: int = int(snapshot.get("current_turn_index", -1))
	return current_index >= -1 and current_index < maxi((turn_order_value as Array).size(), 1)


static func _print_remote_event(turns: WorldTurns, event: String, event_payload: Dictionary) -> void:
	match event:
		WorldTurns.EVENT_TURN_MODE_ENABLED:
			ConsoleOutput.print_console("Turn mode enabled", turns.runtime)
		WorldTurns.EVENT_TURN_MODE_DISABLED:
			ConsoleOutput.print_console("Turn mode disabled", turns.runtime)
		WorldTurns.EVENT_STEPS_CHANGED:
			ConsoleOutput.print_console("Squad member steps updated", turns.runtime)
		WorldTurns.EVENT_ROUND_STARTED:
			ConsoleOutput.print_console("Round %d started" % turns.round_number, turns.runtime)
		WorldTurns.EVENT_PLAYER_TURN_STARTED:
			ConsoleOutput.print_console("Squad turn started: %s" % turns.active_player_id, turns.runtime)
			ConsoleOutput.print_console("Available steps per member: %d" % WorldTurns.MAX_STEPS_PER_MEMBER, turns.runtime)
		WorldTurns.EVENT_WORLD_TURN_STARTED:
			ConsoleOutput.print_console("World turn started", turns.runtime)
		WorldTurns.EVENT_WORLD_TURN_ENDED:
			ConsoleOutput.print_console("World turn ended", turns.runtime)
		WorldTurns.EVENT_PLAYER_TURN_ENDED:
			ConsoleOutput.print_console("Squad turn ended: %s" % str(event_payload.get("player_id", "")), turns.runtime)
		WorldTurns.EVENT_PLAYER_TURN_SKIPPED:
			ConsoleOutput.print_console("Squad turn skipped: %s (%s)" % [str(event_payload.get("player_id", "")), str(event_payload.get("reason", "unknown"))], turns.runtime)
