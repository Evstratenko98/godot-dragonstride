class_name WorldActionStreamDiagnostics
extends RefCounted

var counters: Dictionary[String, int] = {}


func _init() -> void:
	reset()


func increment(counter_name: String) -> void:
	counters[counter_name] = int(counters.get(counter_name, 0)) + 1


func reset() -> void:
	counters = {
		"resync_attempts": 0,
		"resync_successes": 0,
		"resync_failures": 0,
		"stale_packets": 0,
		"buffer_rejections": 0,
		"watchdog_activations": 0,
	}


func create_snapshot(
	buffered_sequence_count: int,
	buffered_payload_count: int,
	buffered_auxiliary_profile_count: int
) -> Dictionary:
	var snapshot: Dictionary = counters.duplicate()
	snapshot["buffered_sequences"] = buffered_sequence_count
	snapshot["buffered_payloads"] = buffered_payload_count
	snapshot["buffered_auxiliary_profiles"] = buffered_auxiliary_profile_count
	return snapshot
