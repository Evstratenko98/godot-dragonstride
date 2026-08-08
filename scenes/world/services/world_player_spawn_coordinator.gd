class_name WorldPlayerSpawnCoordinator
extends RefCounted

const CHARACTER_SCENE := preload("res://scenes/entities/character/character.tscn")
const INVALID_SPAWN_SURFACE: Vector3i = Vector3i(-1, -1, -1)
const SINGLEPLAYER_WARRIOR_COLOR := "Purple"

var runtime: WorldRuntime = null
var players_root: Node2D = null
var squad_registry: PlayerSquadRegistry = null
var spawn_surfaces: Array[Vector3i] = []
var authoritative_snapshot: Dictionary = {}


func configure(
	new_runtime: WorldRuntime,
	new_players_root: Node2D,
	new_registry: PlayerSquadRegistry,
	new_spawn_surfaces: Array[Vector3i]
) -> void:
	runtime = new_runtime
	players_root = new_players_root
	squad_registry = new_registry
	spawn_surfaces = new_spawn_surfaces.duplicate()


func spawn_singleplayer() -> String:
	var player_info: Dictionary = GameSession.get_local_player_record()
	for squad_slot: int in range(GameSession.get_squad_size()):
		var spawn_index: int = squad_slot
		var spawn_surface: Vector3i = WorldPlayerSpawnPlanner.get_default_spawn_surface(runtime, spawn_surfaces, spawn_index)
		var member: PlayerCharacter = _spawn_member(player_info, squad_slot, spawn_surface, SINGLEPLAYER_WARRIOR_COLOR)
		if member == null:
			return "spawn_registration_failed"
	return ""


func spawn_authoritative(session_players: Array[Dictionary]) -> String:
	var spawn_records: Array[Dictionary] = []
	var assigned_surfaces: Dictionary[Vector3i, bool] = {}
	var squad_size: int = GameSession.get_squad_size()
	for player_index: int in range(session_players.size()):
		var player_info: Dictionary = session_players[player_index]
		var warrior_color: String = WorldPlayerSpawnPlanner.get_warrior_color(int(player_info.get("color_index", player_index)))
		for squad_slot: int in range(squad_size):
			var spawn_index: int = player_index * squad_size + squad_slot
			var preferred_surface: Vector3i = INVALID_SPAWN_SURFACE
			var has_preferred_surface: bool = spawn_index < spawn_surfaces.size()
			if has_preferred_surface:
				preferred_surface = spawn_surfaces[spawn_index]
			var spawn_surface: Vector3i = WorldPlayerSpawnPlanner.find_available_surface(
				runtime,
				preferred_surface,
				has_preferred_surface,
				assigned_surfaces
			)
			if spawn_surface == INVALID_SPAWN_SURFACE:
				return "spawn_unavailable"
			var member: PlayerCharacter = _spawn_member(player_info, squad_slot, spawn_surface, warrior_color)
			if member == null:
				return "spawn_registration_failed"
			assigned_surfaces[spawn_surface] = true
			spawn_records.append(_create_spawn_record(member, spawn_surface))
	authoritative_snapshot = {
		"protocol_version": NetworkProtocol.PROTOCOL_VERSION,
		"match_id": GameSession.get_match_id(),
		"level_id": GameSession.selected_level_id,
		"roster_hash": GameSession.get_roster_hash(),
		"squad_size": squad_size,
		"topology_hash": runtime.get_topology_hash(),
		"members": spawn_records,
	}
	return ""


func spawn_from_snapshot(session_players: Array[Dictionary], snapshot: Dictionary) -> bool:
	if (
		int(snapshot.get("protocol_version", 0)) != NetworkProtocol.PROTOCOL_VERSION
		or str(snapshot.get("match_id", "")) != GameSession.get_match_id()
		or str(snapshot.get("level_id", "")) != GameSession.selected_level_id
		or str(snapshot.get("roster_hash", "")) != GameSession.get_roster_hash()
		or int(snapshot.get("squad_size", 0)) != GameSession.get_squad_size()
		or str(snapshot.get("topology_hash", "")) != runtime.get_topology_hash()
	):
		return false
	var records_value: Variant = snapshot.get("members", [])
	var expected_count: int = session_players.size() * GameSession.get_squad_size()
	if not (records_value is Array) or (records_value as Array).size() != expected_count:
		return false
	var records_by_entity_id: Dictionary[String, Dictionary] = {}
	for record_value: Variant in records_value as Array:
		if not (record_value is Dictionary):
			return false
		var record: Dictionary = record_value as Dictionary
		records_by_entity_id[str(record.get("entity_id", ""))] = record
	for player_info: Dictionary in session_players:
		var player_id: String = str(player_info.get("player_id", ""))
		for squad_slot: int in range(GameSession.get_squad_size()):
			var entity_id: String = make_member_entity_id(player_id, squad_slot)
			var record: Dictionary = records_by_entity_id.get(entity_id, {})
			if record.is_empty():
				return false
			var member: PlayerCharacter = _spawn_member(
				player_info,
				squad_slot,
				record.get("spawn_surface", INVALID_SPAWN_SURFACE),
				str(record.get("warrior_color", "Blue"))
			)
			if member == null:
				return false
	return true


static func make_member_entity_id(player_id: String, squad_slot: int) -> String:
	return NetworkProtocol.make_squad_member_entity_id(player_id, squad_slot)


func _spawn_member(
	player_info: Dictionary,
	squad_slot: int,
	spawn_surface: Vector3i,
	warrior_color: String
) -> PlayerCharacter:
	var member_info: Dictionary = player_info.duplicate(true)
	member_info["squad_slot"] = squad_slot
	var member: PlayerCharacter = CHARACTER_SCENE.instantiate() as PlayerCharacter
	if member == null:
		return null
	member.name = WorldPlayerSpawnPlanner.get_player_node_name(member_info)
	players_root.add_child(member)
	member.setup_multiplayer_player(member_info)
	var entity_id: String = make_member_entity_id(str(player_info.get("player_id", "")), squad_slot)
	member.start(runtime.surface_to_world(spawn_surface), bool(player_info.get("is_local", false)), entity_id)
	member.current_surface = spawn_surface
	member.spawn_surface = spawn_surface
	member.global_position = runtime.surface_to_world(spawn_surface)
	member.z_index = spawn_surface.z * 20 + 10
	if GameSession.is_multiplayer() and not GameSession.has_committed_match():
		member.can_receive_input = false
	member.configure_warrior_profile(warrior_color, "Последователь %d" % [squad_slot + 1])
	var registration_result: int = runtime.register_entity(member)
	if registration_result != WorldRegistry.RegistrationError.NONE:
		member.queue_free()
		return null
	if not squad_registry.register_member(member):
		runtime.unregister_entity(member)
		member.queue_free()
		return null
	return member


func _create_spawn_record(member: PlayerCharacter, spawn_surface: Vector3i) -> Dictionary:
	return {
		"player_id": member.owner_player_id,
		"steam_id": member.steam_id,
		"squad_slot": member.squad_slot,
		"entity_id": member.entity_id,
		"spawn_surface": spawn_surface,
		"warrior_color": member.warrior_color,
	}
