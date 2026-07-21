class_name WorldActionRouter
extends RefCounted

const MAX_BLOCKING_EVENT_SECONDS := 10.0

var runtime: WorldRuntime = null
var players: WorldPlayers = null
var network: WorldNetwork = null
var turns: WorldTurns = null
var spells: WorldSpells = null


func configure_context(
	new_runtime: WorldRuntime,
	new_players: WorldPlayers,
	new_network: WorldNetwork,
	new_turns: WorldTurns,
	new_spells: WorldSpells
) -> void:
	runtime = new_runtime
	players = new_players
	network = new_network
	turns = new_turns
	spells = new_spells


func broadcast_action_profile_payload(action: WorldActionRecord) -> void:
	if action == null or network == null:
		return
	match action.action_type:
		WorldActionRecord.ActionType.MOVE, WorldActionRecord.ActionType.INTERACTION:
			network.broadcast_character_action_payload(action)
		WorldActionRecord.ActionType.ATTACK:
			network.broadcast_combat_action_payload(action)
		WorldActionRecord.ActionType.SPELL_CAST:
			if spells != null:
				spells.broadcast_action_payload(action)
		WorldActionRecord.ActionType.INVENTORY_ADD, \
		WorldActionRecord.ActionType.INVENTORY_MOVE, \
		WorldActionRecord.ActionType.INVENTORY_DELETE, \
		WorldActionRecord.ActionType.INVENTORY_USE:
			network.broadcast_inventory_action_payload(action)


func get_schema_rejection_reason(action: WorldActionRecord) -> String:
	if action == null or action.request_id <= 0 or action.actor_entity_id.is_empty():
		return WorldActionStream.REJECTION_INVALID_ACTION
	if GameSession.is_multiplayer() and action.requester_steam_id <= 0:
		return WorldActionStream.REJECTION_INVALID_ACTION
	if not NetworkProtocol.is_valid_identifier(action.actor_entity_id):
		return WorldActionStream.REJECTION_INVALID_ACTION
	if not NetworkProtocol.is_valid_intent_payload(action.payload):
		return "payload_too_large"

	match action.action_type:
		WorldActionRecord.ActionType.MOVE:
			var direction_value: Variant = action.payload.get("direction")
			if not (direction_value is Vector2i):
				return WorldActionStream.REJECTION_INVALID_ACTION
			var direction: Vector2i = direction_value as Vector2i
			if absi(direction.x) + absi(direction.y) != 1:
				return WorldActionStream.REJECTION_INVALID_ACTION
		WorldActionRecord.ActionType.ATTACK, WorldActionRecord.ActionType.INTERACTION:
			if not (action.payload.get("target_cell") is Vector2i):
				return WorldActionStream.REJECTION_INVALID_ACTION
		WorldActionRecord.ActionType.SPELL_CAST:
			var target_kind: String = str(action.payload.get("target_kind", "cell"))
			if target_kind == "cell" and not (action.payload.get("target_cell") is Vector2i):
				return WorldActionStream.REJECTION_INVALID_ACTION
			if target_kind == "entity" and str(action.payload.get("target_entity_id", "")).is_empty():
				return WorldActionStream.REJECTION_INVALID_ACTION
			if target_kind != "cell" and target_kind != "entity":
				return WorldActionStream.REJECTION_INVALID_ACTION
			if int(action.payload.get("spell_slot_index", -1)) < 0:
				return WorldActionStream.REJECTION_INVALID_ACTION
		WorldActionRecord.ActionType.INVENTORY_ADD:
			if (
				str(action.payload.get("item_id", "")).is_empty()
				or int(action.payload.get("amount", 0)) <= 0
				or int(action.payload.get("amount", 0)) > CharacterInventory.ITEM_SLOT_COUNT * CharacterInventory.DEFAULT_MAX_STACK_SIZE
				or int(action.payload.get("expected_inventory_revision", -1)) < 0
			):
				return WorldActionStream.REJECTION_INVALID_ACTION
		WorldActionRecord.ActionType.INVENTORY_MOVE:
			if str(action.payload.get("inventory_kind", "")).is_empty() or int(action.payload.get("expected_inventory_revision", -1)) < 0:
				return WorldActionStream.REJECTION_INVALID_ACTION
			if int(action.payload.get("source_slot_index", -1)) < 0 or int(action.payload.get("target_slot_index", -1)) < 0:
				return WorldActionStream.REJECTION_INVALID_ACTION
		WorldActionRecord.ActionType.INVENTORY_DELETE:
			if str(action.payload.get("inventory_kind", "")).is_empty() or int(action.payload.get("slot_index", -1)) < 0 or int(action.payload.get("expected_inventory_revision", -1)) < 0:
				return WorldActionStream.REJECTION_INVALID_ACTION
		WorldActionRecord.ActionType.INVENTORY_USE:
			if int(action.payload.get("slot_index", -1)) < 0 or int(action.payload.get("expected_inventory_revision", -1)) < 0:
				return WorldActionStream.REJECTION_INVALID_ACTION
		WorldActionRecord.ActionType.CHARACTER_KILL, WorldActionRecord.ActionType.END_PLAYER_TURN:
			pass
		_:
			return WorldActionStream.REJECTION_INVALID_ACTION
	return ""


func get_acceptance_rejection_reason(action: WorldActionRecord) -> String:
	if action == null:
		return WorldActionStream.REJECTION_INVALID_ACTION
	if action.request_id < 0:
		return WorldActionStream.REJECTION_INVALID_ACTION
	if GameSession.is_multiplayer() and action.match_id != GameSession.get_match_id():
		return WorldActionStream.REJECTION_WRONG_MATCH
	if action.request_id == 0:
		if action.requester_steam_id != 0:
			return WorldActionStream.REJECTION_INVALID_ACTION
		return get_rejection_reason(action)
	if GameSession.is_multiplayer() and not GameSession.has_committed_match():
		return WorldActionStream.REJECTION_ACTOR_UNAVAILABLE
	if GameSession.is_multiplayer():
		if action.requester_steam_id <= 0:
			return WorldActionStream.REJECTION_INVALID_ACTION
		if not runtime.is_player_connected(action.requester_steam_id):
			return WorldActionStream.REJECTION_ACTOR_DISCONNECTED
	if not _is_turn_bound_action(action.action_type):
		return get_rejection_reason(action)
	if turns != null and action.turn_revision != turns.get_turn_revision():
		return WorldActionStream.REJECTION_STALE_TURN
	var player: PlayerCharacter = runtime.get_entity_by_id(action.actor_entity_id) as PlayerCharacter
	if player == null or player.health <= 0:
		return WorldActionStream.REJECTION_ACTOR_UNAVAILABLE
	if turns != null and turns.is_world_turn_active():
		return WorldActionStream.REJECTION_WORLD_TURN
	if (
		action.action_type in [
			WorldActionRecord.ActionType.SPELL_CAST,
			WorldActionRecord.ActionType.INVENTORY_USE,
		]
		and (turns == null or not turns.is_entity_active_in_turn(player))
	):
		return WorldActionStream.REJECTION_NOT_ACTIVE_PLAYER
	if turns != null and turns.is_turn_mode_enabled() and not turns.is_entity_active_in_turn(player):
		return WorldActionStream.REJECTION_NOT_ACTIVE_PLAYER
	return get_rejection_reason(action)


func reserve_on_accept(action: WorldActionRecord) -> String:
	if action != null and action.action_type == WorldActionRecord.ActionType.SPELL_CAST and spells != null:
		return spells.reserve_action(action)
	return ""


func release_reservation(action: WorldActionRecord) -> void:
	if action != null and action.action_type == WorldActionRecord.ActionType.SPELL_CAST and spells != null:
		spells.release_action_reservation(action)


func get_rejection_reason(action: WorldActionRecord) -> String:
	if action == null:
		return WorldActionStream.REJECTION_INVALID_ACTION
	var player: PlayerCharacter = runtime.get_entity_by_id(action.actor_entity_id) as PlayerCharacter
	if _is_player_action(action.action_type) and (player == null or player.health <= 0):
		return WorldActionStream.REJECTION_ACTOR_UNAVAILABLE

	match action.action_type:
		WorldActionRecord.ActionType.MOVE:
			var direction: Vector2i = action.payload.get("direction", Vector2i.ZERO)
			if direction == Vector2i.ZERO or not runtime.can_entity_move_in_turn(player):
				return WorldActionStream.REJECTION_INVALID_ACTION
			var from_cell: Vector2i = runtime.world_to_cell(player.global_position)
			var target_cell: Vector2i = from_cell + direction
			if not runtime.can_enter_cell(target_cell, player):
				return WorldActionStream.REJECTION_INVALID_ACTION
			action.payload["from_cell"] = from_cell
			action.payload["target_cell"] = target_cell
		WorldActionRecord.ActionType.ATTACK:
			var attack_cell: Vector2i = action.payload.get("target_cell", Vector2i.ZERO)
			player.current_cell = runtime.world_to_cell(player.global_position)
			if not player.can_attack_cell(attack_cell) or not runtime.can_entity_attack_in_turn(player, attack_cell):
				return WorldActionStream.REJECTION_INVALID_ACTION
		WorldActionRecord.ActionType.INTERACTION:
			var interaction_cell: Vector2i = action.payload.get("target_cell", Vector2i.ZERO)
			player.current_cell = runtime.world_to_cell(player.global_position)
			if not player.can_act() or not player.can_attack_cell(interaction_cell) or not runtime.can_entity_interact_in_turn(player):
				return WorldActionStream.REJECTION_INVALID_ACTION
		WorldActionRecord.ActionType.SPELL_CAST:
			return spells.get_action_rejection_reason(action) if spells != null else WorldActionStream.REJECTION_INVALID_ACTION
		WorldActionRecord.ActionType.INVENTORY_ADD, \
		WorldActionRecord.ActionType.INVENTORY_MOVE, \
		WorldActionRecord.ActionType.INVENTORY_DELETE:
			if player.character_inventory == null:
				return WorldActionStream.REJECTION_INVALID_ACTION
			if not player.character_inventory.matches_revision(int(action.payload.get("expected_inventory_revision", -1))):
				return "stale_inventory"
		WorldActionRecord.ActionType.INVENTORY_USE:
			if player.character_inventory == null or not runtime.can_entity_use_item_in_turn(player):
				return WorldActionStream.REJECTION_INVALID_ACTION
			if not player.character_inventory.matches_revision(int(action.payload.get("expected_inventory_revision", -1))):
				return "stale_inventory"
		WorldActionRecord.ActionType.END_PLAYER_TURN:
			if turns == null or not turns.can_end_turn(player):
				return WorldActionStream.REJECTION_INVALID_ACTION
	return ""


func execute_authoritative(action: WorldActionRecord) -> bool:
	if runtime == null or not runtime.is_inside_tree():
		return false
	var scene_tree: SceneTree = runtime.get_tree()
	var player: PlayerCharacter = runtime.get_entity_by_id(action.actor_entity_id) as PlayerCharacter
	match action.action_type:
		WorldActionRecord.ActionType.MOVE:
			var direction: Vector2i = action.payload.get("direction", Vector2i.ZERO)
			if player == null or not player.execute_authoritative_move(direction):
				return false
			var move_deadline_msec: int = Time.get_ticks_msec() + int((player.move_time + 2.0) * 1000.0)
			while is_instance_valid(player) and player.is_moving and Time.get_ticks_msec() < move_deadline_msec:
				await scene_tree.process_frame
				if not runtime.is_inside_tree():
					return false
			if not is_instance_valid(player):
				return false
			if player.is_moving:
				player.force_cancel_movement(action.payload.get("from_cell", player.current_cell))
				action.payload["cancellation_reason"] = WorldActionStream.REJECTION_PRESENTATION_TIMEOUT
				return false
			return true
		WorldActionRecord.ActionType.ATTACK:
			if player == null:
				return false
			var attack_cell: Vector2i = action.payload.get("target_cell", Vector2i.ZERO)
			player.play_remote_attack(attack_cell, false)
			if not player.is_attacking:
				return false
			runtime.notify_entity_attacked_in_turn(player, attack_cell)
			runtime.apply_attack_to_cell(player, attack_cell, true, false)
			var expected_attack_duration: float = player.get_expected_attack_duration(attack_cell)
			var attack_deadline_msec: int = Time.get_ticks_msec() + int((expected_attack_duration + 2.0) * 1000.0)
			while is_instance_valid(player) and player.is_attacking and Time.get_ticks_msec() < attack_deadline_msec:
				await scene_tree.process_frame
				if not runtime.is_inside_tree():
					return false
			if not is_instance_valid(player):
				return false
			if player.is_attacking:
				player.force_finish_attack_presentation()
			return true
		WorldActionRecord.ActionType.INTERACTION:
			return runtime.try_character_interaction(player, action.payload.get("target_cell", Vector2i.ZERO))
		WorldActionRecord.ActionType.SPELL_CAST:
			if spells == null:
				return false
			return await spells.execute_action_cast(action, true)
		WorldActionRecord.ActionType.INVENTORY_ADD:
			var was_added: bool = player != null and player.character_inventory.try_add_item(str(action.payload.get("item_id", "")), int(action.payload.get("amount", 0)))
			if not was_added:
				action.payload["cancellation_reason"] = _get_inventory_mutation_reason(null if player == null else player.character_inventory)
			return was_added
		WorldActionRecord.ActionType.INVENTORY_MOVE:
			if player == null:
				return false
			var was_moved: bool = player.character_inventory.try_move_stack(
				str(action.payload.get("inventory_kind", "")),
				int(action.payload.get("source_slot_index", -1)),
				int(action.payload.get("target_slot_index", -1))
			)
			if not was_moved:
				action.payload["cancellation_reason"] = _get_inventory_mutation_reason(player.character_inventory)
			return was_moved
		WorldActionRecord.ActionType.INVENTORY_DELETE:
			if player == null:
				return false
			var was_deleted: bool = player.character_inventory.try_delete_stack(
				str(action.payload.get("inventory_kind", "")),
				int(action.payload.get("slot_index", -1))
			)
			if not was_deleted:
				action.payload["cancellation_reason"] = _get_inventory_mutation_reason(player.character_inventory)
			return was_deleted
		WorldActionRecord.ActionType.INVENTORY_USE:
			var was_used: bool = player != null and runtime.try_use_inventory_item(player, int(action.payload.get("slot_index", -1)))
			if not was_used:
				action.payload["cancellation_reason"] = "effect_failed"
			return was_used
		WorldActionRecord.ActionType.CHARACTER_KILL:
			return players != null and players.execute_character_kill_action(player)
		WorldActionRecord.ActionType.END_PLAYER_TURN:
			return turns != null and turns.execute_end_turn_action(player)
		WorldActionRecord.ActionType.PLAYER_TURN_STARTED:
			return turns != null and turns.execute_player_turn_started_action(action.actor_entity_id)
		WorldActionRecord.ActionType.WORLD_TURN_STARTED:
			if turns == null:
				return false
			return await turns.execute_world_turn_started_action()
		WorldActionRecord.ActionType.WORLD_TURN_ENDED:
			return turns != null and turns.execute_world_turn_ended_action()
		WorldActionRecord.ActionType.SET_TURN_MODE:
			return turns != null and turns.execute_set_turn_mode_action(bool(action.payload.get("is_enabled", false)))
		WorldActionRecord.ActionType.PLAYER_TURN_SKIPPED:
			return turns != null and turns.execute_player_turn_skipped_action(
				action.actor_entity_id,
				str(action.payload.get("reason", "unavailable"))
			)
		WorldActionRecord.ActionType.BLOCKING_EVENT:
			var duration_seconds: float = clampf(float(action.payload.get("duration_seconds", 0.0)), 0.0, MAX_BLOCKING_EVENT_SECONDS)
			if duration_seconds > 0.0:
				await scene_tree.create_timer(duration_seconds).timeout
				if not runtime.is_inside_tree():
					return false
			return true
	return false


func play_remote(action: WorldActionRecord) -> void:
	if runtime == null or not runtime.is_inside_tree():
		return
	var scene_tree: SceneTree = runtime.get_tree()
	var player: PlayerCharacter = runtime.get_entity_by_id(action.actor_entity_id) as PlayerCharacter
	if player == null:
		return
	match action.action_type:
		WorldActionRecord.ActionType.MOVE:
			var from_cell: Vector2i = action.payload.get("from_cell", player.current_cell)
			var target_cell: Vector2i = action.payload.get("target_cell", player.current_cell)
			if player.play_remote_move(from_cell, target_cell):
				var move_deadline_msec: int = Time.get_ticks_msec() + int((player.move_time + 2.0) * 1000.0)
				while is_instance_valid(player) and player.is_moving and Time.get_ticks_msec() < move_deadline_msec:
					await scene_tree.process_frame
					if not runtime.is_inside_tree():
						return
				if not is_instance_valid(player):
					return
				if player.is_moving:
					player.force_cancel_movement(from_cell)
		WorldActionRecord.ActionType.ATTACK:
			var attack_cell: Vector2i = action.payload.get("target_cell", player.current_cell)
			player.play_remote_attack(attack_cell, false)
			var expected_attack_duration: float = player.get_expected_attack_duration(attack_cell)
			var attack_deadline_msec: int = Time.get_ticks_msec() + int((expected_attack_duration + 2.0) * 1000.0)
			while is_instance_valid(player) and player.is_attacking and Time.get_ticks_msec() < attack_deadline_msec:
				await scene_tree.process_frame
				if not runtime.is_inside_tree():
					return
			if not is_instance_valid(player):
				return
			if player.is_attacking:
				player.force_finish_attack_presentation()
		WorldActionRecord.ActionType.SPELL_CAST:
			if spells != null:
				await spells.execute_action_cast(action, false)
		WorldActionRecord.ActionType.BLOCKING_EVENT:
			var duration_seconds: float = clampf(float(action.payload.get("duration_seconds", 0.0)), 0.0, MAX_BLOCKING_EVENT_SECONDS)
			if duration_seconds > 0.0:
				await scene_tree.create_timer(duration_seconds).timeout


func finalize_authoritative(action: WorldActionRecord) -> void:
	if network != null:
		network.finalize_authoritative_action(action)


func _get_inventory_mutation_reason(character_inventory: CharacterInventory) -> String:
	if character_inventory == null:
		return WorldActionStream.REJECTION_INVALID_ACTION
	match character_inventory.get_last_mutation_result():
		CharacterInventory.MutationResult.STALE_REVISION:
			return "stale_inventory"
		CharacterInventory.MutationResult.EFFECT_FAILED:
			return "effect_failed"
		_:
			return WorldActionStream.REJECTION_INVALID_ACTION


func _is_turn_bound_action(action_type: WorldActionRecord.ActionType) -> bool:
	return action_type in [
		WorldActionRecord.ActionType.MOVE,
		WorldActionRecord.ActionType.ATTACK,
		WorldActionRecord.ActionType.INTERACTION,
		WorldActionRecord.ActionType.SPELL_CAST,
		WorldActionRecord.ActionType.INVENTORY_USE,
		WorldActionRecord.ActionType.END_PLAYER_TURN,
	]


func _is_player_action(action_type: WorldActionRecord.ActionType) -> bool:
	return action_type in [
		WorldActionRecord.ActionType.MOVE,
		WorldActionRecord.ActionType.ATTACK,
		WorldActionRecord.ActionType.INTERACTION,
		WorldActionRecord.ActionType.SPELL_CAST,
		WorldActionRecord.ActionType.INVENTORY_ADD,
		WorldActionRecord.ActionType.INVENTORY_MOVE,
		WorldActionRecord.ActionType.INVENTORY_DELETE,
		WorldActionRecord.ActionType.INVENTORY_USE,
		WorldActionRecord.ActionType.CHARACTER_KILL,
	]
