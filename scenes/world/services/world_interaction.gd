class_name WorldInteraction
extends Node

var runtime: WorldRuntime = null
var level: WorldLevel = null


func configure_context(new_runtime: WorldRuntime, new_level: WorldLevel) -> void:
	runtime = new_runtime
	level = new_level


func get_available_interaction_surfaces(interactor: PlayerCharacter) -> Array[Vector3i]:
	var available_cells: Array[Vector3i] = []
	if interactor == null or runtime == null or not interactor.can_act():
		return available_cells
	var anchor_surface: Vector3i = interactor.current_surface
	for target_surface: Vector3i in interactor.get_attackable_surfaces(anchor_surface):
		if can_interact_with_surface(interactor, target_surface):
			available_cells.append(target_surface)
	return available_cells


func can_interact_with_surface(interactor: PlayerCharacter, target_surface: Vector3i) -> bool:
	if interactor == null or runtime == null or not interactor.can_act():
		return false
	var anchor_surface: Vector3i = interactor.current_surface
	if (
		not runtime.is_surface_inside(target_surface)
		or not interactor.can_attack_surface_from(anchor_surface, target_surface)
		or not runtime.can_entity_interact_in_turn(interactor)
	):
		return false
	var target_entity: Entity = runtime.get_entity_at_surface(target_surface) as Entity
	if target_entity != null and target_entity != interactor:
		return target_entity.can_interact(interactor, runtime)
	var target_object: GridObject = runtime.get_object_at_surface(target_surface) as GridObject
	return target_object == null or target_object.can_interact(interactor, runtime)


func try_interact(interactor: PlayerCharacter, target_surface: Vector3i) -> bool:
	if not can_interact_with_surface(interactor, target_surface):
		return false

	var target_entity: Entity = runtime.get_entity_at_surface(target_surface) as Entity
	var did_interact: bool = true
	if target_entity != null and target_entity != interactor:
		did_interact = target_entity.interact(interactor, runtime)
	else:
		var target_object: GridObject = runtime.get_object_at_surface(target_surface) as GridObject
		if target_object != null:
			did_interact = target_object.interact(interactor, runtime)
	if not did_interact:
		return false

	runtime.notify_entity_interacted_in_turn(interactor)
	return true
