extends Node

const STATE_DISABLED := "disabled"
const STATE_PLAYER_TURN := "player_turn"
const STATE_WORLD_TURN := "world_turn"

const EVENT_NONE := ""
const EVENT_TURN_MODE_ENABLED := "turn_mode_enabled"
const EVENT_TURN_MODE_DISABLED := "turn_mode_disabled"
const EVENT_STEPS_CHANGED := "steps_changed"
const EVENT_ROUND_STARTED := "round_started"
const EVENT_PLAYER_TURN_STARTED := "player_turn_started"
const EVENT_WORLD_TURN_STARTED := "world_turn_started"
const EVENT_WORLD_TURN_ENDED := "world_turn_ended"
const EVENT_PLAYER_TURN_ENDED := "player_turn_ended"
const EVENT_PLAYER_TURN_SKIPPED := "player_turn_skipped"

const MAX_STEPS_PER_TURN := 10
const MAX_ATTACKS_PER_TURN := 1

var world = null
var state := STATE_DISABLED
var round_number := 0
var turn_order: Array[String] = []
var turn_order_steam_ids: Dictionary = {}
var disconnected_steam_ids: Dictionary = {}
var current_turn_index := -1
var active_entity_id := ""
var steps_left := 0
var attacks_left := 0
var pending_end_turn := false
var pending_world_entity_ids: Dictionary = {}
var is_starting_world_behaviors := false


func _ready() -> void:
	world = get_parent()
	_register_console_commands()
	_connect_network_signals()


func _exit_tree() -> void:
	_unregister_console_commands()
	_disconnect_network_signals()


func enable_turn_mode() -> void:
	if not _can_control_turn_mode():
		ConsoleOutput.print_console("Only host can change turn mode", world)
		return

	_reset_turn_state()
	state = STATE_PLAYER_TURN
	round_number = 1
	_build_player_turn_order()
	ConsoleOutput.print_console("Turn mode enabled", world)
	_broadcast_snapshot(EVENT_TURN_MODE_ENABLED)
	_start_round()


func disable_turn_mode() -> void:
	if not _can_control_turn_mode():
		ConsoleOutput.print_console("Only host can change turn mode", world)
		return

	_reset_turn_state()
	ConsoleOutput.print_console("Turn mode disabled", world)
	_broadcast_snapshot(EVENT_TURN_MODE_DISABLED)


func print_turn_status() -> void:
	if state == STATE_DISABLED:
		ConsoleOutput.print_console("Turn mode: disabled", world)
		return

	var active_name := "none"
	var active_entity: Node = _get_active_entity()
	if active_entity != null:
		active_name = _get_entity_display_name(active_entity)

	ConsoleOutput.print_console("Turn mode: enabled; state: %s; round: %d; active: %s; steps: %d; attack: %d" % [
		state,
		round_number,
		active_name,
		steps_left,
		attacks_left,
	], world)


func is_turn_mode_enabled() -> bool:
	return state != STATE_DISABLED


func can_entity_move(entity: Node) -> bool:
	if state == STATE_DISABLED:
		return true

	if state == STATE_WORLD_TURN:
		return _is_world_turn_entity(entity)

	return state == STATE_PLAYER_TURN and _is_active_entity(entity) and steps_left > 0


func can_entity_attack(entity: Node, target_cell: Vector2i) -> bool:
	if state == STATE_DISABLED:
		return true

	if state == STATE_WORLD_TURN:
		return _is_world_turn_entity(entity)

	if state != STATE_PLAYER_TURN or not _is_active_entity(entity):
		return false

	if _attack_consumes_action(entity, target_cell) and attacks_left <= 0:
		return false

	return true


func can_entity_sync_state(entity: Node) -> bool:
	if state == STATE_DISABLED:
		return true

	return state == STATE_PLAYER_TURN and _is_active_entity(entity)


func notify_entity_moved(entity: Node, _from_cell: Vector2i, _target_cell: Vector2i) -> void:
	if not _is_authority() or state != STATE_PLAYER_TURN or not _is_active_entity(entity):
		return

	steps_left = maxi(steps_left - 1, 0)
	var log_line := "Steps left for %s: %d" % [_get_entity_display_name(entity), steps_left]
	ConsoleOutput.print_console(log_line, world)
	_broadcast_snapshot(EVENT_STEPS_CHANGED)
	_finish_pending_turn_if_ready()


func notify_entity_attacked(entity: Node, target_cell: Vector2i) -> void:
	if not _is_authority() or state != STATE_PLAYER_TURN or not _is_active_entity(entity):
		return

	if _attack_consumes_action(entity, target_cell) and attacks_left > 0:
		attacks_left -= 1
		_broadcast_snapshot()


func notify_entity_action_finished(entity: Node) -> void:
	if _is_authority() and state == STATE_WORLD_TURN and _is_world_turn_entity(entity):
		_mark_world_entity_action_finished(entity)
		return

	if not _is_authority() or not _is_active_entity(entity):
		return

	_finish_pending_turn_if_ready()


func request_end_turn(entity: Node) -> void:
	if state != STATE_PLAYER_TURN or not _is_active_entity(entity):
		return

	if GameSession.is_multiplayer() and not GameSession.is_host():
		var steam_id: int = _get_entity_steam_id(entity)
		NetworkManager.request_turn_end(steam_id)
		return

	_request_end_turn_for_entity(entity)


func apply_remote_snapshot(snapshot: Dictionary) -> void:
	state = str(snapshot.get("state", STATE_DISABLED))
	round_number = int(snapshot.get("round_number", 0))
	active_entity_id = str(snapshot.get("active_entity_id", ""))
	steps_left = int(snapshot.get("steps_left", 0))
	attacks_left = int(snapshot.get("attacks_left", 0))
	current_turn_index = int(snapshot.get("current_turn_index", -1))
	pending_end_turn = bool(snapshot.get("pending_end_turn", false))

	turn_order.clear()
	for id in snapshot.get("turn_order", []):
		turn_order.append(str(id))

	var event_payload: Dictionary = {}
	var snapshot_payload: Variant = snapshot.get("event_payload", {})
	if snapshot_payload is Dictionary:
		event_payload = snapshot_payload

	_print_remote_turn_event(str(snapshot.get("event", EVENT_NONE)), event_payload)


func _start_round() -> void:
	if turn_order.is_empty() or not _has_available_turn_player():
		_broadcast_snapshot()
		return

	current_turn_index = -1
	var log_line := "Round %d started" % round_number
	ConsoleOutput.print_console(log_line, world)
	_broadcast_snapshot(EVENT_ROUND_STARTED)
	_start_next_player_turn()


func _start_next_player_turn() -> void:
	current_turn_index += 1

	while current_turn_index < turn_order.size():
		var entity_id: String = turn_order[current_turn_index]
		var player: Node = world.get_entity_by_id(entity_id)
		var skip_reason: String = _get_player_skip_reason(entity_id, player)
		if not skip_reason.is_empty():
			_log_player_skipped(entity_id, player, skip_reason)
			current_turn_index += 1
			continue

		_start_player_turn(player)
		return

	_start_world_turn()


func _start_player_turn(player: Node) -> void:
	if player.get("health") != null and int(player.get("health")) <= 0 and player.has_method("respawn"):
		player.respawn()

	state = STATE_PLAYER_TURN
	active_entity_id = world.get_entity_id(player)
	steps_left = MAX_STEPS_PER_TURN
	attacks_left = MAX_ATTACKS_PER_TURN
	pending_end_turn = false

	var start_log := "Player turn started: %s" % _get_entity_display_name(player)
	var resources_log := "Available: steps %d, attack %d" % [steps_left, attacks_left]
	ConsoleOutput.print_console(start_log, world)
	ConsoleOutput.print_console(resources_log, world)
	_broadcast_snapshot(EVENT_PLAYER_TURN_STARTED)


func _start_world_turn() -> void:
	state = STATE_WORLD_TURN
	active_entity_id = ""
	steps_left = 0
	attacks_left = 0
	pending_end_turn = false
	pending_world_entity_ids.clear()

	var start_log := "World turn started"
	ConsoleOutput.print_console(start_log, world)
	_broadcast_snapshot(EVENT_WORLD_TURN_STARTED)
	_start_world_behaviors()


func _start_world_behaviors() -> void:
	if not _is_authority():
		return

	var world_entities := _get_world_turn_entities()
	var ready_entities: Array[Node] = []
	for entity in world_entities:
		var entity_id: String = world.get_entity_id(entity)
		if entity_id.is_empty():
			continue

		ready_entities.append(entity)
		pending_world_entity_ids[entity_id] = true

	if pending_world_entity_ids.is_empty():
		_finish_world_turn()
		return

	is_starting_world_behaviors = true
	for entity in ready_entities:
		if _is_world_turn_entity_available(entity) and entity.has_method("behavior"):
			entity.behavior()
		else:
			_mark_world_entity_action_finished(entity)

	is_starting_world_behaviors = false
	_finish_world_turn_if_ready()


func _finish_world_turn() -> void:
	pending_world_entity_ids.clear()
	is_starting_world_behaviors = false
	var finish_log := "World turn ended"
	ConsoleOutput.print_console(finish_log, world)
	_broadcast_snapshot(EVENT_WORLD_TURN_ENDED)
	round_number += 1
	state = STATE_PLAYER_TURN
	_start_round()


func _mark_world_entity_action_finished(entity: Node) -> void:
	if entity == null:
		return

	var entity_id: String = world.get_entity_id(entity)
	if entity_id.is_empty():
		return

	pending_world_entity_ids.erase(entity_id)
	if not is_starting_world_behaviors:
		_finish_world_turn_if_ready()


func _finish_world_turn_if_ready() -> void:
	if state == STATE_WORLD_TURN and pending_world_entity_ids.is_empty():
		_finish_world_turn()


func _request_end_turn_for_entity(entity: Node) -> void:
	if not _is_active_entity(entity):
		return

	if _is_entity_busy(entity):
		pending_end_turn = true
		_broadcast_snapshot()
		return

	_finish_player_turn()


func _finish_pending_turn_if_ready() -> void:
	if not pending_end_turn:
		return

	var active_entity: Node = _get_active_entity()
	if active_entity == null or not _is_entity_busy(active_entity):
		_finish_player_turn()


func _finish_player_turn() -> void:
	var player: Node = _get_active_entity()
	var player_name := active_entity_id
	if player != null:
		player_name = _get_entity_display_name(player)

	var log_line := "Player turn ended: %s" % player_name
	ConsoleOutput.print_console(log_line, world)
	var finished_entity_id := active_entity_id
	active_entity_id = ""
	steps_left = 0
	attacks_left = 0
	pending_end_turn = false
	_broadcast_snapshot(EVENT_PLAYER_TURN_ENDED, {"entity_id": finished_entity_id})
	_start_next_player_turn()


func _skip_active_player(reason: String) -> void:
	var player: Node = _get_active_entity()
	_log_player_skipped(active_entity_id, player, reason)
	active_entity_id = ""
	steps_left = 0
	attacks_left = 0
	pending_end_turn = false
	_start_next_player_turn()


func _log_player_skipped(entity_id: String, player: Node, reason: String) -> void:
	var player_name := entity_id
	if player != null:
		player_name = _get_entity_display_name(player)

	var log_line := "Player turn skipped: %s (%s)" % [player_name, reason]
	ConsoleOutput.print_console(log_line, world)
	_broadcast_snapshot(EVENT_PLAYER_TURN_SKIPPED, {
		"entity_id": entity_id,
		"reason": reason,
	})


func _build_player_turn_order() -> void:
	turn_order.clear()
	turn_order_steam_ids.clear()

	for player_info in GameSession.get_players():
		var steam_id: int = int(player_info.get("steam_id", 0))
		var player: Node = null
		if steam_id != 0:
			player = world.get_player_by_steam_id(steam_id)
		elif GameSession.is_singleplayer():
			player = world.get_local_player()

		_add_player_to_turn_order(player, steam_id)

	if turn_order.is_empty():
		var players_root: Node = world.get_node_or_null("Players")
		if players_root != null:
			for child in players_root.get_children():
				if child is Node and child.get("entity_type") != null and int(child.get("entity_type")) == Entity.EntityType.CHARACTER:
					_add_player_to_turn_order(child, _get_entity_steam_id(child))


func _add_player_to_turn_order(player: Node, steam_id: int) -> void:
	if player == null:
		return

	var entity_id: String = world.get_entity_id(player)
	if entity_id.is_empty() or turn_order.has(entity_id):
		return

	turn_order.append(entity_id)
	turn_order_steam_ids[entity_id] = steam_id


func _get_player_skip_reason(entity_id: String, player: Node) -> String:
	var steam_id: int = int(turn_order_steam_ids.get(entity_id, 0))
	if GameSession.is_multiplayer() and steam_id != 0 and steam_id != GameSession.local_steam_id:
		if not NetworkManager.has_peer_for_steam_id(steam_id):
			return "disconnected"

	if player == null:
		return "missing"

	return ""


func _has_available_turn_player() -> bool:
	for entity_id in turn_order:
		var player: Node = world.get_entity_by_id(entity_id)
		if _get_player_skip_reason(entity_id, player).is_empty():
			return true

	return false


func _attack_consumes_action(attacker: Node, target_cell: Vector2i) -> bool:
	var target_entity: Node = world.get_entity_at_cell(target_cell)
	if target_entity != null and target_entity != attacker:
		return true

	return world.get_object_at_cell(target_cell) != null


func _get_active_entity() -> Node:
	if active_entity_id.is_empty():
		return null

	return world.get_entity_by_id(active_entity_id)


func _is_active_entity(entity: Node) -> bool:
	if entity == null or active_entity_id.is_empty():
		return false

	return world.get_entity_id(entity) == active_entity_id


func _is_entity_busy(entity: Node) -> bool:
	if entity == null:
		return false

	var moving: Variant = entity.get("is_moving")
	var attacking: Variant = entity.get("is_attacking")
	return bool(moving) or bool(attacking)


func _get_entity_steam_id(entity: Node) -> int:
	if entity != null and entity.get("steam_id") != null:
		return int(entity.get("steam_id"))

	return 0


func _get_entity_display_name(entity: Node) -> String:
	if world != null and world.has_method("get_entity_display_name"):
		return world.get_entity_display_name(entity)

	if entity != null:
		return entity.name

	return "player"


func _get_entity_display_name_by_id(entity_id: String) -> String:
	var entity: Node = world.get_entity_by_id(entity_id)
	if entity != null:
		return _get_entity_display_name(entity)

	if not entity_id.is_empty():
		return entity_id

	return "player"


func _print_remote_turn_event(event: String, event_payload: Dictionary) -> void:
	match event:
		EVENT_TURN_MODE_ENABLED:
			ConsoleOutput.print_console("Turn mode enabled", world)
		EVENT_TURN_MODE_DISABLED:
			ConsoleOutput.print_console("Turn mode disabled", world)
		EVENT_STEPS_CHANGED:
			var steps_entity: Node = _get_active_entity()
			ConsoleOutput.print_console("Steps left for %s: %d" % [
				_get_entity_display_name(steps_entity),
				steps_left,
			], world)
		EVENT_ROUND_STARTED:
			ConsoleOutput.print_console("Round %d started" % round_number, world)
		EVENT_PLAYER_TURN_STARTED:
			var turn_entity: Node = _get_active_entity()
			ConsoleOutput.print_console("Player turn started: %s" % _get_entity_display_name(turn_entity), world)
			ConsoleOutput.print_console("Available: steps %d, attack %d" % [steps_left, attacks_left], world)
		EVENT_WORLD_TURN_STARTED:
			ConsoleOutput.print_console("World turn started", world)
		EVENT_WORLD_TURN_ENDED:
			ConsoleOutput.print_console("World turn ended", world)
		EVENT_PLAYER_TURN_ENDED:
			var ended_entity_id := str(event_payload.get("entity_id", ""))
			ConsoleOutput.print_console("Player turn ended: %s" % _get_entity_display_name_by_id(ended_entity_id), world)
		EVENT_PLAYER_TURN_SKIPPED:
			var skipped_entity_id := str(event_payload.get("entity_id", ""))
			var reason := str(event_payload.get("reason", "unknown"))
			ConsoleOutput.print_console("Player turn skipped: %s (%s)" % [
				_get_entity_display_name_by_id(skipped_entity_id),
				reason,
			], world)


func _make_snapshot(event: String = EVENT_NONE, event_payload: Dictionary = {}) -> Dictionary:
	return {
		"state": state,
		"round_number": round_number,
		"active_entity_id": active_entity_id,
		"steps_left": steps_left,
		"attacks_left": attacks_left,
		"current_turn_index": current_turn_index,
		"pending_end_turn": pending_end_turn,
		"turn_order": turn_order.duplicate(),
		"event": event,
		"event_payload": event_payload,
	}


func _broadcast_snapshot(event: String = EVENT_NONE, event_payload: Dictionary = {}) -> void:
	if GameSession.is_multiplayer() and GameSession.is_host():
		NetworkManager.broadcast_turn_state(_make_snapshot(event, event_payload))


func _reset_turn_state() -> void:
	state = STATE_DISABLED
	round_number = 0
	turn_order.clear()
	turn_order_steam_ids.clear()
	disconnected_steam_ids.clear()
	current_turn_index = -1
	active_entity_id = ""
	steps_left = 0
	attacks_left = 0
	pending_end_turn = false
	pending_world_entity_ids.clear()
	is_starting_world_behaviors = false


func _can_control_turn_mode() -> bool:
	return not GameSession.is_multiplayer() or GameSession.is_host()


func _is_authority() -> bool:
	return not GameSession.is_multiplayer() or GameSession.is_host()


func _get_world_turn_entities() -> Array[Node]:
	var entities: Array[Node] = []
	_collect_world_turn_entities(world, entities)
	return entities


func _collect_world_turn_entities(node: Node, entities: Array[Node]) -> void:
	for child in node.get_children():
		if _is_world_turn_entity_available(child):
			entities.append(child)

		_collect_world_turn_entities(child, entities)


func _is_world_turn_entity(entity: Node) -> bool:
	if entity == null or entity.get("entity_type") == null:
		return false

	return int(entity.get("entity_type")) != Entity.EntityType.CHARACTER and entity.has_method("behavior")


func _is_world_turn_entity_available(entity: Node) -> bool:
	if not _is_world_turn_entity(entity):
		return false

	if entity.get("health") != null and int(entity.get("health")) <= 0:
		return false

	return true


func _connect_network_signals() -> void:
	if not NetworkManager.turn_state_received.is_connected(_on_turn_state_received):
		NetworkManager.turn_state_received.connect(_on_turn_state_received)

	if not NetworkManager.turn_end_requested.is_connected(_on_turn_end_requested):
		NetworkManager.turn_end_requested.connect(_on_turn_end_requested)

	if not NetworkManager.steam_peer_disconnected.is_connected(_on_steam_peer_disconnected):
		NetworkManager.steam_peer_disconnected.connect(_on_steam_peer_disconnected)


func _disconnect_network_signals() -> void:
	if NetworkManager.turn_state_received.is_connected(_on_turn_state_received):
		NetworkManager.turn_state_received.disconnect(_on_turn_state_received)

	if NetworkManager.turn_end_requested.is_connected(_on_turn_end_requested):
		NetworkManager.turn_end_requested.disconnect(_on_turn_end_requested)

	if NetworkManager.steam_peer_disconnected.is_connected(_on_steam_peer_disconnected):
		NetworkManager.steam_peer_disconnected.disconnect(_on_steam_peer_disconnected)


func _on_turn_state_received(snapshot: Dictionary) -> void:
	if GameSession.is_host():
		return

	apply_remote_snapshot(snapshot)


func _on_turn_end_requested(steam_id: int) -> void:
	if not _is_authority() or state != STATE_PLAYER_TURN:
		return

	var player: Node = world.get_player_by_steam_id(steam_id)
	if player == null and steam_id == 0:
		player = world.get_local_player()

	_request_end_turn_for_entity(player)


func _on_steam_peer_disconnected(steam_id: int) -> void:
	disconnected_steam_ids[steam_id] = true
	if not _is_authority() or state == STATE_DISABLED:
		return

	var active_player: Node = _get_active_entity()
	if active_player != null and _get_entity_steam_id(active_player) == steam_id:
		_skip_active_player("disconnected")


func _register_console_commands() -> void:
	var console: Node = get_node_or_null("/root/Console")
	if console == null or not console.has_method("add_command"):
		return

	console.add_command("game_turns_enable", enable_turn_mode, 0, 0, "Enable turn-based mode.")
	console.add_command("game_turns_disable", disable_turn_mode, 0, 0, "Disable turn-based mode.")
	console.add_command("game_turns_status", print_turn_status, 0, 0, "Print turn-based mode status.")


func _unregister_console_commands() -> void:
	var console: Node = get_node_or_null("/root/Console")
	if console == null or not console.has_method("remove_command"):
		return

	console.remove_command("game_turns_enable")
	console.remove_command("game_turns_disable")
	console.remove_command("game_turns_status")
