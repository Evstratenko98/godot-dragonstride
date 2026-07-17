class_name NetworkProtocol
extends RefCounted

const PROTOCOL_VERSION := 2
const SNAPSHOT_SCHEMA_VERSION := 1
const MAX_ROSTER_SIZE := 4
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

const SAFE_REASON_CODES: PackedStringArray = [
	"actor_busy",
	"actor_disconnected",
	"actor_unavailable",
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
	"network_unavailable",
	"not_active_player",
	"payload_too_large",
	"presentation_timeout",
	"protocol_mismatch",
	"queue_full",
	"rate_limited",
	"registration_failed",
	"sequence_gap",
	"stale_inventory",
	"stale_turn",
	"state_sync_failed",
	"state_sync_invalid",
	"state_sync_timeout",
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


static func is_valid_cell_value(cell: Vector2i) -> bool:
	return (
		absi(cell.x) <= MAX_ABSOLUTE_GRID_COORDINATE
		and absi(cell.y) <= MAX_ABSOLUTE_GRID_COORDINATE
	)


static func is_valid_nonnegative_value(value: int) -> bool:
	return value >= 0 and value <= MAX_GAMEPLAY_VALUE


static func is_safe_reason_code(reason_code: String) -> bool:
	return reason_code in SAFE_REASON_CODES


static func get_payload_size(payload: Variant) -> int:
	return var_to_bytes(payload).size()


static func is_valid_intent_payload(payload: Variant) -> bool:
	return get_payload_size(payload) <= MAX_INTENT_PAYLOAD_BYTES


static func is_valid_snapshot_size(payload: PackedByteArray) -> bool:
	return not payload.is_empty() and payload.size() <= MAX_SNAPSHOT_BYTES
