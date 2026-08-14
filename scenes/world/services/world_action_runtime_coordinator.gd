class_name WorldActionRuntimeCoordinator
extends RefCounted

var runtime: WorldRuntime = null
var router: WorldActionRouter = WorldActionRouter.new()
var snapshot: WorldStateSnapshot = WorldStateSnapshot.new()
var startup: WorldMatchStartup = WorldMatchStartup.new()


func configure_context(owner: WorldRuntime) -> void:
	runtime = owner
	router.configure_context(
		runtime,
		runtime.players_service,
		runtime.network,
		runtime.turn_manager,
		runtime.spells,
		runtime.loot,
		runtime.visibility,
		runtime.abilities
	)
	snapshot.configure_context(
		runtime,
		runtime.registry,
		runtime.spawner,
		runtime.turn_manager,
		runtime.spells,
		runtime.loot,
		runtime.visibility,
		runtime.abilities,
		NetworkManager.store
	)
	startup.configure_context(
		runtime,
		runtime.registry,
		runtime.network,
		runtime.players_service,
		runtime.action_stream,
		runtime.spawner,
		snapshot
	)


func start_match_runtime() -> String:
	return await startup.start_match_runtime()


func create_snapshot(next_stream_sequence_id: int) -> Dictionary:
	return snapshot.create_action_stream_snapshot(next_stream_sequence_id)


func apply_snapshot(value: Dictionary) -> bool:
	if int(value.get("snapshot_schema_version", -1)) != NetworkProtocol.SNAPSHOT_SCHEMA_VERSION:
		runtime.runtime_sync_failed.emit("snapshot_schema_mismatch")
		return false
	if str(value.get("topology_hash", "")) != runtime.get_topology_hash():
		runtime.runtime_sync_failed.emit("topology_mismatch")
		return false
	return snapshot.apply_action_stream_snapshot(value)


func broadcast_profile(action: WorldActionRecord) -> void:
	router.broadcast_action_profile_payload(action)


func schema_rejection(action: WorldActionRecord) -> String:
	return router.get_schema_rejection_reason(action)


func acceptance_rejection(action: WorldActionRecord) -> String:
	return router.get_acceptance_rejection_reason(action)


func reserve(action: WorldActionRecord) -> String:
	return router.reserve_on_accept(action)


func release(action: WorldActionRecord) -> void:
	router.release_reservation(action)


func rejection(action: WorldActionRecord) -> String:
	return router.get_rejection_reason(action)


func execute(action: WorldActionRecord) -> bool:
	return await router.execute_authoritative(action)


func play_remote(action: WorldActionRecord) -> void:
	await router.play_remote(action)


func finalize(action: WorldActionRecord) -> void:
	router.finalize_authoritative(action)
