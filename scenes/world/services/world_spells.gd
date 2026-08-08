class_name WorldSpells
extends Node

signal targeting_changed(is_targeting: bool, selected_slot_index: int)
signal spell_usage_changed()
signal cast_finished(cast_id: String)

const SPELL_ID_METEOR := "meteor"
const METEOR_DAMAGE := 50
const METEOR_START_OFFSET := Vector2(256.0, -256.0)
const METEOR_EFFECT_SCENE := preload("res://scenes/spells/meteor/meteor_effect.tscn")

const REJECTION_INVALID_PLAYER := "invalid_player"
const REJECTION_INVALID_SLOT := "invalid_slot"
const REJECTION_INVALID_TARGET := "invalid_target"
const REJECTION_INVALID_TURN := "invalid_turn"
const REJECTION_SPELL_UNAVAILABLE := "spell_unavailable"

@export var effects_root_path: NodePath = ^"../WorldRuntime/SpellEffects"

@onready var effects_root: Node2D = get_node(effects_root_path) as Node2D

var runtime: WorldRuntime = null
var level: WorldLevel = null
var selected_player_entity_id: String = ""
var selected_spell_slot_index: int = -1
var usage_ledger: WorldSpellUsageLedger = WorldSpellUsageLedger.new()
var active_casts_by_entity_id: Dictionary[String, String] = {}
var active_cast_target_surfaces_by_entity_id: Dictionary[String, Vector3i] = {}
var impacted_cast_ids: Dictionary[String, bool] = {}
var signal_bridge: WorldSpellSignalBridge = WorldSpellSignalBridge.new()


func _ready() -> void:
	signal_bridge.configure(self)
	signal_bridge.connect_network_signals()
	if not GameSession.session_cleared.is_connected(_on_session_cleared):
		GameSession.session_cleared.connect(_on_session_cleared)


func _exit_tree() -> void:
	signal_bridge.disconnect_signals()
	if GameSession.session_cleared.is_connected(_on_session_cleared):
		GameSession.session_cleared.disconnect(_on_session_cleared)


func configure_context(new_runtime: WorldRuntime, new_level: WorldLevel) -> void:
	signal_bridge.disconnect_signals()
	runtime = new_runtime
	level = new_level
	signal_bridge.connect_network_signals()
	signal_bridge.connect_runtime_signals()


func _on_session_cleared() -> void:
	selected_player_entity_id = ""
	selected_spell_slot_index = -1
	usage_ledger.clear()
	active_casts_by_entity_id.clear()
	active_cast_target_surfaces_by_entity_id.clear()
	impacted_cast_ids.clear()
	signal_bridge.clear()


func toggle_spell_targeting(player: PlayerCharacter, spell_slot_index: int) -> bool:
	if player == null or player != runtime.get_selected_local_character():
		return false

	var player_entity_id: String = runtime.get_entity_id(player)
	if player_entity_id == selected_player_entity_id and spell_slot_index == selected_spell_slot_index:
		cancel_spell_targeting(player)
		return true

	var spell_id: String = player.character_inventory.get_spell_id_at_slot(spell_slot_index)
	if spell_id.is_empty():
		return false
	if not runtime.can_entity_cast_spell_in_turn(player):
		runtime.notify_local_action_rejected(WorldActionStream.REJECTION_NOT_ACTIVE_PLAYER)
		return false
	if get_remaining_spell_slot_uses(player, spell_slot_index) <= 0:
		return false

	selected_player_entity_id = player_entity_id
	selected_spell_slot_index = spell_slot_index
	targeting_changed.emit(true, selected_spell_slot_index)
	return true


func cancel_spell_targeting(player: PlayerCharacter) -> bool:
	if player == null or runtime.get_entity_id(player) != selected_player_entity_id:
		return false

	_clear_targeting()
	return true


func has_selected_spell(player: PlayerCharacter) -> bool:
	return (
		player != null
		and selected_spell_slot_index >= 0
		and runtime.get_entity_id(player) == selected_player_entity_id
	)


func get_selected_spell_slot_index(player: PlayerCharacter) -> int:
	if not has_selected_spell(player):
		return -1

	return selected_spell_slot_index


func request_selected_spell_cast(player: PlayerCharacter, target_surface: Vector3i) -> bool:
	if not has_selected_spell(player):
		return false

	var spell_slot_index: int = selected_spell_slot_index
	cancel_spell_targeting(player)
	if not runtime.is_surface_inside(target_surface):
		_print_rejection(REJECTION_INVALID_TARGET)
		return true

	if GameSession.is_multiplayer() and not NetworkManager.connection.is_ready():
		_print_rejection(REJECTION_SPELL_UNAVAILABLE)
		return true

	var request_id: int = runtime.create_action_request_id()
	if GameSession.is_multiplayer():
		signal_bridge.track_local_request(request_id)
		NetworkManager.spells.request_spell_cast(player.entity_id, spell_slot_index, target_surface, GameSession.get_match_id(), runtime.get_turn_revision(), request_id)
	else:
		runtime.enqueue_player_action(
			WorldActionRecord.ActionType.SPELL_CAST,
			player,
			{
				"spell_slot_index": spell_slot_index,
				"target_surface": target_surface,
				"target_kind": "surface",
			},
			request_id,
			0
		)
	return true


func is_entity_casting(entity: Node) -> bool:
	if entity == null:
		return false

	var entity_id: String = runtime.get_entity_id(entity)
	return not entity_id.is_empty() and active_casts_by_entity_id.has(entity_id)


func is_entity_movement_blocked(entity: Node) -> bool:
	var player: PlayerCharacter = entity as PlayerCharacter
	if player == null or runtime == null:
		return false

	var player_cell: Vector3i = player.current_surface
	for target_surface: Vector3i in active_cast_target_surfaces_by_entity_id.values():
		if target_surface == player_cell:
			return true

	return false


func get_remaining_spell_slot_uses(player: PlayerCharacter, spell_slot_index: int) -> int:
	if player == null:
		return 0

	var spell_id: String = player.character_inventory.get_spell_id_at_slot(spell_slot_index)
	if spell_id.is_empty():
		return 0
	if not runtime.is_turn_mode_enabled():
		return 1

	var entity_id: String = runtime.get_entity_id(player)
	return usage_ledger.get_remaining_uses(entity_id, spell_slot_index, runtime.is_turn_mode_enabled())


func reserve_action(action: WorldActionRecord) -> String:
	if action == null or not runtime.is_turn_mode_enabled():
		return ""
	var rejection_reason: String = usage_ledger.reserve(action)
	if not rejection_reason.is_empty():
		return rejection_reason
	spell_usage_changed.emit()
	return ""


func release_action_reservation(action: WorldActionRecord) -> void:
	if action == null:
		return
	if usage_ledger.release(action):
		spell_usage_changed.emit()


func create_action_stream_snapshot() -> Dictionary:
	return usage_ledger.create_snapshot()


func broadcast_action_payload(action: WorldActionRecord) -> void:
	if action != null:
		NetworkManager.spells.broadcast_action_payload(action.match_id, action.sequence_id, action.payload)


func apply_action_stream_snapshot(snapshot: Dictionary) -> void:
	if not is_valid_action_stream_snapshot(snapshot):
		return
	usage_ledger.apply_snapshot(snapshot)
	spell_usage_changed.emit()


func is_valid_action_stream_snapshot(snapshot: Dictionary) -> bool:
	return usage_ledger.is_valid_snapshot(snapshot)


func get_action_rejection_reason(action: WorldActionRecord) -> String:
	if action == null:
		return REJECTION_INVALID_PLAYER
	var player: PlayerCharacter = runtime.get_entity_by_id(action.actor_entity_id) as PlayerCharacter
	var spell_slot_index: int = int(action.payload.get("spell_slot_index", -1))
	var target_kind: String = str(action.payload.get("target_kind", "surface"))
	var target_surface: Vector3i = action.payload.get("target_surface", Vector3i(-1, -1, -1))
	if target_kind == "entity":
		var target_entity_id: String = str(action.payload.get("target_entity_id", ""))
		var target_entity: Entity = runtime.get_entity_by_id(target_entity_id) as Entity
		if target_entity == null or target_entity.health <= 0:
			return REJECTION_INVALID_TARGET
		target_surface = target_entity.current_surface
		action.payload["target_surface"] = target_surface
	elif target_kind != "surface":
		return REJECTION_INVALID_TARGET
	var rejection_reason: String = _get_cast_rejection_reason(
		player,
		spell_slot_index,
		target_surface,
		str(action.payload.get("reservation_key", ""))
	)
	if not rejection_reason.is_empty():
		return rejection_reason
	action.payload["spell_id"] = player.character_inventory.get_spell_id_at_slot(spell_slot_index)
	action.payload["cast_id"] = "spell_cast_%d" % action.sequence_id
	return ""


func execute_action_cast(action: WorldActionRecord, is_authority: bool) -> bool:
	if action == null or not is_inside_tree():
		return false
	var scene_tree: SceneTree = get_tree()
	var player: PlayerCharacter = runtime.get_entity_by_id(action.actor_entity_id) as PlayerCharacter
	if player == null:
		return false
	var spell_slot_index: int = int(action.payload.get("spell_slot_index", -1))
	var target_surface: Vector3i = action.payload.get("target_surface", Vector3i(-1, -1, -1))
	var spell_id: String = str(action.payload.get("spell_id", ""))
	var cast_id: String = str(action.payload.get("cast_id", "spell_cast_%d" % action.sequence_id))
	var effect: SpellCastEffect = _create_effect(cast_id, player.entity_id, spell_id, target_surface)
	if effect == null:
		return false
	if is_authority:
		runtime.notify_entity_attacked_in_turn(player, target_surface)
	active_casts_by_entity_id[player.entity_id] = cast_id
	active_cast_target_surfaces_by_entity_id[player.entity_id] = target_surface
	release_action_reservation(action)
	_record_spell_slot_use(player.entity_id, spell_slot_index)
	spell_usage_changed.emit()
	_start_effect(effect, target_surface)
	var presentation_deadline_msec: int = Time.get_ticks_msec() + int((effect.get_expected_duration() + 2.0) * 1000.0)
	while (
		active_casts_by_entity_id.get(player.entity_id, "") == cast_id
		and Time.get_ticks_msec() < presentation_deadline_msec
	):
		await scene_tree.process_frame
		if not is_inside_tree():
			return false
	if active_casts_by_entity_id.get(player.entity_id, "") == cast_id:
		var was_applied: bool = bool(impacted_cast_ids.get(cast_id, false))
		_force_finish_cast(cast_id, player.entity_id)
		if is_authority and not was_applied:
			_remove_spell_slot_use(player.entity_id, spell_slot_index)
			action.payload["cancellation_reason"] = WorldActionStream.REJECTION_PRESENTATION_TIMEOUT
			return false
	return true


func _get_cast_rejection_reason(
	player: PlayerCharacter,
	spell_slot_index: int,
	target_surface: Vector3i,
	ignored_reservation_key: String = ""
) -> String:
	if player == null or player.health <= 0:
		return REJECTION_INVALID_PLAYER
	if not runtime.is_surface_inside(target_surface):
		return REJECTION_INVALID_TARGET
	if not runtime.can_entity_cast_spell_in_turn(player):
		return REJECTION_INVALID_TURN

	var spell_id: String = player.character_inventory.get_spell_id_at_slot(spell_slot_index)
	if spell_id != SPELL_ID_METEOR:
		return REJECTION_INVALID_SLOT
	if runtime.is_turn_mode_enabled():
		var entity_id: String = runtime.get_entity_id(player)
		if _is_spell_slot_used(entity_id, spell_slot_index):
			return REJECTION_SPELL_UNAVAILABLE
		var reservation_key: String = usage_ledger.make_key(entity_id, spell_slot_index)
		if usage_ledger.is_reservation_key_reserved(reservation_key) and reservation_key != ignored_reservation_key:
			return REJECTION_SPELL_UNAVAILABLE

	return ""


func _create_effect(
	cast_id: String,
	caster_entity_id: String,
	spell_id: String,
	target_surface: Vector3i
) -> SpellCastEffect:
	if effects_root == null or spell_id != SPELL_ID_METEOR:
		return null

	var effect: SpellCastEffect = METEOR_EFFECT_SCENE.instantiate() as SpellCastEffect
	if effect == null:
		return null

	effect.name = cast_id
	effect.impact.connect(_on_effect_impact.bind(cast_id, caster_entity_id, spell_id, target_surface))
	effect.finished.connect(_on_effect_finished.bind(cast_id, caster_entity_id))
	return effect


func _start_effect(effect: SpellCastEffect, target_surface: Vector3i) -> void:
	effects_root.add_child.call_deferred(effect)
	call_deferred("_begin_effect", effect, target_surface)


func _begin_effect(effect: SpellCastEffect, target_surface: Vector3i) -> void:
	if effect == null or not is_instance_valid(effect):
		return
	if not effect.is_inside_tree():
		call_deferred("_begin_effect", effect, target_surface)
		return

	var target_position: Vector2 = runtime.surface_to_world(target_surface)
	effect.play_effect(target_position + METEOR_START_OFFSET, target_position)


func _on_effect_impact(
	cast_id: String,
	caster_entity_id: String,
	spell_id: String,
	target_surface: Vector3i
) -> void:
	if not _is_authority() or spell_id != SPELL_ID_METEOR:
		return
	if active_casts_by_entity_id.get(caster_entity_id, "") != cast_id:
		return
	if bool(impacted_cast_ids.get(cast_id, false)):
		return

	impacted_cast_ids[cast_id] = true
	var caster: Node = runtime.get_entity_by_id(caster_entity_id)
	runtime.apply_spell_damage_to_surface(caster, target_surface, METEOR_DAMAGE)


func _on_effect_finished(cast_id: String, caster_entity_id: String) -> void:
	if active_casts_by_entity_id.get(caster_entity_id, "") != cast_id:
		return

	active_casts_by_entity_id.erase(caster_entity_id)
	active_cast_target_surfaces_by_entity_id.erase(caster_entity_id)
	impacted_cast_ids.erase(cast_id)
	var caster: Node = runtime.get_entity_by_id(caster_entity_id)
	if caster != null:
		runtime.notify_entity_action_finished_in_turn(caster)
	spell_usage_changed.emit()
	cast_finished.emit(cast_id)


func _force_finish_cast(cast_id: String, caster_entity_id: String) -> void:
	var effect: Node = effects_root.get_node_or_null(NodePath(cast_id))
	if effect != null:
		effect.queue_free()
	active_casts_by_entity_id.erase(caster_entity_id)
	active_cast_target_surfaces_by_entity_id.erase(caster_entity_id)
	impacted_cast_ids.erase(cast_id)
	spell_usage_changed.emit()
	cast_finished.emit(cast_id)


func _record_spell_slot_use(entity_id: String, spell_slot_index: int) -> void:
	if not runtime.is_turn_mode_enabled():
		return

	usage_ledger.record_use(entity_id, spell_slot_index)


func _remove_spell_slot_use(entity_id: String, spell_slot_index: int) -> void:
	usage_ledger.remove_use(entity_id, spell_slot_index)
	spell_usage_changed.emit()


func _is_spell_slot_used(entity_id: String, spell_slot_index: int) -> bool:
	return usage_ledger.is_used(entity_id, spell_slot_index)


func _is_spell_slot_reserved(entity_id: String, spell_slot_index: int) -> bool:
	return usage_ledger.is_reserved(entity_id, spell_slot_index)


func _get_requesting_player(requester_peer_id: int, actor_entity_id: String) -> PlayerCharacter:
	if requester_peer_id == 0:
		return runtime.get_player_by_entity_id(actor_entity_id)

	var requester_steam_id: int = NetworkManager.peers.get_steam_id_for_peer_id(requester_peer_id)
	if requester_steam_id == 0:
		return null

	if not runtime.is_character_owned_by_steam_id(actor_entity_id, requester_steam_id):
		return null
	return runtime.get_player_by_entity_id(actor_entity_id)


func _print_rejection(reason_code: String) -> void:
	var message: String = "Spell cast rejected."
	match reason_code:
		REJECTION_INVALID_PLAYER:
			message = "Spell cast rejected: character is unavailable."
		REJECTION_INVALID_SLOT:
			message = "Spell cast rejected: spell slot is invalid."
		REJECTION_INVALID_TARGET:
			message = "Spell cast rejected: target is outside the world."
		REJECTION_INVALID_TURN:
			message = "Spell cast rejected: it is not this character's turn."
		REJECTION_SPELL_UNAVAILABLE:
			message = "Spell cast rejected: no use is available."

	ConsoleOutput.print_console(message, runtime)


func _clear_targeting() -> void:
	if selected_spell_slot_index < 0:
		return

	selected_player_entity_id = ""
	selected_spell_slot_index = -1
	targeting_changed.emit(false, -1)


func _is_authority() -> bool:
	return not GameSession.is_multiplayer() or GameSession.is_host()
