class_name WorldActionRecord
extends RefCounted

enum ActionType {
	NONE,
	MOVE,
	ATTACK,
	INTERACTION,
	SPELL_CAST,
	INVENTORY_ADD,
	INVENTORY_MOVE,
	INVENTORY_DELETE,
	INVENTORY_USE,
	CHARACTER_KILL,
	PLAYER_TURN_STARTED,
	END_PLAYER_TURN,
	WORLD_TURN_STARTED,
	WORLD_TURN_ENDED,
	SET_TURN_MODE,
	PLAYER_TURN_SKIPPED,
	BLOCKING_EVENT,
}

const KEY_REQUEST_ID := "request_id"
const KEY_PROTOCOL_VERSION := "protocol_version"
const KEY_MATCH_ID := "match_id"
const KEY_SEQUENCE_ID := "sequence_id"
const KEY_REQUESTER_STEAM_ID := "requester_steam_id"
const KEY_ACTOR_ENTITY_ID := "actor_entity_id"
const KEY_ACTION_TYPE := "action_type"
const KEY_TURN_REVISION := "turn_revision"
const KEY_PAYLOAD := "payload"

var request_id: int = 0
var match_id: String = ""
var sequence_id: int = 0
var requester_steam_id: int = 0
var actor_entity_id: String = ""
var action_type: ActionType = ActionType.NONE
var turn_revision: int = 0
var payload: Dictionary = {}


static func create(
	new_request_id: int,
	new_match_id: String,
	new_requester_steam_id: int,
	new_actor_entity_id: String,
	new_action_type: ActionType,
	new_turn_revision: int,
	new_payload: Dictionary
) -> WorldActionRecord:
	var action: WorldActionRecord = WorldActionRecord.new()
	action.request_id = new_request_id
	action.match_id = new_match_id
	action.requester_steam_id = new_requester_steam_id
	action.actor_entity_id = new_actor_entity_id
	action.action_type = new_action_type
	action.turn_revision = new_turn_revision
	action.payload = new_payload.duplicate(true)
	return action


static func from_dictionary(record: Dictionary) -> WorldActionRecord:
	if not NetworkProtocol.is_current_version(int(record.get(KEY_PROTOCOL_VERSION, 0))):
		return null
	var action_type_value: int = int(record.get(KEY_ACTION_TYPE, int(ActionType.NONE)))
	if action_type_value <= int(ActionType.NONE) or action_type_value > int(ActionType.BLOCKING_EVENT):
		return null

	var payload_value: Variant = record.get(KEY_PAYLOAD, {})
	if not (payload_value is Dictionary):
		return null

	var action: WorldActionRecord = WorldActionRecord.new()
	action.request_id = int(record.get(KEY_REQUEST_ID, 0))
	action.match_id = str(record.get(KEY_MATCH_ID, ""))
	action.sequence_id = int(record.get(KEY_SEQUENCE_ID, 0))
	action.requester_steam_id = int(record.get(KEY_REQUESTER_STEAM_ID, 0))
	action.actor_entity_id = str(record.get(KEY_ACTOR_ENTITY_ID, ""))
	action.action_type = action_type_value as ActionType
	action.turn_revision = int(record.get(KEY_TURN_REVISION, 0))
	action.payload = (payload_value as Dictionary).duplicate(true)
	if action.sequence_id <= 0:
		return null
	return action


func to_dictionary() -> Dictionary:
	return {
		KEY_PROTOCOL_VERSION: NetworkProtocol.PROTOCOL_VERSION,
		KEY_REQUEST_ID: request_id,
		KEY_MATCH_ID: match_id,
		KEY_SEQUENCE_ID: sequence_id,
		KEY_REQUESTER_STEAM_ID: requester_steam_id,
		KEY_ACTOR_ENTITY_ID: actor_entity_id,
		KEY_ACTION_TYPE: int(action_type),
		KEY_TURN_REVISION: turn_revision,
		KEY_PAYLOAD: payload.duplicate(true),
	}


func to_lifecycle_dictionary() -> Dictionary:
	return {
		KEY_PROTOCOL_VERSION: NetworkProtocol.PROTOCOL_VERSION,
		KEY_REQUEST_ID: request_id,
		KEY_MATCH_ID: match_id,
		KEY_SEQUENCE_ID: sequence_id,
		KEY_REQUESTER_STEAM_ID: requester_steam_id,
		KEY_ACTOR_ENTITY_ID: actor_entity_id,
		KEY_ACTION_TYPE: int(action_type),
		KEY_TURN_REVISION: turn_revision,
	}
