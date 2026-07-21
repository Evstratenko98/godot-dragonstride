class_name WorldSpawnerDebugCommands
extends RefCounted

const CREATE_COMMAND := "game_create"
const FILL_COMMAND := "game_create_full"
const CLEAR_COMMAND := "game_clear_full"

var spawner: WorldSpawner = null


func configure(owner: WorldSpawner, should_register: bool, type_keys: Array) -> void:
	spawner = owner
	if not should_register:
		return
	var console: Node = spawner.get_node_or_null("/root/Console")
	if console == null or not console.has_method("add_command"):
		return
	console.add_command(CREATE_COMMAND, spawner.console_create, ["type", "x", "y"], 3, "Create an allowed entity or object on a grid cell.")
	console.add_command(FILL_COMMAND, spawner.console_create_full, ["type"], 1, "Fill available ground cells with an allowed entity or object.")
	console.add_command(CLEAR_COMMAND, spawner.console_clear_full, ["type"], 0, "Remove one allowed type, or all world items when type is omitted.")
	if console.has_method("add_command_autocomplete_list"):
		var autocomplete_keys: PackedStringArray = PackedStringArray()
		for type_key: Variant in type_keys:
			autocomplete_keys.append(str(type_key))
		console.add_command_autocomplete_list(CREATE_COMMAND, autocomplete_keys)
		console.add_command_autocomplete_list(FILL_COMMAND, autocomplete_keys)
		console.add_command_autocomplete_list(CLEAR_COMMAND, autocomplete_keys)


func unregister_commands() -> void:
	if spawner == null:
		return
	var console: Node = spawner.get_node_or_null("/root/Console")
	if console == null or not console.has_method("remove_command"):
		return
	console.remove_command(CREATE_COMMAND)
	console.remove_command(FILL_COMMAND)
	console.remove_command(CLEAR_COMMAND)
