class_name WorldVisibilityCharacterSourceCoordinator
extends RefCounted

signal refresh_requested(character: PlayerCharacter)
signal removal_requested(character: PlayerCharacter)

var runtime: WorldRuntime = null
var bound_characters: Array[PlayerCharacter] = []


func configure(new_runtime: WorldRuntime) -> void:
	disconnect_signals()
	runtime = new_runtime
	if runtime == null:
		return
	if not runtime.get_tree().node_added.is_connected(_on_scene_tree_node_added):
		runtime.get_tree().node_added.connect(_on_scene_tree_node_added)
	if runtime.action_stream != null and not runtime.action_stream.action_completed.is_connected(_on_action_completed):
		runtime.action_stream.action_completed.connect(_on_action_completed)
	for player: Dictionary in GameSession.get_players():
		for character: PlayerCharacter in runtime.get_squad_members(str(player.get("player_id", ""))):
			_bind_character(character)


func disconnect_signals() -> void:
	if runtime != null and runtime.is_inside_tree():
		var scene_tree: SceneTree = runtime.get_tree()
		if scene_tree.node_added.is_connected(_on_scene_tree_node_added):
			scene_tree.node_added.disconnect(_on_scene_tree_node_added)
		if runtime.action_stream != null and runtime.action_stream.action_completed.is_connected(_on_action_completed):
			runtime.action_stream.action_completed.disconnect(_on_action_completed)
	for character: PlayerCharacter in bound_characters.duplicate():
		_unbind_character(character)
	bound_characters.clear()
	runtime = null


func _bind_character(character: PlayerCharacter) -> bool:
	if character == null or not is_instance_valid(character) or bound_characters.has(character):
		return false
	bound_characters.append(character)
	var movement_callable: Callable = _on_character_movement_finished.bind(character)
	var radius_callable: Callable = _on_character_vision_radius_changed.bind(character)
	var vitality_callable: Callable = _on_character_vitality_changed.bind(character)
	var exiting_callable: Callable = _on_character_tree_exiting.bind(character)
	if not character.movement_finished.is_connected(movement_callable):
		character.movement_finished.connect(movement_callable)
	if not character.vision_radius_changed.is_connected(radius_callable):
		character.vision_radius_changed.connect(radius_callable)
	if not character.vitality_changed.is_connected(vitality_callable):
		character.vitality_changed.connect(vitality_callable)
	if not character.tree_exiting.is_connected(exiting_callable):
		character.tree_exiting.connect(exiting_callable)
	return true


func _unbind_character(character: PlayerCharacter) -> void:
	if character == null:
		return
	var movement_callable: Callable = _on_character_movement_finished.bind(character)
	var radius_callable: Callable = _on_character_vision_radius_changed.bind(character)
	var vitality_callable: Callable = _on_character_vitality_changed.bind(character)
	var exiting_callable: Callable = _on_character_tree_exiting.bind(character)
	if character.movement_finished.is_connected(movement_callable):
		character.movement_finished.disconnect(movement_callable)
	if character.vision_radius_changed.is_connected(radius_callable):
		character.vision_radius_changed.disconnect(radius_callable)
	if character.vitality_changed.is_connected(vitality_callable):
		character.vitality_changed.disconnect(vitality_callable)
	if character.tree_exiting.is_connected(exiting_callable):
		character.tree_exiting.disconnect(exiting_callable)
	bound_characters.erase(character)


func _on_scene_tree_node_added(node: Node) -> void:
	var character: PlayerCharacter = node as PlayerCharacter
	if character != null:
		_bind_new_character.call_deferred(character)


func _bind_new_character(character: PlayerCharacter) -> void:
	if _bind_character(character):
		refresh_requested.emit(character)


func _on_action_completed(action: WorldActionRecord) -> void:
	if runtime == null or action == null:
		return
	var should_refresh: bool = action.action_type == WorldActionRecord.ActionType.MOVE_PATH
	if action.action_type == WorldActionRecord.ActionType.INTERACTION:
		should_refresh = bool(action.payload.get(WorldInteraction.PAYLOAD_WAS_TELEPORTED, false))
	if not should_refresh:
		return
	var character: PlayerCharacter = runtime.get_entity_by_id(action.actor_entity_id) as PlayerCharacter
	if character != null:
		refresh_requested.emit(character)


func _on_character_movement_finished(
	_from_surface: Vector3i,
	_target_surface: Vector3i,
	character: PlayerCharacter
) -> void:
	if character != null and not character.is_executing_move_path:
		refresh_requested.emit(character)


func _on_character_vision_radius_changed(_current_radius: int, character: PlayerCharacter) -> void:
	refresh_requested.emit(character)


func _on_character_vitality_changed(
	_current_health: int,
	_maximum_health: int,
	character: PlayerCharacter
) -> void:
	refresh_requested.emit(character)


func _on_character_tree_exiting(character: PlayerCharacter) -> void:
	removal_requested.emit(character)
	_unbind_character(character)
