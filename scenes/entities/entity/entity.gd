class_name Entity
extends CharacterBody2D

enum EntityType {
	CHARACTER,
	NPC,
	ENEMY,
	NEUTRAL,
}

const HEALTH_BAR_SCENE := preload("res://scenes/entities/health_bar/health_bar.tscn")

@export var entity_id := ""
@export var entity_name := ""
@export var entity_type: EntityType = EntityType.NPC
@export var max_health := 100
@export var health := 100
@export var damage := 25
@export var move_time := 0.18
@export var occupied_offsets: Array[Vector2i] = [Vector2i.ZERO]
@export var health_bar_offset := Vector2(0, -42)

var world: Node = null
var current_cell := Vector2i.ZERO
var spawn_cell := Vector2i.ZERO
var is_moving := false
var is_attacking := false
var attack_target_cell: Vector2i = Vector2i.ZERO
var health_bar: Node2D = null


func _ready() -> void:
	world = _find_world()
	if world != null and world.has_method("world_to_cell") and world.has_method("cell_to_world"):
		current_cell = world.world_to_cell(global_position)
		spawn_cell = current_cell
		global_position = world.cell_to_world(current_cell)
	_ensure_health_bar()
	_update_health_bar()


func start_entity(
	start_position: Vector2,
	new_entity_id := "",
	new_entity_name := "",
	new_entity_type: EntityType = EntityType.NPC
) -> void:
	entity_id = new_entity_id
	entity_name = new_entity_name
	entity_type = new_entity_type
	global_position = start_position
	world = _find_world()

	if world != null and world.has_method("world_to_cell"):
		current_cell = world.world_to_cell(global_position)
		spawn_cell = current_cell

	health = max_health
	show()
	_ensure_health_bar()
	_update_health_bar()


func can_act() -> bool:
	return health > 0 and not is_moving and not is_attacking


func can_attack_cell(target_cell: Vector2i) -> bool:
	if get_occupied_cells(current_cell).has(target_cell):
		return false

	return _get_attack_direction_to_cell(target_cell) != Vector2i.ZERO


func request_move(direction: Vector2i) -> bool:
	if direction == Vector2i.ZERO or world == null or not world.has_method("can_enter_cell"):
		return false

	if is_moving or is_attacking:
		return false

	if world.has_method("can_entity_move_in_turn") and not world.can_entity_move_in_turn(self):
		return false

	current_cell = world.world_to_cell(global_position)
	var target_cell := current_cell + direction
	_on_move_direction_selected(direction)

	if not world.can_enter_cell(target_cell, self):
		_on_move_blocked(direction, target_cell)
		return false

	if world.has_method("reserve_entity_cell") and not world.reserve_entity_cell(self, current_cell, target_cell):
		_on_move_blocked(direction, target_cell)
		return false

	_move_to_cell(target_cell)
	return true


func request_attack_cell(target_cell: Vector2i, should_apply := true, should_broadcast := true) -> bool:
	if world == null or not world.has_method("world_to_cell"):
		return false

	if is_moving or is_attacking or health <= 0:
		return false

	current_cell = world.world_to_cell(global_position)
	if not can_attack_cell(target_cell):
		return false

	var direction := _get_attack_direction_to_cell(target_cell)
	if world.has_method("can_entity_attack_in_turn") and not world.can_entity_attack_in_turn(self, target_cell):
		return false

	_attack_cell(target_cell, direction, should_apply, should_broadcast)
	return true


func take_damage(amount: int) -> int:
	if amount <= 0 or health <= 0:
		return 0

	var previous_health := health
	health = maxi(health - amount, 0)
	var applied_damage := previous_health - health
	_on_health_changed(previous_health, health)

	if health == 0:
		die()

	return applied_damage


func set_health(new_health: int) -> void:
	var previous_health := health
	health = clampi(new_health, 0, max_health)
	_on_health_changed(previous_health, health)


func die() -> void:
	_on_died()
	if world != null and world.has_method("unregister_entity"):
		world.unregister_entity(self)
	queue_free()


func respawn() -> void:
	set_health(max_health)
	is_moving = false
	is_attacking = false
	current_cell = spawn_cell

	if world != null and world.has_method("cell_to_world"):
		global_position = world.cell_to_world(spawn_cell)

	if world != null and world.has_method("respawn_entity"):
		world.respawn_entity(self, spawn_cell)

	show()
	_update_health_bar()
	_on_respawned()


func get_display_name() -> String:
	if not entity_name.is_empty():
		return entity_name

	return name


func get_occupied_cells(anchor_cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if occupied_offsets.is_empty():
		cells.append(anchor_cell)
		return cells

	for offset in occupied_offsets:
		var occupied_cell := anchor_cell + offset
		if not cells.has(occupied_cell):
			cells.append(occupied_cell)

	return cells


func _move_to_cell(target_cell: Vector2i, should_broadcast := true) -> void:
	is_moving = true
	var from_cell := current_cell
	var target_position: Vector2 = world.cell_to_world(target_cell)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(self, "global_position", target_position, move_time)
	_on_move_started(target_cell)
	if world != null and world.has_method("handle_entity_move_started"):
		world.handle_entity_move_started(self, from_cell, target_cell, should_broadcast)
	tween.finished.connect(func() -> void:
		global_position = target_position
		current_cell = target_cell
		is_moving = false

		if world != null and world.has_method("complete_entity_move"):
			world.complete_entity_move(self, from_cell, target_cell)

		if world != null and world.has_method("notify_entity_moved_in_turn"):
			world.notify_entity_moved_in_turn(self, from_cell, target_cell)

		_on_move_finished(target_cell)
		if _try_continue_moving():
			return

		_on_move_stopped()
	)


func _attack_cell(target_cell: Vector2i, _direction: Vector2i, should_apply: bool, should_broadcast: bool) -> void:
	is_attacking = true
	attack_target_cell = target_cell
	if should_apply:
		_apply_attack_to_world(should_broadcast)
	is_attacking = false
	if world != null and world.has_method("notify_entity_action_finished_in_turn"):
		world.notify_entity_action_finished_in_turn(self)


func _apply_attack_to_world(should_broadcast := true) -> void:
	if world != null and world.has_method("notify_entity_attacked_in_turn"):
		world.notify_entity_attacked_in_turn(self, attack_target_cell)

	if world != null and world.has_method("handle_entity_attack"):
		world.handle_entity_attack(self, attack_target_cell, should_broadcast)
	elif world != null and world.has_method("apply_attack_to_cell"):
		world.apply_attack_to_cell(self, attack_target_cell)


func _is_adjacent_attack_direction(direction: Vector2i) -> bool:
	return direction == Vector2i.RIGHT or direction == Vector2i.LEFT or direction == Vector2i.DOWN or direction == Vector2i.UP


func _get_attack_direction_to_cell(target_cell: Vector2i) -> Vector2i:
	for occupied_cell in get_occupied_cells(current_cell):
		var direction := target_cell - occupied_cell
		if _is_adjacent_attack_direction(direction):
			return direction

	return Vector2i.ZERO


func _on_move_direction_selected(_direction: Vector2i) -> void:
	pass


func _on_move_blocked(_direction: Vector2i, _target_cell: Vector2i) -> void:
	pass


func _on_move_started(_target_cell: Vector2i) -> void:
	pass


func _on_move_finished(_target_cell: Vector2i) -> void:
	pass


func _on_move_stopped() -> void:
	pass


func _try_continue_moving() -> bool:
	return false


func _on_health_changed(_previous_health: int, _new_health: int) -> void:
	_update_health_bar()


func _on_died() -> void:
	pass


func _on_respawned() -> void:
	pass


func _ensure_health_bar() -> void:
	if health_bar != null and is_instance_valid(health_bar):
		health_bar.position = health_bar_offset
		return

	health_bar = HEALTH_BAR_SCENE.instantiate() as Node2D
	if health_bar == null:
		return

	health_bar.position = health_bar_offset
	add_child(health_bar)


func _update_health_bar() -> void:
	if health_bar == null or not is_instance_valid(health_bar):
		return

	var progress := health_bar.get_node_or_null("Progress") as TextureProgressBar
	if progress == null:
		return

	var safe_max_health := maxi(max_health, 1)
	progress.max_value = safe_max_health
	progress.value = clampi(health, 0, safe_max_health)


func _find_world() -> Node:
	var node := get_parent()
	while node != null:
		if node.has_method("can_enter_cell") or node.has_method("handle_entity_attack"):
			return node
		node = node.get_parent()

	return null
