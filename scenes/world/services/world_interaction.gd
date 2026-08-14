class_name WorldInteraction
extends Node

const PAYLOAD_INTERACTION_KIND: String = "interaction_kind"
const PAYLOAD_OBJECT_ID: String = "object_id"
const PAYLOAD_RESULTING_HEALTH: String = "resulting_health"
const PAYLOAD_DESTINATION_PORTAL_ID: String = "destination_portal_id"
const PAYLOAD_DESTINATION_SURFACE: String = "destination_surface"
const PAYLOAD_WAS_TELEPORTED: String = "was_teleported"
const INTERACTION_KIND_HEALING_WELL: String = "healing_well"
const INTERACTION_KIND_LINKED_PORTAL: String = "linked_portal"
const INVALID_SURFACE: Vector3i = Vector3i(-1, -1, -1)
const PORTAL_DESTINATION_OFFSETS: Array[Vector2i] = [
	Vector2i.UP,
	Vector2i.RIGHT,
	Vector2i.DOWN,
	Vector2i.LEFT,
]

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
	var portal: LinkedPortal = target_object as LinkedPortal
	if portal != null and _find_linked_portal(portal) == null:
		return false
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


func prepare_authoritative_action(action: WorldActionRecord, interactor: PlayerCharacter) -> String:
	if action == null or interactor == null or runtime == null:
		return WorldActionStream.REJECTION_INVALID_ACTION
	_clear_authoritative_payload(action.payload)
	var target_surface: Vector3i = action.payload.get("target_surface", INVALID_SURFACE)
	var target_object: GridObject = runtime.get_object_at_surface(target_surface) as GridObject
	var healing_well: HealingWell = target_object as HealingWell
	if healing_well != null:
		action.payload[PAYLOAD_INTERACTION_KIND] = INTERACTION_KIND_HEALING_WELL
		action.payload[PAYLOAD_OBJECT_ID] = healing_well.object_id
		action.payload[PAYLOAD_RESULTING_HEALTH] = healing_well.get_resulting_health(interactor)
		return ""

	var source_portal: LinkedPortal = target_object as LinkedPortal
	if source_portal == null:
		return ""
	var destination_portal: LinkedPortal = _find_linked_portal(source_portal)
	if destination_portal == null:
		return WorldActionStream.REJECTION_INVALID_ACTION
	var destination_surface: Vector3i = _find_portal_destination(destination_portal, interactor)
	action.payload[PAYLOAD_INTERACTION_KIND] = INTERACTION_KIND_LINKED_PORTAL
	action.payload[PAYLOAD_OBJECT_ID] = source_portal.object_id
	action.payload[PAYLOAD_DESTINATION_PORTAL_ID] = destination_portal.object_id
	action.payload[PAYLOAD_WAS_TELEPORTED] = destination_surface != INVALID_SURFACE
	if destination_surface != INVALID_SURFACE:
		action.payload[PAYLOAD_DESTINATION_SURFACE] = destination_surface
	return ""


func execute_authoritative_action(action: WorldActionRecord, interactor: PlayerCharacter) -> bool:
	if action == null or interactor == null or runtime == null:
		return false
	var interaction_kind: String = str(action.payload.get(PAYLOAD_INTERACTION_KIND, ""))
	if interaction_kind == INTERACTION_KIND_HEALING_WELL:
		return _execute_healing_well_action(action, interactor)
	if interaction_kind == INTERACTION_KIND_LINKED_PORTAL:
		return _execute_linked_portal_action(action, interactor)
	return try_interact(interactor, action.payload.get("target_surface", INVALID_SURFACE))


func play_remote_action(action: WorldActionRecord, interactor: PlayerCharacter) -> bool:
	if action == null or interactor == null or runtime == null:
		return false
	var interaction_kind: String = str(action.payload.get(PAYLOAD_INTERACTION_KIND, ""))
	if interaction_kind == INTERACTION_KIND_HEALING_WELL:
		var healing_well: HealingWell = _get_action_target_object(action) as HealingWell
		if healing_well != null:
			healing_well.apply_resulting_health(
				interactor,
				int(action.payload.get(PAYLOAD_RESULTING_HEALTH, interactor.health))
			)
		return true
	if interaction_kind == INTERACTION_KIND_LINKED_PORTAL:
		if bool(action.payload.get(PAYLOAD_WAS_TELEPORTED, false)):
			interactor.relocate_to_surface(
				action.payload.get(PAYLOAD_DESTINATION_SURFACE, INVALID_SURFACE)
			)
		return true
	return false


func _execute_healing_well_action(action: WorldActionRecord, interactor: PlayerCharacter) -> bool:
	var healing_well: HealingWell = _get_action_target_object(action) as HealingWell
	if healing_well == null:
		return false
	var resulting_health: int = int(action.payload.get(PAYLOAD_RESULTING_HEALTH, -1))
	if not healing_well.apply_resulting_health(interactor, resulting_health):
		return false
	runtime.notify_entity_interacted_in_turn(interactor)
	return true


func _execute_linked_portal_action(action: WorldActionRecord, interactor: PlayerCharacter) -> bool:
	var source_portal: LinkedPortal = _get_action_target_object(action) as LinkedPortal
	if source_portal == null:
		return false
	var destination_portal: LinkedPortal = runtime.get_object_by_id(
		str(action.payload.get(PAYLOAD_DESTINATION_PORTAL_ID, ""))
	) as LinkedPortal
	if (
		destination_portal == null
		or destination_portal == source_portal
		or destination_portal.link_group_id != source_portal.link_group_id
	):
		return false
	if bool(action.payload.get(PAYLOAD_WAS_TELEPORTED, false)):
		var destination_surface: Vector3i = action.payload.get(
			PAYLOAD_DESTINATION_SURFACE,
			INVALID_SURFACE
		)
		if not _is_surface_adjacent_to_portal(destination_surface, destination_portal):
			return false
		if not interactor.relocate_to_surface(destination_surface):
			return false
	runtime.notify_entity_interacted_in_turn(interactor)
	return true


func _get_action_target_object(action: WorldActionRecord) -> GridObject:
	var target_surface: Vector3i = action.payload.get("target_surface", INVALID_SURFACE)
	var target_object: GridObject = runtime.get_object_at_surface(target_surface) as GridObject
	if target_object == null or target_object.object_id != str(action.payload.get(PAYLOAD_OBJECT_ID, "")):
		return null
	return target_object


func _find_linked_portal(source_portal: LinkedPortal) -> LinkedPortal:
	if source_portal == null or runtime == null or source_portal.link_group_id.is_empty():
		return null
	var selected_portal: LinkedPortal = null
	for object_value: Variant in runtime.get_registered_objects():
		var candidate: LinkedPortal = object_value as LinkedPortal
		if (
			candidate == null
			or candidate == source_portal
			or candidate.link_group_id != source_portal.link_group_id
		):
			continue
		if selected_portal == null or candidate.object_id < selected_portal.object_id:
			selected_portal = candidate
	return selected_portal


func _find_portal_destination(portal: LinkedPortal, interactor: PlayerCharacter) -> Vector3i:
	var portal_surface: Vector3i = _get_portal_surface(portal)
	for offset: Vector2i in PORTAL_DESTINATION_OFFSETS:
		var candidate: Vector3i = Vector3i(
			portal_surface.x + offset.x,
			portal_surface.y + offset.y,
			portal_surface.z
		)
		if runtime.can_character_enter_surface(candidate, interactor):
			return candidate
	return INVALID_SURFACE


func _is_surface_adjacent_to_portal(surface: Vector3i, portal: LinkedPortal) -> bool:
	var portal_surface: Vector3i = _get_portal_surface(portal)
	return (
		surface.z == portal_surface.z
		and absi(surface.x - portal_surface.x) + absi(surface.y - portal_surface.y) == 1
		and runtime.can_character_enter_surface(surface, null)
	)


func _get_portal_surface(portal: LinkedPortal) -> Vector3i:
	return runtime.world_to_surface(portal.global_position, portal.surface_height)


func _clear_authoritative_payload(payload: Dictionary) -> void:
	payload.erase(PAYLOAD_OBJECT_ID)
	payload.erase(PAYLOAD_RESULTING_HEALTH)
	payload.erase(PAYLOAD_DESTINATION_PORTAL_ID)
	payload.erase(PAYLOAD_DESTINATION_SURFACE)
	payload.erase(PAYLOAD_WAS_TELEPORTED)
