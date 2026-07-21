class_name WorldTurnsDebugCommands
extends RefCounted

var turns: WorldTurns = null


func configure(owner: WorldTurns, should_register: bool) -> void:
	turns = owner
	if should_register:
		register_commands()


func register_commands() -> void:
	var console: Node = turns.get_node_or_null("/root/Console")
	if console == null or not console.has_method("add_command"):
		return
	console.add_command("game_turns_enable", turns.enable_turn_mode, 0, 0, "Enable turn-based mode.")
	console.add_command("game_turns_disable", turns.disable_turn_mode, 0, 0, "Disable turn-based mode.")
	console.add_command("game_turns_status", turns.print_turn_status, 0, 0, "Print turn-based mode status.")


func unregister_commands() -> void:
	if turns == null:
		return
	var console: Node = turns.get_node_or_null("/root/Console")
	if console == null or not console.has_method("remove_command"):
		return
	console.remove_command("game_turns_enable")
	console.remove_command("game_turns_disable")
	console.remove_command("game_turns_status")
