class_name WorldMoveRequestTracker
extends RefCounted

var request_id: int = 0
var sequence_id: int = 0


func is_pending() -> bool:
	return request_id > 0


func begin(new_request_id: int) -> void:
	request_id = new_request_id
	sequence_id = 0


func finish_action(action: WorldActionRecord) -> void:
	if (
		action != null
		and action.action_type == WorldActionRecord.ActionType.MOVE_PATH
		and action.request_id == request_id
	):
		clear()


func handle_rejected(rejected_request_id: int) -> void:
	if rejected_request_id == request_id:
		clear()


func handle_accepted(accepted_request_id: int, accepted_sequence_id: int) -> void:
	if accepted_request_id == request_id:
		sequence_id = accepted_sequence_id


func handle_snapshot_committed(boundary_sequence_id: int) -> void:
	if request_id > 0 and sequence_id > 0 and sequence_id < boundary_sequence_id:
		clear()


func clear() -> void:
	request_id = 0
	sequence_id = 0
