class_name WorldActionIntentGate
extends RefCounted

const MAX_PROCESSED_REQUESTS_PER_PLAYER := 256
const INTENT_RATE_PER_SECOND := 8.0
const INTENT_RATE_BURST := 12.0

var processed_request_keys: Dictionary[String, bool] = {}
var processed_request_order_by_steam_id: Dictionary[int, Array] = {}
var processed_request_head_by_steam_id: Dictionary[int, int] = {}
var intent_tokens_by_steam_id: Dictionary[int, float] = {}
var intent_refill_msec_by_steam_id: Dictionary[int, int] = {}


func has_processed(action: WorldActionRecord) -> bool:
	return action != null and processed_request_keys.has(_make_request_key(action))


func consume_rate_limit_token(steam_id: int) -> bool:
	var now_msec: int = Time.get_ticks_msec()
	var previous_msec: int = int(intent_refill_msec_by_steam_id.get(steam_id, now_msec))
	var elapsed_seconds: float = float(maxi(now_msec - previous_msec, 0)) / 1000.0
	var available_tokens: float = float(intent_tokens_by_steam_id.get(steam_id, INTENT_RATE_BURST))
	available_tokens = minf(INTENT_RATE_BURST, available_tokens + elapsed_seconds * INTENT_RATE_PER_SECOND)
	intent_refill_msec_by_steam_id[steam_id] = now_msec
	if available_tokens < 1.0:
		intent_tokens_by_steam_id[steam_id] = available_tokens
		return false
	intent_tokens_by_steam_id[steam_id] = available_tokens - 1.0
	return true


func record_processed(action: WorldActionRecord) -> void:
	var request_key: String = _make_request_key(action)
	processed_request_keys[request_key] = true
	var request_order: Array = processed_request_order_by_steam_id.get(action.requester_steam_id, []) as Array
	var request_head_index: int = int(processed_request_head_by_steam_id.get(action.requester_steam_id, 0))
	request_order.append(request_key)
	while request_order.size() - request_head_index > MAX_PROCESSED_REQUESTS_PER_PLAYER:
		var expired_key: String = str(request_order[request_head_index])
		request_head_index += 1
		processed_request_keys.erase(expired_key)
	if request_head_index >= MAX_PROCESSED_REQUESTS_PER_PLAYER and request_head_index * 2 >= request_order.size():
		request_order = request_order.slice(request_head_index)
		request_head_index = 0
	processed_request_order_by_steam_id[action.requester_steam_id] = request_order
	processed_request_head_by_steam_id[action.requester_steam_id] = request_head_index


func clear() -> void:
	processed_request_keys.clear()
	processed_request_order_by_steam_id.clear()
	processed_request_head_by_steam_id.clear()
	intent_tokens_by_steam_id.clear()
	intent_refill_msec_by_steam_id.clear()


func _make_request_key(action: WorldActionRecord) -> String:
	return "%s:%d:%d" % [action.match_id, action.requester_steam_id, action.request_id]
