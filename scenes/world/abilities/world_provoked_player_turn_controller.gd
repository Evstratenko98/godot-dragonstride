class_name WorldProvokedPlayerTurnController
extends RefCounted

var abilities: WorldCharacterAbilities = null
var blocked_entity_ids: Dictionary[String, bool] = {}
var pending_attack_target_by_actor: Dictionary[String, String] = {}


func configure(owner: WorldCharacterAbilities) -> void:
	abilities = owner


func begin_player_turn(player_id: String) -> void:
	if abilities == null or abilities.runtime == null:
		return
	_sync_blocks(player_id, true)


func sync_turn_state() -> void:
	if abilities == null or abilities.runtime == null or abilities.runtime.turn_manager == null:
		reset()
		return
	var turns: WorldTurns = abilities.runtime.turn_manager
	var active_player_id: String = (
		turns.get_active_player_id()
		if turns.get_state() == WorldTurns.STATE_PLAYER_TURN
		else ""
	)
	_sync_blocks(active_player_id, false)


func is_control_blocked(character: PlayerCharacter) -> bool:
	return character != null and blocked_entity_ids.has(character.entity_id)


func reset() -> void:
	if abilities != null and abilities.runtime != null:
		for entity_id: String in blocked_entity_ids.keys():
			var character: PlayerCharacter = abilities.runtime.get_entity_by_id(entity_id) as PlayerCharacter
			if character != null:
				abilities.set_player_provocation_control_blocked(character, false)
	blocked_entity_ids.clear()
	pending_attack_target_by_actor.clear()


func handle_action_completed(action: WorldActionRecord) -> void:
	if (
		action == null
		or action.action_type != WorldActionRecord.ActionType.MOVE_PATH
		or not pending_attack_target_by_actor.has(action.actor_entity_id)
	):
		return
	var target_entity_id: String = pending_attack_target_by_actor[action.actor_entity_id]
	pending_attack_target_by_actor.erase(action.actor_entity_id)
	if not blocked_entity_ids.has(action.actor_entity_id):
		return
	var character: PlayerCharacter = abilities.runtime.get_entity_by_id(
		action.actor_entity_id
	) as PlayerCharacter
	var provoker: PlayerCharacter = abilities.runtime.get_entity_by_id(
		target_entity_id
	) as PlayerCharacter
	var active_provoker_entity_id: String = ""
	if character != null:
		active_provoker_entity_id = abilities.provocation_ledger.get_provoker_entity_id(
			character.entity_id
		)
	if (
		character != null
		and provoker != null
		and active_provoker_entity_id == provoker.entity_id
		and character.can_attack_surface(provoker.current_surface)
	):
		_enqueue_attack(character, provoker)


func handle_action_cancelled(action: WorldActionRecord) -> void:
	if action != null:
		pending_attack_target_by_actor.erase(action.actor_entity_id)


func _sync_blocks(player_id: String, should_enqueue_actions: bool) -> void:
	_release_inactive_blocks(player_id)
	for member: PlayerCharacter in abilities.runtime.get_squad_members(player_id):
		if not abilities.provocation_ledger.has_provocation(member.entity_id):
			continue
		if blocked_entity_ids.has(member.entity_id):
			continue
		blocked_entity_ids[member.entity_id] = true
		abilities.set_player_provocation_control_blocked(member, true)
		if should_enqueue_actions and (not GameSession.is_multiplayer() or GameSession.is_host()):
			_enqueue_forced_actions(member)


func _release_inactive_blocks(active_player_id: String) -> void:
	for entity_id: String in blocked_entity_ids.keys():
		var character: PlayerCharacter = abilities.runtime.get_entity_by_id(entity_id) as PlayerCharacter
		if (
			character != null
			and character.owner_player_id == active_player_id
			and abilities.provocation_ledger.has_provocation(entity_id)
		):
			continue
		blocked_entity_ids.erase(entity_id)
		pending_attack_target_by_actor.erase(entity_id)
		if character != null:
			abilities.set_player_provocation_control_blocked(character, false)
		abilities.consume_provocation_by_entity_id(entity_id)


func _enqueue_forced_actions(character: PlayerCharacter) -> void:
	var runtime: WorldRuntime = abilities.runtime
	var turns: WorldTurns = runtime.turn_manager
	var provoker: PlayerCharacter = abilities.get_provoker(character)
	if (
		provoker == null
		or not is_instance_valid(provoker)
		or provoker.health <= 0
	):
		return
	if character.can_attack_surface(provoker.current_surface):
		_enqueue_attack(character, provoker)
		return
	var goal_surfaces: Array[Vector3i] = WorldGridPathfinder.get_adjacent_walkable_surfaces(
		runtime,
		provoker.current_surface
	)
	var path: Array[Vector3i] = WorldGridPathfinder.find_path_to_any(
		runtime,
		character,
		character.current_surface,
		goal_surfaces,
		true
	)
	var available_steps: int = turns.get_steps_left(character.entity_id)
	if path.is_empty() or available_steps <= 0:
		return
	var steps_to_take: int = mini(path.size(), available_steps)
	var destination_surface: Vector3i = path[steps_to_take - 1]
	var was_move_enqueued: bool = runtime.enqueue_system_action(
		WorldActionRecord.ActionType.MOVE_PATH,
		{
			"actor_entity_id": character.entity_id,
			WorldMovePathPolicy.REQUESTED_TARGET_SURFACE_KEY: destination_surface,
		}
	)
	if (
		was_move_enqueued
		and character.can_attack_surface_from(destination_surface, provoker.current_surface)
	):
		pending_attack_target_by_actor[character.entity_id] = provoker.entity_id


func _enqueue_attack(character: PlayerCharacter, provoker: PlayerCharacter) -> void:
	if abilities.runtime.turn_manager.get_attacks_left(character.entity_id) <= 0:
		return
	abilities.runtime.enqueue_system_action(
		WorldActionRecord.ActionType.ATTACK,
		{
			"actor_entity_id": character.entity_id,
			"target_surface": provoker.current_surface,
		}
	)
