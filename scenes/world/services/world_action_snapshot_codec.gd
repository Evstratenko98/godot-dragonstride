class_name WorldActionSnapshotCodec
extends RefCounted

const REJECTION_SNAPSHOT_TOO_LARGE := "snapshot_too_large"


static func create_envelope(
	base_snapshot: Dictionary,
	match_id: String,
	sync_id: String,
	boundary_sequence_id: int
) -> Dictionary:
	var snapshot: Dictionary = base_snapshot.duplicate(true)
	snapshot["protocol_version"] = NetworkProtocol.PROTOCOL_VERSION
	snapshot["snapshot_schema_version"] = NetworkProtocol.SNAPSHOT_SCHEMA_VERSION
	snapshot["match_id"] = match_id
	snapshot["sync_id"] = sync_id
	snapshot["boundary_sequence_id"] = boundary_sequence_id
	snapshot["roster_hash"] = GameSession.get_roster_hash()
	return snapshot


static func create_preflight_envelope(
	base_snapshot: Dictionary,
	boundary_sequence_id: int
) -> Dictionary:
	return create_envelope(
		base_snapshot,
		GameSession.get_match_id(),
		"s".repeat(NetworkProtocol.MAX_IDENTIFIER_LENGTH),
		boundary_sequence_id
	)


static func get_capacity_rejection_reason(snapshot: Dictionary) -> String:
	var turn_state: Dictionary = snapshot.get("turn_state", {}) as Dictionary
	var spell_state: Dictionary = snapshot.get("spell_state", {}) as Dictionary
	var loot_state: Dictionary = snapshot.get("loot_state", {}) as Dictionary
	if (
		_get_collection_size(turn_state.get("turn_order", [])) > NetworkProtocol.MAX_ROSTER_SIZE
		or _get_collection_size(turn_state.get("steps_left_by_entity_id", {})) > NetworkProtocol.MAX_PLAYER_CHARACTERS
		or _get_collection_size(turn_state.get("attacks_left_by_entity_id", {})) > NetworkProtocol.MAX_PLAYER_CHARACTERS
		or _get_collection_size(turn_state.get("interactions_left_by_entity_id", {})) > NetworkProtocol.MAX_PLAYER_CHARACTERS
		or _get_collection_size(spell_state.get("used_spell_slots", {})) > NetworkProtocol.MAX_PLAYER_CHARACTERS
		or _get_collection_size(loot_state.get("pending_rewards", [])) > NetworkProtocol.MAX_WORLD_RECORDS
	):
		return REJECTION_SNAPSHOT_TOO_LARGE
	var world_state_value: Variant = snapshot.get("world_state", {})
	if world_state_value is Dictionary:
		var world_state: Dictionary = world_state_value as Dictionary
		if (
			_get_collection_size(world_state.get("entities", [])) > NetworkProtocol.MAX_WORLD_RECORDS
			or _get_collection_size(world_state.get("objects", [])) > NetworkProtocol.MAX_WORLD_RECORDS
			or _get_collection_size(world_state.get("inventories", [])) > NetworkProtocol.MAX_PLAYER_CHARACTERS
			or _get_collection_size(world_state.get("dynamic_spawns", [])) > NetworkProtocol.MAX_WORLD_RECORDS
			or _get_collection_size(world_state.get("removed_items", [])) > NetworkProtocol.MAX_WORLD_RECORDS
			or _get_collection_size(world_state.get("ai_states", {})) > NetworkProtocol.MAX_WORLD_RECORDS
		):
			return REJECTION_SNAPSHOT_TOO_LARGE
	var serialized_snapshot: PackedByteArray = var_to_bytes(snapshot)
	return NetworkProtocol.get_snapshot_size_rejection_reason(serialized_snapshot)


static func _get_collection_size(value: Variant) -> int:
	if value is Array:
		return (value as Array).size()
	if value is Dictionary:
		return (value as Dictionary).size()
	return 0
