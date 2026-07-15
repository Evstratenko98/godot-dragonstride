class_name WorldRuntime
extends Node

signal match_end_requested()

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


func start_game() -> void:
	_configure_services()
	registry.collect_blockers()
	network.apply_cached_object_states()
	players_service.prepare_players_root()

	if GameSession.is_singleplayer():
		players_service.start_singleplayer()
	elif GameSession.is_multiplayer():
		if not NetworkManager.connection.is_ready():
			push_warning(
				"Multiplayer session started before network became ready: "
				+ NetworkManager.connection.last_error
			)
		players_service.start_multiplayer()
	else:
		push_warning("Unknown game session mode: " + str(GameSession.mode))
		players_service.start_singleplayer()

	_register_world_entities()
	spawner.apply_cached_world_removals()
	network.apply_cached_entity_ai_states()
	network.apply_cached_entity_vitality_states()


func connect_signals() -> void:
	if network != null:
		network.connect_signals()


func disconnect_signals() -> void:
	if network != null:
		network.disconnect_signals()


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


func register_entity(entity: Node) -> void:
	registry.register_entity(entity)
	if awareness != null:
		awareness.notify_entity_registered(entity)


func unregister_entity(entity: Node) -> void:
	if turn_manager != null:
		turn_manager.notify_entity_removed(entity)
	registry.unregister_entity(entity)


func register_object(target_object: Node, anchor_cell: Vector2i) -> void:
	registry.register_object(target_object, anchor_cell)


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


func complete_entity_move(entity: Node, from_cell: Vector2i, target_cell: Vector2i) -> void:
	registry.complete_entity_move(entity, from_cell, target_cell)
	if awareness != null:
		awareness.notify_character_changed(entity)


func respawn_entity(entity: Node, cell: Vector2i) -> void:
	registry.respawn_entity(entity, cell)


func notify_character_defeated(character: PlayerCharacter) -> void:
	if awareness != null:
		awareness.notify_character_defeated(character)


func sync_entity_cell(entity: Node, cell: Vector2i) -> void:
	var previous_cell: Vector2i = Vector2i.ZERO
	var had_previous_cell: bool = entity != null and entity.get("current_cell") != null
	if had_previous_cell:
		previous_cell = entity.get("current_cell")

	registry.sync_entity_cell(entity, cell)
	if had_previous_cell and previous_cell != cell and awareness != null:
		awareness.notify_character_changed(entity)


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


func notify_entity_action_finished_in_turn(entity: Node) -> void:
	if turn_manager != null:
		turn_manager.notify_entity_action_finished(entity)


func request_end_turn(entity: Node) -> void:
	if turn_manager != null:
		turn_manager.request_end_turn(entity)


func create_action_request_id() -> int:
	if action_stream == null:
		return 0
	return action_stream.create_local_request_id()


func enqueue_player_action(
	action_type: WorldActionRecord.ActionType,
	player: PlayerCharacter,
	payload: Dictionary,
	request_id: int,
	requester_peer_id: int
) -> bool:
	if action_stream == null or player == null or request_id <= 0:
		return false
	var action: WorldActionRecord = WorldActionRecord.create(
		request_id,
		player.steam_id,
		player.entity_id,
		action_type,
		turn_manager.get_turn_epoch() if turn_manager != null else 0,
		payload
	)
	return action_stream.enqueue_external_action(action, requester_peer_id)


func enqueue_system_action(action_type: WorldActionRecord.ActionType, payload: Dictionary = {}) -> bool:
	if action_stream == null:
		return false
	var action: WorldActionRecord = WorldActionRecord.create(
		0,
		0,
		str(payload.get("actor_entity_id", "")),
		action_type,
		turn_manager.get_turn_epoch() if turn_manager != null else 0,
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


func claim_current_action_subsequence_id() -> int:
	return 0 if action_stream == null else action_stream.claim_current_subsequence_id()


func allows_spell_intents() -> bool:
	return action_stream == null or action_stream.allows_spell_intents()


func is_world_turn_active() -> bool:
	return turn_manager != null and turn_manager.is_world_turn_active()


func request_action_stream_snapshot(peer_id: int) -> void:
	if action_stream != null:
		action_stream.request_peer_snapshot(peer_id)


func create_action_stream_snapshot(next_stream_sequence_id: int) -> Dictionary:
	return {
		"next_sequence_id": next_stream_sequence_id,
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
	_apply_world_state_snapshot(world_state_value as Dictionary)
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
		var player: PlayerCharacter = entity as PlayerCharacter
		if player != null and player.character_inventory != null:
			inventory_records.append(player.character_inventory.create_snapshot())

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
	}


func _apply_world_state_snapshot(world_state: Dictionary) -> void:
	for record_value: Variant in world_state.get("entities", []):
		if not (record_value is Dictionary):
			continue
		var record: Dictionary = record_value as Dictionary
		var entity: Entity = get_entity_by_id(str(record.get("entity_id", ""))) as Entity
		if entity == null:
			continue
		var cell: Vector2i = record.get("cell", entity.current_cell)
		entity.max_health = maxi(int(record.get("max_health", entity.max_health)), 1)
		entity.set_health(int(record.get("health", entity.health)))
		entity.apply_attack_damage_state(int(record.get("damage", entity.damage)))
		entity.current_cell = cell
		entity.global_position = cell_to_world(cell)
		sync_entity_cell(entity, cell)

	for record_value: Variant in world_state.get("objects", []):
		if not (record_value is Dictionary):
			continue
		var record: Dictionary = record_value as Dictionary
		var grid_object: GridObject = get_object_by_id(str(record.get("object_id", ""))) as GridObject
		if grid_object != null:
			grid_object.apply_network_state(int(record.get("object_state", int(grid_object.object_state))))

	for snapshot_value: Variant in world_state.get("inventories", []):
		if not (snapshot_value is Dictionary):
			continue
		var inventory_snapshot: Dictionary = snapshot_value as Dictionary
		var player: PlayerCharacter = get_entity_by_id(str(inventory_snapshot.get("entity_id", ""))) as PlayerCharacter
		if player != null and player.character_inventory != null:
			player.character_inventory.apply_snapshot(inventory_snapshot)


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
			if str(action.payload.get("item_id", "")).is_empty() or int(action.payload.get("amount", 0)) <= 0:
				return WorldActionStream.REJECTION_INVALID_ACTION
		WorldActionRecord.ActionType.INVENTORY_MOVE:
			if str(action.payload.get("inventory_kind", "")).is_empty():
				return WorldActionStream.REJECTION_INVALID_ACTION
			if int(action.payload.get("source_slot_index", -1)) < 0 or int(action.payload.get("target_slot_index", -1)) < 0:
				return WorldActionStream.REJECTION_INVALID_ACTION
		WorldActionRecord.ActionType.INVENTORY_DELETE:
			if str(action.payload.get("inventory_kind", "")).is_empty() or int(action.payload.get("slot_index", -1)) < 0:
				return WorldActionStream.REJECTION_INVALID_ACTION
		WorldActionRecord.ActionType.INVENTORY_USE:
			if int(action.payload.get("slot_index", -1)) < 0:
				return WorldActionStream.REJECTION_INVALID_ACTION
		WorldActionRecord.ActionType.CHARACTER_KILL:
			pass
		WorldActionRecord.ActionType.END_PLAYER_TURN:
			pass
		_:
			return WorldActionStream.REJECTION_INVALID_ACTION
	return ""


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
		WorldActionRecord.ActionType.INVENTORY_DELETE, \
		WorldActionRecord.ActionType.INVENTORY_USE:
			if player.character_inventory == null:
				return WorldActionStream.REJECTION_INVALID_ACTION
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
			return player.character_inventory.try_add_item(str(action.payload.get("item_id", "")), int(action.payload.get("amount", 0)))
		WorldActionRecord.ActionType.INVENTORY_MOVE:
			return player.character_inventory.try_move_stack(
				str(action.payload.get("inventory_kind", "")),
				int(action.payload.get("source_slot_index", -1)),
				int(action.payload.get("target_slot_index", -1))
			)
		WorldActionRecord.ActionType.INVENTORY_DELETE:
			return player.character_inventory.try_delete_stack(
				str(action.payload.get("inventory_kind", "")),
				int(action.payload.get("slot_index", -1))
			)
		WorldActionRecord.ActionType.INVENTORY_USE:
			return try_use_inventory_item(player, int(action.payload.get("slot_index", -1)))
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
			var duration_seconds: float = clampf(float(action.payload.get("duration_seconds", 0.0)), 0.0, 3600.0)
			if duration_seconds > 0.0:
				await scene_tree.create_timer(duration_seconds).timeout
				if not is_inside_tree():
					return false
			return true
	return false


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
			var duration_seconds: float = clampf(float(action.payload.get("duration_seconds", 0.0)), 0.0, 3600.0)
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
