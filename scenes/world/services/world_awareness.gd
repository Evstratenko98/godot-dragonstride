class_name WorldAwareness
extends Node

var runtime: WorldRuntime = null
var level: WorldLevel = null


func configure_context(new_runtime: WorldRuntime, new_level: WorldLevel) -> void:
	runtime = new_runtime
	level = new_level


func notify_entity_registered(entity: Node) -> void:
	if not _can_update_warrior_ai_state():
		return

	if is_character_entity(entity):
		notify_character_changed(entity)
		return

	if entity is NonPlayerEntity:
		(entity as NonPlayerEntity).consider_character_triggers(_get_registered_characters())


func notify_character_changed(character: Node) -> void:
	if not _can_update_warrior_ai_state() or not is_character_entity(character):
		return

	for entity in runtime.get_registered_entities():
		if entity != character and entity is NonPlayerEntity:
			(entity as NonPlayerEntity).consider_character_trigger(character)


func notify_character_defeated(character: PlayerCharacter) -> void:
	if not _can_update_warrior_ai_state() or character == null:
		return

	var character_entity_id: String = runtime.get_entity_id(character)
	if character_entity_id.is_empty():
		return

	for entity in runtime.get_registered_entities():
		if entity is NonPlayerEntity:
			(entity as NonPlayerEntity).consider_character_defeated(character_entity_id)


func is_character_entity(entity: Node) -> bool:
	return entity != null and entity.get("entity_type") != null and int(entity.get("entity_type")) == Entity.EntityType.CHARACTER


func _get_registered_characters() -> Array[Node]:
	var characters: Array[Node] = []
	for entity in runtime.get_registered_entities():
		if is_character_entity(entity):
			characters.append(entity)

	characters.sort_custom(func(a: Node, b: Node) -> bool:
		return runtime.get_entity_id(a) < runtime.get_entity_id(b)
	)
	return characters


func _can_update_warrior_ai_state() -> bool:
	if runtime == null or not runtime.is_turn_mode_enabled():
		return false

	return not GameSession.is_multiplayer() or GameSession.is_host()
