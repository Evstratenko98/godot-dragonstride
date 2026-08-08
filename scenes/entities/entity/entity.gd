class_name Entity
extends CharacterBody2D

signal movement_finished(from_surface: Vector3i, target_surface: Vector3i)
signal movement_started(from_surface: Vector3i, target_surface: Vector3i)
signal attack_finished(target_surface: Vector3i)
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
@export_range(0, 15, 1) var surface_height: int = 0
@export var occupied_offsets: Array[Vector2i] = [Vector2i.ZERO]
@export var health_bar_offset: Vector2 = Vector2(0, -42)

var runtime: WorldRuntime = null
var movement_controller: EntityMovementController = EntityMovementController.new()
var current_surface: Vector3i:
	get:
		return movement_controller.current_surface
	set(value):
		movement_controller.current_surface = value
var spawn_surface: Vector3i:
	get:
		return movement_controller.spawn_surface
	set(value):
		movement_controller.spawn_surface = value
var is_moving: bool:
	get:
		return movement_controller.is_moving
	set(value):
		movement_controller.is_moving = value
var is_attacking: bool = false
var attack_target_surface: Vector3i = Vector3i.ZERO
var movement_tween: Tween:
	get:
		return movement_controller.movement_tween
	set(value):
		movement_controller.movement_tween = value
var action_generation: int:
	get:
		return movement_controller.action_generation
	set(value):
		movement_controller.action_generation = value
var health_presenter: EntityHealthPresenter = EntityHealthPresenter.new()
var occlusion_silhouette: EntityOcclusionSilhouette = null


func _ready() -> void:
	health_presenter.configure(self)
	runtime = _find_runtime()
	movement_controller.configure(self, runtime)
	if runtime != null:
		current_surface = runtime.world_to_surface(global_position, surface_height)
		spawn_surface = current_surface
		global_position = runtime.surface_to_world(current_surface)
		z_index = current_surface.z * 20 + 10
	health_presenter.ensure_created(health_bar_offset)
	health_presenter.update(health, max_health)
	_configure_occlusion_silhouette()


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
	movement_controller.configure(self, runtime)

	if runtime != null:
		current_surface = runtime.world_to_surface(global_position, surface_height)
		spawn_surface = current_surface
		z_index = current_surface.z * 20 + 10

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


func can_attack_surface(target_surface: Vector3i) -> bool:
	return can_attack_surface_from(current_surface, target_surface)


func can_attack_surface_from(anchor_surface: Vector3i, target_surface: Vector3i) -> bool:
	if get_occupied_surfaces(anchor_surface).has(target_surface):
		return false

	return EntityFootprint.get_adjacent_direction(
		anchor_surface,
		target_surface,
		occupied_offsets
	) != Vector2i.ZERO


func get_attackable_surfaces(anchor_surface: Vector3i) -> Array[Vector3i]:
	var attackable_surfaces: Array[Vector3i] = []
	var occupied_surfaces: Array[Vector3i] = get_occupied_surfaces(anchor_surface)
	var directions: Array[Vector2i] = [
		Vector2i.RIGHT,
		Vector2i.LEFT,
		Vector2i.DOWN,
		Vector2i.UP,
	]
	for occupied_surface: Vector3i in occupied_surfaces:
		for direction: Vector2i in directions:
			var target_surface: Vector3i = Vector3i(
				occupied_surface.x + direction.x,
				occupied_surface.y + direction.y,
				occupied_surface.z
			)
			if not occupied_surfaces.has(target_surface) and not attackable_surfaces.has(target_surface):
				attackable_surfaces.append(target_surface)
	return attackable_surfaces


func request_move(direction: Vector2i) -> bool:
	return execute_move(direction, true)


func execute_move(direction: Vector2i, should_broadcast: bool, movement_step_cost: int = 1) -> bool:
	if direction == Vector2i.ZERO or runtime == null:
		return false

	if is_moving or is_attacking or runtime.is_entity_movement_blocked_by_spell(self):
		return false

	if not runtime.can_entity_move_in_turn(self):
		return false

	var target_surface: Vector3i = runtime.get_surface_in_direction(current_surface, direction)
	_on_move_direction_selected(direction)
	if target_surface == WorldGridTopology.INVALID_SURFACE:
		_on_move_blocked(direction, target_surface)
		return false

	if not runtime.can_enter_surface(target_surface, self):
		_on_move_blocked(direction, target_surface)
		return false

	if not runtime.reserve_entity_surface(self, current_surface, target_surface):
		_on_move_blocked(direction, target_surface)
		return false

	_move_to_surface(target_surface, should_broadcast, movement_step_cost)
	return true


func request_attack_surface(target_surface: Vector3i, should_apply: bool = true, should_broadcast: bool = true) -> bool:
	if runtime == null:
		return false

	if is_moving or is_attacking or health <= 0 or runtime.is_entity_casting(self):
		return false

	if not can_attack_surface(target_surface):
		return false

	var direction: Vector2i = _get_attack_direction_to_surface(target_surface)
	if not runtime.can_entity_attack_in_turn(self, target_surface):
		return false

	_attack_surface(target_surface, direction, should_apply, should_broadcast)
	return true


func interact(_interactor: PlayerCharacter, _world_runtime: WorldRuntime) -> bool:
	return false


func can_interact(_interactor: PlayerCharacter, _world_runtime: WorldRuntime) -> bool:
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
	return respawn_at_surface(spawn_surface)


func respawn_at_surface(respawn_surface: Vector3i) -> bool:
	if runtime != null:
		var registration_result: int = runtime.respawn_entity(self, respawn_surface)
		if registration_result != WorldRegistry.RegistrationError.NONE:
			return false
	movement_controller.reset_at_surface(respawn_surface)
	set_health(max_health)
	is_attacking = false

	show()
	health_presenter.update(health, max_health)
	_on_respawned()
	return true


func force_cancel_movement(from_surface: Vector3i) -> void:
	movement_controller.cancel_to_surface(from_surface)


func force_finish_attack_presentation() -> void:
	action_generation += 1
	is_attacking = false
	_on_attack_presentation_forced()


func get_expected_attack_duration(_target_surface: Vector3i) -> float:
	return 0.0


func get_display_name() -> String:
	if not entity_name.is_empty():
		return entity_name

	return name


func get_occupied_surfaces(anchor_surface: Vector3i) -> Array[Vector3i]:
	return EntityFootprint.get_occupied_surfaces(anchor_surface, occupied_offsets)


func get_action_generation() -> int:
	return action_generation


func _move_to_surface(target_surface: Vector3i, should_broadcast: bool = true, movement_step_cost: int = 1) -> void:
	movement_controller.move_to_surface(target_surface, should_broadcast, movement_step_cost)


func _attack_surface(target_surface: Vector3i, _direction: Vector2i, should_apply: bool, should_broadcast: bool) -> void:
	is_attacking = true
	attack_target_surface = target_surface
	if should_apply:
		_apply_attack_to_world(should_broadcast)
	is_attacking = false
	if runtime != null:
		runtime.notify_entity_action_finished_in_turn(self)
	attack_finished.emit(target_surface)


func _apply_attack_to_world(
	should_broadcast: bool = true,
	should_broadcast_action: bool = true
) -> void:
	if runtime == null:
		return

	runtime.notify_entity_attacked_in_turn(self, attack_target_surface)
	runtime.handle_entity_attack(
		self,
		attack_target_surface,
		should_broadcast,
		should_broadcast_action
	)


func _on_attack_presentation_forced() -> void:
	pass


func _play_target_incoming_attack_guard(target_surface: Vector3i, duration: float) -> void:
	if duration <= 0.0 or runtime == null:
		return

	var target_entity: Node = runtime.get_entity_at_surface(target_surface)
	if target_entity == null or target_entity == self:
		return

	if target_entity is NonPlayerEntity:
		(target_entity as NonPlayerEntity).play_incoming_attack_guard(duration)


func _get_attack_direction_to_surface(target_surface: Vector3i) -> Vector2i:
	return EntityFootprint.get_adjacent_direction(current_surface, target_surface, occupied_offsets)


func _on_move_direction_selected(_direction: Vector2i) -> void:
	pass


func _on_move_blocked(_direction: Vector2i, _target_surface: Vector3i) -> void:
	pass


func _on_move_started(_target_surface: Vector3i) -> void:
	pass


func _on_move_finished(_target_surface: Vector3i) -> void:
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


func _configure_occlusion_silhouette() -> void:
	var source_sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
	if source_sprite == null:
		return
	occlusion_silhouette = EntityOcclusionSilhouette.new()
	occlusion_silhouette.name = "OcclusionSilhouette"
	add_child(occlusion_silhouette)
	occlusion_silhouette.configure(self, source_sprite)
