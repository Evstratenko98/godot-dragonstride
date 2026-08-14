class_name WorldRuntime
extends Node

signal match_end_requested()
signal action_rejected(reason_code: String)
signal runtime_sync_failed(reason_code: String)
signal world_occupancy_changed
signal selected_local_character_changed(character: PlayerCharacter)

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
@export var loot_path: NodePath = ^"../Loot"
@export var action_stream_path: NodePath = ^"../ActionStream"
@export var visibility_path: NodePath = ^"../Visibility"
@export var abilities_path: NodePath = ^"../CharacterAbilities"

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
var loot: WorldLoot = null
var action_stream: WorldActionStream = null
var visibility: WorldVisibility = null
var abilities: WorldCharacterAbilities = null
var action_coordinator: WorldActionRuntimeCoordinator = WorldActionRuntimeCoordinator.new()
var composition: WorldRuntimeComposition = WorldRuntimeComposition.new()
var event_coordinator: WorldRuntimeEventCoordinator = WorldRuntimeEventCoordinator.new()
var spatial: WorldSpatialFacade = WorldSpatialFacade.new()


func configure_for_level(new_level: WorldLevel) -> void:
	event_coordinator.configure(self)
	level = new_level
	if level != null:
		level.configure_runtime(self)
	_bind_services()
	_configure_services()
	event_coordinator.connect_service_signals()


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
		and loot != null
		and action_stream != null
		and visibility != null
		and abilities != null
	)


func start_match_runtime() -> String:
	_configure_services()
	return await action_coordinator.start_match_runtime()


func connect_signals() -> void:
	event_coordinator.connect_runtime_signals()


func disconnect_signals() -> void:
	event_coordinator.disconnect_runtime_signals()


func notify_local_action_rejected(reason_code: String) -> void:
	if reason_code.is_empty():
		return
	action_rejected.emit(reason_code)


func handle_entity_attack(
	attacker: Node,
	target_surface: Vector3i,
	should_broadcast: bool = true,
	should_broadcast_action: bool = true
) -> void:
	apply_attack_to_surface(attacker, target_surface, should_broadcast, should_broadcast_action)


func broadcast_entity_attack_action(attacker: Node, target_surface: Vector3i) -> void:
	combat.broadcast_attack_action(attacker, target_surface)


func handle_entity_move_started(entity: Node, from_surface: Vector3i, target_surface: Vector3i, should_broadcast: bool = true) -> void:
	network.request_entity_move_started(entity, from_surface, target_surface, should_broadcast)


func handle_entity_move_completed(entity: Node, from_surface: Vector3i, target_surface: Vector3i, movement_step_cost: int = 1) -> void:
	complete_entity_move(entity, from_surface, target_surface)
	notify_entity_moved_in_turn(entity, from_surface, target_surface, movement_step_cost)


func handle_character_attack(attacker: Node, target_surface: Vector3i) -> void:
	handle_entity_attack(attacker, target_surface, true)


func request_character_attack(attacker: PlayerCharacter, target_surface: Vector3i) -> bool:
	if visibility != null and not visibility.is_surface_visible_for_character(attacker, target_surface):
		return false
	return network.request_character_attack(attacker, target_surface)


func request_character_move_path(player: PlayerCharacter, requested_path: Array[Vector3i]) -> bool:
	return network.request_character_move_path(player, requested_path)


func request_character_interaction(interactor: PlayerCharacter, target_surface: Vector3i) -> void:
	if visibility != null and not visibility.is_surface_visible_for_character(interactor, target_surface):
		return
	network.request_character_interaction(interactor, target_surface)


func request_character_ability(character: PlayerCharacter, target_surface: Vector3i) -> bool:
	return abilities != null and abilities.request_character_ability(character, target_surface)


func can_character_use_ability(character: PlayerCharacter) -> bool:
	return abilities != null and abilities.can_character_use_ability(character)


func get_character_ability_cooldown(character: PlayerCharacter) -> int:
	return 0 if abilities == null else abilities.get_remaining_cooldown_turns(character)


func try_character_interaction(interactor: PlayerCharacter, target_surface: Vector3i) -> bool:
	if interaction == null:
		return false

	return interaction.try_interact(interactor, target_surface)


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


func request_selected_spell_cast(player: PlayerCharacter, target_surface: Vector3i) -> bool:
	if visibility != null and not visibility.is_surface_visible_for_character(player, target_surface):
		return false
	return spells != null and spells.request_selected_spell_cast(player, target_surface)


func is_entity_casting(entity: Node) -> bool:
	return spells != null and spells.is_entity_casting(entity)


func is_entity_movement_blocked_by_spell(entity: Node) -> bool:
	return spells != null and spells.is_entity_movement_blocked(entity)


func get_remaining_spell_slot_uses(player: PlayerCharacter, spell_slot_index: int) -> int:
	if spells == null:
		return 0

	return spells.get_remaining_spell_slot_uses(player, spell_slot_index)


func apply_spell_damage_to_surface(caster: Node, target_surface: Vector3i, damage_amount: int) -> void:
	if combat != null:
		combat.apply_spell_damage_to_surface(caster, target_surface, damage_amount)


func register_entity(entity: Node) -> int:
	var result: int = registry.register_entity(entity)
	if result == WorldRegistry.RegistrationError.NONE and awareness != null:
		awareness.notify_entity_registered(entity)
	return result


func unregister_entity(entity: Node) -> void:
	if turn_manager != null:
		turn_manager.notify_entity_removed(entity)
	if abilities != null:
		abilities.handle_entity_removed(entity)
	registry.unregister_entity(entity)


func register_object(target_object: Node, anchor_surface: Vector3i) -> int:
	return registry.register_object(target_object, anchor_surface)


func unregister_object(target_object: Node) -> void:
	registry.unregister_object(target_object)


func remove_world_object(target_object: GridObject) -> bool:
	return spawner.remove_world_object(target_object)


func remove_defeated_non_player(target_entity: NonPlayerEntity) -> bool:
	return spawner.remove_defeated_non_player(target_entity)


func spawn_world_object(type_key: String, surface: Vector3i) -> bool:
	return spawner.spawn_world_object(type_key, surface)


func get_placement_error(spawn_node: Node, anchor_surface: Vector3i) -> String:
	return registry.get_placement_error(spawn_node, anchor_surface)


func reserve_entity_surface(entity: Node, from_surface: Vector3i, target_surface: Vector3i) -> bool:
	return registry.reserve_entity_surface(entity, from_surface, target_surface)


func complete_entity_move(entity: Node, from_surface: Vector3i, target_surface: Vector3i) -> int:
	var result: int = registry.complete_entity_move(entity, from_surface, target_surface)
	if result == WorldRegistry.RegistrationError.NONE and awareness != null:
		awareness.notify_character_changed(entity)
	return result


func respawn_entity(entity: Node, surface: Vector3i) -> int:
	return registry.respawn_entity(entity, surface)


func request_player_respawn(player: PlayerCharacter) -> bool:
	return players_service.request_player_respawn(player) if players_service != null else false


func notify_character_defeated(character: PlayerCharacter) -> void:
	if awareness != null:
		awareness.notify_character_defeated(character)


func sync_entity_surface(entity: Node, surface: Vector3i) -> int:
	var previous_surface: Vector3i = Vector3i.ZERO
	var had_previous_surface: bool = entity != null and entity.get("current_surface") != null
	if had_previous_surface:
		previous_surface = entity.get("current_surface")

	var result: int = registry.sync_entity_surface(entity, surface)
	if result == WorldRegistry.RegistrationError.NONE and had_previous_surface and previous_surface != surface and awareness != null:
		awareness.notify_character_changed(entity)
	return result


func clear_registered_entities() -> void:
	registry.clear_entities()


func get_entity_by_id(entity_id: String) -> Node:
	return spatial.get_entity_by_id(entity_id)


func get_entity_at_surface(cell: Vector3i) -> Node:
	return spatial.get_entity_at_surface(cell)


func is_entity_registered_at_surface(entity: Node, surface: Vector3i) -> bool:
	return registry.is_entity_registered_at_surface(entity, surface)


func has_entity_surface_reservation(entity: Node, surface: Vector3i) -> bool:
	return registry.has_entity_surface_reservation(entity, surface)


func get_object_at_surface(cell: Vector3i) -> Node:
	return spatial.get_object_at_surface(cell)


func get_object_by_id(object_id: String) -> Node:
	return spatial.get_object_by_id(object_id)


func get_registered_objects() -> Array:
	return spatial.get_registered_objects()


func get_registered_entities() -> Array:
	return spatial.get_registered_entities()


func can_enter_surface(cell: Vector3i, moving_entity: Node = null) -> bool:
	return registry.can_enter_surface(cell, moving_entity)


func can_character_enter_surface(cell: Vector3i, ignored_entity: Entity = null) -> bool:
	return registry.can_character_enter_surface(cell, ignored_entity)


func get_reachable_surfaces_for_entity(entity: Entity, max_steps: int) -> Array[Vector3i]:
	return WorldGridPathfinder.get_reachable_surfaces_for_entity(self, entity, max_steps)


func get_available_attack_surfaces(entity: Entity) -> Array[Vector3i]:
	var surfaces: Array[Vector3i] = [] if combat == null else combat.get_available_attack_surfaces(entity)
	var player: PlayerCharacter = entity as PlayerCharacter
	if visibility == null or player == null:
		return surfaces
	var visible_surfaces: Array[Vector3i] = []
	for surface: Vector3i in surfaces:
		if visibility.is_surface_visible_for_character(player, surface):
			visible_surfaces.append(surface)
	return visible_surfaces


func get_available_interaction_surfaces(character: PlayerCharacter) -> Array[Vector3i]:
	var surfaces: Array[Vector3i] = [] if interaction == null else interaction.get_available_interaction_surfaces(character)
	if visibility == null:
		return surfaces
	var visible_surfaces: Array[Vector3i] = []
	for surface: Vector3i in surfaces:
		if visibility.is_surface_visible_for_character(character, surface):
			visible_surfaces.append(surface)
	return visible_surfaces


func is_surface_interactable(cell: Vector3i) -> bool:
	return registry.is_surface_interactable(cell)


func get_surface_display_name(cell: Vector3i) -> String:
	return registry.get_surface_display_name(cell)


func apply_attack_to_surface(
	attacker: Node,
	surface: Vector3i,
	should_broadcast: bool = true,
	should_broadcast_action: bool = true
) -> void:
	combat.apply_attack_to_surface(attacker, surface, should_broadcast, should_broadcast_action)


func can_entity_move_in_turn(entity: Node) -> bool:
	if turn_manager == null:
		return true

	return turn_manager.can_entity_move(entity)


func can_entity_attack_in_turn(entity: Node, target_surface: Vector3i) -> bool:
	if turn_manager == null:
		return true

	return turn_manager.can_entity_attack(entity, target_surface)


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


func notify_entity_moved_in_turn(entity: Node, from_surface: Vector3i, target_surface: Vector3i, movement_step_cost: int = 1) -> void:
	if turn_manager != null:
		turn_manager.notify_entity_moved(entity, from_surface, target_surface, movement_step_cost)


func notify_entity_attacked_in_turn(entity: Node, target_surface: Vector3i) -> void:
	if turn_manager != null:
		turn_manager.notify_entity_attacked(entity, target_surface)


func notify_entity_interacted_in_turn(entity: Node) -> void:
	if turn_manager != null:
		turn_manager.notify_entity_interacted(entity)


func notify_entity_action_finished_in_turn(entity: Node, world_turn_generation: int = 0) -> void:
	if turn_manager != null:
		var non_player: NonPlayerEntity = entity as NonPlayerEntity
		if non_player != null and world_turn_generation == 0:
			world_turn_generation = non_player.get_behavior_generation()
		turn_manager.notify_entity_action_finished(entity, world_turn_generation)


func request_end_turn(entity: Node = null) -> void:
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


func has_pending_move_path(entity: Node) -> bool:
	if action_stream == null or entity == null:
		return false
	return action_stream.has_pending_move_path(get_entity_id(entity))


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
	return action_coordinator.create_snapshot(next_stream_sequence_id)


func apply_action_stream_snapshot(snapshot: Dictionary) -> bool:
	return action_coordinator.apply_snapshot(snapshot)


func receive_action_profile_payload(sequence_id: int, payload: Dictionary) -> void:
	if action_stream != null:
		action_stream.receive_profile_payload(sequence_id, payload)


func broadcast_action_profile_payload(action: WorldActionRecord) -> void:
	action_coordinator.broadcast_profile(action)


func get_action_schema_rejection_reason(action: WorldActionRecord) -> String:
	return action_coordinator.schema_rejection(action)


func get_action_acceptance_rejection_reason(action: WorldActionRecord) -> String:
	return action_coordinator.acceptance_rejection(action)


func reserve_action_on_accept(action: WorldActionRecord) -> String:
	return action_coordinator.reserve(action)


func release_action_reservation(action: WorldActionRecord) -> void:
	action_coordinator.release(action)


func get_action_rejection_reason(action: WorldActionRecord) -> String:
	return action_coordinator.rejection(action)


func execute_authoritative_action(action: WorldActionRecord) -> bool:
	return await action_coordinator.execute(action)


func play_remote_action(action: WorldActionRecord) -> void:
	await action_coordinator.play_remote(action)


func finalize_authoritative_action(action: WorldActionRecord) -> void:
	action_coordinator.finalize(action)


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


func print_non_entity_attack_result(attacker: Node, target_surface: Vector3i) -> void:
	combat.print_non_entity_attack_result(attacker, target_surface)


func get_squad_members(player_id: String) -> Array[PlayerCharacter]:
	return [] if players_service == null else players_service.get_squad_members(player_id)


func get_squad_members_by_steam_id(steam_id: int) -> Array[PlayerCharacter]:
	return [] if players_service == null else players_service.get_squad_members_by_steam_id(steam_id)


func get_local_squad_members() -> Array[PlayerCharacter]:
	return [] if players_service == null else players_service.get_local_squad_members()


func get_selected_local_character() -> PlayerCharacter:
	return null if players_service == null else players_service.get_selected_local_character()


func select_local_character(character: PlayerCharacter) -> bool:
	return players_service != null and players_service.request_select_local_character(character)


func get_local_camera_mode() -> String:
	return GameCamera.MODE_FOLLOW if players_service == null else players_service.get_local_camera_mode()


func set_local_camera_mode(camera_mode: String) -> bool:
	return players_service != null and players_service.set_local_camera_mode(camera_mode)


func set_local_camera_input_blocked(should_block: bool) -> void:
	if players_service != null:
		players_service.set_local_camera_input_blocked(should_block)


func get_player_by_entity_id(entity_id: String) -> PlayerCharacter:
	if players_service == null:
		return null
	return players_service.get_player_by_entity_id(entity_id)


func is_character_owned_by_steam_id(entity_id: String, steam_id: int) -> bool:
	return players_service != null and players_service.is_character_owned_by_steam_id(steam_id, entity_id)


func get_players_root() -> Node2D:
	return players_service.get_players_root()


func update_player_authorities() -> void:
	players_service.update_player_authorities()

func broadcast_object_state(target_object: Node) -> void:
	network.broadcast_object_state(target_object)
	if visibility != null:
		visibility.request_recompute()

func broadcast_all_object_states() -> void:
	network.broadcast_all_object_states()


func has_surface(surface: Vector3i) -> bool:
	return spatial.has_surface(surface)
func is_surface_walkable(surface: Vector3i) -> bool:
	return spatial.is_surface_walkable(surface)
func is_surface_walkable_for_entity(surface: Vector3i, entity: Entity) -> bool:
	return spatial.is_surface_walkable_for_entity(surface, entity)
func is_surface_walkable_for_character(surface: Vector3i) -> bool:
	return spatial.is_surface_walkable_for_character(surface)
func is_surface_inside(surface: Vector3i) -> bool:
	return spatial.is_surface_inside(surface)
func get_surface_neighbors(surface: Vector3i) -> Array[Vector3i]:
	return spatial.get_surface_neighbors(surface)
func get_surface_in_direction(surface: Vector3i, direction: Vector2i) -> Vector3i:
	return spatial.get_surface_in_direction(surface, direction)
func has_traversal_edge(from_surface: Vector3i, to_surface: Vector3i) -> bool:
	return spatial.has_traversal_edge(from_surface, to_surface)
func is_ramp_edge(from_surface: Vector3i, to_surface: Vector3i) -> bool:
	return spatial.is_ramp_edge(from_surface, to_surface)
func is_ramp_footprint_cell(cell: Vector2i) -> bool:
	return spatial.is_ramp_footprint_cell(cell)
func get_traversal_kind(from_surface: Vector3i, to_surface: Vector3i) -> int:
	return spatial.get_traversal_kind(from_surface, to_surface)
func get_traversal_input_direction(from_surface: Vector3i, to_surface: Vector3i) -> Vector2i:
	return spatial.get_traversal_input_direction(from_surface, to_surface)
func get_surfaces_at(cell: Vector2i) -> Array[Vector3i]:
	return spatial.get_surfaces_at(cell)
func get_all_surfaces() -> Array[Vector3i]:
	return spatial.get_all_surfaces()
func resolve_surface_at_world(world_position: Vector2, preferred_elevation: int) -> Vector3i:
	return spatial.resolve_surface_at_world(world_position, preferred_elevation)
func set_selected_input_surface(surface: Vector3i) -> void:
	spatial.set_selected_input_surface(surface)
func resolve_selected_surface_at_world(world_position: Vector2, preferred_elevation: int) -> Vector3i:
	return spatial.resolve_selected_surface_at_world(world_position, preferred_elevation)
func get_topology_hash() -> String:
	return spatial.get_topology_hash()
func get_grid_size() -> Vector2i:
	return spatial.get_grid_size()
func get_cell_size() -> int:
	return spatial.get_cell_size()
func get_grid_world_bounds() -> Rect2:
	return spatial.get_grid_world_bounds()
func world_to_surface(world_position: Vector2, elevation: int = 0) -> Vector3i:
	return spatial.world_to_surface(world_position, elevation)
func surface_to_world(surface: Vector3i) -> Vector2:
	return spatial.surface_to_world(surface)
func get_surface_center(world_position: Vector2, elevation: int = 0) -> Vector2:
	return spatial.surface_to_world(spatial.world_to_surface(world_position, elevation))
func get_adjacent_surface_center(world_position: Vector2, direction: Vector2i, elevation: int = 0) -> Vector2:
	var surface: Vector3i = spatial.world_to_surface(world_position, elevation)
	var target: Vector3i = spatial.get_surface_in_direction(surface, direction)
	return spatial.surface_to_world(surface if target == WorldGridTopology.INVALID_SURFACE else target)


func print_console(text: String) -> void:
	ConsoleOutput.print_line(text)


func _bind_services() -> void:
	composition.bind_services(self, level)
	spatial.configure(grid, registry)
	event_coordinator.connect_service_signals()


func _configure_services() -> void:
	composition.configure_level_services(self, level)


func register_level_entities() -> void:
	event_coordinator.register_level_entities()
