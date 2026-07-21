class_name WorldNetworkBufferPolicy
extends RefCounted


static func can_buffer_sequence(sequence_id: int, expected_sequence_id: int) -> bool:
	return (
		sequence_id >= expected_sequence_id
		and sequence_id - expected_sequence_id <= NetworkProtocol.MAX_FUTURE_SEQUENCE_DISTANCE
	)


static func get_message_count(
	inventory_snapshots: Dictionary[int, Dictionary],
	combat_messages: Dictionary[int, Array],
	entity_messages: Dictionary[int, Array],
	npc_action_messages: Dictionary[int, Array]
) -> int:
	var count: int = inventory_snapshots.size()
	for messages_value: Variant in combat_messages.values():
		count += (messages_value as Array).size()
	for messages_value: Variant in entity_messages.values():
		count += (messages_value as Array).size()
	for messages_value: Variant in npc_action_messages.values():
		count += (messages_value as Array).size()
	return count
