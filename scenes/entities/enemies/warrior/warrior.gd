class_name Warrior
extends "res://scenes/entities/non_player_entity/non_player_entity.gd"

const WARRIOR_MAX_HEALTH := 50
const WARRIOR_DAMAGE := 10
const WARRIOR_MOVE_TIME := 0.6
const DEATH_DROP_TYPE := "precision_stone"
const STATE_PASSIVE := "passive"
const STATE_ACTIVE := "active"
const REASON_NONE := ""
const REASON_TARGET_DEFEATED := "target defeated"
const REASON_TARGET_MISSING := "target missing"
const REASON_TARGET_UNREACHABLE := "target unreachable"
const MAX_STEPS_PER_TURN := 3
const MAX_ATTACKS_PER_TURN := 1
var ai_state: String = STATE_PASSIVE
var target_entity_id: String = ""
var attacks_used_this_turn: int = 0
var is_running_behavior_turn: bool = false
var ignored_defeated_character_ids: Dictionary[String, bool] = {}
var pending_behavior_attack_target_id: String = ""
var remote_presentation: WarriorRemotePresentation = WarriorRemotePresentation.new()
var ai_logger: WarriorAiLogger = WarriorAiLogger.new()


func _ready() -> void:
	_apply_base_stats()
	super._ready()
	remote_presentation.configure(self)
	ai_logger.configure(self)
	entity_type = EntityType.ENEMY
	if entity_name.is_empty():
		entity_name = "Warrior"


func start(
	start_position: Vector2,
	new_entity_id: String = "",
	new_entity_name: String = "Warrior"
) -> void:
	_apply_base_stats()
	start_non_player_entity(start_position, new_entity_id, new_entity_name, EntityType.ENEMY)


func spawn_death_drop(death_cell: Vector2i) -> bool:
	if runtime == null:
		return false

	return runtime.spawn_world_object(DEATH_DROP_TYPE, death_cell)


func get_max_movement_steps_per_turn() -> int:
	return MAX_STEPS_PER_TURN


func behavior() -> void:
	var behavior_generation: int = get_behavior_generation()
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

	var target: Node = _get_current_target()
	if not _is_valid_hunt_target(target):
		_set_ai_state(STATE_PASSIVE, "", _get_invalid_target_reason(target))
		_end_behavior_turn()
		return

	if _can_attack_target(target):
		is_running_behavior_turn = false
		var did_initial_attack: bool = await _perform_behavior_attack(target)
		if behavior_generation != get_behavior_generation():
			return
		if did_initial_attack:
			return
		_finish_behavior()
		return

	var attack_cells: Array[Vector2i] = _get_attack_goal_cells(target)
	if not _has_terrain_path_to_any(attack_cells):
		_set_ai_state(STATE_PASSIVE, "", REASON_TARGET_UNREACHABLE)
		_end_behavior_turn()
		return

	var path: Array[Vector2i] = _find_path_to_any(attack_cells, true)
	if path.is_empty():
		_end_behavior_turn()
		return

	var steps_to_take: int = mini(MAX_STEPS_PER_TURN, path.size())
	for i in range(steps_to_take):
		target = _get_current_target()
		if not _is_valid_hunt_target(target):
			_set_ai_state(STATE_PASSIVE, "", _get_invalid_target_reason(target))
			_end_behavior_turn()
			return

		if _can_attack_target(target):
			is_running_behavior_turn = false
			var did_pre_move_attack: bool = await _perform_behavior_attack(target)
			if behavior_generation != get_behavior_generation():
				return
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
		if behavior_generation != get_behavior_generation():
			return
		if not is_running_behavior_turn:
			return
		_sync_current_cell()

		target = _get_current_target()
		if not _is_valid_hunt_target(target):
			_set_ai_state(STATE_PASSIVE, "", _get_invalid_target_reason(target))
			_end_behavior_turn()
			return

		if _can_attack_target(target):
			is_running_behavior_turn = false
			var did_post_move_attack: bool = await _perform_behavior_attack(target)
			if behavior_generation != get_behavior_generation():
				return
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
		if ignored_defeated_character_ids.has(_get_entity_id(character)):
			continue

		if not _can_trigger_on_character(character):
			continue
		if selected_character == null or _is_preferred_target(character, selected_character):
			selected_character = character

	if selected_character != null:
		_set_ai_state(STATE_ACTIVE, _get_entity_id(selected_character), REASON_NONE)


func _is_preferred_target(candidate: Node, current: Node) -> bool:
	var candidate_cell: Vector2i = candidate.get("current_cell")
	var current_target_cell: Vector2i = current.get("current_cell")
	var candidate_distance: int = absi(candidate_cell.x - current_cell.x) + absi(candidate_cell.y - current_cell.y)
	var current_distance: int = absi(current_target_cell.x - current_cell.x) + absi(current_target_cell.y - current_cell.y)
	if candidate_distance != current_distance:
		return candidate_distance < current_distance
	return _get_entity_id(candidate) < _get_entity_id(current)


func consider_character_trigger(character: Node) -> void:
	if not _is_ai_authority() or not _is_turn_mode_enabled():
		return

	ignored_defeated_character_ids.erase(_get_entity_id(character))
	if not _can_trigger_on_character(character):
		return

	_set_ai_state(STATE_ACTIVE, _get_entity_id(character), REASON_NONE)


func consider_character_defeated(character_entity_id: String) -> void:
	if not _is_ai_authority() or character_entity_id.is_empty():
		return

	if ai_state != STATE_ACTIVE or target_entity_id != character_entity_id:
		return

	ignored_defeated_character_ids[character_entity_id] = true
	_set_ai_state(STATE_PASSIVE, "", REASON_TARGET_DEFEATED)


func apply_remote_ai_state(new_state: String, new_target_entity_id: String, reason: String) -> void:
	if new_state != STATE_PASSIVE and new_state != STATE_ACTIVE:
		return

	_set_ai_state(new_state, new_target_entity_id, reason, false)


func play_remote_move(from_cell: Vector2i, target_cell: Vector2i) -> void:
	remote_presentation.enqueue_move(from_cell, target_cell)


func play_remote_attack(target_cell: Vector2i, should_apply: bool = true) -> void:
	remote_presentation.enqueue_attack(target_cell, should_apply)


func play_incoming_attack_guard(duration: float) -> void:
	remote_presentation.play_guard(duration)


func _attack_cell(target_cell: Vector2i, direction: Vector2i, should_apply: bool, should_broadcast: bool) -> void:
	var attack_facing_left: bool = _get_facing_left()
	var update_horizontal_facing: bool = direction.x != 0
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
	var attack_generation: int = get_action_generation()
	remote_presentation.cancel_guard()
	attack_target_cell = target_cell
	var was_action_broadcast: bool = (
		should_apply
		and should_broadcast
		and GameSession.is_multiplayer()
		and _is_ai_authority()
	)
	if was_action_broadcast and runtime != null:
		runtime.broadcast_entity_attack_action(self, target_cell)
	_play_target_incoming_attack_guard(target_cell, _get_attack_duration())

	var warrior_view: WarriorView = view as WarriorView
	if warrior_view != null:
		await warrior_view.play_attack(attack_facing_left, update_horizontal_facing)
	if attack_generation != get_action_generation():
		return

	var can_apply_attack: bool = should_apply
	if not pending_behavior_attack_target_id.is_empty():
		can_apply_attack = (
			ai_state == STATE_ACTIVE
			and target_entity_id == pending_behavior_attack_target_id
		)

	if can_apply_attack:
		_apply_attack_to_world(should_broadcast, not was_action_broadcast)

	pending_behavior_attack_target_id = ""
	is_attacking = false
	if runtime != null:
		runtime.notify_entity_action_finished_in_turn(self, get_behavior_generation())

	if view != null:
		view.play_idle()


func _perform_behavior_attack(target: Node) -> bool:
	if attacks_used_this_turn >= MAX_ATTACKS_PER_TURN:
		return false

	if not _can_attack_target(target):
		return false

	attacks_used_this_turn += 1
	pending_behavior_attack_target_id = _get_entity_id(target)

	var target_cell: Vector2i = target.get("current_cell")
	var direction: Vector2i = _get_attack_direction_to_cell(target_cell)
	var attack_facing_left: bool = _get_facing_left()
	var update_horizontal_facing: bool = direction.x != 0
	if direction == Vector2i.RIGHT:
		attack_facing_left = false
	elif direction == Vector2i.LEFT:
		attack_facing_left = true

	await _attack(attack_facing_left, update_horizontal_facing, target_cell, true, true)
	return true


func cancel_behavior() -> void:
	is_running_behavior_turn = false
	pending_behavior_attack_target_id = ""
	super.cancel_behavior()


func _on_move_started(target_cell: Vector2i) -> void:
	remote_presentation.cancel_guard()
	super._on_move_started(target_cell)


func _on_move_stopped() -> void:
	if view != null:
		view.play_idle()

	if is_running_behavior_turn or remote_presentation.is_replaying_action:
		return

	_finish_behavior()


func _end_behavior_turn() -> void:
	is_running_behavior_turn = false
	_finish_behavior()


func _wait_until_ready_for_next_action() -> void:
	if not is_inside_tree():
		return
	var scene_tree: SceneTree = get_tree()
	while is_moving or is_attacking:
		await scene_tree.process_frame
		if not is_inside_tree():
			return


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
	if target_entity_id.is_empty() or runtime == null:
		return null

	return runtime.get_entity_by_id(target_entity_id)


func _can_attack_target(target: Node) -> bool:
	if not _is_valid_hunt_target(target):
		return false

	return can_attack_cell(target.get("current_cell"))


func _get_attack_goal_cells(target: Node) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if target == null or target.get("current_cell") == null:
		return cells
	var target_cell: Vector2i = target.get("current_cell")
	return WorldGridPathfinder.get_adjacent_walkable_cells(runtime, target_cell)


func _has_terrain_path_to_any(goal_cells: Array[Vector2i]) -> bool:
	return not _find_path_to_any(goal_cells, false).is_empty() or goal_cells.has(current_cell)


func _find_path_to_any(goal_cells: Array[Vector2i], respect_current_occupancy: bool) -> Array[Vector2i]:
	return WorldGridPathfinder.find_path_to_any(
		runtime,
		self,
		current_cell,
		goal_cells,
		respect_current_occupancy
	)


func _set_ai_state(new_state: String, new_target_entity_id: String, reason: String = REASON_NONE, should_broadcast: bool = true) -> void:
	if ai_state == new_state and target_entity_id == new_target_entity_id:
		return

	var previous_state: String = ai_state
	var previous_target_entity_id: String = target_entity_id
	ai_state = new_state
	target_entity_id = new_target_entity_id
	ai_logger.print_state_change(previous_state, previous_target_entity_id, reason)

	if (
		should_broadcast
		and _is_ai_authority()
		and GameSession.is_multiplayer()
		and not entity_id.is_empty()
		and runtime != null
	):
		runtime.broadcast_entity_ai_state(entity_id, ai_state, target_entity_id, reason)


func _get_registered_characters() -> Array[Node]:
	var characters: Array[Node] = []
	if runtime == null:
		return characters

	for entity in runtime.get_registered_entities():
		if entity is Node and entity.get("entity_type") != null and int(entity.get("entity_type")) == EntityType.CHARACTER:
			characters.append(entity)

	characters.sort_custom(func(a: Node, b: Node) -> bool:
		return _get_entity_id(a) < _get_entity_id(b)
	)
	return characters


func _get_entity_id(entity: Node) -> String:
	if entity == null:
		return ""

	if runtime != null:
		return runtime.get_entity_id(entity)

	if entity.get("entity_id") != null:
		return str(entity.get("entity_id"))

	return ""


func _sync_current_cell() -> void:
	if runtime == null:
		runtime = _find_runtime()

	if runtime != null:
		current_cell = runtime.world_to_cell(global_position)


func _is_turn_mode_enabled() -> bool:
	return runtime != null and runtime.is_turn_mode_enabled()


func _is_ai_authority() -> bool:
	return not GameSession.is_multiplayer() or GameSession.is_host()


func _get_attack_duration() -> float:
	if view != null:
		return float(view.get_attack_duration())

	return 0.0


func _get_facing_left() -> bool:
	if view != null:
		return bool(view.get_facing_left())

	return false


func _apply_base_stats() -> void:
	max_health = WARRIOR_MAX_HEALTH
	health = mini(health, max_health) if health > 0 else max_health
	damage = WARRIOR_DAMAGE
	move_time = WARRIOR_MOVE_TIME
	entity_type = EntityType.ENEMY
