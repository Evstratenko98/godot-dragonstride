class_name WorldStateSnapshot
extends RefCounted

var runtime: WorldRuntime = null
var registry: WorldRegistry = null
var spawner: WorldSpawner = null
var turns: WorldTurns = null
var spells: WorldSpells = null
var replication_store: NetworkReplicationStore = null


func configure_context(
	new_runtime: WorldRuntime,
	new_registry: WorldRegistry,
	new_spawner: WorldSpawner,
	new_turns: WorldTurns,
	new_spells: WorldSpells,
	new_replication_store: NetworkReplicationStore
) -> void:
	runtime = new_runtime
	registry = new_registry
	spawner = new_spawner
	turns = new_turns
	spells = new_spells
	replication_store = new_replication_store


func create_action_stream_snapshot(next_stream_sequence_id: int) -> Dictionary:
	return {
		"next_sequence_id": next_stream_sequence_id,
		"turn_revision": turns.get_turn_revision() if turns != null else 0,
		"turn_state": turns.create_action_stream_snapshot() if turns != null else {},
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
	if turns != null and not turns.is_valid_remote_snapshot(turn_state_value as Dictionary):
		return false
	if spells != null and not spells.is_valid_action_stream_snapshot(spell_state_value as Dictionary):
		return false
	if not _validate_world_state_snapshot(world_state_value as Dictionary):
		return false
	if not _apply_world_state_snapshot(world_state_value as Dictionary):
		return false
	if turns != null:
		turns.apply_remote_snapshot(turn_state_value as Dictionary)
	if spells != null:
		spells.apply_action_stream_snapshot(spell_state_value as Dictionary)
	return true


func _create_world_state_snapshot() -> Dictionary:
	var entity_records: Array[Dictionary] = []
	var inventory_records: Array[Dictionary] = []
	for entity_value: Variant in runtime.get_registered_entities():
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
			var player: PlayerCharacter = runtime.get_player_by_steam_id(int(roster_player.get("steam_id", 0)))
			if player != null and player.character_inventory != null:
				inventory_records.append(player.character_inventory.create_snapshot())
	else:
		var local_player: PlayerCharacter = runtime.get_local_player()
		if local_player != null and local_player.character_inventory != null:
			inventory_records.append(local_player.character_inventory.create_snapshot())

	var object_records: Array[Dictionary] = []
	for object_value: Variant in runtime.get_registered_objects():
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
		"dynamic_spawns": replication_store.get_world_spawn_records(),
		"removed_items": replication_store.get_removed_world_items(),
		"ai_states": replication_store.get_entity_ai_states(),
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
			or not runtime.is_cell_inside(cell_value as Vector2i)
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
		var player: PlayerCharacter = runtime.get_entity_by_id(inventory_entity_id) as PlayerCharacter
		if player == null:
			for roster_player: Dictionary in GameSession.get_players():
				if str(roster_player.get("entity_id", "")) == inventory_entity_id:
					player = runtime.get_player_by_steam_id(int(roster_player.get("steam_id", 0)))
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
			or not runtime.is_cell_inside(spawn_cell)
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
		var entity: Entity = runtime.get_entity_by_id(str(record.get("entity_id", ""))) as Entity
		if entity == null:
			return false
		var cell: Vector2i = record.get("cell", entity.current_cell)
		entity.max_health = maxi(int(record.get("max_health", entity.max_health)), 1)
		entity.set_health(int(record.get("health", entity.health)))
		entity.apply_attack_damage_state(int(record.get("damage", entity.damage)))
		entity.current_cell = cell
		entity.global_position = runtime.cell_to_world(cell)

	for record_value: Variant in world_state.get("objects", []):
		if not (record_value is Dictionary):
			continue
		var record: Dictionary = record_value as Dictionary
		var grid_object: GridObject = runtime.get_object_by_id(str(record.get("object_id", ""))) as GridObject
		if grid_object == null:
			return false
		grid_object.apply_network_state(int(record.get("object_state", int(grid_object.object_state))))

	for snapshot_value: Variant in world_state.get("inventories", []):
		if not (snapshot_value is Dictionary):
			continue
		var inventory_snapshot: Dictionary = snapshot_value as Dictionary
		var player: PlayerCharacter = runtime.get_entity_by_id(str(inventory_snapshot.get("entity_id", ""))) as PlayerCharacter
		if player == null:
			for roster_player: Dictionary in GameSession.get_players():
				if str(roster_player.get("entity_id", "")) == str(inventory_snapshot.get("entity_id", "")):
					player = runtime.get_player_by_steam_id(int(roster_player.get("steam_id", 0)))
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
			var entity: NonPlayerEntity = runtime.get_entity_by_id(entity_id) as NonPlayerEntity
			var state: Dictionary = ai_states.get(entity_id, {}) as Dictionary
			if entity != null:
				entity.apply_remote_ai_state(
					str(state.get("state", "")),
					str(state.get("target_entity_id", "")),
					str(state.get("reason", ""))
				)
	if spawner != null:
		spawner.commit_action_stream_snapshot_spawns()
	replication_store.replace_from_world_snapshot(world_state)
	return true

