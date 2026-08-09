class_name WarriorAiLogger
extends RefCounted

var warrior: Warrior = null


func configure(owner: Warrior) -> void:
	warrior = owner


func print_state_change(previous_state: String, previous_target_entity_id: String, reason: String) -> void:
	if warrior.runtime == null:
		return
	if previous_state != warrior.STATE_ACTIVE and warrior.ai_state == warrior.STATE_ACTIVE:
		_print("%s became active and targets %s." % [warrior.get_display_name(), _get_target_display_name(warrior.target_entity_id)])
		return
	if previous_state == warrior.STATE_ACTIVE and warrior.ai_state == warrior.STATE_ACTIVE and previous_target_entity_id != warrior.target_entity_id:
		_print("%s switched target from %s to %s." % [warrior.get_display_name(), _get_target_display_name(previous_target_entity_id), _get_target_display_name(warrior.target_entity_id)])
		return
	if previous_state == warrior.STATE_ACTIVE and warrior.ai_state == warrior.STATE_PASSIVE:
		_print("%s became passive: %s." % [warrior.get_display_name(), reason if not reason.is_empty() else "no target"])


func _get_target_display_name(entity_id: String) -> String:
	if entity_id.is_empty():
		return "none"
	var entity: Node = warrior.runtime.get_entity_by_id(entity_id)
	if (
		entity is Entity
		and warrior.runtime.visibility != null
		and not warrior.runtime.visibility.is_surface_visible_for_local_player((entity as Entity).current_surface)
	):
		return "unknown"
	return warrior.runtime.get_entity_display_name(entity) if entity != null else entity_id


func _print(text: String) -> void:
	if (
		warrior.runtime.visibility != null
		and not warrior.runtime.visibility.is_surface_visible_for_local_player(warrior.current_surface)
	):
		return
	ConsoleOutput.print_console(text, warrior.runtime)
