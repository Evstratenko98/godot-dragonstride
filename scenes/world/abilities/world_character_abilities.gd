class_name WorldCharacterAbilities
extends Node

signal ability_state_changed

const REJECTION_ABILITY_UNAVAILABLE := "ability_unavailable"
const REJECTION_INVALID_TARGET := "invalid_target"

var runtime: WorldRuntime = null
var level: WorldLevel = null
var usage_ledger: WorldCharacterAbilityLedger = WorldCharacterAbilityLedger.new()
var provocation_ledger: WorldProvocationLedger = WorldProvocationLedger.new()
var player_turn_controller: WorldProvokedPlayerTurnController = WorldProvokedPlayerTurnController.new()
var signal_bridge: WorldCharacterAbilitySignalBridge = WorldCharacterAbilitySignalBridge.new()


func _exit_tree() -> void:
	signal_bridge.disconnect_signals()


func configure_context(new_runtime: WorldRuntime, new_level: WorldLevel) -> void:
	signal_bridge.disconnect_signals()
	runtime = new_runtime
	level = new_level
	player_turn_controller.configure(self)
	signal_bridge.configure(self)
	signal_bridge.connect_signals()
	_refresh_provocation_indicators()


func request_character_ability(character: PlayerCharacter, target_surface: Vector3i) -> bool:
	if (
		character == null
		or runtime == null
		or runtime.turn_manager == null
		or not runtime.turn_manager.is_turn_mode_enabled()
		or not runtime.turn_manager.is_entity_active_in_turn(character)
		or not usage_ledger.can_use(character.entity_id)
	):
		return false
	var ability_id: String = character.get_special_ability_id()
	if not CharacterAbilityCatalog.is_ability_available_to_character(ability_id, character):
		return false
	var request_id: int = runtime.create_action_request_id()
	if GameSession.is_multiplayer():
		if not NetworkManager.connection.is_ready():
			return false
		signal_bridge.track_local_request(request_id)
		NetworkManager.abilities.request_character_ability(
			character.entity_id,
			ability_id,
			target_surface,
			GameSession.get_match_id(),
			runtime.get_turn_revision(),
			request_id
		)
	else:
		runtime.enqueue_player_action(
			WorldActionRecord.ActionType.CHARACTER_ABILITY,
			character,
			{"ability_id": ability_id, "target_surface": target_surface},
			request_id,
			0
		)
	return true


func get_remaining_cooldown_turns(character: PlayerCharacter) -> int:
	return 0 if character == null else usage_ledger.get_remaining_turns(character.entity_id)


func can_character_use_ability(character: PlayerCharacter) -> bool:
	return (
		character != null
		and runtime != null
		and runtime.turn_manager != null
		and runtime.turn_manager.is_turn_mode_enabled()
		and runtime.turn_manager.is_entity_active_in_turn(character)
		and CharacterAbilityCatalog.is_ability_available_to_character(character.get_special_ability_id(), character)
		and usage_ledger.can_use(character.entity_id)
	)


func reserve_action(action: WorldActionRecord) -> String:
	if action == null or action.action_type != WorldActionRecord.ActionType.CHARACTER_ABILITY:
		return ""
	return usage_ledger.reserve(action)


func release_action_reservation(action: WorldActionRecord) -> void:
	if action != null and action.action_type == WorldActionRecord.ActionType.CHARACTER_ABILITY:
		usage_ledger.release(action)
		ability_state_changed.emit()


func get_action_rejection_reason(action: WorldActionRecord) -> String:
	if action == null or runtime == null:
		return WorldActionStream.REJECTION_INVALID_ACTION
	var player: PlayerCharacter = runtime.get_entity_by_id(action.actor_entity_id) as PlayerCharacter
	var ability_id: String = str(action.payload.get("ability_id", ""))
	if (
		player == null
		or runtime.turn_manager == null
		or not runtime.turn_manager.is_turn_mode_enabled()
		or not runtime.turn_manager.is_entity_active_in_turn(player)
		or not CharacterAbilityCatalog.is_ability_available_to_character(ability_id, player)
		or not usage_ledger.can_validate_action(action)
	):
		return REJECTION_ABILITY_UNAVAILABLE
	var target_surface: Vector3i = action.payload.get("target_surface", WorldGridTopology.INVALID_SURFACE)
	var target: Entity = runtime.get_entity_at_surface(target_surface) as Entity
	var target_player: PlayerCharacter = target as PlayerCharacter
	if (
		target == null
		or target.health <= 0
		or target == player
		or (target_player != null and target_player.owner_player_id == player.owner_player_id)
		or not player.can_attack_surface(target_surface)
		or (runtime.visibility != null and not runtime.visibility.is_surface_visible_for_character(player, target_surface))
	):
		return REJECTION_INVALID_TARGET
	action.payload["target_entity_id"] = target.entity_id
	action.payload["target_surface"] = target.current_surface
	return ""


func execute_action(action: WorldActionRecord) -> bool:
	if action == null or runtime == null:
		return false
	var player: PlayerCharacter = runtime.get_entity_by_id(action.actor_entity_id) as PlayerCharacter
	var target: Entity = runtime.get_entity_by_id(str(action.payload.get("target_entity_id", ""))) as Entity
	var ability_id: String = str(action.payload.get("ability_id", ""))
	if player == null or target == null or target.health <= 0:
		return false
	usage_ledger.record_use(action, ability_id)
	provocation_ledger.provoke(target.entity_id, player.entity_id)
	_set_provoked_indicator_visible(target, true)
	if player.is_locally_owned:
		player.set_action_mode(PlayerCharacter.ActionMode.NONE)
	ability_state_changed.emit()
	return true


func get_provoker(target: Entity) -> PlayerCharacter:
	if target == null or runtime == null:
		return null
	var provoker_entity_id: String = provocation_ledger.get_provoker_entity_id(target.entity_id)
	return runtime.get_entity_by_id(provoker_entity_id) as PlayerCharacter


func has_active_provocation(target: Entity) -> bool:
	return target != null and provocation_ledger.has_provocation(target.entity_id)


func begin_player_turn(player_id: String) -> void:
	if runtime == null:
		return
	usage_ledger.begin_player_turn(runtime.get_squad_members(player_id))
	player_turn_controller.begin_player_turn(player_id)
	ability_state_changed.emit()


func clear_provocations() -> void:
	provocation_ledger.clear()
	player_turn_controller.reset()
	_refresh_provocation_indicators()
	ability_state_changed.emit()


func clear_non_player_provocations() -> void:
	if runtime == null:
		return
	for target_entity_id: String in provocation_ledger.get_target_entity_ids():
		if runtime.get_entity_by_id(target_entity_id) is NonPlayerEntity:
			provocation_ledger.remove_target(target_entity_id)
	_refresh_provocation_indicators()
	ability_state_changed.emit()


func sync_player_provocation_turn_state() -> void:
	player_turn_controller.sync_turn_state()


func handle_player_provocation_action_completed(action: WorldActionRecord) -> void:
	player_turn_controller.handle_action_completed(action)


func handle_player_provocation_action_cancelled(action: WorldActionRecord) -> void:
	player_turn_controller.handle_action_cancelled(action)


func is_player_control_blocked(character: PlayerCharacter) -> bool:
	return player_turn_controller.is_control_blocked(character)


func set_player_provocation_control_blocked(character: PlayerCharacter, should_block: bool) -> void:
	if character == null:
		return
	character.set_provocation_control_blocked(should_block)
	ability_state_changed.emit()


func consume_provocation_by_entity_id(target_entity_id: String) -> void:
	if target_entity_id.is_empty():
		return
	provocation_ledger.remove_target(target_entity_id)
	var target: Entity = null
	if runtime != null:
		target = runtime.get_entity_by_id(target_entity_id) as Entity
	_set_provoked_indicator_visible(target, false)
	ability_state_changed.emit()


func handle_entity_removed(entity: Node) -> void:
	if entity == null or entity.get("entity_id") == null:
		return
	provocation_ledger.remove_entity(str(entity.get("entity_id")))
	_refresh_provocation_indicators()
	player_turn_controller.sync_turn_state()
	ability_state_changed.emit()


func reset_state() -> void:
	player_turn_controller.reset()
	usage_ledger.clear()
	provocation_ledger.clear()
	signal_bridge.clear()
	_refresh_provocation_indicators()
	ability_state_changed.emit()


func create_snapshot() -> Dictionary:
	var snapshot: Dictionary = usage_ledger.create_snapshot()
	snapshot.merge(provocation_ledger.create_snapshot(), true)
	return snapshot


func is_valid_snapshot(snapshot: Dictionary, valid_target_entity_ids: Array[String]) -> bool:
	if runtime == null:
		return false
	var valid_entity_ids: Array[String] = []
	for player: PlayerCharacter in runtime.players_service.get_all_characters():
		valid_entity_ids.append(player.entity_id)
	return (
		usage_ledger.is_valid_snapshot(snapshot, valid_entity_ids)
		and provocation_ledger.is_valid_snapshot(
			snapshot,
			valid_target_entity_ids,
			valid_entity_ids
		)
	)


func apply_snapshot(snapshot: Dictionary) -> bool:
	if not is_valid_snapshot(snapshot, _get_registered_entity_ids()):
		return false
	player_turn_controller.reset()
	usage_ledger.apply_snapshot(snapshot)
	provocation_ledger.apply_snapshot(snapshot)
	_refresh_provocation_indicators()
	player_turn_controller.sync_turn_state()
	ability_state_changed.emit()
	return true


func broadcast_action_payload(action: WorldActionRecord) -> void:
	if action != null:
		NetworkManager.abilities.broadcast_action_payload(action.match_id, action.sequence_id, action.payload)


func get_requesting_player(requester_peer_id: int, actor_entity_id: String) -> PlayerCharacter:
	var player: PlayerCharacter = runtime.get_entity_by_id(actor_entity_id) as PlayerCharacter
	if player == null:
		return null
	if requester_peer_id == 0:
		return player if GameSession.is_host() and player.is_locally_owned else null
	var requester_steam_id: int = NetworkManager.peers.get_steam_id_for_peer_id(requester_peer_id)
	return player if requester_steam_id > 0 and player.steam_id == requester_steam_id else null


func notify_rejected(reason_code: String) -> void:
	if runtime != null:
		runtime.notify_local_action_rejected(reason_code)
	ability_state_changed.emit()


func _refresh_provocation_indicators() -> void:
	if runtime == null:
		return
	for entity_value: Variant in runtime.get_registered_entities():
		var entity: Entity = entity_value as Entity
		if entity != null:
			_set_provoked_indicator_visible(
				entity,
				not provocation_ledger.get_provoker_entity_id(entity.entity_id).is_empty()
			)


func _get_registered_entity_ids() -> Array[String]:
	var result: Array[String] = []
	if runtime == null:
		return result
	for entity_value: Variant in runtime.get_registered_entities():
		var entity: Entity = entity_value as Entity
		if entity != null:
			result.append(entity.entity_id)
	return result


func _set_provoked_indicator_visible(target: Entity, is_visible: bool) -> void:
	var non_player: NonPlayerEntity = target as NonPlayerEntity
	if non_player != null:
		non_player.set_provoked_indicator_visible(is_visible)
		return
	var player: PlayerCharacter = target as PlayerCharacter
	if player != null:
		player.set_provoked_indicator_visible(is_visible)
