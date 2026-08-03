class_name WarriorRemotePresentation
extends RefCounted

const MAX_QUEUED_ACTIONS := 8

var warrior: Warrior = null
var action_queue: Array[Dictionary] = []
var queue_head_index: int = 0
var is_processing: bool = false
var is_replaying_action: bool = false
var guard_token: int = 0


func configure(owner: Warrior) -> void:
	warrior = owner


func enqueue_move(from_cell: Vector2i, target_cell: Vector2i) -> void:
	if not _can_enqueue():
		return
	action_queue.append({"type": "move", "from_cell": from_cell, "target_cell": target_cell})
	_process_queue()


func enqueue_attack(target_cell: Vector2i, should_apply: bool) -> void:
	if not _can_enqueue():
		return
	action_queue.append({"type": "attack", "target_cell": target_cell, "should_apply": should_apply})
	_process_queue()


func play_guard(duration: float) -> void:
	if duration <= 0.0 or warrior.is_moving or warrior.is_attacking or warrior.health <= 0 or not warrior.is_inside_tree():
		return
	var scene_tree: SceneTree = warrior.get_tree()
	guard_token += 1
	var active_guard_token: int = guard_token
	if warrior.view != null:
		warrior.view.play_guard()
	await scene_tree.create_timer(duration).timeout
	if not warrior.is_inside_tree() or guard_token != active_guard_token:
		return
	if warrior.health <= 0 or warrior.is_moving or warrior.is_attacking:
		return
	if warrior.view != null:
		warrior.view.play_idle()


func cancel_guard() -> void:
	guard_token += 1


func _can_enqueue() -> bool:
	if action_queue.size() - queue_head_index < MAX_QUEUED_ACTIONS:
		return true
	if warrior.runtime != null and warrior.runtime.action_stream != null:
		warrior.runtime.action_stream.request_runtime_resync(WorldActionStream.REJECTION_SEQUENCE_GAP)
	return false


func _process_queue() -> void:
	if is_processing or not warrior.is_inside_tree():
		return
	var scene_tree: SceneTree = warrior.get_tree()
	is_processing = true
	while queue_head_index < action_queue.size():
		if warrior.is_moving or warrior.is_attacking:
			await scene_tree.process_frame
			if not warrior.is_inside_tree():
				return
			continue
		var action: Dictionary = action_queue[queue_head_index]
		queue_head_index += 1
		is_replaying_action = true
		if str(action.get("type", "")) == "move":
			await _play_move(action)
		elif str(action.get("type", "")) == "attack":
			await _play_attack(action)
		is_replaying_action = false
	action_queue.clear()
	queue_head_index = 0
	is_processing = false


func _play_move(action: Dictionary) -> void:
	if warrior.runtime == null:
		warrior.runtime = warrior._find_runtime()
	if warrior.runtime == null:
		return
	var from_cell: Vector2i = action.get("from_cell", warrior.current_cell)
	var target_cell: Vector2i = action.get("target_cell", warrior.current_cell)
	warrior.current_cell = from_cell
	warrior.global_position = warrior.runtime.cell_to_world(from_cell)
	if not warrior.runtime.reserve_entity_cell(warrior, from_cell, target_cell):
		return
	warrior._move_to_cell(target_cell, false)
	await warrior._wait_until_ready_for_next_action()


func _play_attack(action: Dictionary) -> void:
	if warrior.runtime == null:
		warrior.runtime = warrior._find_runtime()
	if warrior.runtime == null:
		return
	warrior.current_cell = warrior.runtime.world_to_cell(warrior.global_position)
	var target_cell: Vector2i = action.get("target_cell", warrior.current_cell)
	warrior.request_attack_cell(target_cell, bool(action.get("should_apply", false)), false)
	await warrior._wait_until_ready_for_next_action()
