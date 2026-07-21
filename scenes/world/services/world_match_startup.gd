class_name WorldMatchStartup
extends RefCounted

var runtime: WorldRuntime = null
var registry: WorldRegistry = null
var network: WorldNetwork = null
var players: WorldPlayers = null
var action_stream: WorldActionStream = null
var spawner: WorldSpawner = null


func configure_context(
	new_runtime: WorldRuntime,
	new_registry: WorldRegistry,
	new_network: WorldNetwork,
	new_players: WorldPlayers,
	new_action_stream: WorldActionStream,
	new_spawner: WorldSpawner
) -> void:
	runtime = new_runtime
	registry = new_registry
	network = new_network
	players = new_players
	action_stream = new_action_stream
	spawner = new_spawner


func start_match_runtime() -> String:
	if not _has_required_services():
		return "runtime_services_unavailable"

	registry.collect_blockers()
	network.apply_cached_object_states()
	players.prepare_players_root()
	runtime.register_level_entities()

	var preparation_error: String = await _prepare_players_and_synchronize()
	if not preparation_error.is_empty():
		return preparation_error

	spawner.apply_cached_world_removals()
	network.apply_cached_entity_ai_states()
	network.apply_cached_entity_vitality_states()
	return ""


func _prepare_players_and_synchronize() -> String:
	if GameSession.is_singleplayer():
		players.start_singleplayer()
		return ""
	if not GameSession.is_multiplayer():
		push_warning("Unknown game session mode: " + str(GameSession.mode))
		players.start_singleplayer()
		return ""

	if not NetworkManager.connection.is_ready():
		push_warning(
			"Multiplayer session started before network became ready: "
				+ NetworkManager.connection.last_error
		)
	var player_prepare_error: String = await players.prepare_multiplayer_players()
	if not player_prepare_error.is_empty():
		return player_prepare_error
	var sync_error: String = await action_stream.synchronize_initial_state()
	if not sync_error.is_empty():
		NetworkManager.players.report_player_world_failed(GameSession.get_match_id(), sync_error)
		return sync_error
	return await players.report_world_ready_and_wait_for_commit()


func _has_required_services() -> bool:
	return (
		runtime != null
		and registry != null
		and network != null
		and players != null
		and action_stream != null
		and spawner != null
	)
