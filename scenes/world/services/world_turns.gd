class_name WorldTurns
extends Node

signal player_turn_started(player_id: String)
signal round_started(round_number: int)
signal turn_mode_changed(is_enabled: bool)
signal turn_state_changed
signal world_turn_behaviors_finished

const STATE_FREE := "free"
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

const MAX_STEPS_PER_MEMBER := WorldSquadTurnBudget.MAX_STEPS_PER_MEMBER
const MAX_ATTACKS_PER_TURN := WorldSquadTurnBudget.MAX_ATTACKS_PER_MEMBER
const MAX_INTERACTIONS_PER_TURN := WorldSquadTurnBudget.MAX_INTERACTIONS_PER_MEMBER
const WORLD_TURN_WATCHDOG_MSEC := 32000
const NPC_BEHAVIOR_WATCHDOG_MSEC := 8000

var runtime: WorldRuntime = null
var level: WorldLevel = null
var state: String = STATE_FREE
var round_number: int = 0
var turn_revision: int = 0
var turn_order: Array[String] = []
var turn_order_steam_ids: Dictionary = {}
var current_turn_index: int = -1
var active_player_id: String = ""
var budget: WorldSquadTurnBudget = WorldSquadTurnBudget.new()
var pending_end_turn: bool = false
var pending_world_entity_ids: Dictionary = {}
var is_starting_world_behaviors: bool = false
var was_world_turn_completion_emitted: bool = false
var world_turn_generation: int = 0
var behavior_deadline_by_entity_id: Dictionary[String, int] = {}
var watchdog_activation_count: int = 0
var pending_remote_snapshots: Dictionary[int, Dictionary] = {}
var debug_commands: WorldTurnsDebugCommands = WorldTurnsDebugCommands.new()


func _ready() -> void:
	_connect_network_signals()
	if not GameSession.session_cleared.is_connected(_on_session_cleared):
		GameSession.session_cleared.connect(_on_session_cleared)


func configure_context(new_runtime: WorldRuntime, new_level: WorldLevel) -> void:
	runtime = new_runtime
	level = new_level
	debug_commands.configure(self, level != null and level.allows_debug_commands())
	if runtime.action_stream != null and not runtime.action_stream.action_started.is_connected(_on_stream_action_started):
		runtime.action_stream.action_started.connect(_on_stream_action_started)


func _exit_tree() -> void:
	debug_commands.unregister_commands()
	_disconnect_network_signals()
	if runtime != null and runtime.action_stream != null and runtime.action_stream.action_started.is_connected(_on_stream_action_started):
		runtime.action_stream.action_started.disconnect(_on_stream_action_started)
	if GameSession.session_cleared.is_connected(_on_session_cleared):
		GameSession.session_cleared.disconnect(_on_session_cleared)


func enable_turn_mode() -> void:
	if level == null or not level.allows_debug_commands():
		return
	if not _can_control_turn_mode():
		ConsoleOutput.print_console("Only host can change turn mode", runtime)
		return
	runtime.enqueue_system_action(WorldActionRecord.ActionType.SET_TURN_MODE, {"is_enabled": true})


func disable_turn_mode() -> void:
	if level == null or not level.allows_debug_commands():
		return
	if not _can_control_turn_mode():
		ConsoleOutput.print_console("Only host can change turn mode", runtime)
		return

	runtime.enqueue_system_action(WorldActionRecord.ActionType.SET_TURN_MODE, {"is_enabled": false})


func print_turn_status() -> void:
	if level == null or not level.allows_debug_commands():
		return
	if state == STATE_FREE:
		ConsoleOutput.print_console("Game mode: free", runtime)
		return

	var active_name: String = active_player_id if not active_player_id.is_empty() else "none"

	ConsoleOutput.print_console("Turn mode: enabled; state: %s; round: %d; active: %s; selected steps: %d; attack: %d; interaction: %d" % [
		state,
		round_number,
		active_name,
		get_steps_left(_resolve_budget_entity_id("")),
		get_attacks_left(),
		get_interactions_left(),
	], runtime)


func is_turn_mode_enabled() -> bool:
	return state != STATE_FREE


func is_world_turn_active() -> bool:
	return state == STATE_WORLD_TURN


func is_entity_active_in_turn(entity: Node) -> bool:
	return state == STATE_PLAYER_TURN and _is_active_entity(entity)


func get_turn_revision() -> int:
	return turn_revision


func get_state() -> String:
	return state


func get_round_number() -> int:
	return round_number


func get_active_player_id() -> String:
	return active_player_id


func get_steps_left(entity_id: String) -> int:
	return budget.get_steps_left(entity_id)


func get_max_steps_per_member() -> int:
	return MAX_STEPS_PER_MEMBER


func get_attacks_left(entity_id: String = "") -> int:
	var resolved_entity_id: String = _resolve_budget_entity_id(entity_id)
	return budget.get_attacks_left(resolved_entity_id)


func get_interactions_left(entity_id: String = "") -> int:
	var resolved_entity_id: String = _resolve_budget_entity_id(entity_id)
	return budget.get_interactions_left(resolved_entity_id)


func can_entity_move(entity: Node) -> bool:
	if state == STATE_FREE:
		return true

	if state == STATE_WORLD_TURN:
		return _is_world_turn_entity(entity)

	return state == STATE_PLAYER_TURN and _is_active_entity(entity) and budget.can_move(runtime.get_entity_id(entity))


func can_entity_attack(entity: Node, _target_cell: Vector2i) -> bool:
	if state == STATE_FREE:
		return true

	if state == STATE_WORLD_TURN:
		return _is_world_turn_entity(entity)

	if state != STATE_PLAYER_TURN or not _is_active_entity(entity):
		return false

	return budget.can_attack(runtime.get_entity_id(entity))


func can_entity_interact(entity: Node) -> bool:
	if state == STATE_FREE:
		return true

	return (
		state == STATE_PLAYER_TURN
		and _is_active_entity(entity)
		and budget.can_interact(runtime.get_entity_id(entity))
	)


func can_entity_use_item(entity: Node) -> bool:
	return state == STATE_PLAYER_TURN and _is_active_entity(entity)


func can_entity_cast_spell(entity: Node) -> bool:
	if runtime != null and not runtime.allows_spell_intents():
		return false

	return state == STATE_PLAYER_TURN and _is_active_entity(entity)


func can_entity_sync_state(entity: Node) -> bool:
	if state == STATE_FREE:
		return true

	return state == STATE_PLAYER_TURN and _is_active_entity(entity)


func notify_entity_moved(entity: Node, _from_cell: Vector2i, _target_cell: Vector2i, movement_step_cost: int = 1) -> void:
	if not _is_authority() or state != STATE_PLAYER_TURN or not _is_active_entity(entity) or movement_step_cost <= 0:
		return

	var entity_id: String = runtime.get_entity_id(entity)
	if not budget.consume_steps(entity_id, movement_step_cost):
		return
	var log_line: String = "Steps left for %s: %d" % [
		_get_entity_display_name(entity),
		budget.get_steps_left(entity_id),
	]
	ConsoleOutput.print_console(log_line, runtime)
	_broadcast_snapshot(EVENT_STEPS_CHANGED)
	_finish_pending_turn_if_ready()


func notify_entity_attacked(entity: Node, _target_cell: Vector2i) -> void:
	if not _is_authority() or state != STATE_PLAYER_TURN or not _is_active_entity(entity):
		return

	if budget.consume_attack(runtime.get_entity_id(entity)):
		_broadcast_snapshot()


func notify_entity_interacted(entity: Node) -> void:
	if not _is_authority() or state != STATE_PLAYER_TURN or not _is_active_entity(entity):
		return
	if budget.consume_interaction(runtime.get_entity_id(entity)):
		_broadcast_snapshot()


func notify_entity_action_finished(entity: Node, completed_generation: int = 0) -> void:
	if _is_authority() and state == STATE_WORLD_TURN and _is_world_turn_entity(entity):
		_mark_world_entity_action_finished(entity, completed_generation)
		return

	if not _is_authority() or not _is_active_entity(entity):
		return

	_finish_pending_turn_if_ready()


func notify_entity_removed(entity: Node) -> void:
	if not _is_authority() or entity == null:
		return

	var entity_id: String = runtime.get_entity_id(entity)
	if entity_id.is_empty() or not pending_world_entity_ids.has(entity_id):
		return

	pending_world_entity_ids.erase(entity_id)
	behavior_deadline_by_entity_id.erase(entity_id)
	if not is_starting_world_behaviors:
		_finish_world_turn_if_ready()


func request_end_turn(entity: Node = null) -> void:
	var representative: PlayerCharacter = entity as PlayerCharacter
	if representative == null:
		representative = _get_local_squad_representative()
	if not can_end_turn(representative) or not runtime.is_action_stream_idle():
		return

	var request_id: int = runtime.create_action_request_id()
	if GameSession.is_multiplayer() and not GameSession.is_host():
		NetworkManager.turns.request_turn_end(GameSession.get_match_id(), turn_revision, request_id)
		return

	runtime.enqueue_player_action(
		WorldActionRecord.ActionType.END_PLAYER_TURN,
		representative,
		{},
		request_id,
		0
	)


func can_end_turn(entity: Node) -> bool:
	return state == STATE_PLAYER_TURN and _is_active_entity(entity)


func execute_set_turn_mode_action(is_enabled: bool) -> bool:
	if is_enabled:
		_reset_turn_state()
		_advance_turn_revision()
		state = STATE_PLAYER_TURN
		round_number = 1
		_build_player_turn_order()
		turn_mode_changed.emit(true)
		ConsoleOutput.print_console("Turn mode enabled", runtime)
		_broadcast_snapshot(EVENT_TURN_MODE_ENABLED)
		_start_round()
		return true

	_reset_turn_state()
	_advance_turn_revision()
	turn_mode_changed.emit(false)
	ConsoleOutput.print_console("Free mode enabled", runtime)
	_broadcast_snapshot(EVENT_TURN_MODE_DISABLED)
	return true


func execute_player_turn_started_action(entity_id: String) -> bool:
	var player: PlayerCharacter = runtime.get_player_by_entity_id(entity_id)
	if player == null or not turn_order.has(player.owner_player_id):
		return false
	_start_player_turn(player.owner_player_id)
	return true


func execute_end_turn_action(entity: Node) -> bool:
	if not can_end_turn(entity):
		return false
	_finish_player_turn()
	return true


func execute_player_turn_skipped_action(entity_id: String, reason: String) -> bool:
	var player: PlayerCharacter = runtime.get_player_by_entity_id(entity_id)
	if state != STATE_PLAYER_TURN or player == null or player.owner_player_id != active_player_id:
		return false
	_skip_active_player(reason)
	return true


func execute_world_turn_started_action() -> bool:
	if not is_inside_tree():
		return false
	var scene_tree: SceneTree = get_tree()
	_start_world_turn()
	var deadline_msec: int = Time.get_ticks_msec() + WORLD_TURN_WATCHDOG_MSEC
	while not was_world_turn_completion_emitted and Time.get_ticks_msec() < deadline_msec:
		_cancel_timed_out_world_behaviors()
		await scene_tree.process_frame
		if not is_inside_tree():
			return false
	if not was_world_turn_completion_emitted:
		watchdog_activation_count += 1
		for entity_id_value: Variant in pending_world_entity_ids.keys():
			var entity: NonPlayerEntity = runtime.get_entity_by_id(str(entity_id_value)) as NonPlayerEntity
			if entity != null:
				entity.cancel_behavior()
		pending_world_entity_ids.clear()
		_emit_world_turn_behaviors_finished()
	runtime.enqueue_system_action(WorldActionRecord.ActionType.WORLD_TURN_ENDED)
	return true


func execute_world_turn_ended_action() -> bool:
	if state != STATE_WORLD_TURN or not was_world_turn_completion_emitted:
		return false
	_finish_world_turn()
	return true


func apply_remote_snapshot(snapshot: Dictionary) -> void:
	if not is_valid_remote_snapshot(snapshot):
		return
	state = str(snapshot.get("state", STATE_FREE))
	round_number = int(snapshot.get("round_number", 0))
	turn_revision = int(snapshot.get("turn_revision", turn_revision))
	world_turn_generation = int(snapshot.get("world_turn_generation", world_turn_generation))
	active_player_id = str(snapshot.get("active_player_id", ""))
	budget.apply_snapshot(snapshot)
	current_turn_index = int(snapshot.get("current_turn_index", -1))
	pending_end_turn = bool(snapshot.get("pending_end_turn", false))

	turn_order.clear()
	for player_id_value: Variant in snapshot.get("turn_order", []):
		turn_order.append(str(player_id_value))

	var event_payload: Dictionary = {}
	var snapshot_payload: Variant = snapshot.get("event_payload", {})
	if snapshot_payload is Dictionary:
		event_payload = snapshot_payload

	var event: String = str(snapshot.get("event", EVENT_NONE))
	_print_remote_turn_event(event, event_payload)
	if event == EVENT_TURN_MODE_ENABLED:
		turn_mode_changed.emit(true)
	elif event == EVENT_TURN_MODE_DISABLED:
		turn_mode_changed.emit(false)
	elif event == EVENT_PLAYER_TURN_STARTED:
		player_turn_started.emit(active_player_id)
	elif event == EVENT_ROUND_STARTED:
		round_started.emit(round_number)
	turn_state_changed.emit()


func is_valid_remote_snapshot(snapshot: Dictionary) -> bool:
	var snapshot_state: String = str(snapshot.get("state", ""))
	var snapshot_active_player_id: String = str(snapshot.get("active_player_id", ""))
	var turn_order_value: Variant = snapshot.get("turn_order")
	var event_payload_value: Variant = snapshot.get("event_payload", {})
	if (
		snapshot_state not in [STATE_FREE, STATE_PLAYER_TURN, STATE_WORLD_TURN]
		or int(snapshot.get("round_number", -1)) < 0
		or int(snapshot.get("turn_revision", -1)) < 0
		or int(snapshot.get("world_turn_generation", -1)) < 0
		or not NetworkProtocol.is_valid_optional_identifier(str(snapshot.get("active_player_id", "")))
		or not (turn_order_value is Array)
		or (turn_order_value as Array).size() > NetworkProtocol.MAX_ROSTER_SIZE
		or not (event_payload_value is Dictionary)
		or not NetworkProtocol.is_valid_bounded_text(str(snapshot.get("event", "")))
	):
		return false
	var seen_player_ids: Dictionary[String, bool] = {}
	for player_id_value: Variant in turn_order_value as Array:
		var player_id: String = str(player_id_value)
		if not NetworkProtocol.is_valid_identifier(player_id) or seen_player_ids.has(player_id):
			return false
		seen_player_ids[player_id] = true
	var valid_entity_ids: Array[String] = []
	if snapshot_state == STATE_PLAYER_TURN:
		if snapshot_active_player_id.is_empty() or not seen_player_ids.has(snapshot_active_player_id):
			return false
		for player: PlayerCharacter in runtime.get_squad_members(snapshot_active_player_id):
			valid_entity_ids.append(player.entity_id)
	elif not snapshot_active_player_id.is_empty():
		return false
	if not budget.is_valid_snapshot(snapshot, valid_entity_ids):
		return false
	var current_index: int = int(snapshot.get("current_turn_index", -1))
	return current_index >= -1 and current_index < maxi((turn_order_value as Array).size(), 1)


func create_action_stream_snapshot() -> Dictionary:
	return _make_snapshot()


func get_watchdog_activation_count() -> int:
	return watchdog_activation_count


func _start_round() -> void:
	if turn_order.is_empty() or not _has_available_turn_player():
		_broadcast_snapshot()
		return

	current_turn_index = -1
	var log_line: String = "Round %d started" % round_number
	ConsoleOutput.print_console(log_line, runtime)
	round_started.emit(round_number)
	_broadcast_snapshot(EVENT_ROUND_STARTED)
	_start_next_player_turn()


func _start_next_player_turn() -> void:
	current_turn_index += 1

	while current_turn_index < turn_order.size():
		var player_id: String = turn_order[current_turn_index]
		var members: Array[PlayerCharacter] = runtime.get_squad_members(player_id)
		var skip_reason: String = _get_player_skip_reason(player_id, members)
		if not skip_reason.is_empty():
			_advance_turn_revision()
			_log_player_skipped(player_id, skip_reason)
			current_turn_index += 1
			continue

		var representative: PlayerCharacter = members[0]
		runtime.enqueue_system_action(WorldActionRecord.ActionType.PLAYER_TURN_STARTED, {
			"actor_entity_id": representative.entity_id,
		})
		return

	runtime.enqueue_system_action(WorldActionRecord.ActionType.WORLD_TURN_STARTED)


func _start_player_turn(player_id: String) -> void:
	var members: Array[PlayerCharacter] = runtime.get_squad_members(player_id)
	var available_entity_ids: Array[String] = []
	for member: PlayerCharacter in members:
		if member.health <= 0:
			member.respawn()
		if member.health > 0 and member.visible:
			available_entity_ids.append(member.entity_id)
	_advance_turn_revision()
	state = STATE_PLAYER_TURN
	active_player_id = player_id
	budget.begin_turn(available_entity_ids)
	pending_end_turn = false
	player_turn_started.emit(active_player_id)
	if available_entity_ids.is_empty():
		if members.is_empty():
			_skip_active_player("missing")
			return
		runtime.enqueue_system_action(WorldActionRecord.ActionType.PLAYER_TURN_SKIPPED, {
			"actor_entity_id": members[0].entity_id,
			"reason": "respawn_pending",
		})
		return

	var start_log: String = "Squad turn started: %s" % active_player_id
	var resources_log: String = "Available per member: steps %d, attack/interactions %d" % [
		MAX_STEPS_PER_MEMBER,
		MAX_ATTACKS_PER_TURN,
	]
	ConsoleOutput.print_console(start_log, runtime)
	ConsoleOutput.print_console(resources_log, runtime)
	_broadcast_snapshot(EVENT_PLAYER_TURN_STARTED)


func _start_world_turn() -> void:
	_advance_turn_revision()
	world_turn_generation += 1
	state = STATE_WORLD_TURN
	active_player_id = ""
	budget.reset()
	pending_end_turn = false
	pending_world_entity_ids.clear()
	behavior_deadline_by_entity_id.clear()
	was_world_turn_completion_emitted = false

	var start_log: String = "World turn started"
	ConsoleOutput.print_console(start_log, runtime)
	_broadcast_snapshot(EVENT_WORLD_TURN_STARTED)
	_start_world_behaviors()


func _start_world_behaviors() -> void:
	if not _is_authority():
		return

	var world_entities: Array[NonPlayerEntity] = _get_world_turn_entities()
	world_entities.sort_custom(func(first: NonPlayerEntity, second: NonPlayerEntity) -> bool:
		return runtime.get_entity_id(first) < runtime.get_entity_id(second)
	)
	var ready_entities: Array[NonPlayerEntity] = []
	for entity in world_entities:
		var entity_id: String = runtime.get_entity_id(entity)
		if entity_id.is_empty():
			continue

		ready_entities.append(entity)
		pending_world_entity_ids[entity_id] = world_turn_generation
		behavior_deadline_by_entity_id[entity_id] = Time.get_ticks_msec() + NPC_BEHAVIOR_WATCHDOG_MSEC
		entity.begin_behavior_generation(world_turn_generation)

	if pending_world_entity_ids.is_empty():
		_emit_world_turn_behaviors_finished()
		return

	is_starting_world_behaviors = true
	for entity in ready_entities:
		if _is_world_turn_entity_available(entity):
			(entity as NonPlayerEntity).behavior()
		else:
			_mark_world_entity_action_finished(entity, world_turn_generation)

	is_starting_world_behaviors = false
	_finish_world_turn_if_ready()


func _finish_world_turn() -> void:
	_advance_turn_revision()
	pending_world_entity_ids.clear()
	behavior_deadline_by_entity_id.clear()
	pending_remote_snapshots.clear()
	is_starting_world_behaviors = false
	was_world_turn_completion_emitted = false
	var finish_log: String = "World turn ended"
	ConsoleOutput.print_console(finish_log, runtime)
	_broadcast_snapshot(EVENT_WORLD_TURN_ENDED)
	round_number += 1
	state = STATE_PLAYER_TURN
	_start_round()


func _mark_world_entity_action_finished(entity: Node, completed_generation: int) -> void:
	if entity == null:
		return

	var entity_id: String = runtime.get_entity_id(entity)
	if entity_id.is_empty():
		return
	if int(pending_world_entity_ids.get(entity_id, -1)) != completed_generation:
		return

	pending_world_entity_ids.erase(entity_id)
	behavior_deadline_by_entity_id.erase(entity_id)
	if not is_starting_world_behaviors:
		_finish_world_turn_if_ready()


func _finish_world_turn_if_ready() -> void:
	if state == STATE_WORLD_TURN and pending_world_entity_ids.is_empty():
		_emit_world_turn_behaviors_finished()


func _cancel_timed_out_world_behaviors() -> void:
	var now_msec: int = Time.get_ticks_msec()
	for entity_id: String in behavior_deadline_by_entity_id.keys():
		if now_msec < int(behavior_deadline_by_entity_id[entity_id]):
			continue
		var entity: NonPlayerEntity = runtime.get_entity_by_id(entity_id) as NonPlayerEntity
		if entity != null:
			entity.cancel_behavior()
		watchdog_activation_count += 1
		pending_world_entity_ids.erase(entity_id)
		behavior_deadline_by_entity_id.erase(entity_id)
	_finish_world_turn_if_ready()


func _emit_world_turn_behaviors_finished() -> void:
	if was_world_turn_completion_emitted:
		return
	was_world_turn_completion_emitted = true
	world_turn_behaviors_finished.emit()


func _finish_pending_turn_if_ready() -> void:
	if not pending_end_turn:
		return

	if not _is_active_squad_busy():
		_finish_player_turn()


func _finish_player_turn() -> void:
	_advance_turn_revision()
	var finished_player_id: String = active_player_id
	var log_line: String = "Squad turn ended: %s" % finished_player_id
	ConsoleOutput.print_console(log_line, runtime)
	active_player_id = ""
	budget.reset()
	pending_end_turn = false
	_broadcast_snapshot(EVENT_PLAYER_TURN_ENDED, {"player_id": finished_player_id})
	_start_next_player_turn()


func _skip_active_player(reason: String) -> void:
	_advance_turn_revision()
	_log_player_skipped(active_player_id, reason)
	active_player_id = ""
	budget.reset()
	pending_end_turn = false
	_start_next_player_turn()


func _log_player_skipped(player_id: String, reason: String) -> void:
	var log_line: String = "Squad turn skipped: %s (%s)" % [player_id, reason]
	ConsoleOutput.print_console(log_line, runtime)
	_broadcast_snapshot(EVENT_PLAYER_TURN_SKIPPED, {
		"player_id": player_id,
		"reason": reason,
	})


func _build_player_turn_order() -> void:
	turn_order.clear()
	turn_order_steam_ids.clear()

	for player_info: Dictionary in GameSession.get_players():
		var player_id: String = str(player_info.get("player_id", ""))
		var steam_id: int = int(player_info.get("steam_id", 0))
		if player_id.is_empty() or turn_order.has(player_id):
			continue
		turn_order.append(player_id)
		turn_order_steam_ids[player_id] = steam_id


func _get_player_skip_reason(player_id: String, members: Array[PlayerCharacter]) -> String:
	var steam_id: int = int(turn_order_steam_ids.get(player_id, 0))
	if GameSession.is_multiplayer() and steam_id != 0 and not runtime.is_player_connected(steam_id):
		return "disconnected"

	if members.is_empty():
		return "missing"

	return ""


func _has_available_turn_player() -> bool:
	for player_id: String in turn_order:
		if _get_player_skip_reason(player_id, runtime.get_squad_members(player_id)).is_empty():
			return true

	return false


func _get_active_entity() -> Node:
	if active_player_id.is_empty():
		return null
	var members: Array[PlayerCharacter] = runtime.get_squad_members(active_player_id)
	return null if members.is_empty() else members[0]


func _is_active_entity(entity: Node) -> bool:
	var player: PlayerCharacter = entity as PlayerCharacter
	if player == null or active_player_id.is_empty():
		return false
	return player.owner_player_id == active_player_id


func _is_active_squad_busy() -> bool:
	for member: PlayerCharacter in runtime.get_squad_members(active_player_id):
		if _is_entity_busy(member):
			return true
	return false


func _resolve_budget_entity_id(entity_id: String) -> String:
	if not entity_id.is_empty():
		return entity_id
	var selected: PlayerCharacter = runtime.get_selected_local_character()
	return "" if selected == null else selected.entity_id


func _get_local_squad_representative() -> PlayerCharacter:
	var selected: PlayerCharacter = runtime.get_selected_local_character()
	if selected != null:
		return selected
	var members: Array[PlayerCharacter] = runtime.get_local_squad_members()
	return null if members.is_empty() else members[0]


func _is_entity_busy(entity: Node) -> bool:
	if entity == null:
		return false

	var moving: Variant = entity.get("is_moving")
	var attacking: Variant = entity.get("is_attacking")
	return bool(moving) or bool(attacking) or runtime.is_entity_casting(entity)


func _get_entity_display_name(entity: Node) -> String:
	return runtime.get_entity_display_name(entity)


func _print_remote_turn_event(event: String, event_payload: Dictionary) -> void:
	match event:
		EVENT_TURN_MODE_ENABLED:
			ConsoleOutput.print_console("Turn mode enabled", runtime)
		EVENT_TURN_MODE_DISABLED:
			ConsoleOutput.print_console("Turn mode disabled", runtime)
		EVENT_STEPS_CHANGED:
			ConsoleOutput.print_console("Squad member steps updated", runtime)
		EVENT_ROUND_STARTED:
			ConsoleOutput.print_console("Round %d started" % round_number, runtime)
		EVENT_PLAYER_TURN_STARTED:
			ConsoleOutput.print_console("Squad turn started: %s" % active_player_id, runtime)
			ConsoleOutput.print_console("Available steps per member: %d" % MAX_STEPS_PER_MEMBER, runtime)
		EVENT_WORLD_TURN_STARTED:
			ConsoleOutput.print_console("World turn started", runtime)
		EVENT_WORLD_TURN_ENDED:
			ConsoleOutput.print_console("World turn ended", runtime)
		EVENT_PLAYER_TURN_ENDED:
			ConsoleOutput.print_console("Squad turn ended: %s" % str(event_payload.get("player_id", "")), runtime)
		EVENT_PLAYER_TURN_SKIPPED:
			var skipped_player_id: String = str(event_payload.get("player_id", ""))
			var reason: String = str(event_payload.get("reason", "unknown"))
			ConsoleOutput.print_console("Squad turn skipped: %s (%s)" % [
				skipped_player_id,
				reason,
			], runtime)


func _make_snapshot(event: String = EVENT_NONE, event_payload: Dictionary = {}) -> Dictionary:
	var snapshot: Dictionary = {
		"state": state,
		"round_number": round_number,
		"turn_revision": turn_revision,
		"world_turn_generation": world_turn_generation,
		"active_player_id": active_player_id,
		"current_turn_index": current_turn_index,
		"pending_end_turn": pending_end_turn,
		"turn_order": turn_order.duplicate(),
		"event": event,
		"event_payload": event_payload,
	}
	snapshot.merge(budget.create_snapshot(), true)
	return snapshot


func _broadcast_snapshot(event: String = EVENT_NONE, event_payload: Dictionary = {}) -> void:
	turn_state_changed.emit()
	if GameSession.is_multiplayer() and GameSession.is_host():
		NetworkManager.turns.broadcast_turn_state(
			_make_snapshot(event, event_payload),
			runtime.get_current_action_sequence_id()
		)


func _reset_turn_state() -> void:
	state = STATE_FREE
	round_number = 0
	turn_order.clear()
	turn_order_steam_ids.clear()
	current_turn_index = -1
	active_player_id = ""
	budget.reset()
	pending_end_turn = false
	pending_world_entity_ids.clear()
	behavior_deadline_by_entity_id.clear()
	is_starting_world_behaviors = false
	was_world_turn_completion_emitted = false
	turn_state_changed.emit()


func _on_session_cleared() -> void:
	_reset_turn_state()


func _advance_turn_revision() -> void:
	turn_revision += 1


func _can_control_turn_mode() -> bool:
	return not GameSession.is_multiplayer() or GameSession.is_host()


func _is_authority() -> bool:
	return not GameSession.is_multiplayer() or GameSession.is_host()


func _get_world_turn_entities() -> Array[NonPlayerEntity]:
	var entities: Array[NonPlayerEntity] = []
	_collect_world_turn_entities(level, entities)
	return entities


func _collect_world_turn_entities(node: Node, entities: Array[NonPlayerEntity]) -> void:
	for child in node.get_children():
		if _is_world_turn_entity_available(child):
			entities.append(child as NonPlayerEntity)

		_collect_world_turn_entities(child, entities)


func _is_world_turn_entity(entity: Node) -> bool:
	if entity == null or entity.get("entity_type") == null:
		return false

	return entity is NonPlayerEntity and int(entity.get("entity_type")) != Entity.EntityType.CHARACTER


func _is_world_turn_entity_available(entity: Node) -> bool:
	if not _is_world_turn_entity(entity):
		return false

	if entity.get("health") != null and int(entity.get("health")) <= 0:
		return false

	return true


func _connect_network_signals() -> void:
	if not NetworkManager.turns.turn_state_received.is_connected(_on_turn_state_received):
		NetworkManager.turns.turn_state_received.connect(_on_turn_state_received)

	if not NetworkManager.turns.turn_end_requested.is_connected(_on_turn_end_requested):
		NetworkManager.turns.turn_end_requested.connect(_on_turn_end_requested)



func _disconnect_network_signals() -> void:
	if NetworkManager.turns.turn_state_received.is_connected(_on_turn_state_received):
		NetworkManager.turns.turn_state_received.disconnect(_on_turn_state_received)

	if NetworkManager.turns.turn_end_requested.is_connected(_on_turn_end_requested):
		NetworkManager.turns.turn_end_requested.disconnect(_on_turn_end_requested)



func _on_turn_state_received(snapshot: Dictionary, sequence_id: int) -> void:
	if GameSession.is_host():
		return
	if sequence_id > 0:
		runtime.action_stream.receive_auxiliary_profile(sequence_id, "turn_snapshot")
	if sequence_id > 0 and runtime.get_current_action_sequence_id() != sequence_id:
		var expected_sequence_id: int = runtime.get_expected_remote_action_sequence_id()
		if sequence_id < expected_sequence_id:
			return
		if (
			sequence_id - expected_sequence_id > NetworkProtocol.MAX_FUTURE_SEQUENCE_DISTANCE
			or pending_remote_snapshots.size() >= NetworkProtocol.MAX_BUFFERED_SEQUENCES
		):
			runtime.action_stream.request_runtime_resync(WorldActionStream.REJECTION_SEQUENCE_GAP)
			return
		pending_remote_snapshots[sequence_id] = snapshot.duplicate(true)
		return
	apply_remote_snapshot(snapshot)


func _on_stream_action_started(action: WorldActionRecord) -> void:
	if action != null and pending_remote_snapshots.has(action.sequence_id):
		var snapshot: Dictionary = pending_remote_snapshots[action.sequence_id]
		pending_remote_snapshots.erase(action.sequence_id)
		apply_remote_snapshot(snapshot)


func _on_turn_end_requested(
	match_id: String,
	requested_turn_revision: int,
	request_id: int,
	requester_peer_id: int
) -> void:
	if not _is_authority() or state != STATE_PLAYER_TURN:
		return
	var steam_id: int = 0
	if requester_peer_id > 0:
		steam_id = NetworkManager.peers.get_steam_id_for_peer_id(requester_peer_id)
	else:
		var local_record: Dictionary = GameSession.get_local_player_record()
		steam_id = int(local_record.get("steam_id", 0))
	var members: Array[PlayerCharacter] = runtime.get_squad_members_by_steam_id(steam_id)
	if steam_id == 0 and GameSession.is_singleplayer():
		members = runtime.get_local_squad_members()
	if not members.is_empty():
		runtime.enqueue_player_action(
			WorldActionRecord.ActionType.END_PLAYER_TURN,
			members[0],
			{},
			request_id,
			requester_peer_id,
			requested_turn_revision,
			match_id
		)


func handle_player_disconnected(steam_id: int) -> void:
	if not _is_authority() or state == STATE_FREE:
		return

	var active_members: Array[PlayerCharacter] = runtime.get_squad_members(active_player_id)
	if not active_members.is_empty() and active_members[0].steam_id == steam_id:
		if runtime.action_stream.has_pending_action(
			active_members[0].entity_id,
			WorldActionRecord.ActionType.PLAYER_TURN_SKIPPED
		):
			return
		runtime.enqueue_system_action(WorldActionRecord.ActionType.PLAYER_TURN_SKIPPED, {
			"actor_entity_id": active_members[0].entity_id,
			"reason": "disconnected",
		})
