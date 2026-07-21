class_name Entity
extends CharacterBody2D

signal movement_finished(from_cell: Vector2i, target_cell: Vector2i)
signal movement_started(from_cell: Vector2i, target_cell: Vector2i)
signal attack_finished(target_cell: Vector2i)
signal vitality_changed(current_health: int, maximum_health: int)
signal damage_changed(current_damage: int)

enum EntityType {
	CHARACTER,
	NPC,
	ENEMY,
	NEUTRAL,
}

@export var entity_id: String = ""
@export var entity_name: String = ""
@export var entity_type: EntityType = EntityType.NPC
@export var max_health: int = 100
@export var health: int = 100
@export var damage: int = 25
@export var move_time: float = 0.18
@export var occupied_offsets: Array[Vector2i] = [Vector2i.ZERO]
@export var health_bar_offset: Vector2 = Vector2(0, -42)

var runtime: WorldRuntime = null
var current_cell: Vector2i = Vector2i.ZERO
var spawn_cell: Vector2i = Vector2i.ZERO
var is_moving: bool = false
var is_attacking: bool = false
var attack_target_cell: Vector2i = Vector2i.ZERO
var movement_tween: Tween = null
var action_generation: int = 0
var health_presenter: EntityHealthPresenter = EntityHealthPresenter.new()


func _ready() -> void:
	health_presenter.configure(self)
	runtime = _find_runtime()
	if runtime != null:
		current_cell = runtime.world_to_cell(global_position)
		spawn_cell = current_cell
		global_position = runtime.cell_to_world(current_cell)
	health_presenter.ensure_created(health_bar_offset)
	health_presenter.update(health, max_health)


func start_entity(
	start_position: Vector2,
	new_entity_id: String = "",
	new_entity_name: String = "",
	new_entity_type: EntityType = EntityType.NPC
) -> void:
	entity_id = new_entity_id
	entity_name = new_entity_name
	entity_type = new_entity_type
	global_position = start_position
	runtime = _find_runtime()

	if runtime != null:
		current_cell = runtime.world_to_cell(global_position)
		spawn_cell = current_cell

	health = max_health
	show()
	health_presenter.ensure_created(health_bar_offset)
	health_presenter.update(health, max_health)


func can_act() -> bool:
	return (
		health > 0
		and not is_moving
		and not is_attacking
		and (runtime == null or not runtime.is_entity_casting(self))
	)


func get_max_movement_steps_per_turn() -> int:
	return 1


func can_attack_cell(target_cell: Vector2i) -> bool:
	if get_occupied_cells(current_cell).has(target_cell):
		return false

	return _get_attack_direction_to_cell(target_cell) != Vector2i.ZERO


func request_move(direction: Vector2i) -> bool:
	return execute_move(direction, true)


func execute_move(direction: Vector2i, should_broadcast: bool) -> bool:
	if direction == Vector2i.ZERO or runtime == null:
		return false

	if is_moving or is_attacking or runtime.is_entity_movement_blocked_by_spell(self):
		return false

	if not runtime.can_entity_move_in_turn(self):
		return false

	current_cell = runtime.world_to_cell(global_position)
	var target_cell: Vector2i = current_cell + direction
	_on_move_direction_selected(direction)

	if not runtime.can_enter_cell(target_cell, self):
		_on_move_blocked(direction, target_cell)
		return false

	if not runtime.reserve_entity_cell(self, current_cell, target_cell):
		_on_move_blocked(direction, target_cell)
		return false

	_move_to_cell(target_cell, should_broadcast)
	return true


func request_attack_cell(target_cell: Vector2i, should_apply: bool = true, should_broadcast: bool = true) -> bool:
	if runtime == null:
		return false

	if is_moving or is_attacking or health <= 0 or runtime.is_entity_casting(self):
		return false

	current_cell = runtime.world_to_cell(global_position)
	if not can_attack_cell(target_cell):
		return false

	var direction: Vector2i = _get_attack_direction_to_cell(target_cell)
	if not runtime.can_entity_attack_in_turn(self, target_cell):
		return false

	_attack_cell(target_cell, direction, should_apply, should_broadcast)
	return true


func interact(_interactor: PlayerCharacter, _world_runtime: WorldRuntime) -> bool:
	return false


func take_damage(amount: int) -> int:
	if amount <= 0 or health <= 0:
		return 0

	var previous_health: int = health
	health = maxi(health - amount, 0)
	var applied_damage: int = previous_health - health
	_on_health_changed(previous_health, health)

	if health == 0:
		die()

	return applied_damage


func set_health(new_health: int) -> void:
	var previous_health: int = health
	health = clampi(new_health, 0, max_health)
	_on_health_changed(previous_health, health)


func apply_health_capacity_bonus(maximum_health_increase: int, health_restore: int) -> bool:
	if maximum_health_increase <= 0 or health_restore < 0 or health <= 0:
		return false

	max_health += maximum_health_increase
	set_health(health + health_restore)
	return true


func apply_attack_damage_bonus(damage_increase: int) -> bool:
	if damage_increase <= 0 or health <= 0:
		return false

	damage += damage_increase
	damage_changed.emit(damage)
	return true


func apply_attack_damage_state(new_damage: int) -> void:
	var next_damage: int = maxi(new_damage, 0)
	if damage == next_damage:
		return
	damage = next_damage
	damage_changed.emit(damage)


func apply_vitality_state(new_health: int, new_max_health: int) -> void:
	max_health = maxi(new_max_health, 1)
	set_health(new_health)


func die() -> void:
	_on_died()
	if runtime != null:
		runtime.unregister_entity(self)
	queue_free()


func respawn() -> bool:
	if runtime != null and self is PlayerCharacter:
		return runtime.request_player_respawn(self as PlayerCharacter)
	return respawn_at_cell(spawn_cell)


func respawn_at_cell(respawn_cell: Vector2i) -> bool:
	if runtime != null:
		var registration_result: int = runtime.respawn_entity(self, respawn_cell)
		if registration_result != WorldRegistry.RegistrationError.NONE:
			return false
	action_generation += 1
	if movement_tween != null and movement_tween.is_valid():
		movement_tween.kill()
	movement_tween = null
	set_health(max_health)
	is_moving = false
	is_attacking = false
	current_cell = respawn_cell

	if runtime != null:
		global_position = runtime.cell_to_world(respawn_cell)

	show()
	health_presenter.update(health, max_health)
	_on_respawned()
	return true


func force_cancel_movement(from_cell: Vector2i) -> void:
	action_generation += 1
	if movement_tween != null and movement_tween.is_valid():
		movement_tween.kill()
	movement_tween = null
	is_moving = false
	current_cell = from_cell
	if runtime != null:
		global_position = runtime.cell_to_world(from_cell)
		runtime.sync_entity_cell(self, from_cell)
	_on_move_stopped()


func force_finish_attack_presentation() -> void:
	action_generation += 1
	is_attacking = false
	_on_attack_presentation_forced()


func get_expected_attack_duration(_target_cell: Vector2i) -> float:
	return 0.0


func get_display_name() -> String:
	if not entity_name.is_empty():
		return entity_name

	return name


func get_occupied_cells(anchor_cell: Vector2i) -> Array[Vector2i]:
	return EntityFootprint.get_occupied_cells(anchor_cell, occupied_offsets)


func get_action_generation() -> int:
	return action_generation


func _move_to_cell(target_cell: Vector2i, should_broadcast: bool = true) -> void:
	if runtime == null:
		return

	is_moving = true
	var from_cell: Vector2i = current_cell
	var target_position: Vector2 = runtime.cell_to_world(target_cell)
	var move_generation: int = action_generation
	movement_tween = create_tween()
	movement_tween.set_trans(Tween.TRANS_LINEAR)
	movement_tween.set_ease(Tween.EASE_IN)
	movement_tween.tween_property(self, "global_position", target_position, move_time)
	_on_move_started(target_cell)
	if runtime != null:
		runtime.handle_entity_move_started(self, from_cell, target_cell, should_broadcast)
	movement_started.emit(from_cell, target_cell)
	movement_tween.finished.connect(func() -> void:
		if move_generation != action_generation:
			return

		movement_tween = null
		global_position = target_position
		current_cell = target_cell
		is_moving = false

		if runtime != null:
			runtime.handle_entity_move_completed(self, from_cell, target_cell)
		movement_finished.emit(from_cell, target_cell)

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
	if runtime != null:
		runtime.notify_entity_action_finished_in_turn(self)
	attack_finished.emit(target_cell)


func _apply_attack_to_world(
	should_broadcast: bool = true,
	should_broadcast_action: bool = true
) -> void:
	if runtime == null:
		return

	runtime.notify_entity_attacked_in_turn(self, attack_target_cell)
	runtime.handle_entity_attack(
		self,
		attack_target_cell,
		should_broadcast,
		should_broadcast_action
	)


func _on_attack_presentation_forced() -> void:
	pass


func _play_target_incoming_attack_guard(target_cell: Vector2i, duration: float) -> void:
	if duration <= 0.0 or runtime == null:
		return

	var target_entity: Node = runtime.get_entity_at_cell(target_cell)
	if target_entity == null or target_entity == self:
		return

	if target_entity is NonPlayerEntity:
		(target_entity as NonPlayerEntity).play_incoming_attack_guard(duration)


func _get_attack_direction_to_cell(target_cell: Vector2i) -> Vector2i:
	return EntityFootprint.get_adjacent_direction(current_cell, target_cell, occupied_offsets)


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
	health_presenter.update(health, max_health)
	vitality_changed.emit(health, max_health)


func _on_died() -> void:
	pass


func _on_respawned() -> void:
	pass


func _find_runtime() -> WorldRuntime:
	return WorldRuntimeResolver.from_node(self)
