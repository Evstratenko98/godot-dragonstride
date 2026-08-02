class_name LocalSquadSelectionController
extends Node

signal selected_character_changed(previous_character: PlayerCharacter, selected_character: PlayerCharacter)

var runtime: WorldRuntime = null
var squad_registry: PlayerSquadRegistry = null
var camera: GameCamera = null
var selected_character: PlayerCharacter = null


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_action_pressed("cycle_squad_member") or event.is_echo():
		return
	if request_select_next_available():
		get_viewport().set_input_as_handled()


func configure(new_runtime: WorldRuntime, new_registry: PlayerSquadRegistry, new_camera: GameCamera) -> void:
	runtime = new_runtime
	squad_registry = new_registry
	camera = new_camera
	ensure_available_selection()


func set_camera(new_camera: GameCamera) -> void:
	camera = new_camera
	_focus_camera()


func focus_selected_character() -> void:
	_focus_camera()


func clear_selection() -> void:
	_set_selected_character(null)


func get_selected_character() -> PlayerCharacter:
	return selected_character if selected_character != null and is_instance_valid(selected_character) else null


func ensure_available_selection() -> void:
	if _is_available(selected_character):
		return
	var members: Array[PlayerCharacter] = _get_local_members()
	for member: PlayerCharacter in members:
		if _is_available(member):
			_set_selected_character(member)
			return
	_set_selected_character(null)


func request_select_character(next_character: PlayerCharacter) -> bool:
	if not _can_accept_selection_input():
		return false
	if not _get_local_members().has(next_character) or not _is_available(next_character):
		return false
	_set_selected_character(next_character)
	return true


func request_select_next_available() -> bool:
	if not _can_accept_selection_input():
		return false
	var members: Array[PlayerCharacter] = _get_local_members()
	if members.is_empty():
		_set_selected_character(null)
		return false
	var start_index: int = members.find(selected_character)
	for offset: int in range(1, members.size() + 1):
		var candidate_index: int = (start_index + offset + members.size()) % members.size()
		var candidate: PlayerCharacter = members[candidate_index]
		if _is_available(candidate):
			_set_selected_character(candidate)
			return true
	return false


func _set_selected_character(next_character: PlayerCharacter) -> void:
	var previous_character: PlayerCharacter = get_selected_character()
	if previous_character == next_character:
		_focus_camera()
		return
	if previous_character != null:
		if runtime != null:
			runtime.cancel_spell_targeting(previous_character)
		previous_character.set_selected_local_character(false)
	selected_character = next_character
	if selected_character != null:
		selected_character.set_selected_local_character(true)
	_focus_camera()
	selected_character_changed.emit(previous_character, selected_character)


func _focus_camera() -> void:
	if camera != null and camera.is_follow_mode() and selected_character != null:
		camera.follow_character(selected_character)


func _get_local_members() -> Array[PlayerCharacter]:
	return squad_registry.get_local_members() if squad_registry != null else []


func _is_available(member: PlayerCharacter) -> bool:
	return (
		member != null
		and is_instance_valid(member)
		and member.is_inside_tree()
		and member.visible
		and member.health > 0
		and runtime != null
		and runtime.get_entity_by_id(member.entity_id) == member
	)


func _is_local_action_busy() -> bool:
	for member: PlayerCharacter in _get_local_members():
		if member.is_local_input_blocked:
			return true
	if selected_character == null or not is_instance_valid(selected_character):
		return false
	return (
		selected_character.is_moving
		or selected_character.is_attacking
		or selected_character.is_executing_move_path
		or (runtime != null and runtime.is_entity_casting(selected_character))
		or (runtime != null and runtime.has_pending_move_path(selected_character))
	)


func _can_accept_selection_input() -> bool:
	return not _is_text_input_focused() and not _is_console_open() and not _is_local_action_busy()


func _is_text_input_focused() -> bool:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit


func _is_console_open() -> bool:
	var console: Node = get_node_or_null("/root/Console")
	return console != null and console.has_method("is_visible") and console.is_visible()
