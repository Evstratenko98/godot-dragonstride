extends "res://scenes/entities/non_player_entity/non_player_entity.gd"

const WARRIOR_MAX_HEALTH := 50
const WARRIOR_DAMAGE := 10
const WARRIOR_MOVE_TIME := 0.6
const STATE_PASSIVE := "passive"
const STATE_ACTIVE := "active"
const REASON_NONE := ""
const REASON_TARGET_DEFEATED := "target defeated"
const REASON_TARGET_MISSING := "target missing"
const REASON_TARGET_UNREACHABLE := "target unreachable"
const MAX_STEPS_PER_TURN := 3
const MAX_ATTACKS_PER_TURN := 1
const ORTHOGONAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i.RIGHT,
	Vector2i.LEFT,
	Vector2i.DOWN,
	Vector2i.UP,
]

var incoming_guard_token := 0
var ai_state := STATE_PASSIVE
var target_entity_id := ""
var attacks_used_this_turn := 0
var is_running_behavior_turn := false
var pending_behavior_attack_target_id := ""
var pending_behavior_attack_was_lethal := false
var remote_action_queue: Array[Dictionary] = []
var is_processing_remote_actions := false
var is_replaying_remote_action := false


func _ready() -> void:
	_apply_base_stats()
	super._ready()
	entity_type = EntityType.ENEMY
	if entity_name.is_empty():
		entity_name = "Warrior"


func start(
	start_position: Vector2,
	new_entity_id := "",
	new_entity_name := "Warrior"
) -> void:
	_apply_base_stats()
	start_non_player_entity(start_position, new_entity_id, new_entity_name, EntityType.ENEMY)


func behavior() -> void:
	if not _is_turn_mode_enabled() or not _is_ai_authority():
		_finish_behavior()
		return

	if not can_act():
		_finish_behavior()
		return

	_sync_current_cell()
	attacks_used_this_turn = 0
	is_running_behavior_turn = true

	if ai_state == STATE_PASSIVE:
		consider_character_triggers(_get_registered_characters())

	if ai_state != STATE_ACTIVE:
		_end_behavior_turn()
		return

	var target := _get_current_target()
	if not _is_valid_hunt_target(target):
		_set_ai_state(STATE_PASSIVE, "", _get_invalid_target_reason(target))
		_end_behavior_turn()
		return

	if _can_attack_target(target):
		is_running_behavior_turn = false
		var did_initial_attack := await _perform_behavior_attack(target)
		if did_initial_attack:
			return
		_finish_behavior()
		return

	var attack_cells := _get_attack_goal_cells(target)
	if not _has_terrain_path_to_any(attack_cells):
		_set_ai_state(STATE_PASSIVE, "", REASON_TARGET_UNREACHABLE)
		_end_behavior_turn()
		return

	var path := _find_path_to_any(attack_cells, true)
	if path.is_empty():
		_end_behavior_turn()
		return

	var steps_to_take := mini(MAX_STEPS_PER_TURN, path.size())
	for i in range(steps_to_take):
		target = _get_current_target()
		if not _is_valid_hunt_target(target):
			_set_ai_state(STATE_PASSIVE, "", _get_invalid_target_reason(target))
			_end_behavior_turn()
			return

		if _can_attack_target(target):
			is_running_behavior_turn = false
			var did_pre_move_attack := await _perform_behavior_attack(target)
			if did_pre_move_attack:
				return
			_finish_behavior()
			return

		var next_cell: Vector2i = path[i]
		var direction: Vector2i = next_cell - current_cell
		if not request_move(direction):
			_end_behavior_turn()
			return

		await _wait_until_ready_for_next_action()
		_sync_current_cell()

		target = _get_current_target()
		if not _is_valid_hunt_target(target):
			_set_ai_state(STATE_PASSIVE, "", _get_invalid_target_reason(target))
			_end_behavior_turn()
			return

		if _can_attack_target(target):
			is_running_behavior_turn = false
			var did_post_move_attack := await _perform_behavior_attack(target)
			if did_post_move_attack:
				return
			_finish_behavior()
			return

	_end_behavior_turn()


func consider_character_triggers(characters: Array[Node]) -> void:
	if not _is_ai_authority() or not _is_turn_mode_enabled():
		return

	var selected_character: Node = null
	for character in characters:
		if _can_trigger_on_character(character):
			selected_character = character

	if selected_character != null:
		_set_ai_state(STATE_ACTIVE, _get_entity_id(selected_character), REASON_NONE)


func consider_character_trigger(character: Node) -> void:
	if not _is_ai_authority() or not _is_turn_mode_enabled():
		return

	if not _can_trigger_on_character(character):
		return

	_set_ai_state(STATE_ACTIVE, _get_entity_id(character), REASON_NONE)


func apply_remote_ai_state(new_state: String, new_target_entity_id: String, reason: String) -> void:
	if new_state != STATE_PASSIVE and new_state != STATE_ACTIVE:
		return

	_set_ai_state(new_state, new_target_entity_id, reason, false)


func play_remote_move(from_cell: Vector2i, target_cell: Vector2i) -> void:
	remote_action_queue.append({
		"type": "move",
		"from_cell": from_cell,
		"target_cell": target_cell,
	})
	_process_remote_action_queue()


func play_remote_attack(target_cell: Vector2i, should_apply := true) -> void:
	remote_action_queue.append({
		"type": "attack",
		"target_cell": target_cell,
		"should_apply": should_apply,
	})
	_process_remote_action_queue()


func play_incoming_attack_guard(duration: float) -> void:
	if duration <= 0.0 or is_moving or is_attacking or health <= 0:
		return

	incoming_guard_token += 1
	var guard_token := incoming_guard_token
	if view != null and view.has_method("play_guard"):
		view.play_guard()

	await get_tree().create_timer(duration).timeout

	if incoming_guard_token != guard_token:
		return

	if health <= 0 or is_moving or is_attacking:
		return

	if view != null and view.has_method("play_idle"):
		view.play_idle()


func _process_remote_action_queue() -> void:
	if is_processing_remote_actions:
		return

	is_processing_remote_actions = true
	while not remote_action_queue.is_empty():
		if is_moving or is_attacking:
			await get_tree().process_frame
			continue

		var action: Dictionary = remote_action_queue.pop_front()
		is_replaying_remote_action = true
		if str(action.get("type", "")) == "move":
			await _play_remote_move_now(action)
		elif str(action.get("type", "")) == "attack":
			await _play_remote_attack_now(action)
		is_replaying_remote_action = false

	is_processing_remote_actions = false


func _play_remote_move_now(action: Dictionary) -> void:
	if world == null:
		world = _find_world()

	if world == null:
		return

	var from_cell: Vector2i = action.get("from_cell", current_cell)
	var target_cell: Vector2i = action.get("target_cell", current_cell)
	current_cell = from_cell
	global_position = world.cell_to_world(from_cell)
	if world.has_method("reserve_entity_cell") and not world.reserve_entity_cell(self, from_cell, target_cell):
		return

	_move_to_cell(target_cell, false)
	await _wait_until_ready_for_next_action()


func _play_remote_attack_now(action: Dictionary) -> void:
	if world == null:
		world = _find_world()

	if world == null:
		return

	current_cell = world.world_to_cell(global_position)
	var target_cell: Vector2i = action.get("target_cell", current_cell)
	var should_apply := bool(action.get("should_apply", false))
	request_attack_cell(
		target_cell,
		should_apply,
		false
	)
	await _wait_until_ready_for_next_action()


func _attack_cell(target_cell: Vector2i, direction: Vector2i, should_apply: bool, should_broadcast: bool) -> void:
	var attack_facing_left := _get_facing_left()
	var update_horizontal_facing := direction.x != 0
	if direction == Vector2i.RIGHT:
		attack_facing_left = false
	elif direction == Vector2i.LEFT:
		attack_facing_left = true

	_attack(attack_facing_left, update_horizontal_facing, target_cell, should_apply, should_broadcast)


func _attack(
	attack_facing_left: bool,
	update_horizontal_facing: bool,
	target_cell: Vector2i,
	should_apply: bool,
	should_broadcast: bool
) -> void:
	is_attacking = true
	incoming_guard_token += 1
	attack_target_cell = target_cell
	_play_target_incoming_attack_guard(target_cell, _get_attack_duration())

	if view != null and view.has_method("play_attack"):
		await view.play_attack(attack_facing_left, update_horizontal_facing)

	if should_apply:
		_apply_attack_to_world(should_broadcast)

	if pending_behavior_attack_was_lethal:
		_set_ai_state(STATE_PASSIVE, "", REASON_TARGET_DEFEATED)

	pending_behavior_attack_target_id = ""
	pending_behavior_attack_was_lethal = false
	is_attacking = false
	if world != null and world.has_method("notify_entity_action_finished_in_turn"):
		world.notify_entity_action_finished_in_turn(self)

	if view != null and view.has_method("play_idle"):
		view.play_idle()


func _perform_behavior_attack(target: Node) -> bool:
	if attacks_used_this_turn >= MAX_ATTACKS_PER_TURN:
		return false

	if not _can_attack_target(target):
		return false

	attacks_used_this_turn += 1
	pending_behavior_attack_target_id = _get_entity_id(target)
	pending_behavior_attack_was_lethal = _will_attack_defeat_target(target)

	var target_cell: Vector2i = target.get("current_cell")
	var direction: Vector2i = _get_attack_direction_to_cell(target_cell)
	var attack_facing_left := _get_facing_left()
	var update_horizontal_facing := direction.x != 0
	if direction == Vector2i.RIGHT:
		attack_facing_left = false
	elif direction == Vector2i.LEFT:
		attack_facing_left = true

	await _attack(attack_facing_left, update_horizontal_facing, target_cell, true, true)
	return true


func _on_move_started(target_cell: Vector2i) -> void:
	incoming_guard_token += 1
	super._on_move_started(target_cell)


func _on_move_stopped() -> void:
	if view != null and view.has_method("play_idle"):
		view.play_idle()

	if is_running_behavior_turn or is_replaying_remote_action:
		return

	_finish_behavior()


func _end_behavior_turn() -> void:
	is_running_behavior_turn = false
	_finish_behavior()


func _wait_until_ready_for_next_action() -> void:
	while is_moving or is_attacking:
		await get_tree().process_frame


func _can_trigger_on_character(character: Node) -> bool:
	if not _is_valid_hunt_target(character):
		return false

	_sync_current_cell()
	var character_cell: Vector2i = character.get("current_cell")
	var delta: Vector2i = character_cell - current_cell
	return maxi(absi(delta.x), absi(delta.y)) == 1


func _is_valid_hunt_target(target: Node) -> bool:
	return target != null and target.get("entity_type") != null and int(target.get("entity_type")) == EntityType.CHARACTER and _is_character_alive(target)


func _is_character_alive(character: Node) -> bool:
	return character != null and character.get("health") != null and int(character.get("health")) > 0


func _get_invalid_target_reason(target: Node) -> String:
	if target == null:
		return REASON_TARGET_MISSING

	return REASON_TARGET_DEFEATED


func _get_current_target() -> Node:
	if target_entity_id.is_empty() or world == null or not world.has_method("get_entity_by_id"):
		return null

	return world.get_entity_by_id(target_entity_id)


func _can_attack_target(target: Node) -> bool:
	if not _is_valid_hunt_target(target):
		return false

	return can_attack_cell(target.get("current_cell"))


func _get_attack_goal_cells(target: Node) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if target == null or target.get("current_cell") == null:
		return cells

	var target_cell: Vector2i = target.get("current_cell")
	for direction in ORTHOGONAL_DIRECTIONS:
		var attack_cell: Vector2i = target_cell + direction
		if world.is_cell_inside(attack_cell) and world.is_cell_walkable(attack_cell):
			cells.append(attack_cell)

	return cells


func _has_terrain_path_to_any(goal_cells: Array[Vector2i]) -> bool:
	return not _find_path_to_any(goal_cells, false).is_empty() or goal_cells.has(current_cell)


func _find_path_to_any(goal_cells: Array[Vector2i], respect_current_occupancy: bool) -> Array[Vector2i]:
	var empty_path: Array[Vector2i] = []
	if world == null or goal_cells.is_empty():
		return empty_path

	var goals := {}
	for goal_cell in goal_cells:
		goals[goal_cell] = true

	if goals.has(current_cell):
		return empty_path

	var frontier: Array[Vector2i] = [current_cell]
	var came_from := {}
	came_from[current_cell] = current_cell

	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_front()
		for direction in ORTHOGONAL_DIRECTIONS:
			var next_cell: Vector2i = cell + direction
			if came_from.has(next_cell):
				continue

			if not _can_path_enter_cell(next_cell, respect_current_occupancy):
				continue

			came_from[next_cell] = cell
			if goals.has(next_cell):
				return _reconstruct_path(came_from, current_cell, next_cell)

			frontier.append(next_cell)

	return empty_path


func _can_path_enter_cell(cell: Vector2i, respect_current_occupancy: bool) -> bool:
	if not world.is_cell_inside(cell) or not world.is_cell_walkable(cell):
		return false

	if world.has_method("get_object_at_cell") and world.get_object_at_cell(cell) != null:
		return false

	if respect_current_occupancy:
		return world.can_enter_cell(cell, self)

	return true


func _reconstruct_path(came_from: Dictionary, start_cell: Vector2i, end_cell: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var cell: Vector2i = end_cell
	while cell != start_cell:
		path.push_front(cell)
		cell = came_from[cell]

	return path


func _set_ai_state(new_state: String, new_target_entity_id: String, reason := REASON_NONE, should_broadcast := true) -> void:
	if ai_state == new_state and target_entity_id == new_target_entity_id:
		return

	var previous_state := ai_state
	var previous_target_entity_id := target_entity_id
	ai_state = new_state
	target_entity_id = new_target_entity_id
	_print_ai_state_log(previous_state, previous_target_entity_id, reason)

	if should_broadcast and _is_ai_authority() and GameSession.is_multiplayer() and not entity_id.is_empty():
		NetworkManager.broadcast_entity_ai_state(entity_id, ai_state, target_entity_id, reason)


func _print_ai_state_log(previous_state: String, previous_target_entity_id: String, reason: String) -> void:
	if world == null:
		return

	if previous_state != STATE_ACTIVE and ai_state == STATE_ACTIVE:
		_print_ai_log("%s became active and targets %s." % [get_display_name(), _get_target_display_name(target_entity_id)])
		return

	if previous_state == STATE_ACTIVE and ai_state == STATE_ACTIVE and previous_target_entity_id != target_entity_id:
		_print_ai_log("%s switched target from %s to %s." % [
			get_display_name(),
			_get_target_display_name(previous_target_entity_id),
			_get_target_display_name(target_entity_id),
		])
		return

	if previous_state == STATE_ACTIVE and ai_state == STATE_PASSIVE:
		_print_ai_log("%s became passive: %s." % [get_display_name(), _get_passive_reason_text(reason)])


func _print_ai_log(text: String) -> void:
	ConsoleOutput.print_console(text, world)


func _get_target_display_name(id: String) -> String:
	if id.is_empty():
		return "none"

	if world != null and world.has_method("get_entity_by_id") and world.has_method("get_entity_display_name"):
		var entity: Node = world.get_entity_by_id(id)
		if entity != null:
			return world.get_entity_display_name(entity)

	return id


func _get_passive_reason_text(reason: String) -> String:
	if reason.is_empty():
		return "no target"

	return reason


func _will_attack_defeat_target(target: Node) -> bool:
	if target == null or target.get("health") == null:
		return false

	return int(target.get("health")) > 0 and int(target.get("health")) <= damage


func _get_registered_characters() -> Array[Node]:
	var characters: Array[Node] = []
	if world == null or not world.has_method("get_registered_entities"):
		return characters

	for entity in world.get_registered_entities():
		if entity is Node and entity.get("entity_type") != null and int(entity.get("entity_type")) == EntityType.CHARACTER:
			characters.append(entity)

	characters.sort_custom(func(a: Node, b: Node) -> bool:
		return _get_entity_id(a) < _get_entity_id(b)
	)
	return characters


func _get_entity_id(entity: Node) -> String:
	if entity == null:
		return ""

	if world != null and world.has_method("get_entity_id"):
		return world.get_entity_id(entity)

	if entity.get("entity_id") != null:
		return str(entity.get("entity_id"))

	return ""


func _sync_current_cell() -> void:
	if world == null:
		world = _find_world()

	if world != null and world.has_method("world_to_cell"):
		current_cell = world.world_to_cell(global_position)


func _is_turn_mode_enabled() -> bool:
	return world != null and world.has_method("is_turn_mode_enabled") and world.is_turn_mode_enabled()


func _is_ai_authority() -> bool:
	return not GameSession.is_multiplayer() or GameSession.is_host()


func _get_attack_duration() -> float:
	if view != null and view.has_method("get_attack_duration"):
		return float(view.get_attack_duration())

	return 0.0


func _get_facing_left() -> bool:
	if view != null and view.has_method("get_facing_left"):
		return bool(view.get_facing_left())

	return false


func _apply_base_stats() -> void:
	max_health = WARRIOR_MAX_HEALTH
	health = mini(health, max_health) if health > 0 else max_health
	damage = WARRIOR_DAMAGE
	move_time = WARRIOR_MOVE_TIME
	entity_type = EntityType.ENEMY
