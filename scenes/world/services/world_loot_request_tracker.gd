class_name WorldLootRequestTracker
extends RefCounted

const REQUEST_TIMEOUT_MSEC: int = 35_000

var deadline_by_chest_id: Dictionary[String, int] = {}
var next_deadline_msec: int = 0


func begin(chest_id: String) -> void:
	var deadline_msec: int = Time.get_ticks_msec() + REQUEST_TIMEOUT_MSEC
	deadline_by_chest_id[chest_id] = deadline_msec
	if next_deadline_msec <= 0 or deadline_msec < next_deadline_msec:
		next_deadline_msec = deadline_msec


func finish(chest_id: String) -> void:
	deadline_by_chest_id.erase(chest_id)


func take_expired(now_msec: int) -> Array[String]:
	var expired_chest_ids: Array[String] = []
	if next_deadline_msec <= 0 or now_msec < next_deadline_msec:
		return expired_chest_ids
	next_deadline_msec = 0
	for chest_id: String in deadline_by_chest_id.keys():
		var deadline_msec: int = int(deadline_by_chest_id.get(chest_id, 0))
		if now_msec >= deadline_msec:
			expired_chest_ids.append(chest_id)
			deadline_by_chest_id.erase(chest_id)
			continue
		if next_deadline_msec <= 0 or deadline_msec < next_deadline_msec:
			next_deadline_msec = deadline_msec
	return expired_chest_ids


func clear() -> void:
	deadline_by_chest_id.clear()
	next_deadline_msec = 0
