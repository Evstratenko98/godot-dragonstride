class_name WorldInteraction
extends Node

var runtime: WorldRuntime = null
var level: WorldLevel = null


func configure_context(new_runtime: WorldRuntime, new_level: WorldLevel) -> void:
	runtime = new_runtime
	level = new_level


func try_interact(interactor: PlayerCharacter, target_cell: Vector2i) -> bool:
	if interactor == null or runtime == null or not interactor.can_act():
		return false

	interactor.current_cell = runtime.world_to_cell(interactor.global_position)
	if not interactor.can_attack_cell(target_cell):
		return false
	if not runtime.can_entity_interact_in_turn(interactor):
		return false

	var target_entity: Entity = runtime.get_entity_at_cell(target_cell) as Entity
	var was_successful: bool = false
	if target_entity != null and target_entity != interactor:
		was_successful = target_entity.interact(interactor, runtime)
	else:
		var target_object: GridObject = runtime.get_object_at_cell(target_cell) as GridObject
		if target_object != null:
			was_successful = target_object.interact(interactor, runtime)

	if was_successful:
		runtime.notify_entity_interacted_in_turn(interactor)
	return was_successful
