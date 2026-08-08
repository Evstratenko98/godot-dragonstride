class_name WorldLoot
extends Node

signal loot_revealed(chest_id: String, loot_entries: Array[Dictionary])
signal loot_resolved(chest_id: String)
signal loot_request_failed(chest_id: String, reason_code: String)

const DEFAULT_LOOT_TABLE: ChestLootTable = preload("res://scenes/loot/default_chest_loot_table.tres")
const INTERACTION_KIND_CHEST := "chest"
const SOURCE_KIND_CHEST := "chest"
const PAYLOAD_INTERACTION_KIND := "interaction_kind"
const PAYLOAD_CHEST_ID := "chest_id"
const PAYLOAD_LOOT_ENTRIES := "loot_entries"
const PAYLOAD_SOURCE_KIND := "source_kind"
const PAYLOAD_SOURCE_CHEST_ID := "source_chest_id"
const PAYLOAD_INVENTORY_KIND := "inventory_kind"
const PAYLOAD_TARGET_SLOT_INDEX := "target_slot_index"

var runtime: WorldRuntime = null
var level: WorldLevel = null
var loot_table: ChestLootTable = DEFAULT_LOOT_TABLE
var random_number_generator: RandomNumberGenerator = RandomNumberGenerator.new()
var pending_records: Dictionary[String, ChestLootRecord] = {}
var open_reservation_action_ids: Dictionary[String, int] = {}
var network_bridge: WorldLootNetworkBridge = WorldLootNetworkBridge.new()


func _ready() -> void:
	random_number_generator.randomize()


func _exit_tree() -> void:
	network_bridge.disconnect_signals()


func configure_context(new_runtime: WorldRuntime, new_level: WorldLevel) -> void:
	runtime = new_runtime
	level = new_level
	network_bridge.configure(self, runtime)


func get_action_rejection_reason(action: WorldActionRecord) -> String:
	if action == null:
		return WorldActionStream.REJECTION_INVALID_ACTION
	if action.action_type == WorldActionRecord.ActionType.INTERACTION:
		return _get_open_rejection_reason(action)
	if is_chest_claim_action(action):
		return _get_claim_rejection_reason(action)
	return ""


func reserve_action(action: WorldActionRecord) -> String:
	if action == null:
		return WorldActionStream.REJECTION_INVALID_ACTION
	if action.action_type == WorldActionRecord.ActionType.INTERACTION:
		return _reserve_open_action(action)
	if is_chest_claim_action(action):
		var rejection_reason: String = _get_claim_rejection_reason(action)
		if not rejection_reason.is_empty():
			return rejection_reason
		var record: ChestLootRecord = _get_record(str(action.payload.get(PAYLOAD_SOURCE_CHEST_ID, "")))
		record.claim_reservation_action_id = action.get_instance_id()
	return ""


func release_action_reservation(action: WorldActionRecord) -> void:
	if action == null:
		return
	var chest_id: String = str(action.payload.get(PAYLOAD_CHEST_ID, ""))
	if open_reservation_action_ids.get(chest_id, 0) == action.get_instance_id():
		open_reservation_action_ids.erase(chest_id)
	chest_id = str(action.payload.get(PAYLOAD_SOURCE_CHEST_ID, ""))
	var record: ChestLootRecord = _get_record(chest_id)
	if record != null and record.claim_reservation_action_id == action.get_instance_id():
		record.claim_reservation_action_id = 0


func is_chest_interaction_action(action: WorldActionRecord) -> bool:
	return (
		action != null
		and action.action_type == WorldActionRecord.ActionType.INTERACTION
		and str(action.payload.get(PAYLOAD_INTERACTION_KIND, "")) == INTERACTION_KIND_CHEST
	)


func is_chest_claim_action(action: WorldActionRecord) -> bool:
	return (
		action != null
		and action.action_type == WorldActionRecord.ActionType.INVENTORY_ADD
		and str(action.payload.get(PAYLOAD_SOURCE_KIND, "")) == SOURCE_KIND_CHEST
	)


func execute_open_action(action: WorldActionRecord, player: PlayerCharacter) -> bool:
	if player == null or not is_chest_interaction_action(action):
		return false
	var chest: Chest = runtime.get_object_by_id(str(action.payload.get(PAYLOAD_CHEST_ID, ""))) as Chest
	if chest == null or not chest.can_open():
		return false
	await chest.play_opening_animation()
	chest.set_opened()
	var record: ChestLootRecord = _record_from_action(action)
	if record == null:
		return false
	pending_records[record.chest_id] = record
	open_reservation_action_ids.erase(record.chest_id)
	runtime.broadcast_object_state(chest)
	_reveal_if_local(record)
	return true


func play_remote_open_action(action: WorldActionRecord) -> void:
	if not is_chest_interaction_action(action):
		return
	var record: ChestLootRecord = _record_from_action(action)
	if record == null:
		return
	pending_records[record.chest_id] = record
	var chest: Chest = runtime.get_object_by_id(str(action.payload.get(PAYLOAD_CHEST_ID, ""))) as Chest
	if chest != null and chest.can_open():
		await chest.play_opening_animation()
		chest.set_opened()
	_reveal_if_local(record)


func execute_claim_action(action: WorldActionRecord, player: PlayerCharacter) -> bool:
	if player == null or player.character_inventory == null or not is_chest_claim_action(action):
		return false
	var chest_id: String = str(action.payload.get(PAYLOAD_SOURCE_CHEST_ID, ""))
	var record: ChestLootRecord = _get_record(chest_id)
	if record == null or record.claim_reservation_action_id != action.get_instance_id():
		return false
	return player.character_inventory.try_add_item_at(
		record.get_item_id(),
		record.get_quantity(),
		int(action.payload.get(PAYLOAD_TARGET_SLOT_INDEX, -1))
	)


func request_claim(chest_id: String, inventory_kind: String, target_slot_index: int) -> bool:
	var record: ChestLootRecord = _get_record(chest_id)
	var player: PlayerCharacter = _get_local_opener(record)
	if player == null:
		return false
	if record.is_local_request_pending or not _is_matching_inventory_kind(record, player, inventory_kind):
		return false
	var request_id: int = runtime.create_action_request_id()
	if request_id <= 0:
		return false
	record.is_local_request_pending = true
	if GameSession.is_singleplayer():
		enqueue_claim_request(
			player,
			chest_id,
			inventory_kind,
			target_slot_index,
			player.character_inventory.revision,
			request_id,
			0,
			runtime.get_turn_revision(),
			GameSession.get_match_id()
		)
		return true
	if not NetworkManager.connection.is_ready():
		record.is_local_request_pending = false
		return false
	network_bridge.request_claim(
		player,
		chest_id,
		inventory_kind,
		target_slot_index,
		player.character_inventory.revision,
		request_id
	)
	return true


func request_discard(chest_id: String) -> bool:
	var record: ChestLootRecord = _get_record(chest_id)
	var player: PlayerCharacter = _get_local_opener(record)
	if player == null:
		return false
	if record.is_local_request_pending:
		return false
	var request_id: int = runtime.create_action_request_id()
	if request_id <= 0:
		return false
	record.is_local_request_pending = true
	if GameSession.is_singleplayer():
		return discard_authoritative(chest_id, player)
	if not NetworkManager.connection.is_ready():
		record.is_local_request_pending = false
		return false
	network_bridge.request_discard(player, chest_id, request_id)
	return true


func create_snapshot() -> Dictionary:
	var records: Array[Dictionary] = []
	for record: ChestLootRecord in pending_records.values():
		records.append(record.to_dictionary())
	return {"pending_rewards": records}


func is_valid_snapshot(snapshot: Dictionary) -> bool:
	var records_value: Variant = snapshot.get("pending_rewards", [])
	if not (records_value is Array) or (records_value as Array).size() > NetworkProtocol.MAX_WORLD_RECORDS:
		return false
	var seen_chest_ids: Dictionary[String, bool] = {}
	for record_value: Variant in records_value as Array:
		if not (record_value is Dictionary):
			return false
		var record: ChestLootRecord = ChestLootRecord.from_dictionary(record_value as Dictionary)
		if not _is_valid_record(record) or seen_chest_ids.has(record.chest_id):
			return false
		seen_chest_ids[record.chest_id] = true
	return true


func apply_snapshot(snapshot: Dictionary) -> bool:
	if not is_valid_snapshot(snapshot):
		return false
	pending_records.clear()
	for record_value: Variant in snapshot.get("pending_rewards", []):
		var record: ChestLootRecord = ChestLootRecord.from_dictionary(record_value as Dictionary)
		pending_records[record.chest_id] = record
	reveal_pending_for_local_player.call_deferred()
	return true


func reveal_pending_for_local_player() -> void:
	for record: ChestLootRecord in pending_records.values():
		if _get_local_opener(record) != null:
			_reveal_if_local(record)
			return


func _get_open_rejection_reason(action: WorldActionRecord) -> String:
	var chest: Chest = _get_chest_for_action(action)
	if chest == null:
		return WorldActionStream.REJECTION_INVALID_ACTION if is_chest_interaction_action(action) else ""
	var reservation_action_id: int = int(open_reservation_action_ids.get(chest.object_id, 0))
	if not chest.can_open():
		return "invalid_target"
	if reservation_action_id != 0 and reservation_action_id != action.get_instance_id():
		return WorldActionStream.REJECTION_ACTOR_BUSY
	return ""


func _reserve_open_action(action: WorldActionRecord) -> String:
	var chest: Chest = _get_chest_for_action(action)
	if chest == null:
		return ""
	var rejection_reason: String = _get_open_rejection_reason(action)
	if not rejection_reason.is_empty():
		return rejection_reason
	if not loot_table.is_valid():
		return WorldActionStream.REJECTION_INVALID_ACTION
	var item_id: String = loot_table.roll_reward_item_id(random_number_generator)
	if item_id.is_empty():
		return WorldActionStream.REJECTION_INVALID_ACTION
	action.payload[PAYLOAD_INTERACTION_KIND] = INTERACTION_KIND_CHEST
	action.payload[PAYLOAD_CHEST_ID] = chest.object_id
	action.payload[PAYLOAD_LOOT_ENTRIES] = [{
		ChestLootRecord.ENTRY_KEY_ITEM_ID: item_id,
		ChestLootRecord.ENTRY_KEY_QUANTITY: 1,
	}]
	open_reservation_action_ids[chest.object_id] = action.get_instance_id()
	return ""


func _get_claim_rejection_reason(action: WorldActionRecord) -> String:
	var player: PlayerCharacter = runtime.get_entity_by_id(action.actor_entity_id) as PlayerCharacter
	var record: ChestLootRecord = _get_record(str(action.payload.get(PAYLOAD_SOURCE_CHEST_ID, "")))
	if player == null or player.character_inventory == null or record == null:
		return "invalid_target"
	if record.opener_entity_id != player.entity_id:
		return "invalid_target"
	if record.claim_reservation_action_id not in [0, action.get_instance_id()]:
		return WorldActionStream.REJECTION_ACTOR_BUSY
	if str(action.payload.get("item_id", "")) != record.get_item_id():
		return WorldActionStream.REJECTION_INVALID_ACTION
	var inventory_kind: String = str(action.payload.get(PAYLOAD_INVENTORY_KIND, ""))
	if not _is_matching_inventory_kind(record, player, inventory_kind):
		return "invalid_slot"
	if not player.character_inventory.matches_revision(int(action.payload.get("expected_inventory_revision", -1))):
		return "stale_inventory"
	var target_slot_index: int = int(action.payload.get(PAYLOAD_TARGET_SLOT_INDEX, -1))
	var target_item: InventoryItem = player.character_inventory.get_item_at_slot(inventory_kind, target_slot_index)
	if target_item == null:
		return "" if target_slot_index >= 0 and target_slot_index < player.character_inventory.get_slot_count(inventory_kind) else "invalid_slot"
	if player.character_inventory.get_item_id(target_item) != record.get_item_id():
		return "invalid_slot"
	return "" if target_item.get_free_stack_space() >= record.get_quantity() else "invalid_slot"


func enqueue_claim_request(
	player: PlayerCharacter,
	chest_id: String,
	inventory_kind: String,
	target_slot_index: int,
	expected_inventory_revision: int,
	request_id: int,
	requester_peer_id: int,
	turn_revision: int,
	match_id: String
) -> void:
	var record: ChestLootRecord = _get_record(chest_id)
	var item_id: String = "" if record == null else record.get_item_id()
	var quantity: int = 0 if record == null else record.get_quantity()
	runtime.enqueue_player_action(
		WorldActionRecord.ActionType.INVENTORY_ADD,
		player,
		{
			"item_id": item_id,
			"amount": quantity,
			"expected_inventory_revision": expected_inventory_revision,
			PAYLOAD_SOURCE_KIND: SOURCE_KIND_CHEST,
			PAYLOAD_SOURCE_CHEST_ID: chest_id,
			PAYLOAD_INVENTORY_KIND: inventory_kind,
			PAYLOAD_TARGET_SLOT_INDEX: target_slot_index,
		},
		request_id,
		requester_peer_id,
		turn_revision,
		match_id
	)


func discard_authoritative(chest_id: String, player: PlayerCharacter) -> bool:
	var record: ChestLootRecord = _get_record(chest_id)
	if record == null or player == null or record.opener_entity_id != player.entity_id:
		return false
	if record.claim_reservation_action_id != 0:
		record.is_local_request_pending = false
		loot_request_failed.emit(record.chest_id, WorldActionStream.REJECTION_ACTOR_BUSY)
		return false
	pending_records.erase(record.chest_id)
	if GameSession.is_multiplayer():
		network_bridge.broadcast_discarded(record.chest_id, record.opener_entity_id)
	else:
		loot_resolved.emit(record.chest_id)
	return true


func _record_from_action(action: WorldActionRecord) -> ChestLootRecord:
	var entries: Array[Dictionary] = []
	for entry_value: Variant in action.payload.get(PAYLOAD_LOOT_ENTRIES, []):
		if entry_value is Dictionary:
			entries.append((entry_value as Dictionary).duplicate(true))
	var record: ChestLootRecord = ChestLootRecord.create(
		str(action.payload.get(PAYLOAD_CHEST_ID, "")),
		action.actor_entity_id,
		entries
	)
	return record if _is_valid_record(record) else null


func _is_valid_record(record: ChestLootRecord) -> bool:
	return (
		record != null
		and NetworkProtocol.is_valid_identifier(record.chest_id)
		and NetworkProtocol.is_valid_identifier(record.opener_entity_id)
		and record.loot_entries.size() == 1
		and record.get_item_id() in CharacterInventory.KNOWN_ITEM_IDS
		and record.get_quantity() == 1
	)


func _get_chest_for_action(action: WorldActionRecord) -> Chest:
	if runtime == null or action == null:
		return null
	return runtime.get_object_at_surface(action.payload.get("target_surface", Vector3i.ZERO)) as Chest


func _get_record(chest_id: String) -> ChestLootRecord:
	return pending_records.get(chest_id, null) as ChestLootRecord


func _is_matching_inventory_kind(
	record: ChestLootRecord,
	player: PlayerCharacter,
	inventory_kind: String
) -> bool:
	return (
		record != null
		and player != null
		and player.character_inventory != null
		and player.character_inventory.get_inventory_kind_for_item_id(record.get_item_id()) == inventory_kind
	)


func _reveal_if_local(record: ChestLootRecord) -> void:
	if _get_local_opener(record) != null:
		loot_revealed.emit(record.chest_id, record.loot_entries.duplicate(true))


func apply_discarded(chest_id: String, opener_entity_id: String) -> void:
	pending_records.erase(chest_id)
	var player: PlayerCharacter = runtime.get_player_by_entity_id(opener_entity_id)
	if player != null and player.is_locally_owned:
		loot_resolved.emit(chest_id)


func notify_request_failed(chest_id: String, reason_code: String) -> void:
	var record: ChestLootRecord = _get_record(chest_id)
	if record != null:
		record.is_local_request_pending = false
	loot_request_failed.emit(chest_id, reason_code)


func handle_action_completed(action: WorldActionRecord) -> void:
	if not is_chest_claim_action(action):
		return
	var chest_id: String = str(action.payload.get(PAYLOAD_SOURCE_CHEST_ID, ""))
	var record: ChestLootRecord = _get_record(chest_id)
	pending_records.erase(chest_id)
	if record != null:
		_reveal_resolution_if_local(record)


func handle_action_cancelled(action: WorldActionRecord, reason_code: String) -> void:
	if not is_chest_claim_action(action):
		return
	release_action_reservation(action)
	var chest_id: String = str(action.payload.get(PAYLOAD_SOURCE_CHEST_ID, ""))
	var record: ChestLootRecord = _get_record(chest_id)
	if record != null:
		record.is_local_request_pending = false
	loot_request_failed.emit(chest_id, reason_code)


func handle_local_action_rejected(reason_code: String) -> void:
	for record: ChestLootRecord in pending_records.values():
		if record.is_local_request_pending:
			record.is_local_request_pending = false
			loot_request_failed.emit(record.chest_id, reason_code)
			return


func _reveal_resolution_if_local(record: ChestLootRecord) -> void:
	if _get_local_opener(record) != null:
		loot_resolved.emit(record.chest_id)


func _get_local_opener(record: ChestLootRecord) -> PlayerCharacter:
	if runtime == null or record == null:
		return null
	var player: PlayerCharacter = runtime.get_player_by_entity_id(record.opener_entity_id)
	return player if player != null and player.is_locally_owned else null


func clear_state() -> void:
	pending_records.clear()
	open_reservation_action_ids.clear()
