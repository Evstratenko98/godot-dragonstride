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
const KEY_SEQUENCE_ID := "sequence_id"
const KEY_REQUESTER_STEAM_ID := "requester_steam_id"
const KEY_ACTOR_ENTITY_ID := "actor_entity_id"
const KEY_ACTION_TYPE := "action_type"
const KEY_TURN_EPOCH := "turn_epoch"
const KEY_PAYLOAD := "payload"

var request_id: int = 0
var sequence_id: int = 0
var requester_steam_id: int = 0
var actor_entity_id: String = ""
var action_type: ActionType = ActionType.NONE
var turn_epoch: int = 0
var payload: Dictionary = {}


static func create(
	new_request_id: int,
	new_requester_steam_id: int,
	new_actor_entity_id: String,
	new_action_type: ActionType,
	new_turn_epoch: int,
	new_payload: Dictionary
) -> WorldActionRecord:
	var action: WorldActionRecord = WorldActionRecord.new()
	action.request_id = new_request_id
	action.requester_steam_id = new_requester_steam_id
	action.actor_entity_id = new_actor_entity_id
	action.action_type = new_action_type
	action.turn_epoch = new_turn_epoch
	action.payload = new_payload.duplicate(true)
	return action


static func from_dictionary(record: Dictionary) -> WorldActionRecord:
	var action_type_value: int = int(record.get(KEY_ACTION_TYPE, int(ActionType.NONE)))
	if action_type_value <= int(ActionType.NONE) or action_type_value > int(ActionType.BLOCKING_EVENT):
		return null

	var payload_value: Variant = record.get(KEY_PAYLOAD, {})
	if not (payload_value is Dictionary):
		return null

	var action: WorldActionRecord = WorldActionRecord.new()
	action.request_id = int(record.get(KEY_REQUEST_ID, 0))
	action.sequence_id = int(record.get(KEY_SEQUENCE_ID, 0))
	action.requester_steam_id = int(record.get(KEY_REQUESTER_STEAM_ID, 0))
	action.actor_entity_id = str(record.get(KEY_ACTOR_ENTITY_ID, ""))
	action.action_type = action_type_value as ActionType
	action.turn_epoch = int(record.get(KEY_TURN_EPOCH, 0))
	action.payload = (payload_value as Dictionary).duplicate(true)
	if action.sequence_id <= 0:
		return null
	return action


func to_dictionary() -> Dictionary:
	return {
		KEY_REQUEST_ID: request_id,
		KEY_SEQUENCE_ID: sequence_id,
		KEY_REQUESTER_STEAM_ID: requester_steam_id,
		KEY_ACTOR_ENTITY_ID: actor_entity_id,
		KEY_ACTION_TYPE: int(action_type),
		KEY_TURN_EPOCH: turn_epoch,
		KEY_PAYLOAD: payload.duplicate(true),
	}


func to_lifecycle_dictionary() -> Dictionary:
	return {
		KEY_REQUEST_ID: request_id,
		KEY_SEQUENCE_ID: sequence_id,
		KEY_REQUESTER_STEAM_ID: requester_steam_id,
		KEY_ACTOR_ENTITY_ID: actor_entity_id,
		KEY_ACTION_TYPE: int(action_type),
		KEY_TURN_EPOCH: turn_epoch,
	}
