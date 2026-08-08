class_name WorldActionRouter
extends RefCounted

const MAX_BLOCKING_EVENT_SECONDS := 10.0

var runtime: WorldRuntime = null
var players: WorldPlayers = null
var network: WorldNetwork = null
var turns: WorldTurns = null
var spells: WorldSpells = null
var loot: WorldLoot = null


func configure_context(
	new_runtime: WorldRuntime,
	new_players: WorldPlayers,
	new_network: WorldNetwork,
	new_turns: WorldTurns,
	new_spells: WorldSpells,
	new_loot: WorldLoot
) -> void:
	runtime = new_runtime
	players = new_players
	network = new_network
	turns = new_turns
	spells = new_spells
	loot = new_loot


func broadcast_action_profile_payload(action: WorldActionRecord) -> void:
	if action == null or network == null:
		return
	match WorldActionCatalog.get_profile_channel(action.action_type):
		WorldActionCatalog.ProfileChannel.CHARACTER:
			network.broadcast_character_action_payload(action)
		WorldActionCatalog.ProfileChannel.COMBAT:
			network.broadcast_combat_action_payload(action)
		WorldActionCatalog.ProfileChannel.SPELL:
			if spells != null:
				spells.broadcast_action_payload(action)
		WorldActionCatalog.ProfileChannel.INVENTORY:
			network.broadcast_inventory_action_payload(action)


func get_schema_rejection_reason(action: WorldActionRecord) -> String:
	return WorldActionSchemaValidator.get_rejection_reason(action)


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
	if not WorldActionCatalog.is_turn_bound(action.action_type):
		return get_rejection_reason(action)
	if turns != null and action.turn_revision != turns.get_turn_revision():
		return WorldActionStream.REJECTION_STALE_TURN
	var player: PlayerCharacter = runtime.get_entity_by_id(action.actor_entity_id) as PlayerCharacter
	if player == null:
		return WorldActionStream.REJECTION_ACTOR_UNAVAILABLE
	if action.requester_steam_id > 0 and not runtime.is_character_owned_by_steam_id(action.actor_entity_id, action.requester_steam_id):
		return WorldActionStream.REJECTION_ACTOR_UNAVAILABLE
	if action.action_type != WorldActionRecord.ActionType.END_PLAYER_TURN and player.health <= 0:
		return WorldActionStream.REJECTION_ACTOR_UNAVAILABLE
	if turns != null and turns.is_world_turn_active():
		return WorldActionStream.REJECTION_WORLD_TURN
	if (
		WorldActionCatalog.requires_active_player(action.action_type)
		and (turns == null or not turns.is_entity_active_in_turn(player))
	):
		return WorldActionStream.REJECTION_NOT_ACTIVE_PLAYER
	if turns != null and turns.is_turn_mode_enabled() and not turns.is_entity_active_in_turn(player):
		return WorldActionStream.REJECTION_NOT_ACTIVE_PLAYER
	return get_rejection_reason(action)


func reserve_on_accept(action: WorldActionRecord) -> String:
	if action != null and action.action_type == WorldActionRecord.ActionType.SPELL_CAST and spells != null:
		return spells.reserve_action(action)
	if loot != null:
		return loot.reserve_action(action)
	return ""


func release_reservation(action: WorldActionRecord) -> void:
	if action != null and action.action_type == WorldActionRecord.ActionType.SPELL_CAST and spells != null:
		spells.release_action_reservation(action)
	if loot != null:
		loot.release_action_reservation(action)


func get_rejection_reason(action: WorldActionRecord) -> String:
	if action == null:
		return WorldActionStream.REJECTION_INVALID_ACTION
	var player: PlayerCharacter = runtime.get_entity_by_id(action.actor_entity_id) as PlayerCharacter
	if (
		WorldActionCatalog.is_external(action.action_type)
		and action.action_type != WorldActionRecord.ActionType.END_PLAYER_TURN
		and (player == null or player.health <= 0)
	):
		return WorldActionStream.REJECTION_ACTOR_UNAVAILABLE

	match action.action_type:
		WorldActionRecord.ActionType.MOVE_PATH:
			return WorldMovePathPolicy.prepare_authoritative_path(runtime, turns, player, action)
		WorldActionRecord.ActionType.ATTACK:
			var attack_cell: Vector3i = action.payload.get("target_surface", Vector3i.ZERO)
			if not player.can_attack_surface(attack_cell) or not runtime.can_entity_attack_in_turn(player, attack_cell):
				return WorldActionStream.REJECTION_INVALID_ACTION
		WorldActionRecord.ActionType.INTERACTION:
			var interaction_cell: Vector3i = action.payload.get("target_surface", Vector3i.ZERO)
			if not player.can_act() or not player.can_attack_surface(interaction_cell) or not runtime.can_entity_interact_in_turn(player):
				return WorldActionStream.REJECTION_INVALID_ACTION
			if loot != null:
				return loot.get_action_rejection_reason(action)
		WorldActionRecord.ActionType.SPELL_CAST:
			return spells.get_action_rejection_reason(action) if spells != null else WorldActionStream.REJECTION_INVALID_ACTION
		WorldActionRecord.ActionType.INVENTORY_ADD, \
		WorldActionRecord.ActionType.INVENTORY_MOVE, \
		WorldActionRecord.ActionType.INVENTORY_DELETE:
			if player.character_inventory == null:
				return WorldActionStream.REJECTION_INVALID_ACTION
			if not player.character_inventory.matches_revision(int(action.payload.get("expected_inventory_revision", -1))):
				return "stale_inventory"
			if action.action_type == WorldActionRecord.ActionType.INVENTORY_ADD and loot != null:
				return loot.get_action_rejection_reason(action)
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
		WorldActionRecord.ActionType.MOVE_PATH:
			var authoritative_path: Array[Vector3i] = WorldMovePathPolicy.read_surfaces(
				action.payload,
				WorldMovePathPolicy.AUTHORITATIVE_PATH_KEY
			)
			if player == null or not await player.execute_authoritative_move_path(authoritative_path):
				action.payload["cancellation_reason"] = WorldActionStream.REJECTION_PRESENTATION_TIMEOUT
				return false
			return true
		WorldActionRecord.ActionType.ATTACK:
			if player == null:
				return false
			var attack_cell: Vector3i = action.payload.get("target_surface", Vector3i.ZERO)
			player.play_remote_attack(attack_cell, false)
			if not player.is_attacking:
				return false
			runtime.notify_entity_attacked_in_turn(player, attack_cell)
			runtime.apply_attack_to_surface(player, attack_cell, true, false)
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
			if loot != null and loot.is_chest_interaction_action(action):
				var was_opened: bool = await loot.execute_open_action(action, player)
				if was_opened:
					runtime.notify_entity_interacted_in_turn(player)
				return was_opened
			return runtime.try_character_interaction(player, action.payload.get("target_surface", Vector3i.ZERO))
		WorldActionRecord.ActionType.SPELL_CAST:
			if spells == null:
				return false
			return await spells.execute_action_cast(action, true)
		WorldActionRecord.ActionType.INVENTORY_ADD:
			if loot != null and loot.is_chest_claim_action(action):
				var was_claimed: bool = loot.execute_claim_action(action, player)
				if not was_claimed:
					action.payload["cancellation_reason"] = _get_inventory_mutation_reason(null if player == null else player.character_inventory)
				return was_claimed
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
		WorldActionRecord.ActionType.MOVE_PATH:
			var authoritative_path: Array[Vector3i] = WorldMovePathPolicy.read_surfaces(
				action.payload,
				WorldMovePathPolicy.AUTHORITATIVE_PATH_KEY
			)
			await player.play_remote_move_path(authoritative_path)
		WorldActionRecord.ActionType.ATTACK:
			var attack_cell: Vector3i = action.payload.get("target_surface", player.current_surface)
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
		WorldActionRecord.ActionType.INTERACTION:
			if loot != null:
				await loot.play_remote_open_action(action)
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
