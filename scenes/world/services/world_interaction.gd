class_name WorldInteraction
extends Node

var runtime: WorldRuntime = null
var level: WorldLevel = null


func configure_context(new_runtime: WorldRuntime, new_level: WorldLevel) -> void:
	runtime = new_runtime
	level = new_level


func get_available_interaction_cells(interactor: PlayerCharacter) -> Array[Vector2i]:
	var available_cells: Array[Vector2i] = []
	if interactor == null or runtime == null or not interactor.can_act():
		return available_cells
	var anchor_cell: Vector2i = runtime.world_to_cell(interactor.global_position)
	for target_cell: Vector2i in interactor.get_attackable_cells(anchor_cell):
		if can_interact_with_cell(interactor, target_cell):
			available_cells.append(target_cell)
	return available_cells


func can_interact_with_cell(interactor: PlayerCharacter, target_cell: Vector2i) -> bool:
	if interactor == null or runtime == null or not interactor.can_act():
		return false
	var anchor_cell: Vector2i = runtime.world_to_cell(interactor.global_position)
	return not (
		not runtime.is_cell_inside(target_cell)
		or not interactor.can_attack_cell_from(anchor_cell, target_cell)
		or not runtime.can_entity_interact_in_turn(interactor)
	)


func try_interact(interactor: PlayerCharacter, target_cell: Vector2i) -> bool:
	if not can_interact_with_cell(interactor, target_cell):
		return false

	interactor.current_cell = runtime.world_to_cell(interactor.global_position)
	var target_entity: Entity = runtime.get_entity_at_cell(target_cell) as Entity
	if target_entity != null and target_entity != interactor:
		target_entity.interact(interactor, runtime)
	else:
		var target_object: GridObject = runtime.get_object_at_cell(target_cell) as GridObject
		if target_object != null:
			target_object.interact(interactor, runtime)

	runtime.notify_entity_interacted_in_turn(interactor)
	return true
