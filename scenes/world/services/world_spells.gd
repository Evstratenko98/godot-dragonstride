class_name WorldSpells
extends Node

signal targeting_changed(is_targeting: bool, selected_slot_index: int)
signal spell_usage_changed()

const SPELL_ID_METEOR := "meteor"
const METEOR_DAMAGE := 50
const METEOR_START_OFFSET := Vector2(256.0, -256.0)
const METEOR_EFFECT_SCENE := preload("res://scenes/spells/meteor/meteor_effect.tscn")

const REJECTION_INVALID_PLAYER := "invalid_player"
const REJECTION_INVALID_SLOT := "invalid_slot"
const REJECTION_INVALID_TARGET := "invalid_target"
const REJECTION_INVALID_TURN := "invalid_turn"
const REJECTION_SPELL_UNAVAILABLE := "spell_unavailable"
const REJECTION_CASTER_BUSY := "caster_busy"

@export var effects_root_path: NodePath = ^"../WorldRuntime/SpellEffects"

@onready var effects_root: Node2D = get_node(effects_root_path) as Node2D

var runtime: WorldRuntime = null
var level: WorldLevel = null
var selected_player_entity_id: String = ""
var selected_spell_slot_index: int = -1
var cast_counter: int = 0
var used_spell_slots: Dictionary[String, Dictionary] = {}
var active_casts_by_entity_id: Dictionary[String, String] = {}
var active_cast_target_cells_by_entity_id: Dictionary[String, Vector2i] = {}


func _ready() -> void:
	_connect_network_signals()


func _exit_tree() -> void:
	_disconnect_turn_signals()
	_disconnect_network_signals()


func configure_context(new_runtime: WorldRuntime, new_level: WorldLevel) -> void:
	_disconnect_turn_signals()
	runtime = new_runtime
	level = new_level
	_connect_turn_signals()


func toggle_spell_targeting(player: PlayerCharacter, spell_slot_index: int) -> bool:
	if player == null or player != runtime.get_local_player():
		return false

	var player_entity_id: String = runtime.get_entity_id(player)
	if player_entity_id == selected_player_entity_id and spell_slot_index == selected_spell_slot_index:
		cancel_spell_targeting(player)
		return true

	var spell_id: String = player.character_inventory.get_spell_id_at_slot(spell_slot_index)
	if spell_id.is_empty() or is_entity_casting(player):
		return false
	if not runtime.can_entity_cast_spell_in_turn(player):
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


func request_selected_spell_cast(player: PlayerCharacter, target_cell: Vector2i) -> bool:
	if not has_selected_spell(player):
		return false

	var spell_slot_index: int = selected_spell_slot_index
	cancel_spell_targeting(player)
	if not runtime.is_cell_inside(target_cell):
		_print_rejection(REJECTION_INVALID_TARGET)
		return true

	if GameSession.is_singleplayer():
		_try_start_authoritative_cast(player, spell_slot_index, target_cell, 0)
		return true

	if not NetworkManager.connection.is_ready():
		_print_rejection(REJECTION_SPELL_UNAVAILABLE)
		return true

	if not GameSession.is_host():
		var entity_id: String = runtime.get_entity_id(player)
		active_casts_by_entity_id[entity_id] = "pending"
		active_cast_target_cells_by_entity_id[entity_id] = target_cell
		spell_usage_changed.emit()
	NetworkManager.spells.request_spell_cast(spell_slot_index, target_cell)
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

	var player_cell: Vector2i = runtime.world_to_cell(player.global_position)
	for target_cell: Vector2i in active_cast_target_cells_by_entity_id.values():
		if target_cell == player_cell:
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

	return 0 if _is_spell_slot_used(runtime.get_entity_id(player), spell_slot_index) else 1


func _try_start_authoritative_cast(
	player: PlayerCharacter,
	spell_slot_index: int,
	target_cell: Vector2i,
	requester_peer_id: int
) -> bool:
	var rejection_reason: String = _get_cast_rejection_reason(player, spell_slot_index, target_cell)
	if not rejection_reason.is_empty():
		_reject_cast(requester_peer_id, rejection_reason)
		return false

	var spell_id: String = player.character_inventory.get_spell_id_at_slot(spell_slot_index)
	var cast_id: String = _make_cast_id()
	var effect: SpellCastEffect = _create_effect(
		cast_id,
		player.entity_id,
		spell_id,
		target_cell
	)
	if effect == null:
		_reject_cast(requester_peer_id, REJECTION_SPELL_UNAVAILABLE)
		return false

	active_casts_by_entity_id[player.entity_id] = cast_id
	active_cast_target_cells_by_entity_id[player.entity_id] = target_cell
	_record_spell_slot_use(player.entity_id, spell_slot_index)
	spell_usage_changed.emit()
	if GameSession.is_multiplayer():
		NetworkManager.spells.broadcast_spell_cast(
			cast_id,
			player.entity_id,
			spell_id,
			spell_slot_index,
			target_cell
		)
	_start_effect(effect, target_cell)

	return true


func _get_cast_rejection_reason(
	player: PlayerCharacter,
	spell_slot_index: int,
	target_cell: Vector2i
) -> String:
	if player == null or player.health <= 0:
		return REJECTION_INVALID_PLAYER
	if not runtime.is_cell_inside(target_cell):
		return REJECTION_INVALID_TARGET
	if is_entity_casting(player):
		return REJECTION_CASTER_BUSY
	if not runtime.can_entity_cast_spell_in_turn(player):
		return REJECTION_INVALID_TURN

	var spell_id: String = player.character_inventory.get_spell_id_at_slot(spell_slot_index)
	if spell_id != SPELL_ID_METEOR:
		return REJECTION_INVALID_SLOT
	if get_remaining_spell_slot_uses(player, spell_slot_index) <= 0:
		return REJECTION_SPELL_UNAVAILABLE

	return ""


func _spawn_effect(
	cast_id: String,
	caster_entity_id: String,
	spell_id: String,
	target_cell: Vector2i
) -> bool:
	var effect: SpellCastEffect = _create_effect(
		cast_id,
		caster_entity_id,
		spell_id,
		target_cell
	)
	if effect == null:
		return false

	_start_effect(effect, target_cell)
	return true


func _create_effect(
	cast_id: String,
	caster_entity_id: String,
	spell_id: String,
	target_cell: Vector2i
) -> SpellCastEffect:
	if effects_root == null or spell_id != SPELL_ID_METEOR:
		return null

	var effect: SpellCastEffect = METEOR_EFFECT_SCENE.instantiate() as SpellCastEffect
	if effect == null:
		return null

	effect.name = cast_id
	effect.impact.connect(_on_effect_impact.bind(cast_id, caster_entity_id, spell_id, target_cell))
	effect.finished.connect(_on_effect_finished.bind(cast_id, caster_entity_id))
	return effect


func _start_effect(effect: SpellCastEffect, target_cell: Vector2i) -> void:
	effects_root.add_child.call_deferred(effect)
	call_deferred("_begin_effect", effect, target_cell)


func _begin_effect(effect: SpellCastEffect, target_cell: Vector2i) -> void:
	if effect == null or not is_instance_valid(effect):
		return
	if not effect.is_inside_tree():
		call_deferred("_begin_effect", effect, target_cell)
		return

	var target_position: Vector2 = runtime.cell_to_world(target_cell)
	effect.play_effect(target_position + METEOR_START_OFFSET, target_position)


func _on_effect_impact(
	cast_id: String,
	caster_entity_id: String,
	spell_id: String,
	target_cell: Vector2i
) -> void:
	if not _is_authority() or spell_id != SPELL_ID_METEOR:
		return
	if active_casts_by_entity_id.get(caster_entity_id, "") != cast_id:
		return

	var caster: Node = runtime.get_entity_by_id(caster_entity_id)
	runtime.apply_spell_damage_to_cell(caster, target_cell, METEOR_DAMAGE)


func _on_effect_finished(cast_id: String, caster_entity_id: String) -> void:
	if active_casts_by_entity_id.get(caster_entity_id, "") != cast_id:
		return

	active_casts_by_entity_id.erase(caster_entity_id)
	active_cast_target_cells_by_entity_id.erase(caster_entity_id)
	var caster: Node = runtime.get_entity_by_id(caster_entity_id)
	if caster != null:
		runtime.notify_entity_action_finished_in_turn(caster)
	spell_usage_changed.emit()


func _record_spell_slot_use(entity_id: String, spell_slot_index: int) -> void:
	if not runtime.is_turn_mode_enabled():
		return

	var entity_slots: Dictionary = used_spell_slots.get(entity_id, {}) as Dictionary
	entity_slots[spell_slot_index] = true
	used_spell_slots[entity_id] = entity_slots


func _is_spell_slot_used(entity_id: String, spell_slot_index: int) -> bool:
	var entity_slots: Dictionary = used_spell_slots.get(entity_id, {}) as Dictionary
	return bool(entity_slots.get(spell_slot_index, false))


func _make_cast_id() -> String:
	cast_counter += 1
	return "spell_cast_%d" % cast_counter


func _get_requesting_player(requester_peer_id: int) -> PlayerCharacter:
	if requester_peer_id == 0:
		return runtime.get_local_player()

	var requester_steam_id: int = NetworkManager.peers.get_steam_id_for_peer_id(requester_peer_id)
	if requester_steam_id == 0:
		return null

	return runtime.get_player_by_steam_id(requester_steam_id)


func _reject_cast(requester_peer_id: int, reason_code: String) -> void:
	if requester_peer_id == 0:
		_print_rejection(reason_code)
		return

	NetworkManager.spells.send_spell_cast_rejection(requester_peer_id, reason_code)


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
		REJECTION_CASTER_BUSY:
			message = "Spell cast rejected: another spell is active."

	ConsoleOutput.print_console(message, runtime)


func _on_spell_cast_requested(
	spell_slot_index: int,
	target_cell: Vector2i,
	requester_peer_id: int
) -> void:
	if not GameSession.is_host():
		return

	var player: PlayerCharacter = _get_requesting_player(requester_peer_id)
	_try_start_authoritative_cast(player, spell_slot_index, target_cell, requester_peer_id)


func _on_spell_cast_received(
	cast_id: String,
	caster_entity_id: String,
	spell_id: String,
	spell_slot_index: int,
	target_cell: Vector2i
) -> void:
	if GameSession.is_host() or cast_id.is_empty() or spell_id != SPELL_ID_METEOR:
		return

	var caster: PlayerCharacter = runtime.get_entity_by_id(caster_entity_id) as PlayerCharacter
	if caster == null:
		active_casts_by_entity_id.erase(caster_entity_id)
		active_cast_target_cells_by_entity_id.erase(caster_entity_id)
		spell_usage_changed.emit()
		return

	active_casts_by_entity_id[caster_entity_id] = cast_id
	active_cast_target_cells_by_entity_id[caster_entity_id] = target_cell
	_record_spell_slot_use(caster_entity_id, spell_slot_index)
	if not _spawn_effect(cast_id, caster_entity_id, spell_id, target_cell):
		active_casts_by_entity_id.erase(caster_entity_id)
		active_cast_target_cells_by_entity_id.erase(caster_entity_id)
	spell_usage_changed.emit()


func _on_spell_cast_rejected(reason_code: String) -> void:
	var local_player: PlayerCharacter = runtime.get_local_player()
	if local_player != null:
		active_casts_by_entity_id.erase(local_player.entity_id)
		active_cast_target_cells_by_entity_id.erase(local_player.entity_id)
	spell_usage_changed.emit()
	_print_rejection(reason_code)


func _on_player_turn_started(_entity_id: String) -> void:
	_clear_targeting()
	used_spell_slots.clear()
	spell_usage_changed.emit()


func _on_turn_mode_changed(_is_enabled: bool) -> void:
	used_spell_slots.clear()
	spell_usage_changed.emit()


func _clear_targeting() -> void:
	if selected_spell_slot_index < 0:
		return

	selected_player_entity_id = ""
	selected_spell_slot_index = -1
	targeting_changed.emit(false, -1)


func _connect_turn_signals() -> void:
	if runtime == null or runtime.turn_manager == null:
		return
	if not runtime.turn_manager.player_turn_started.is_connected(_on_player_turn_started):
		runtime.turn_manager.player_turn_started.connect(_on_player_turn_started)
	if not runtime.turn_manager.turn_mode_changed.is_connected(_on_turn_mode_changed):
		runtime.turn_manager.turn_mode_changed.connect(_on_turn_mode_changed)


func _disconnect_turn_signals() -> void:
	if runtime == null or runtime.turn_manager == null:
		return
	if runtime.turn_manager.player_turn_started.is_connected(_on_player_turn_started):
		runtime.turn_manager.player_turn_started.disconnect(_on_player_turn_started)
	if runtime.turn_manager.turn_mode_changed.is_connected(_on_turn_mode_changed):
		runtime.turn_manager.turn_mode_changed.disconnect(_on_turn_mode_changed)


func _connect_network_signals() -> void:
	if not NetworkManager.spells.spell_cast_requested.is_connected(_on_spell_cast_requested):
		NetworkManager.spells.spell_cast_requested.connect(_on_spell_cast_requested)
	if not NetworkManager.spells.spell_cast_received.is_connected(_on_spell_cast_received):
		NetworkManager.spells.spell_cast_received.connect(_on_spell_cast_received)
	if not NetworkManager.spells.spell_cast_rejected.is_connected(_on_spell_cast_rejected):
		NetworkManager.spells.spell_cast_rejected.connect(_on_spell_cast_rejected)


func _disconnect_network_signals() -> void:
	if NetworkManager.spells.spell_cast_requested.is_connected(_on_spell_cast_requested):
		NetworkManager.spells.spell_cast_requested.disconnect(_on_spell_cast_requested)
	if NetworkManager.spells.spell_cast_received.is_connected(_on_spell_cast_received):
		NetworkManager.spells.spell_cast_received.disconnect(_on_spell_cast_received)
	if NetworkManager.spells.spell_cast_rejected.is_connected(_on_spell_cast_rejected):
		NetworkManager.spells.spell_cast_rejected.disconnect(_on_spell_cast_rejected)


func _is_authority() -> bool:
	return not GameSession.is_multiplayer() or GameSession.is_host()
