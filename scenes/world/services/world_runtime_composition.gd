class_name WorldRuntimeComposition
extends RefCounted


func bind_services(runtime: WorldRuntime, level: WorldLevel) -> void:
	if level == null:
		return
	runtime.grid = runtime.get_node_or_null(runtime.grid_path) as WorldGrid
	runtime.registry = runtime.get_node_or_null(runtime.registry_path) as WorldRegistry
	runtime.players_service = runtime.get_node_or_null(runtime.players_service_path) as WorldPlayers
	runtime.combat = runtime.get_node_or_null(runtime.combat_path) as WorldCombat
	runtime.network = runtime.get_node_or_null(runtime.network_path) as WorldNetwork
	runtime.turn_manager = runtime.get_node_or_null(runtime.turn_manager_path) as WorldTurns
	runtime.spawner = runtime.get_node_or_null(runtime.spawner_path) as WorldSpawner
	runtime.awareness = runtime.get_node_or_null(runtime.awareness_path) as WorldAwareness
	runtime.interaction = runtime.get_node_or_null(runtime.interaction_path) as WorldInteraction
	runtime.item_usage = runtime.get_node_or_null(runtime.item_usage_path) as WorldItemUsage
	runtime.spells = runtime.get_node_or_null(runtime.spells_path) as WorldSpells
	runtime.loot = runtime.get_node_or_null(runtime.loot_path) as WorldLoot
	runtime.action_stream = runtime.get_node_or_null(runtime.action_stream_path) as WorldActionStream
	runtime.visibility = runtime.get_node_or_null(runtime.visibility_path) as WorldVisibility
	runtime.abilities = runtime.get_node_or_null(runtime.abilities_path) as WorldCharacterAbilities

	if runtime.grid != null:
		runtime.grid.configure_context(runtime, level)
	if runtime.registry != null:
		runtime.registry.configure_context(runtime, level)
	if runtime.players_service != null:
		runtime.players_service.configure_context(runtime, level)
	if runtime.combat != null:
		runtime.combat.configure_context(runtime, level)
	if runtime.network != null:
		runtime.network.configure_context(runtime, level)
	if runtime.turn_manager != null:
		runtime.turn_manager.configure_context(runtime, level)
	if runtime.spawner != null:
		runtime.spawner.configure_context(runtime, level)
	if runtime.awareness != null:
		runtime.awareness.configure_context(runtime, level)
	if runtime.interaction != null:
		runtime.interaction.configure_context(runtime, level)
	if runtime.item_usage != null:
		runtime.item_usage.configure_context(runtime, level)
	if runtime.spells != null:
		runtime.spells.configure_context(runtime, level)
	if runtime.loot != null:
		runtime.loot.configure_context(runtime, level)
	if runtime.action_stream != null:
		runtime.action_stream.configure_context(runtime, level)
	if runtime.abilities != null:
		runtime.abilities.configure_context(runtime, level)
	runtime.action_coordinator.configure_context(runtime)


func configure_level_services(runtime: WorldRuntime, level: WorldLevel) -> void:
	if level == null:
		return
	if runtime.grid != null:
		runtime.grid.configure(
			level.get_grid_size(),
			level.get_walkable_layer_names(),
			level.get_character_walkable_layer_names()
		)
	if runtime.players_service != null:
		runtime.players_service.configure(level.get_spawn_surfaces())
	if runtime.visibility != null:
		runtime.visibility.configure_context(runtime, level)
