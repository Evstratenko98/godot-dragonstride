class_name WorldPlayersDebugCommands
extends RefCounted

const KILL_COMMAND_NAME := "game_character_kill"
const INVENTORY_ADD_COMMAND_NAME := "game_inventory_add"

var players: WorldPlayers = null
var runtime: WorldRuntime = null
var level: WorldLevel = null


func configure_context(
	new_players: WorldPlayers,
	new_runtime: WorldRuntime,
	new_level: WorldLevel
) -> void:
	players = new_players
	runtime = new_runtime
	level = new_level
	if level != null and level.allows_debug_commands():
		register_commands()


func unregister_commands() -> void:
	var console: Node = players.get_node_or_null("/root/Console")
	if console == null or not console.has_method("remove_command"):
		return
	console.remove_command(KILL_COMMAND_NAME)
	console.remove_command(INVENTORY_ADD_COMMAND_NAME)


func kill_local_character() -> void:
	if not _can_mutate():
		ConsoleOutput.print_console("ERROR: Debug mutations are unavailable for this level.", runtime)
		return
	if players.local_player == null:
		ConsoleOutput.print_console("ERROR: Local character is not ready.", runtime)
		return
	if GameSession.is_multiplayer() and not NetworkManager.connection.is_ready():
		ConsoleOutput.print_console("ERROR: Cannot kill character: network is not ready.", runtime)
		return
	var request_id: int = runtime.create_action_request_id()
	if GameSession.is_multiplayer() and not GameSession.is_host():
		NetworkManager.character.request_character_kill(GameSession.get_match_id(), runtime.get_turn_revision(), request_id)
		return
	runtime.enqueue_player_action(
		WorldActionRecord.ActionType.CHARACTER_KILL,
		players.local_player,
		{},
		request_id,
		0
	)


func add_inventory_item(item_id: String, amount_text: String) -> void:
	if not _can_mutate():
		ConsoleOutput.print_console("ERROR: Debug mutations are unavailable for this level.", runtime)
		return
	if players.local_player == null:
		ConsoleOutput.print_console("ERROR: Local character is not ready.", runtime)
		return
	if not players.local_player.character_inventory.has_item_id(item_id):
		ConsoleOutput.print_console("ERROR: Unknown inventory item: %s." % item_id, runtime)
		return
	if (
		not amount_text.is_valid_int()
		or amount_text.to_int() <= 0
		or amount_text.to_int() > CharacterInventory.ITEM_SLOT_COUNT * CharacterInventory.DEFAULT_MAX_STACK_SIZE
	):
		ConsoleOutput.print_console(
			"ERROR: Usage: %s <item_id> <positive_amount>." % INVENTORY_ADD_COMMAND_NAME,
			runtime
		)
		return
	if GameSession.is_multiplayer() and not NetworkManager.connection.is_ready():
		ConsoleOutput.print_console("ERROR: Cannot add inventory item: network is not ready.", runtime)
		return
	var amount: int = amount_text.to_int()
	runtime.request_inventory_add(item_id, amount)
	ConsoleOutput.print_console("Requested %d %s inventory item(s)." % [amount, item_id], runtime)


func register_commands() -> void:
	var console: Node = players.get_node_or_null("/root/Console")
	if console == null or not console.has_method("add_command"):
		return
	console.add_command(KILL_COMMAND_NAME, kill_local_character, 0, 0, "Kill and immediately respawn the local character.")
	console.add_command(
		INVENTORY_ADD_COMMAND_NAME,
		add_inventory_item,
		["item_id", "amount"],
		2,
		"Add a complete item amount to the local character inventory."
	)
	if console.has_method("add_command_autocomplete_list"):
		console.add_command_autocomplete_list(INVENTORY_ADD_COMMAND_NAME, CharacterInventory.KNOWN_ITEM_IDS)


func allows_commands() -> bool:
	return level != null and level.allows_debug_commands()


func _can_mutate() -> bool:
	return allows_commands()
