class_name WorldNetworkMessageBuffer
extends RefCounted

var network: WorldNetwork = null
var inventory_snapshots: Dictionary[int, Dictionary] = {}
var combat_messages: Dictionary[int, Array] = {}
var entity_messages: Dictionary[int, Array] = {}
var npc_action_messages: Dictionary[int, Array] = {}


func configure(owner: WorldNetwork) -> void:
	network = owner


func buffer_inventory_snapshot(sequence_id: int, snapshot: Dictionary) -> bool:
	if sequence_id <= 0 or network.runtime.get_current_action_sequence_id() == sequence_id:
		return false
	if not _can_buffer_sequence(sequence_id) or inventory_snapshots.size() >= NetworkProtocol.MAX_BUFFERED_SEQUENCES:
		_request_resync()
		return true
	inventory_snapshots[sequence_id] = snapshot.duplicate(true)
	return true


func buffer_combat(sequence_id: int, message: Dictionary) -> bool:
	return _buffer_message(combat_messages, sequence_id, message)


func buffer_entity(sequence_id: int, message: Dictionary) -> bool:
	return _buffer_message(entity_messages, sequence_id, message)


func buffer_npc_action(sequence_id: int, message: Dictionary) -> bool:
	return _buffer_message(npc_action_messages, sequence_id, message)


func flush_action(action: WorldActionRecord) -> void:
	if action == null:
		return
	var sequence_id: int = action.sequence_id
	var buffered_npc_actions: Array = npc_action_messages.get(sequence_id, []) as Array
	npc_action_messages.erase(sequence_id)
	buffered_npc_actions.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return int(first.get("subsequence_id", 0)) < int(second.get("subsequence_id", 0))
	)
	for message_value: Variant in buffered_npc_actions:
		_apply_npc_action(message_value as Dictionary)

	var buffered_entity_messages: Array = entity_messages.get(sequence_id, []) as Array
	entity_messages.erase(sequence_id)
	for message_value: Variant in buffered_entity_messages:
		_apply_entity(message_value as Dictionary)

	var buffered_combat_messages: Array = combat_messages.get(sequence_id, []) as Array
	combat_messages.erase(sequence_id)
	for message_value: Variant in buffered_combat_messages:
		_apply_combat(message_value as Dictionary)

	if inventory_snapshots.has(sequence_id):
		var snapshot: Dictionary = inventory_snapshots[sequence_id]
		inventory_snapshots.erase(sequence_id)
		network.inventory_bridge.apply_snapshot(snapshot)


func clear() -> void:
	inventory_snapshots.clear()
	combat_messages.clear()
	entity_messages.clear()
	npc_action_messages.clear()


func _buffer_message(target: Dictionary[int, Array], sequence_id: int, message: Dictionary) -> bool:
	if sequence_id <= 0 or network.runtime.get_current_action_sequence_id() == sequence_id:
		return false
	if not _can_buffer_sequence(sequence_id):
		if sequence_id >= network.runtime.get_expected_remote_action_sequence_id():
			_request_resync()
		return true
	var messages: Array = target.get(sequence_id, []) as Array
	if messages.size() >= NetworkProtocol.MAX_MESSAGES_PER_SEQUENCE or _get_message_count() >= NetworkProtocol.MAX_BUFFERED_MESSAGES:
		_request_resync()
		return true
	messages.append(message)
	target[sequence_id] = messages
	return true


func _can_buffer_sequence(sequence_id: int) -> bool:
	return WorldNetworkBufferPolicy.can_buffer_sequence(
		sequence_id,
		network.runtime.get_expected_remote_action_sequence_id()
	)


func _get_message_count() -> int:
	return WorldNetworkBufferPolicy.get_message_count(
		inventory_snapshots,
		combat_messages,
		entity_messages,
		npc_action_messages
	)


func _request_resync() -> void:
	if network.runtime.action_stream != null:
		network.runtime.action_stream.request_runtime_resync(WorldActionStream.REJECTION_SEQUENCE_GAP)


func _apply_combat(message: Dictionary) -> void:
	match str(message.get("kind", "")):
		"attack_result":
			network._apply_attack_result_message(str(message.get("attacker_entity_id", "")), str(message.get("target_entity_id", "")), int(message.get("damage_amount", 0)), int(message.get("target_health", 0)), int(message.get("target_max_health", 1)))
		"health":
			network._apply_health_message(str(message.get("entity_id", "")), int(message.get("health", 0)))
		"vitality":
			network._apply_vitality_message(str(message.get("entity_id", "")), int(message.get("health", 0)), int(message.get("max_health", 1)), int(message.get("damage", 0)))


func _apply_entity(message: Dictionary) -> void:
	match str(message.get("kind", "")):
		"object_state":
			network._apply_object_state_message(str(message.get("object_id", "")), int(message.get("object_state", 0)))
		"ai_state":
			network._apply_ai_state_message(str(message.get("entity_id", "")), str(message.get("state", "")), str(message.get("target_entity_id", "")), str(message.get("reason", "")))
		"respawn":
			network._apply_respawn_message(str(message.get("entity_id", "")), message.get("surface", Vector3i.ZERO), int(message.get("health", 0)))
		"removed":
			network._apply_removed_message(str(message.get("entity_id", "")))


func _apply_npc_action(message: Dictionary) -> void:
	match str(message.get("kind", "")):
		"move":
			network._apply_npc_move_message(str(message.get("entity_id", "")), message.get("from_surface", Vector3i.ZERO), message.get("target_surface", Vector3i.ZERO))
		"attack":
			network._apply_npc_attack_message(str(message.get("entity_id", "")), message.get("target_surface", Vector3i.ZERO))
