class_name WorldRuntime
extends Node

signal match_end_requested()
signal action_rejected(reason_code: String)
signal runtime_sync_failed(reason_code: String)
signal world_occupancy_changed

const CARDINAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i.LEFT,
	Vector2i.RIGHT,
	Vector2i.UP,
	Vector2i.DOWN,
]

@export var grid_path: NodePath = ^"../Grid"
@export var registry_path: NodePath = ^"../Registry"
@export var players_service_path: NodePath = ^"../PlayersService"
@export var combat_path: NodePath = ^"../Combat"
@export var network_path: NodePath = ^"../Network"
@export var turn_manager_path: NodePath = ^"../TurnManager"
@export var spawner_path: NodePath = ^"../WorldSpawner"
@export var awareness_path: NodePath = ^"../Awareness"
@export var interaction_path: NodePath = ^"../Interaction"
@export var item_usage_path: NodePath = ^"../ItemUsage"
@export var spells_path: NodePath = ^"../Spells"
@export var action_stream_path: NodePath = ^"../ActionStream"

var level: WorldLevel = null
var grid: WorldGrid = null
var registry: WorldRegistry = null
var players_service: WorldPlayers = null
var combat: WorldCombat = null
var network: WorldNetwork = null
var turn_manager: WorldTurns = null
var spawner: WorldSpawner = null
var awareness: WorldAwareness = null
var interaction: WorldInteraction = null
var item_usage: WorldItemUsage = null
var spells: WorldSpells = null
var action_stream: WorldActionStream = null
var action_router: WorldActionRouter = WorldActionRouter.new()
var state_snapshot: WorldStateSnapshot = WorldStateSnapshot.new()
var match_startup: WorldMatchStartup = WorldMatchStartup.new()


func configure_for_level(new_level: WorldLevel) -> void:
	level = new_level
	if level != null:
		level.configure_runtime(self)
	_bind_services()
	_configure_services()
	if players_service != null and not players_service.player_connection_changed.is_connected(_on_player_connection_changed):
		players_service.player_connection_changed.connect(_on_player_connection_changed)


func is_configured_for(target_level: WorldLevel) -> bool:
	return (
		level == target_level
		and grid != null
		and registry != null
		and players_service != null
		and combat != null
		and network != null
		and turn_manager != null
		and spawner != null
		and awareness != null
		and interaction != null
		and item_usage != null
		and spells != null
		and action_stream != null
	)


func start_match_runtime() -> String:
	_configure_services()
	return await match_startup.start_match_runtime()


func connect_signals() -> void:
	if network != null:
		network.connect_signals()
	if action_stream != null and not action_stream.runtime_sync_failed.is_connected(_on_action_stream_sync_failed):
		action_stream.runtime_sync_failed.connect(_on_action_stream_sync_failed)
	if action_stream != null and not action_stream.sync_state_changed.is_connected(_on_action_stream_sync_state_changed):
		action_stream.sync_state_changed.connect(_on_action_stream_sync_state_changed)


func disconnect_signals() -> void:
	if network != null:
		network.disconnect_signals()
	if action_stream != null and action_stream.runtime_sync_failed.is_connected(_on_action_stream_sync_failed):
		action_stream.runtime_sync_failed.disconnect(_on_action_stream_sync_failed)
	if action_stream != null and action_stream.sync_state_changed.is_connected(_on_action_stream_sync_state_changed):
		action_stream.sync_state_changed.disconnect(_on_action_stream_sync_state_changed)


func notify_local_action_rejected(reason_code: String) -> void:
	if reason_code.is_empty():
		return
	action_rejected.emit(reason_code)


func handle_entity_attack(
	attacker: Node,
	target_cell: Vector2i,
	should_broadcast: bool = true,
	should_broadcast_action: bool = true
) -> void:
	apply_attack_to_cell(attacker, target_cell, should_broadcast, should_broadcast_action)


func broadcast_entity_attack_action(attacker: Node, target_cell: Vector2i) -> void:
	combat.broadcast_attack_action(attacker, target_cell)


func handle_entity_move_started(entity: Node, from_cell: Vector2i, target_cell: Vector2i, should_broadcast: bool = true) -> void:
	network.request_entity_move_started(entity, from_cell, target_cell, should_broadcast)


func handle_entity_move_completed(entity: Node, from_cell: Vector2i, target_cell: Vector2i) -> void:
	complete_entity_move(entity, from_cell, target_cell)
	notify_entity_moved_in_turn(entity, from_cell, target_cell)


func handle_character_attack(attacker: Node, target_cell: Vector2i) -> void:
	handle_entity_attack(attacker, target_cell, true)


func request_character_attack(attacker: PlayerCharacter, target_cell: Vector2i) -> bool:
	return network.request_character_attack(attacker, target_cell)


func request_character_move(player: PlayerCharacter, direction: Vector2i) -> bool:
	return network.request_character_move(player, direction)


func request_character_interaction(interactor: PlayerCharacter, target_cell: Vector2i) -> void:
	network.request_character_interaction(interactor, target_cell)


func try_character_interaction(interactor: PlayerCharacter, target_cell: Vector2i) -> bool:
	if interaction == null:
		return false

	return interaction.try_interact(interactor, target_cell)


func request_inventory_add(item_id: String, amount: int) -> void:
	network.request_inventory_add(item_id, amount)


func request_inventory_move(inventory_kind: String, source_slot_index: int, target_slot_index: int) -> void:
	network.request_inventory_move(inventory_kind, source_slot_index, target_slot_index)


func request_inventory_delete(inventory_kind: String, slot_index: int) -> void:
	network.request_inventory_delete(inventory_kind, slot_index)


func request_inventory_use(slot_index: int) -> void:
	network.request_inventory_use(slot_index)


func broadcast_entity_ai_state(
	entity_id: String,
	state: String,
	target_entity_id: String,
	reason: String
) -> void:
	network.broadcast_entity_ai_state(entity_id, state, target_entity_id, reason)


func try_use_inventory_item(player: PlayerCharacter, slot_index: int) -> bool:
	if item_usage == null:
		return false

	return item_usage.try_use_item(player, slot_index)


func toggle_spell_targeting(player: PlayerCharacter, spell_slot_index: int) -> bool:
	return spells != null and spells.toggle_spell_targeting(player, spell_slot_index)


func cancel_spell_targeting(player: PlayerCharacter) -> bool:
	return spells != null and spells.cancel_spell_targeting(player)


func has_selected_spell(player: PlayerCharacter) -> bool:
	return spells != null and spells.has_selected_spell(player)


func get_selected_spell_slot_index(player: PlayerCharacter) -> int:
	if spells == null:
		return -1

	return spells.get_selected_spell_slot_index(player)


func request_selected_spell_cast(player: PlayerCharacter, target_cell: Vector2i) -> bool:
	return spells != null and spells.request_selected_spell_cast(player, target_cell)


func is_entity_casting(entity: Node) -> bool:
	return spells != null and spells.is_entity_casting(entity)


func is_entity_movement_blocked_by_spell(entity: Node) -> bool:
	return spells != null and spells.is_entity_movement_blocked(entity)


func get_remaining_spell_slot_uses(player: PlayerCharacter, spell_slot_index: int) -> int:
	if spells == null:
		return 0

	return spells.get_remaining_spell_slot_uses(player, spell_slot_index)


func apply_spell_damage_to_cell(caster: Node, target_cell: Vector2i, damage_amount: int) -> void:
	if combat != null:
		combat.apply_spell_damage_to_cell(caster, target_cell, damage_amount)


func register_entity(entity: Node) -> int:
	var result: int = registry.register_entity(entity)
	if result == WorldRegistry.RegistrationError.NONE and awareness != null:
		awareness.notify_entity_registered(entity)
	return result


func unregister_entity(entity: Node) -> void:
	if turn_manager != null:
		turn_manager.notify_entity_removed(entity)
	registry.unregister_entity(entity)


func register_object(target_object: Node, anchor_cell: Vector2i) -> int:
	return registry.register_object(target_object, anchor_cell)


func unregister_object(target_object: Node) -> void:
	registry.unregister_object(target_object)


func remove_world_object(target_object: GridObject) -> bool:
	return spawner.remove_world_object(target_object)


func remove_defeated_non_player(target_entity: NonPlayerEntity) -> bool:
	return spawner.remove_defeated_non_player(target_entity)


func spawn_world_object(type_key: String, cell: Vector2i) -> bool:
	return spawner.spawn_world_object(type_key, cell)


func get_placement_error(spawn_node: Node, anchor_cell: Vector2i) -> String:
	return registry.get_placement_error(spawn_node, anchor_cell)


func reserve_entity_cell(entity: Node, from_cell: Vector2i, target_cell: Vector2i) -> bool:
	return registry.reserve_entity_cell(entity, from_cell, target_cell)


func complete_entity_move(entity: Node, from_cell: Vector2i, target_cell: Vector2i) -> int:
	var result: int = registry.complete_entity_move(entity, from_cell, target_cell)
	if result == WorldRegistry.RegistrationError.NONE and awareness != null:
		awareness.notify_character_changed(entity)
	return result


func respawn_entity(entity: Node, cell: Vector2i) -> int:
	return registry.respawn_entity(entity, cell)


func request_player_respawn(player: PlayerCharacter) -> bool:
	return players_service.request_player_respawn(player) if players_service != null else false


func notify_character_defeated(character: PlayerCharacter) -> void:
	if awareness != null:
		awareness.notify_character_defeated(character)


func sync_entity_cell(entity: Node, cell: Vector2i) -> int:
	var previous_cell: Vector2i = Vector2i.ZERO
	var had_previous_cell: bool = entity != null and entity.get("current_cell") != null
	if had_previous_cell:
		previous_cell = entity.get("current_cell")

	var result: int = registry.sync_entity_cell(entity, cell)
	if result == WorldRegistry.RegistrationError.NONE and had_previous_cell and previous_cell != cell and awareness != null:
		awareness.notify_character_changed(entity)
	return result


func clear_registered_entities() -> void:
	registry.clear_entities()


func get_entity_by_id(entity_id: String) -> Node:
	return registry.get_entity_by_id(entity_id)


func get_entity_at_cell(cell: Vector2i) -> Node:
	return registry.get_entity_at_cell(cell)


func is_entity_registered_at_cell(entity: Node, cell: Vector2i) -> bool:
	return registry.is_entity_registered_at_cell(entity, cell)


func has_entity_cell_reservation(entity: Node, cell: Vector2i) -> bool:
	return registry.has_entity_cell_reservation(entity, cell)


func get_object_at_cell(cell: Vector2i) -> Node:
	return registry.get_object_at_cell(cell)


func get_object_by_id(object_id: String) -> Node:
	return registry.get_object_by_id(object_id)


func get_registered_objects() -> Array:
	return registry.get_registered_objects()


func get_registered_entities() -> Array:
	return registry.get_registered_entities()


func can_enter_cell(cell: Vector2i, moving_entity: Node = null) -> bool:
	return registry.can_enter_cell(cell, moving_entity)


func can_character_enter_cell(cell: Vector2i, ignored_entity: Entity = null) -> bool:
	return registry.can_character_enter_cell(cell, ignored_entity)


func get_reachable_cells_for_entity(entity: Entity, max_steps: int) -> Array[Vector2i]:
	var reachable_cells: Array[Vector2i] = []
	if entity == null or grid == null or registry == null or max_steps <= 0:
		return reachable_cells

	var start_cell: Vector2i = world_to_cell(entity.global_position)
	var maximum_distance: int = mini(max_steps, grid.get_grid_size().x * grid.get_grid_size().y)
	var frontier: Array[Vector2i] = [start_cell]
	var distances: Dictionary[Vector2i, int] = {start_cell: 0}
	var frontier_index: int = 0
	while frontier_index < frontier.size():
		var current_cell: Vector2i = frontier[frontier_index]
		frontier_index += 1
		var current_distance: int = distances[current_cell]
		if current_distance >= maximum_distance:
			continue

		for direction: Vector2i in CARDINAL_DIRECTIONS:
			var next_cell: Vector2i = current_cell + direction
			if distances.has(next_cell) or not registry.can_enter_cell(next_cell, entity):
				continue
			distances[next_cell] = current_distance + 1
			frontier.append(next_cell)
			reachable_cells.append(next_cell)

	return reachable_cells


func is_cell_interactable(cell: Vector2i) -> bool:
	return registry.is_cell_interactable(cell)


func get_cell_display_name(cell: Vector2i) -> String:
	return registry.get_cell_display_name(cell)


func apply_attack_to_cell(
	attacker: Node,
	cell: Vector2i,
	should_broadcast: bool = true,
	should_broadcast_action: bool = true
) -> void:
	combat.apply_attack_to_cell(attacker, cell, should_broadcast, should_broadcast_action)


func can_entity_move_in_turn(entity: Node) -> bool:
	if turn_manager == null:
		return true

	return turn_manager.can_entity_move(entity)


func can_entity_attack_in_turn(entity: Node, target_cell: Vector2i) -> bool:
	if turn_manager == null:
		return true

	return turn_manager.can_entity_attack(entity, target_cell)


func can_entity_interact_in_turn(entity: Node) -> bool:
	if turn_manager == null:
		return true

	return turn_manager.can_entity_interact(entity)


func can_entity_use_item_in_turn(entity: Node) -> bool:
	if turn_manager == null:
		return true

	return turn_manager.can_entity_use_item(entity)


func can_entity_cast_spell_in_turn(entity: Node) -> bool:
	if turn_manager == null:
		return true

	return turn_manager.can_entity_cast_spell(entity)


func can_entity_sync_state_in_turn(entity: Node) -> bool:
	if turn_manager == null:
		return true

	return turn_manager.can_entity_sync_state(entity)


func notify_entity_moved_in_turn(entity: Node, from_cell: Vector2i, target_cell: Vector2i) -> void:
	if turn_manager != null:
		turn_manager.notify_entity_moved(entity, from_cell, target_cell)


func notify_entity_attacked_in_turn(entity: Node, target_cell: Vector2i) -> void:
	if turn_manager != null:
		turn_manager.notify_entity_attacked(entity, target_cell)


func notify_entity_interacted_in_turn(entity: Node) -> void:
	if turn_manager != null:
		turn_manager.notify_entity_interacted(entity)


func notify_entity_action_finished_in_turn(entity: Node, world_turn_generation: int = 0) -> void:
	if turn_manager != null:
		var non_player: NonPlayerEntity = entity as NonPlayerEntity
		if non_player != null and world_turn_generation == 0:
			world_turn_generation = non_player.get_behavior_generation()
		turn_manager.notify_entity_action_finished(entity, world_turn_generation)


func request_end_turn(entity: Node) -> void:
	if turn_manager != null:
		turn_manager.request_end_turn(entity)


func create_action_request_id() -> int:
	if action_stream == null:
		return 0
	return action_stream.create_local_request_id()


func get_turn_revision() -> int:
	return turn_manager.get_turn_revision() if turn_manager != null else 0


func enqueue_player_action(
	action_type: WorldActionRecord.ActionType,
	player: PlayerCharacter,
	payload: Dictionary,
	request_id: int,
	requester_peer_id: int,
	requested_turn_revision: int = -1,
	requested_match_id: String = ""
) -> bool:
	if action_stream == null or player == null or request_id <= 0:
		return false
	var action: WorldActionRecord = WorldActionRecord.create(
		request_id,
		GameSession.get_match_id() if requested_match_id.is_empty() else requested_match_id,
		player.steam_id,
		player.entity_id,
		action_type,
		turn_manager.get_turn_revision() if requested_turn_revision < 0 and turn_manager != null else maxi(requested_turn_revision, 0),
		payload
	)
	return action_stream.enqueue_external_action(action, requester_peer_id)


func enqueue_system_action(action_type: WorldActionRecord.ActionType, payload: Dictionary = {}) -> bool:
	if action_stream == null:
		return false
	var action: WorldActionRecord = WorldActionRecord.create(
		0,
		GameSession.get_match_id(),
		0,
		str(payload.get("actor_entity_id", "")),
		action_type,
		turn_manager.get_turn_revision() if turn_manager != null else 0,
		payload
	)
	return action_stream.enqueue_internal_action(action)


func has_pending_move(entity: Node) -> bool:
	if action_stream == null or entity == null:
		return false
	return action_stream.has_pending_move(get_entity_id(entity))


func is_action_stream_idle() -> bool:
	return action_stream == null or action_stream.is_idle()


func get_current_action_sequence_id() -> int:
	return 0 if action_stream == null else action_stream.get_current_sequence_id()


func get_expected_remote_action_sequence_id() -> int:
	return 1 if action_stream == null else action_stream.get_expected_remote_sequence_id()


func claim_current_action_subsequence_id() -> int:
	return 0 if action_stream == null else action_stream.claim_current_subsequence_id()


func allows_spell_intents() -> bool:
	return action_stream == null or action_stream.allows_spell_intents()


func is_world_turn_active() -> bool:
	return turn_manager != null and turn_manager.is_world_turn_active()


func is_player_connected(steam_id: int) -> bool:
	return players_service == null or players_service.is_player_connected(steam_id)


func request_action_stream_snapshot(peer_id: int) -> void:
	if action_stream != null:
		action_stream.request_peer_snapshot(peer_id)


func create_action_stream_snapshot(next_stream_sequence_id: int) -> Dictionary:
	return state_snapshot.create_action_stream_snapshot(next_stream_sequence_id)


func apply_action_stream_snapshot(snapshot: Dictionary) -> bool:
	return state_snapshot.apply_action_stream_snapshot(snapshot)


func receive_action_profile_payload(sequence_id: int, payload: Dictionary) -> void:
	if action_stream != null:
		action_stream.receive_profile_payload(sequence_id, payload)


func broadcast_action_profile_payload(action: WorldActionRecord) -> void:
	action_router.broadcast_action_profile_payload(action)


func get_action_schema_rejection_reason(action: WorldActionRecord) -> String:
	return action_router.get_schema_rejection_reason(action)


func get_action_acceptance_rejection_reason(action: WorldActionRecord) -> String:
	return action_router.get_acceptance_rejection_reason(action)


func reserve_action_on_accept(action: WorldActionRecord) -> String:
	return action_router.reserve_on_accept(action)


func release_action_reservation(action: WorldActionRecord) -> void:
	action_router.release_reservation(action)


func get_action_rejection_reason(action: WorldActionRecord) -> String:
	return action_router.get_rejection_reason(action)


func execute_authoritative_action(action: WorldActionRecord) -> bool:
	return await action_router.execute_authoritative(action)


func play_remote_action(action: WorldActionRecord) -> void:
	await action_router.play_remote(action)


func finalize_authoritative_action(action: WorldActionRecord) -> void:
	action_router.finalize_authoritative(action)


func is_turn_mode_enabled() -> bool:
	if turn_manager == null:
		return false

	return turn_manager.is_turn_mode_enabled()


func get_entity_id(entity: Node) -> String:
	return combat.get_entity_id(entity)


func get_entity_display_name(entity: Node) -> String:
	return combat.get_entity_display_name(entity)


func print_entity_attack_result(
	attacker_entity_id: String,
	target_entity_id: String,
	damage_amount: int,
	target_health: int,
	target_max_health: int
) -> void:
	combat.print_entity_attack_result(
		attacker_entity_id,
		target_entity_id,
		damage_amount,
		target_health,
		target_max_health
	)


func print_non_entity_attack_result(attacker: Node, target_cell: Vector2i) -> void:
	combat.print_non_entity_attack_result(attacker, target_cell)


func get_player_by_steam_id(steam_id: int) -> PlayerCharacter:
	return players_service.get_player_by_steam_id(steam_id)


func get_local_player() -> PlayerCharacter:
	if players_service == null:
		return null

	return players_service.get_local_player()


func get_player_by_entity_id(entity_id: String) -> PlayerCharacter:
	if players_service == null:
		return null
	return players_service.get_player_by_entity_id(entity_id)


func get_players_root() -> Node2D:
	return players_service.get_players_root()


func update_player_authorities() -> void:
	players_service.update_player_authorities()


func broadcast_object_state(target_object: Node) -> void:
	network.broadcast_object_state(target_object)


func broadcast_all_object_states() -> void:
	network.broadcast_all_object_states()


func is_cell_walkable(cell: Vector2i) -> bool:
	return grid.is_cell_walkable(cell)


func is_cell_walkable_for_entity(cell: Vector2i, entity: Entity) -> bool:
	return grid.is_cell_walkable_for_entity(cell, entity)


func is_cell_walkable_for_character(cell: Vector2i) -> bool:
	return grid.is_cell_walkable_for_character(cell)


func is_cell_inside(cell: Vector2i) -> bool:
	return grid.is_cell_inside(cell)


func get_grid_size() -> Vector2i:
	return _get_grid_service().get_grid_size()


func get_cell_size() -> int:
	return _get_grid_service().get_cell_size()


func get_grid_world_bounds() -> Rect2:
	return _get_grid_service().get_world_bounds()


func world_to_cell(world_position: Vector2) -> Vector2i:
	return _get_grid_service().world_to_cell(world_position)


func cell_to_world(cell: Vector2i) -> Vector2:
	return _get_grid_service().cell_to_world(cell)


func get_cell_center(world_position: Vector2) -> Vector2:
	return _get_grid_service().get_cell_center(world_position)


func get_adjacent_cell_center(world_position: Vector2, direction: Vector2i) -> Vector2:
	return _get_grid_service().get_adjacent_cell_center(world_position, direction)


func print_console(text: String) -> void:
	ConsoleOutput.print_line(text)


func _bind_services() -> void:
	if level == null:
		return

	grid = get_node_or_null(grid_path) as WorldGrid
	registry = get_node_or_null(registry_path) as WorldRegistry
	players_service = get_node_or_null(players_service_path) as WorldPlayers
	combat = get_node_or_null(combat_path) as WorldCombat
	network = get_node_or_null(network_path) as WorldNetwork
	turn_manager = get_node_or_null(turn_manager_path) as WorldTurns
	spawner = get_node_or_null(spawner_path) as WorldSpawner
	awareness = get_node_or_null(awareness_path) as WorldAwareness
	interaction = get_node_or_null(interaction_path) as WorldInteraction
	item_usage = get_node_or_null(item_usage_path) as WorldItemUsage
	spells = get_node_or_null(spells_path) as WorldSpells
	action_stream = get_node_or_null(action_stream_path) as WorldActionStream

	if grid != null:
		grid.configure_context(self, level)
	if registry != null:
		registry.configure_context(self, level)
		if not registry.occupancy_changed.is_connected(_on_registry_occupancy_changed):
			registry.occupancy_changed.connect(_on_registry_occupancy_changed)
	if players_service != null:
		players_service.configure_context(self, level)
	if combat != null:
		combat.configure_context(self, level)
	if network != null:
		network.configure_context(self, level)
		if not network.match_end_requested.is_connected(_on_network_match_end_requested):
			network.match_end_requested.connect(_on_network_match_end_requested)
	if turn_manager != null:
		turn_manager.configure_context(self, level)
	if spawner != null:
		spawner.configure_context(self, level)
	if awareness != null:
		awareness.configure_context(self, level)
	if interaction != null:
		interaction.configure_context(self, level)
	if item_usage != null:
		item_usage.configure_context(self, level)
	if spells != null:
		spells.configure_context(self, level)
	if action_stream != null:
		action_stream.configure_context(self, level)
	action_router.configure_context(self, players_service, network, turn_manager, spells)
	state_snapshot.configure_context(
		self,
		registry,
		spawner,
		turn_manager,
		spells,
		NetworkManager.store
	)
	match_startup.configure_context(
		self,
		registry,
		network,
		players_service,
		action_stream,
		spawner
	)


func _configure_services() -> void:
	if level == null:
		return

	if grid != null:
		grid.configure(
			level.get_grid_size(),
			level.get_walkable_layer_names(),
			level.get_character_walkable_layer_names()
		)
	if players_service != null:
		players_service.configure(level.get_spawn_cells())


func register_level_entities() -> void:
	if level == null:
		return

	var world_entities_root: Node = level.get_world_entities_root()
	if world_entities_root == null:
		return

	_register_world_entity_children(world_entities_root)


func _register_world_entity_children(parent: Node) -> void:
	for child in parent.get_children():
		if child.get("entity_type") != null and int(child.get("entity_type")) != Entity.EntityType.CHARACTER:
			_ensure_world_entity_id(child)
			register_entity(child)

		_register_world_entity_children(child)


func _ensure_world_entity_id(entity: Node) -> void:
	if entity.get("entity_id") == null:
		return

	if not str(entity.get("entity_id")).is_empty():
		return

	entity.set("entity_id", entity.name)


func _get_grid_service() -> WorldGrid:
	return grid


func _on_network_match_end_requested() -> void:
	match_end_requested.emit()


func _on_action_stream_sync_failed(reason_code: String) -> void:
	runtime_sync_failed.emit(reason_code)


func _on_action_stream_sync_state_changed(is_synchronizing: bool) -> void:
	var player: PlayerCharacter = get_local_player()
	if player != null:
		player.can_receive_input = not is_synchronizing and GameSession.has_committed_match()


func _on_player_connection_changed(steam_id: int, is_connected: bool) -> void:
	if is_connected or not GameSession.is_host():
		return
	if action_stream != null:
		action_stream.cancel_actions_for_steam_id(steam_id)
	if action_stream != null:
		action_stream.prune_disconnected_snapshot_peers()
	if turn_manager != null:
		turn_manager.handle_player_disconnected(steam_id)


func _on_registry_occupancy_changed() -> void:
	world_occupancy_changed.emit()
