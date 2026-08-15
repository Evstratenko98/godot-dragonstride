class_name NetworkProtocol
extends RefCounted

const PROTOCOL_VERSION := 14
const SNAPSHOT_SCHEMA_VERSION := 5
const MAP_SCHEMA_VERSION := 2
const MAX_ROSTER_SIZE := 4
const MAX_SQUAD_SIZE := 4
const MAX_PLAYER_CHARACTERS := MAX_ROSTER_SIZE * MAX_SQUAD_SIZE
const MAX_IDENTIFIER_LENGTH := 64
const MAX_INTENT_PAYLOAD_BYTES := 8 * 1024
const MAX_SNAPSHOT_BYTES := 512 * 1024
const SNAPSHOT_CHUNK_BYTES := 48 * 1024
const MAX_SNAPSHOT_CHUNKS := 16
const MAX_WORLD_RECORDS := 512
const MAX_FUTURE_SEQUENCE_DISTANCE := 64
const MAX_BUFFERED_SEQUENCES := 64
const MAX_MESSAGES_PER_SEQUENCE := 32
const MAX_BUFFERED_MESSAGES := 256
const MAX_GAMEPLAY_VALUE := 1_000_000
const MAX_ABSOLUTE_GRID_COORDINATE := 1_000_000
const MAX_MOVE_PATH_SURFACES := 512
const MAX_LEVEL_MAP_BYTES := 4 * 1024 * 1024
const LEVEL_MAP_CHUNK_BYTES := 48 * 1024
const MAX_LEVEL_MAP_CHUNKS := 86
const MAX_LEVEL_MAP_LAYERS := 16
const MAX_LEVEL_MAP_TILE_RECORDS := 131_072
const MAX_LEVEL_MAP_PLACEMENTS := 512


static func make_squad_member_entity_id(player_id: String, squad_slot: int) -> String:
	return "%s_follower_%d" % [player_id, squad_slot + 1]

const SAFE_REASON_CODES: PackedStringArray = [
	"actor_busy",
	"actor_disconnected",
	"actor_unavailable",
	"ability_unavailable",
	"duplicate_request",
	"effect_failed",
	"invalid_action",
	"invalid_clear_type",
	"invalid_placement",
	"invalid_payload",
	"invalid_player",
	"invalid_slot",
	"invalid_target",
	"invalid_turn",
	"map_build_failed",
	"map_invalid",
	"map_sync_timeout",
	"map_too_large",
	"network_unavailable",
	"not_active_player",
	"payload_too_large",
	"presentation_timeout",
	"protocol_mismatch",
	"queue_full",
	"rate_limited",
	"registration_failed",
	"sequence_gap",
	"snapshot_too_large",
	"stale_inventory",
	"stale_turn",
	"state_sync_failed",
	"state_sync_invalid",
	"state_sync_timeout",
	"topology_mismatch",
	"spell_unavailable",
	"unknown_type",
	"world_turn",
	"wrong_match",
]


static func is_current_version(protocol_version: int) -> bool:
	return protocol_version == PROTOCOL_VERSION


static func is_valid_match_id(match_id: String) -> bool:
	return (
		not match_id.is_empty()
		and match_id.length() <= MAX_IDENTIFIER_LENGTH
		and match_id == GameSession.get_match_id()
	)


static func is_valid_identifier(identifier: String) -> bool:
	return not identifier.is_empty() and identifier.length() <= MAX_IDENTIFIER_LENGTH


static func is_valid_optional_identifier(identifier: String) -> bool:
	return identifier.is_empty() or is_valid_identifier(identifier)


static func is_valid_bounded_text(value: String) -> bool:
	return value.length() <= MAX_IDENTIFIER_LENGTH


static func is_valid_surface_value(surface: Vector3i) -> bool:
	return (
		absi(surface.x) <= MAX_ABSOLUTE_GRID_COORDINATE
		and absi(surface.y) <= MAX_ABSOLUTE_GRID_COORDINATE
		and surface.z >= WorldGridTopology.MIN_ELEVATION
		and surface.z <= WorldGridTopology.MAX_ELEVATION
	)


static func is_valid_move_path(path_value: Variant) -> bool:
	if not (path_value is Array):
		return false
	var path: Array = path_value as Array
	if path.is_empty() or path.size() > MAX_MOVE_PATH_SURFACES:
		return false
	for surface_value: Variant in path:
		if not (surface_value is Vector3i) or not is_valid_surface_value(surface_value as Vector3i):
			return false
	return true


static func is_valid_nonnegative_value(value: int) -> bool:
	return value >= 0 and value <= MAX_GAMEPLAY_VALUE


static func is_safe_reason_code(reason_code: String) -> bool:
	return reason_code in SAFE_REASON_CODES


static func get_payload_size(payload: Variant) -> int:
	return var_to_bytes(payload).size()


static func is_valid_intent_payload(payload: Variant) -> bool:
	return get_payload_size(payload) <= MAX_INTENT_PAYLOAD_BYTES


static func is_valid_snapshot_size(payload: PackedByteArray) -> bool:
	return not payload.is_empty() and get_snapshot_size_rejection_reason(payload).is_empty()


static func get_snapshot_size_rejection_reason(payload: PackedByteArray) -> String:
	if payload.size() > MAX_SNAPSHOT_BYTES:
		return "snapshot_too_large"
	var chunk_count: int = ceili(float(payload.size()) / float(SNAPSHOT_CHUNK_BYTES))
	if chunk_count > MAX_SNAPSHOT_CHUNKS:
		return "snapshot_too_large"
	return ""


static func is_safe_snapshot_sync_failure_reason(reason_code: String) -> bool:
	return reason_code in ["state_sync_timeout", "state_sync_invalid", "snapshot_too_large"]


static func is_safe_world_start_failure_reason(reason_code: String) -> bool:
	return reason_code in [
		"invalid_spawn_snapshot",
		"map_build_failed",
		"map_invalid",
		"map_sync_timeout",
		"map_too_large",
		"snapshot_too_large",
		"spawn_snapshot_timeout",
		"state_sync_invalid",
		"state_sync_timeout",
		"world_timeout",
	]
