class_name WorldRuntime
extends Node

signal match_end_requested()
signal action_rejected(reason_code: String)
signal runtime_sync_failed(reason_code: String)
signal world_occupancy_changed

const MAX_BLOCKING_EVENT_SECONDS := 10.0
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


func start_game() -> String:
	_configure_services()
	registry.collect_blockers()
	network.apply_cached_object_states()
	players_service.prepare_players_root()
	_register_world_entities()

	if GameSession.is_singleplayer():
		players_service.start_singleplayer()
	elif GameSession.is_multiplayer():
		if not NetworkManager.connection.is_ready():
			push_warning(
				"Multiplayer session started before network became ready: "
				+ NetworkManager.connection.last_error
			)
		var player_prepare_error: String = await players_service.prepare_multiplayer_players()
		if not player_prepare_error.is_empty():
			return player_prepare_error
		var sync_error: String = await action_stream.synchronize_initial_state()
		if not sync_error.is_empty():
			NetworkManager.players.report_player_world_failed(GameSession.get_match_id(), sync_error)
			return sync_error
		var commit_error: String = await players_service.report_world_ready_and_wait_for_commit()
		if not commit_error.is_empty():
			return commit_error
	else:
		push_warning("Unknown game session mode: " + str(GameSession.mode))
		players_service.start_singleplayer()

	spawner.apply_cached_world_removals()
	network.apply_cached_entity_ai_states()
	network.apply_cached_entity_vitality_states()
	return ""


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
	return {
		"next_sequence_id": next_stream_sequence_id,
		"turn_revision": turn_manager.get_turn_revision() if turn_manager != null else 0,
		"turn_state": turn_manager.create_action_stream_snapshot() if turn_manager != null else {},
		"spell_state": spells.create_action_stream_snapshot() if spells != null else {},
		"world_state": _create_world_state_snapshot(),
	}


func apply_action_stream_snapshot(snapshot: Dictionary) -> bool:
	var turn_state_value: Variant = snapshot.get("turn_state", {})
	var spell_state_value: Variant = snapshot.get("spell_state", {})
	var world_state_value: Variant = snapshot.get("world_state", {})
	if (
		not (turn_state_value is Dictionary)
		or not (spell_state_value is Dictionary)
		or not (world_state_value is Dictionary)
	):
		return false
	if turn_manager != null and not turn_manager.is_valid_remote_snapshot(turn_state_value as Dictionary):
		return false
	if spells != null and not spells.is_valid_action_stream_snapshot(spell_state_value as Dictionary):
		return false
	if not _validate_world_state_snapshot(world_state_value as Dictionary):
		return false
	if not _apply_world_state_snapshot(world_state_value as Dictionary):
		return false
	if turn_manager != null:
		turn_manager.apply_remote_snapshot(turn_state_value as Dictionary)
	if spells != null:
		spells.apply_action_stream_snapshot(spell_state_value as Dictionary)
	return true


func _create_world_state_snapshot() -> Dictionary:
	var entity_records: Array[Dictionary] = []
	var inventory_records: Array[Dictionary] = []
	for entity_value: Variant in get_registered_entities():
		var entity: Entity = entity_value as Entity
		if entity == null:
			continue
		entity_records.append({
			"entity_id": entity.entity_id,
			"cell": entity.current_cell,
			"health": entity.health,
			"max_health": entity.max_health,
			"damage": entity.damage,
		})
	if GameSession.is_multiplayer():
		for roster_player: Dictionary in GameSession.get_players():
			var player: PlayerCharacter = get_player_by_steam_id(int(roster_player.get("steam_id", 0)))
			if player != null and player.character_inventory != null:
				inventory_records.append(player.character_inventory.create_snapshot())
	else:
		var local_player: PlayerCharacter = get_local_player()
		if local_player != null and local_player.character_inventory != null:
			inventory_records.append(local_player.character_inventory.create_snapshot())

	var object_records: Array[Dictionary] = []
	for object_value: Variant in get_registered_objects():
		var grid_object: GridObject = object_value as GridObject
		if grid_object == null:
			continue
		object_records.append({
			"object_id": grid_object.object_id,
			"object_state": int(grid_object.object_state),
		})
	return {
		"entities": entity_records,
		"objects": object_records,
		"inventories": inventory_records,
		"dynamic_spawns": NetworkManager.store.get_world_spawn_records(),
		"removed_items": NetworkManager.store.get_removed_world_items(),
		"ai_states": NetworkManager.store.get_entity_ai_states(),
	}


func _validate_world_state_snapshot(world_state: Dictionary) -> bool:
	var entities_value: Variant = world_state.get("entities", [])
	var objects_value: Variant = world_state.get("objects", [])
	var inventories_value: Variant = world_state.get("inventories", [])
	var dynamic_spawns_value: Variant = world_state.get("dynamic_spawns", [])
	var removed_items_value: Variant = world_state.get("removed_items", [])
	var ai_states_value: Variant = world_state.get("ai_states", {})
	if (
		not (entities_value is Array)
		or not (objects_value is Array)
		or not (inventories_value is Array)
		or not (dynamic_spawns_value is Array)
		or not (removed_items_value is Array)
		or not (ai_states_value is Dictionary)
	):
		return false
	var entities: Array = entities_value as Array
	var objects: Array = objects_value as Array
	var inventories: Array = inventories_value as Array
	if (
		entities.size() > NetworkProtocol.MAX_WORLD_RECORDS
		or objects.size() > NetworkProtocol.MAX_WORLD_RECORDS
		or inventories.size() > NetworkProtocol.MAX_ROSTER_SIZE
		or (dynamic_spawns_value as Array).size() > NetworkProtocol.MAX_WORLD_RECORDS
		or (removed_items_value as Array).size() > NetworkProtocol.MAX_WORLD_RECORDS
		or (ai_states_value as Dictionary).size() > NetworkProtocol.MAX_WORLD_RECORDS
	):
		return false
	var seen_entity_ids: Dictionary[String, bool] = {}
	var entity_cells_by_id: Dictionary[String, Vector2i] = {}
	var seen_cells: Dictionary[Vector2i, bool] = {}
	for record_value: Variant in entities:
		if not (record_value is Dictionary):
			return false
		var record: Dictionary = record_value as Dictionary
		var entity_id: String = str(record.get("entity_id", ""))
		var cell_value: Variant = record.get("cell")
		if (
			not NetworkProtocol.is_valid_identifier(entity_id)
			or seen_entity_ids.has(entity_id)
			or not (cell_value is Vector2i)
			or not is_cell_inside(cell_value as Vector2i)
			or seen_cells.has(cell_value as Vector2i)
			or int(record.get("max_health", 0)) <= 0
			or int(record.get("max_health", 0)) > NetworkProtocol.MAX_GAMEPLAY_VALUE
			or int(record.get("health", -1)) < 0
			or int(record.get("health", -1)) > int(record.get("max_health", 0))
			or not NetworkProtocol.is_valid_nonnegative_value(int(record.get("damage", -1)))
		):
			return false
		seen_entity_ids[entity_id] = true
		entity_cells_by_id[entity_id] = cell_value as Vector2i
		seen_cells[cell_value as Vector2i] = true
	var seen_object_ids: Dictionary[String, bool] = {}
	for record_value: Variant in objects:
		if not (record_value is Dictionary):
			return false
		var record: Dictionary = record_value as Dictionary
		var object_id: String = str(record.get("object_id", ""))
		if (
			not NetworkProtocol.is_valid_identifier(object_id)
			or seen_object_ids.has(object_id)
			or int(record.get("object_state", -1)) not in [0, 1]
		):
			return false
		seen_object_ids[object_id] = true
	var expected_inventory_count: int = GameSession.get_players().size() if GameSession.is_multiplayer() else 1
	if inventories.size() != expected_inventory_count:
		return false
	var seen_inventory_entity_ids: Dictionary[String, bool] = {}
	for snapshot_value: Variant in inventories:
		if not (snapshot_value is Dictionary):
			return false
		var inventory_snapshot: Dictionary = snapshot_value as Dictionary
		var inventory_entity_id: String = str(inventory_snapshot.get("entity_id", ""))
		var player: PlayerCharacter = get_entity_by_id(inventory_entity_id) as PlayerCharacter
		if player == null:
			for roster_player: Dictionary in GameSession.get_players():
				if str(roster_player.get("entity_id", "")) == inventory_entity_id:
					player = get_player_by_steam_id(int(roster_player.get("steam_id", 0)))
					break
		if (
			player == null
			or player.character_inventory == null
			or seen_inventory_entity_ids.has(inventory_entity_id)
			or not player.character_inventory.is_valid_authoritative_snapshot(
				inventory_snapshot,
				inventory_entity_id
			)
		):
			return false
		seen_inventory_entity_ids[inventory_entity_id] = true
	var seen_spawn_ids: Dictionary[String, bool] = {}
	for record_value: Variant in dynamic_spawns_value as Array:
		if not (record_value is Dictionary):
			return false
		var spawn_record: Dictionary = record_value as Dictionary
		var spawn_id: String = str(spawn_record.get("spawn_id", ""))
		var spawn_cell_value: Variant = spawn_record.get("cell")
		var spawn_cell: Vector2i = spawn_record.get("cell", Vector2i(-1, -1))
		var is_matching_entity_cell: bool = (
			seen_entity_ids.has(spawn_id)
			and spawn_cell_value is Vector2i
			and entity_cells_by_id.get(spawn_id, Vector2i(-1, -1)) == spawn_cell
		)
		if (
			not NetworkProtocol.is_valid_identifier(spawn_id)
			or seen_spawn_ids.has(spawn_id)
			or not NetworkProtocol.is_valid_identifier(str(spawn_record.get("type_key", "")))
			or not (spawn_cell_value is Vector2i)
			or not is_cell_inside(spawn_cell)
			or (seen_cells.has(spawn_cell) and not is_matching_entity_cell)
		):
			return false
		seen_spawn_ids[spawn_id] = true
		if not is_matching_entity_cell:
			seen_cells[spawn_cell] = true
	for record_value: Variant in removed_items_value as Array:
		if not (record_value is Dictionary):
			return false
		var removal_record: Dictionary = record_value as Dictionary
		if (
			str(removal_record.get("kind", "")) not in ["entity", "object"]
			or not NetworkProtocol.is_valid_identifier(str(removal_record.get("id", "")))
		):
			return false
	for entity_id_value: Variant in (ai_states_value as Dictionary).keys():
		var entity_id: String = str(entity_id_value)
		var state_value: Variant = (ai_states_value as Dictionary)[entity_id_value]
		if not NetworkProtocol.is_valid_identifier(entity_id) or not (state_value is Dictionary):
			return false
		var state_record: Dictionary = state_value as Dictionary
		if (
			not NetworkProtocol.is_valid_bounded_text(str(state_record.get("state", "")))
			or not NetworkProtocol.is_valid_optional_identifier(str(state_record.get("target_entity_id", "")))
			or not NetworkProtocol.is_valid_bounded_text(str(state_record.get("reason", "")))
		):
			return false
	return true


func _apply_world_state_snapshot(world_state: Dictionary) -> bool:
	var dynamic_spawn_records: Array[Dictionary] = []
	for record_value: Variant in world_state.get("dynamic_spawns", []):
		if record_value is Dictionary:
			dynamic_spawn_records.append(record_value as Dictionary)
	var removal_records: Array[Dictionary] = []
	for record_value: Variant in world_state.get("removed_items", []):
		if record_value is Dictionary:
			removal_records.append(record_value as Dictionary)
	if spawner != null:
		if not spawner.apply_action_stream_snapshot(dynamic_spawn_records, removal_records):
			return false
	var cells_by_entity_id: Dictionary[String, Vector2i] = {}
	for record_value: Variant in world_state.get("entities", []):
		if record_value is Dictionary:
			var cell_record: Dictionary = record_value as Dictionary
			cells_by_entity_id[str(cell_record.get("entity_id", ""))] = cell_record.get("cell", Vector2i.ZERO)
	if registry.apply_entity_cell_batch(cells_by_entity_id) != WorldRegistry.RegistrationError.NONE:
		if spawner != null:
			spawner.rollback_action_stream_snapshot_spawns()
		return false
	for record_value: Variant in world_state.get("entities", []):
		if not (record_value is Dictionary):
			continue
		var record: Dictionary = record_value as Dictionary
		var entity: Entity = get_entity_by_id(str(record.get("entity_id", ""))) as Entity
		if entity == null:
			return false
		var cell: Vector2i = record.get("cell", entity.current_cell)
		entity.max_health = maxi(int(record.get("max_health", entity.max_health)), 1)
		entity.set_health(int(record.get("health", entity.health)))
		entity.apply_attack_damage_state(int(record.get("damage", entity.damage)))
		entity.current_cell = cell
		entity.global_position = cell_to_world(cell)

	for record_value: Variant in world_state.get("objects", []):
		if not (record_value is Dictionary):
			continue
		var record: Dictionary = record_value as Dictionary
		var grid_object: GridObject = get_object_by_id(str(record.get("object_id", ""))) as GridObject
		if grid_object == null:
			return false
		grid_object.apply_network_state(int(record.get("object_state", int(grid_object.object_state))))

	for snapshot_value: Variant in world_state.get("inventories", []):
		if not (snapshot_value is Dictionary):
			continue
		var inventory_snapshot: Dictionary = snapshot_value as Dictionary
		var player: PlayerCharacter = get_entity_by_id(str(inventory_snapshot.get("entity_id", ""))) as PlayerCharacter
		if player == null:
			for roster_player: Dictionary in GameSession.get_players():
				if str(roster_player.get("entity_id", "")) == str(inventory_snapshot.get("entity_id", "")):
					player = get_player_by_steam_id(int(roster_player.get("steam_id", 0)))
					break
		if player == null or player.character_inventory == null:
			return false
		if not player.character_inventory.apply_authoritative_snapshot(inventory_snapshot):
			return false

	var ai_states_value: Variant = world_state.get("ai_states", {})
	if ai_states_value is Dictionary:
		var ai_states: Dictionary = ai_states_value as Dictionary
		for entity_id_value: Variant in ai_states.keys():
			var entity_id: String = str(entity_id_value)
			var entity: NonPlayerEntity = get_entity_by_id(entity_id) as NonPlayerEntity
			var state: Dictionary = ai_states.get(entity_id, {}) as Dictionary
			if entity != null:
				entity.apply_remote_ai_state(
					str(state.get("state", "")),
					str(state.get("target_entity_id", "")),
					str(state.get("reason", ""))
				)
	if spawner != null:
		spawner.commit_action_stream_snapshot_spawns()
	NetworkManager.store.replace_from_world_snapshot(world_state)
	return true


func receive_action_profile_payload(sequence_id: int, payload: Dictionary) -> void:
	if action_stream != null:
		action_stream.receive_profile_payload(sequence_id, payload)


func broadcast_action_profile_payload(action: WorldActionRecord) -> void:
	if action == null or network == null:
		return
	match action.action_type:
		WorldActionRecord.ActionType.MOVE, WorldActionRecord.ActionType.INTERACTION:
			network.broadcast_character_action_payload(action)
		WorldActionRecord.ActionType.ATTACK:
			network.broadcast_combat_action_payload(action)
		WorldActionRecord.ActionType.SPELL_CAST:
			spells.broadcast_action_payload(action)
		WorldActionRecord.ActionType.INVENTORY_ADD, \
		WorldActionRecord.ActionType.INVENTORY_MOVE, \
		WorldActionRecord.ActionType.INVENTORY_DELETE, \
		WorldActionRecord.ActionType.INVENTORY_USE:
			network.broadcast_inventory_action_payload(action)


func get_action_schema_rejection_reason(action: WorldActionRecord) -> String:
	if action == null or action.request_id <= 0 or action.actor_entity_id.is_empty():
		return WorldActionStream.REJECTION_INVALID_ACTION
	if GameSession.is_multiplayer() and action.requester_steam_id <= 0:
		return WorldActionStream.REJECTION_INVALID_ACTION
	if not NetworkProtocol.is_valid_identifier(action.actor_entity_id):
		return WorldActionStream.REJECTION_INVALID_ACTION
	if not NetworkProtocol.is_valid_intent_payload(action.payload):
		return "payload_too_large"

	match action.action_type:
		WorldActionRecord.ActionType.MOVE:
			var direction_value: Variant = action.payload.get("direction")
			if not (direction_value is Vector2i):
				return WorldActionStream.REJECTION_INVALID_ACTION
			var direction: Vector2i = direction_value as Vector2i
			if absi(direction.x) + absi(direction.y) != 1:
				return WorldActionStream.REJECTION_INVALID_ACTION
		WorldActionRecord.ActionType.ATTACK, WorldActionRecord.ActionType.INTERACTION:
			if not (action.payload.get("target_cell") is Vector2i):
				return WorldActionStream.REJECTION_INVALID_ACTION
		WorldActionRecord.ActionType.SPELL_CAST:
			var target_kind: String = str(action.payload.get("target_kind", "cell"))
			if target_kind == "cell" and not (action.payload.get("target_cell") is Vector2i):
				return WorldActionStream.REJECTION_INVALID_ACTION
			if target_kind == "entity" and str(action.payload.get("target_entity_id", "")).is_empty():
				return WorldActionStream.REJECTION_INVALID_ACTION
			if target_kind != "cell" and target_kind != "entity":
				return WorldActionStream.REJECTION_INVALID_ACTION
			if int(action.payload.get("spell_slot_index", -1)) < 0:
				return WorldActionStream.REJECTION_INVALID_ACTION
		WorldActionRecord.ActionType.INVENTORY_ADD:
			if (
				str(action.payload.get("item_id", "")).is_empty()
				or int(action.payload.get("amount", 0)) <= 0
				or int(action.payload.get("amount", 0)) > CharacterInventory.ITEM_SLOT_COUNT * CharacterInventory.DEFAULT_MAX_STACK_SIZE
				or int(action.payload.get("expected_inventory_revision", -1)) < 0
			):
				return WorldActionStream.REJECTION_INVALID_ACTION
		WorldActionRecord.ActionType.INVENTORY_MOVE:
			if str(action.payload.get("inventory_kind", "")).is_empty() or int(action.payload.get("expected_inventory_revision", -1)) < 0:
				return WorldActionStream.REJECTION_INVALID_ACTION
			if int(action.payload.get("source_slot_index", -1)) < 0 or int(action.payload.get("target_slot_index", -1)) < 0:
				return WorldActionStream.REJECTION_INVALID_ACTION
		WorldActionRecord.ActionType.INVENTORY_DELETE:
			if str(action.payload.get("inventory_kind", "")).is_empty() or int(action.payload.get("slot_index", -1)) < 0 or int(action.payload.get("expected_inventory_revision", -1)) < 0:
				return WorldActionStream.REJECTION_INVALID_ACTION
		WorldActionRecord.ActionType.INVENTORY_USE:
			if int(action.payload.get("slot_index", -1)) < 0 or int(action.payload.get("expected_inventory_revision", -1)) < 0:
				return WorldActionStream.REJECTION_INVALID_ACTION
		WorldActionRecord.ActionType.CHARACTER_KILL:
			pass
		WorldActionRecord.ActionType.END_PLAYER_TURN:
			pass
		_:
			return WorldActionStream.REJECTION_INVALID_ACTION
	return ""


func get_action_acceptance_rejection_reason(action: WorldActionRecord) -> String:
	if action == null:
		return WorldActionStream.REJECTION_INVALID_ACTION
	if action.request_id < 0:
		return WorldActionStream.REJECTION_INVALID_ACTION
	if GameSession.is_multiplayer() and action.match_id != GameSession.get_match_id():
		return WorldActionStream.REJECTION_WRONG_MATCH
	if action.request_id == 0:
		if action.requester_steam_id != 0:
			return WorldActionStream.REJECTION_INVALID_ACTION
		return get_action_rejection_reason(action)
	if GameSession.is_multiplayer() and not GameSession.has_committed_match():
		return WorldActionStream.REJECTION_ACTOR_UNAVAILABLE
	if GameSession.is_multiplayer():
		if action.requester_steam_id <= 0:
			return WorldActionStream.REJECTION_INVALID_ACTION
		if not is_player_connected(action.requester_steam_id):
			return WorldActionStream.REJECTION_ACTOR_DISCONNECTED
	if not _is_turn_bound_action(action.action_type):
		return get_action_rejection_reason(action)
	if turn_manager != null and action.turn_revision != turn_manager.get_turn_revision():
		return WorldActionStream.REJECTION_STALE_TURN
	var player: PlayerCharacter = get_entity_by_id(action.actor_entity_id) as PlayerCharacter
	if player == null or player.health <= 0:
		return WorldActionStream.REJECTION_ACTOR_UNAVAILABLE
	if turn_manager != null and turn_manager.is_world_turn_active():
		return WorldActionStream.REJECTION_WORLD_TURN
	if (
		action.action_type in [
			WorldActionRecord.ActionType.SPELL_CAST,
			WorldActionRecord.ActionType.INVENTORY_USE,
		]
		and (turn_manager == null or not turn_manager.is_entity_active_in_turn(player))
	):
		return WorldActionStream.REJECTION_NOT_ACTIVE_PLAYER
	if (
		turn_manager != null
		and turn_manager.is_turn_mode_enabled()
		and not turn_manager.is_entity_active_in_turn(player)
	):
		return WorldActionStream.REJECTION_NOT_ACTIVE_PLAYER
	return get_action_rejection_reason(action)


func _is_turn_bound_action(action_type: WorldActionRecord.ActionType) -> bool:
	return action_type in [
		WorldActionRecord.ActionType.MOVE,
		WorldActionRecord.ActionType.ATTACK,
		WorldActionRecord.ActionType.INTERACTION,
		WorldActionRecord.ActionType.SPELL_CAST,
		WorldActionRecord.ActionType.INVENTORY_USE,
		WorldActionRecord.ActionType.END_PLAYER_TURN,
	]


func reserve_action_on_accept(action: WorldActionRecord) -> String:
	if action != null and action.action_type == WorldActionRecord.ActionType.SPELL_CAST:
		return spells.reserve_action(action)
	return ""


func release_action_reservation(action: WorldActionRecord) -> void:
	if action != null and action.action_type == WorldActionRecord.ActionType.SPELL_CAST:
		spells.release_action_reservation(action)


func get_action_rejection_reason(action: WorldActionRecord) -> String:
	if action == null:
		return WorldActionStream.REJECTION_INVALID_ACTION
	var player: PlayerCharacter = get_entity_by_id(action.actor_entity_id) as PlayerCharacter
	if _is_player_action(action.action_type) and (player == null or player.health <= 0):
		return WorldActionStream.REJECTION_ACTOR_UNAVAILABLE

	match action.action_type:
		WorldActionRecord.ActionType.MOVE:
			var direction: Vector2i = action.payload.get("direction", Vector2i.ZERO)
			if direction == Vector2i.ZERO or not can_entity_move_in_turn(player):
				return WorldActionStream.REJECTION_INVALID_ACTION
			var from_cell: Vector2i = world_to_cell(player.global_position)
			var target_cell: Vector2i = from_cell + direction
			if not can_enter_cell(target_cell, player):
				return WorldActionStream.REJECTION_INVALID_ACTION
			action.payload["from_cell"] = from_cell
			action.payload["target_cell"] = target_cell
		WorldActionRecord.ActionType.ATTACK:
			var attack_cell: Vector2i = action.payload.get("target_cell", Vector2i.ZERO)
			player.current_cell = world_to_cell(player.global_position)
			if not player.can_attack_cell(attack_cell) or not can_entity_attack_in_turn(player, attack_cell):
				return WorldActionStream.REJECTION_INVALID_ACTION
		WorldActionRecord.ActionType.INTERACTION:
			var interaction_cell: Vector2i = action.payload.get("target_cell", Vector2i.ZERO)
			player.current_cell = world_to_cell(player.global_position)
			if not player.can_act() or not player.can_attack_cell(interaction_cell) or not can_entity_interact_in_turn(player):
				return WorldActionStream.REJECTION_INVALID_ACTION
		WorldActionRecord.ActionType.SPELL_CAST:
			return spells.get_action_rejection_reason(action)
		WorldActionRecord.ActionType.INVENTORY_ADD, \
		WorldActionRecord.ActionType.INVENTORY_MOVE, \
		WorldActionRecord.ActionType.INVENTORY_DELETE:
			if player.character_inventory == null:
				return WorldActionStream.REJECTION_INVALID_ACTION
			if not player.character_inventory.matches_revision(int(action.payload.get("expected_inventory_revision", -1))):
				return "stale_inventory"
		WorldActionRecord.ActionType.INVENTORY_USE:
			if player.character_inventory == null or not can_entity_use_item_in_turn(player):
				return WorldActionStream.REJECTION_INVALID_ACTION
			if not player.character_inventory.matches_revision(int(action.payload.get("expected_inventory_revision", -1))):
				return "stale_inventory"
		WorldActionRecord.ActionType.END_PLAYER_TURN:
			if not turn_manager.can_end_turn(player):
				return WorldActionStream.REJECTION_INVALID_ACTION
	return ""


func execute_authoritative_action(action: WorldActionRecord) -> bool:
	if not is_inside_tree():
		return false
	var scene_tree: SceneTree = get_tree()
	var player: PlayerCharacter = get_entity_by_id(action.actor_entity_id) as PlayerCharacter
	match action.action_type:
		WorldActionRecord.ActionType.MOVE:
			var direction: Vector2i = action.payload.get("direction", Vector2i.ZERO)
			if not player.execute_authoritative_move(direction):
				return false
			var move_deadline_msec: int = Time.get_ticks_msec() + int((player.move_time + 2.0) * 1000.0)
			while is_instance_valid(player) and player.is_moving and Time.get_ticks_msec() < move_deadline_msec:
				await scene_tree.process_frame
				if not is_inside_tree():
					return false
			if not is_instance_valid(player):
				return false
			if player.is_moving:
				player.force_cancel_movement(action.payload.get("from_cell", player.current_cell))
				action.payload["cancellation_reason"] = WorldActionStream.REJECTION_PRESENTATION_TIMEOUT
				return false
			return true
		WorldActionRecord.ActionType.ATTACK:
			var attack_cell: Vector2i = action.payload.get("target_cell", Vector2i.ZERO)
			player.play_remote_attack(attack_cell, false)
			if not player.is_attacking:
				return false
			notify_entity_attacked_in_turn(player, attack_cell)
			apply_attack_to_cell(player, attack_cell, true, false)
			var expected_attack_duration: float = player.get_expected_attack_duration(attack_cell)
			var attack_deadline_msec: int = Time.get_ticks_msec() + int((expected_attack_duration + 2.0) * 1000.0)
			while is_instance_valid(player) and player.is_attacking and Time.get_ticks_msec() < attack_deadline_msec:
				await scene_tree.process_frame
				if not is_inside_tree():
					return false
			if not is_instance_valid(player):
				return false
			if player.is_attacking:
				player.force_finish_attack_presentation()
			return true
		WorldActionRecord.ActionType.INTERACTION:
			return try_character_interaction(player, action.payload.get("target_cell", Vector2i.ZERO))
		WorldActionRecord.ActionType.SPELL_CAST:
			return await spells.execute_action_cast(action, true)
		WorldActionRecord.ActionType.INVENTORY_ADD:
			var was_added: bool = player.character_inventory.try_add_item(str(action.payload.get("item_id", "")), int(action.payload.get("amount", 0)))
			if not was_added:
				action.payload["cancellation_reason"] = _get_inventory_mutation_reason(player.character_inventory)
			return was_added
		WorldActionRecord.ActionType.INVENTORY_MOVE:
			var was_moved: bool = player.character_inventory.try_move_stack(
				str(action.payload.get("inventory_kind", "")),
				int(action.payload.get("source_slot_index", -1)),
				int(action.payload.get("target_slot_index", -1))
			)
			if not was_moved:
				action.payload["cancellation_reason"] = _get_inventory_mutation_reason(player.character_inventory)
			return was_moved
		WorldActionRecord.ActionType.INVENTORY_DELETE:
			var was_deleted: bool = player.character_inventory.try_delete_stack(
				str(action.payload.get("inventory_kind", "")),
				int(action.payload.get("slot_index", -1))
			)
			if not was_deleted:
				action.payload["cancellation_reason"] = _get_inventory_mutation_reason(player.character_inventory)
			return was_deleted
		WorldActionRecord.ActionType.INVENTORY_USE:
			var was_used: bool = try_use_inventory_item(player, int(action.payload.get("slot_index", -1)))
			if not was_used:
				action.payload["cancellation_reason"] = "effect_failed"
			return was_used
		WorldActionRecord.ActionType.CHARACTER_KILL:
			return players_service.execute_character_kill_action(player)
		WorldActionRecord.ActionType.END_PLAYER_TURN:
			return turn_manager.execute_end_turn_action(player)
		WorldActionRecord.ActionType.PLAYER_TURN_STARTED:
			return turn_manager.execute_player_turn_started_action(action.actor_entity_id)
		WorldActionRecord.ActionType.WORLD_TURN_STARTED:
			return await turn_manager.execute_world_turn_started_action()
		WorldActionRecord.ActionType.WORLD_TURN_ENDED:
			return turn_manager.execute_world_turn_ended_action()
		WorldActionRecord.ActionType.SET_TURN_MODE:
			return turn_manager.execute_set_turn_mode_action(bool(action.payload.get("is_enabled", false)))
		WorldActionRecord.ActionType.PLAYER_TURN_SKIPPED:
			return turn_manager.execute_player_turn_skipped_action(
				action.actor_entity_id,
				str(action.payload.get("reason", "unavailable"))
			)
		WorldActionRecord.ActionType.BLOCKING_EVENT:
			var duration_seconds: float = clampf(float(action.payload.get("duration_seconds", 0.0)), 0.0, MAX_BLOCKING_EVENT_SECONDS)
			if duration_seconds > 0.0:
				await scene_tree.create_timer(duration_seconds).timeout
				if not is_inside_tree():
					return false
			return true
	return false


func _get_inventory_mutation_reason(character_inventory: CharacterInventory) -> String:
	if character_inventory == null:
		return WorldActionStream.REJECTION_INVALID_ACTION
	match character_inventory.get_last_mutation_result():
		CharacterInventory.MutationResult.STALE_REVISION:
			return "stale_inventory"
		CharacterInventory.MutationResult.EFFECT_FAILED:
			return "effect_failed"
		_:
			return WorldActionStream.REJECTION_INVALID_ACTION


func play_remote_action(action: WorldActionRecord) -> void:
	if not is_inside_tree():
		return
	var scene_tree: SceneTree = get_tree()
	var player: PlayerCharacter = get_entity_by_id(action.actor_entity_id) as PlayerCharacter
	if player == null:
		return
	match action.action_type:
		WorldActionRecord.ActionType.MOVE:
			var from_cell: Vector2i = action.payload.get("from_cell", player.current_cell)
			var target_cell: Vector2i = action.payload.get("target_cell", player.current_cell)
			if player.play_remote_move(from_cell, target_cell):
				var move_deadline_msec: int = Time.get_ticks_msec() + int((player.move_time + 2.0) * 1000.0)
				while is_instance_valid(player) and player.is_moving and Time.get_ticks_msec() < move_deadline_msec:
					await scene_tree.process_frame
					if not is_inside_tree():
						return
				if not is_instance_valid(player):
					return
				if player.is_moving:
					player.force_cancel_movement(from_cell)
		WorldActionRecord.ActionType.ATTACK:
			var attack_cell: Vector2i = action.payload.get("target_cell", player.current_cell)
			player.play_remote_attack(attack_cell, false)
			var expected_attack_duration: float = player.get_expected_attack_duration(attack_cell)
			var attack_deadline_msec: int = Time.get_ticks_msec() + int((expected_attack_duration + 2.0) * 1000.0)
			while is_instance_valid(player) and player.is_attacking and Time.get_ticks_msec() < attack_deadline_msec:
				await scene_tree.process_frame
				if not is_inside_tree():
					return
			if not is_instance_valid(player):
				return
			if player.is_attacking:
				player.force_finish_attack_presentation()
		WorldActionRecord.ActionType.SPELL_CAST:
			await spells.execute_action_cast(action, false)
		WorldActionRecord.ActionType.BLOCKING_EVENT:
			var duration_seconds: float = clampf(float(action.payload.get("duration_seconds", 0.0)), 0.0, MAX_BLOCKING_EVENT_SECONDS)
			if duration_seconds > 0.0:
				await scene_tree.create_timer(duration_seconds).timeout


func finalize_authoritative_action(action: WorldActionRecord) -> void:
	if network != null:
		network.finalize_authoritative_action(action)


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


func _is_player_action(action_type: WorldActionRecord.ActionType) -> bool:
	return action_type in [
		WorldActionRecord.ActionType.MOVE,
		WorldActionRecord.ActionType.ATTACK,
		WorldActionRecord.ActionType.INTERACTION,
		WorldActionRecord.ActionType.SPELL_CAST,
		WorldActionRecord.ActionType.INVENTORY_ADD,
		WorldActionRecord.ActionType.INVENTORY_MOVE,
		WorldActionRecord.ActionType.INVENTORY_DELETE,
		WorldActionRecord.ActionType.INVENTORY_USE,
		WorldActionRecord.ActionType.CHARACTER_KILL,
	]


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


func _register_world_entities() -> void:
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
