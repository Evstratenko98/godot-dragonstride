class_name WarriorBehaviorController
extends RefCounted

var warrior: Warrior = null
var attacks_used_this_turn: int = 0
var is_running_turn: bool = false
var pending_attack_target_id: String = ""


func configure(owner: Warrior) -> void:
	warrior = owner


func run_turn() -> void:
	if warrior == null:
		return
	var behavior_generation: int = warrior.get_behavior_generation()
	if not warrior._is_turn_mode_enabled() or not warrior._is_ai_authority() or not warrior.can_act():
		warrior._finish_behavior()
		return
	warrior._sync_current_surface()
	attacks_used_this_turn = 0
	is_running_turn = true

	if warrior.ai_state == Warrior.STATE_PASSIVE:
		warrior.consider_character_triggers(warrior._get_registered_characters())
	if warrior.ai_state != Warrior.STATE_ACTIVE:
		end_turn()
		return
	var target: Node = warrior._get_current_target()
	if not warrior._is_valid_hunt_target(target):
		warrior._set_ai_state(Warrior.STATE_PASSIVE, "", warrior._get_invalid_target_reason(target))
		end_turn()
		return
	await _pursue_and_attack(target, behavior_generation)


func cancel() -> void:
	is_running_turn = false
	pending_attack_target_id = ""


func end_turn() -> void:
	is_running_turn = false
	warrior._finish_behavior()


func _pursue_and_attack(target: Node, behavior_generation: int) -> void:
	if warrior._can_attack_target(target):
		is_running_turn = false
		if await warrior._perform_behavior_attack(target):
			return
		warrior._finish_behavior()
		return
	var attack_surfaces: Array[Vector3i] = warrior._get_attack_goal_surfaces(target)
	var path: Array[Vector3i] = warrior._find_path_to_any(attack_surfaces, true)
	if path.is_empty():
		if not warrior._has_terrain_path_to_any(attack_surfaces):
			warrior._set_ai_state(Warrior.STATE_PASSIVE, "", Warrior.REASON_TARGET_UNREACHABLE)
		end_turn()
		return
	var steps_to_take: int = mini(Warrior.MAX_STEPS_PER_TURN, path.size())
	for index: int in range(steps_to_take):
		if not warrior._is_valid_hunt_target(target):
			warrior._set_ai_state(Warrior.STATE_PASSIVE, "", warrior._get_invalid_target_reason(target))
			end_turn()
			return
		var next_surface: Vector3i = path[index]
		var direction: Vector2i = warrior.runtime.get_traversal_input_direction(warrior.current_surface, next_surface)
		if not warrior.request_move(direction):
			end_turn()
			return
		await warrior._wait_until_ready_for_next_action()
		if behavior_generation != warrior.get_behavior_generation() or not is_running_turn:
			return
		warrior._sync_current_surface()
		if warrior._can_attack_target(target):
			is_running_turn = false
			if await warrior._perform_behavior_attack(target):
				return
			warrior._finish_behavior()
			return
	end_turn()
