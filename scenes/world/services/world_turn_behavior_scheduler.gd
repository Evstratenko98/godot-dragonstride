class_name WorldTurnBehaviorScheduler
extends RefCounted

signal behaviors_finished

const WORLD_TURN_WATCHDOG_MSEC := 32000
const NPC_BEHAVIOR_WATCHDOG_MSEC := 8000

var runtime: WorldRuntime = null
var level: WorldLevel = null
var generation: int = 0
var pending_entity_ids: Dictionary[String, int] = {}
var deadline_by_entity_id: Dictionary[String, int] = {}
var is_starting: bool = false
var is_completion_emitted: bool = false
var watchdog_activation_count: int = 0


func configure_context(new_runtime: WorldRuntime, new_level: WorldLevel) -> void:
	runtime = new_runtime
	level = new_level


func start(new_generation: int) -> void:
	reset()
	generation = new_generation
	var world_entities: Array[NonPlayerEntity] = _get_world_turn_entities()
	world_entities.sort_custom(func(first: NonPlayerEntity, second: NonPlayerEntity) -> bool:
		return runtime.get_entity_id(first) < runtime.get_entity_id(second)
	)
	var ready_entities: Array[NonPlayerEntity] = []
	for entity: NonPlayerEntity in world_entities:
		var entity_id: String = runtime.get_entity_id(entity)
		if entity_id.is_empty():
			continue
		ready_entities.append(entity)
		pending_entity_ids[entity_id] = generation
		deadline_by_entity_id[entity_id] = Time.get_ticks_msec() + NPC_BEHAVIOR_WATCHDOG_MSEC
		entity.begin_behavior_generation(generation)
	if pending_entity_ids.is_empty():
		_emit_finished()
		return
	is_starting = true
	for entity: NonPlayerEntity in ready_entities:
		if _is_world_turn_entity_available(entity):
			entity.behavior()
		else:
			notify_finished(entity, generation)
	is_starting = false
	_finish_if_ready()


func wait_until_finished() -> bool:
	if runtime == null or not runtime.is_inside_tree():
		return false
	var scene_tree: SceneTree = runtime.get_tree()
	var deadline_msec: int = Time.get_ticks_msec() + WORLD_TURN_WATCHDOG_MSEC
	while not is_completion_emitted and Time.get_ticks_msec() < deadline_msec:
		_cancel_timed_out_behaviors()
		await scene_tree.process_frame
		if not runtime.is_inside_tree():
			return false
	if not is_completion_emitted:
		watchdog_activation_count += 1
		for entity_id_value: Variant in pending_entity_ids.keys():
			var entity: NonPlayerEntity = runtime.get_entity_by_id(str(entity_id_value)) as NonPlayerEntity
			if entity != null:
				entity.cancel_behavior()
		pending_entity_ids.clear()
		deadline_by_entity_id.clear()
		_emit_finished()
	return true


func notify_finished(entity: Node, completed_generation: int) -> void:
	if entity == null:
		return
	var entity_id: String = runtime.get_entity_id(entity)
	if entity_id.is_empty() or int(pending_entity_ids.get(entity_id, -1)) != completed_generation:
		return
	pending_entity_ids.erase(entity_id)
	deadline_by_entity_id.erase(entity_id)
	if not is_starting:
		_finish_if_ready()


func notify_removed(entity: Node) -> void:
	if entity == null:
		return
	var entity_id: String = runtime.get_entity_id(entity)
	if entity_id.is_empty() or not pending_entity_ids.has(entity_id):
		return
	pending_entity_ids.erase(entity_id)
	deadline_by_entity_id.erase(entity_id)
	if not is_starting:
		_finish_if_ready()


func is_world_turn_entity(entity: Node) -> bool:
	return entity is NonPlayerEntity and (entity as NonPlayerEntity).entity_type != Entity.EntityType.CHARACTER


func reset() -> void:
	pending_entity_ids.clear()
	deadline_by_entity_id.clear()
	is_starting = false
	is_completion_emitted = false


func _cancel_timed_out_behaviors() -> void:
	var now_msec: int = Time.get_ticks_msec()
	for entity_id: String in deadline_by_entity_id.keys():
		if now_msec < int(deadline_by_entity_id[entity_id]):
			continue
		var entity: NonPlayerEntity = runtime.get_entity_by_id(entity_id) as NonPlayerEntity
		if entity != null:
			entity.cancel_behavior()
		watchdog_activation_count += 1
		pending_entity_ids.erase(entity_id)
		deadline_by_entity_id.erase(entity_id)
	_finish_if_ready()


func _finish_if_ready() -> void:
	if pending_entity_ids.is_empty():
		_emit_finished()


func _emit_finished() -> void:
	if is_completion_emitted:
		return
	is_completion_emitted = true
	behaviors_finished.emit()


func _get_world_turn_entities() -> Array[NonPlayerEntity]:
	var entities: Array[NonPlayerEntity] = []
	_collect_world_turn_entities(level, entities)
	return entities


func _collect_world_turn_entities(node: Node, entities: Array[NonPlayerEntity]) -> void:
	if node == null:
		return
	for child: Node in node.get_children():
		if _is_world_turn_entity_available(child):
			entities.append(child as NonPlayerEntity)
		_collect_world_turn_entities(child, entities)


func _is_world_turn_entity_available(entity: Node) -> bool:
	return is_world_turn_entity(entity) and (entity as NonPlayerEntity).health > 0
