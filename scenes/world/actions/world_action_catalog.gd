class_name WorldActionCatalog
extends RefCounted

enum ProfileChannel {
	NONE,
	CHARACTER,
	COMBAT,
	SPELL,
	INVENTORY,
	ABILITY,
}

const KEY_IS_EXTERNAL := "is_external"
const KEY_IS_TURN_BOUND := "is_turn_bound"
const KEY_REQUIRES_ACTIVE_PLAYER := "requires_active_player"
const KEY_REQUIRES_PROFILE_PAYLOAD := "requires_profile_payload"
const KEY_REQUIRES_TURN_PROFILE := "requires_turn_profile"
const KEY_REQUIRES_TURN_PROFILE_IN_TURN_MODE := "requires_turn_profile_in_turn_mode"
const KEY_PROFILE_CHANNEL := "profile_channel"
const KEY_INLINE_LIFECYCLE_PAYLOAD := "inline_lifecycle_payload"

const DEFINITIONS := {
	WorldActionRecord.ActionType.MOVE_PATH: {KEY_IS_EXTERNAL: true, KEY_IS_TURN_BOUND: true, KEY_REQUIRES_PROFILE_PAYLOAD: true, KEY_REQUIRES_TURN_PROFILE_IN_TURN_MODE: true, KEY_PROFILE_CHANNEL: ProfileChannel.CHARACTER},
	WorldActionRecord.ActionType.ATTACK: {KEY_IS_EXTERNAL: true, KEY_IS_TURN_BOUND: true, KEY_REQUIRES_PROFILE_PAYLOAD: true, KEY_REQUIRES_TURN_PROFILE_IN_TURN_MODE: true, KEY_PROFILE_CHANNEL: ProfileChannel.COMBAT},
	WorldActionRecord.ActionType.INTERACTION: {KEY_IS_EXTERNAL: true, KEY_IS_TURN_BOUND: true, KEY_REQUIRES_PROFILE_PAYLOAD: true, KEY_REQUIRES_TURN_PROFILE_IN_TURN_MODE: true, KEY_PROFILE_CHANNEL: ProfileChannel.CHARACTER},
	WorldActionRecord.ActionType.SPELL_CAST: {KEY_IS_EXTERNAL: true, KEY_IS_TURN_BOUND: true, KEY_REQUIRES_ACTIVE_PLAYER: true, KEY_REQUIRES_PROFILE_PAYLOAD: true, KEY_PROFILE_CHANNEL: ProfileChannel.SPELL},
	WorldActionRecord.ActionType.INVENTORY_ADD: {KEY_IS_EXTERNAL: true, KEY_REQUIRES_PROFILE_PAYLOAD: true, KEY_PROFILE_CHANNEL: ProfileChannel.INVENTORY},
	WorldActionRecord.ActionType.INVENTORY_MOVE: {KEY_IS_EXTERNAL: true, KEY_REQUIRES_PROFILE_PAYLOAD: true, KEY_PROFILE_CHANNEL: ProfileChannel.INVENTORY},
	WorldActionRecord.ActionType.INVENTORY_DELETE: {KEY_IS_EXTERNAL: true, KEY_REQUIRES_PROFILE_PAYLOAD: true, KEY_PROFILE_CHANNEL: ProfileChannel.INVENTORY},
	WorldActionRecord.ActionType.INVENTORY_USE: {KEY_IS_EXTERNAL: true, KEY_IS_TURN_BOUND: true, KEY_REQUIRES_ACTIVE_PLAYER: true, KEY_REQUIRES_PROFILE_PAYLOAD: true, KEY_PROFILE_CHANNEL: ProfileChannel.INVENTORY},
	WorldActionRecord.ActionType.CHARACTER_KILL: {KEY_IS_EXTERNAL: true},
	WorldActionRecord.ActionType.PLAYER_TURN_STARTED: {KEY_REQUIRES_TURN_PROFILE: true},
	WorldActionRecord.ActionType.END_PLAYER_TURN: {KEY_IS_EXTERNAL: true, KEY_IS_TURN_BOUND: true, KEY_REQUIRES_TURN_PROFILE: true},
	WorldActionRecord.ActionType.WORLD_TURN_STARTED: {KEY_REQUIRES_TURN_PROFILE: true},
	WorldActionRecord.ActionType.WORLD_TURN_ENDED: {KEY_REQUIRES_TURN_PROFILE: true},
	WorldActionRecord.ActionType.SET_TURN_MODE: {KEY_REQUIRES_TURN_PROFILE: true},
	WorldActionRecord.ActionType.PLAYER_TURN_SKIPPED: {KEY_REQUIRES_TURN_PROFILE: true},
	WorldActionRecord.ActionType.BLOCKING_EVENT: {},
	WorldActionRecord.ActionType.SET_FOG_OF_WAR: {KEY_INLINE_LIFECYCLE_PAYLOAD: true},
	WorldActionRecord.ActionType.CHARACTER_ABILITY: {KEY_IS_EXTERNAL: true, KEY_IS_TURN_BOUND: true, KEY_REQUIRES_PROFILE_PAYLOAD: true, KEY_REQUIRES_TURN_PROFILE_IN_TURN_MODE: true, KEY_PROFILE_CHANNEL: ProfileChannel.ABILITY},
}


static func is_known(action_type: WorldActionRecord.ActionType) -> bool:
	return DEFINITIONS.has(action_type)


static func is_external(action_type: WorldActionRecord.ActionType) -> bool:
	return _read_flag(action_type, KEY_IS_EXTERNAL)


static func is_turn_bound(action_type: WorldActionRecord.ActionType) -> bool:
	return _read_flag(action_type, KEY_IS_TURN_BOUND)


static func requires_active_player(action_type: WorldActionRecord.ActionType) -> bool:
	return _read_flag(action_type, KEY_REQUIRES_ACTIVE_PLAYER)


static func requires_profile_payload(action_type: WorldActionRecord.ActionType) -> bool:
	return _read_flag(action_type, KEY_REQUIRES_PROFILE_PAYLOAD)


static func requires_turn_profile(action_type: WorldActionRecord.ActionType, is_turn_mode_enabled: bool) -> bool:
	return (
		_read_flag(action_type, KEY_REQUIRES_TURN_PROFILE)
		or (is_turn_mode_enabled and _read_flag(action_type, KEY_REQUIRES_TURN_PROFILE_IN_TURN_MODE))
	)


static func get_profile_channel(action_type: WorldActionRecord.ActionType) -> ProfileChannel:
	var definition: Dictionary = DEFINITIONS.get(action_type, {}) as Dictionary
	return int(definition.get(KEY_PROFILE_CHANNEL, int(ProfileChannel.NONE))) as ProfileChannel


static func uses_inline_lifecycle_payload(action_type: WorldActionRecord.ActionType) -> bool:
	return _read_flag(action_type, KEY_INLINE_LIFECYCLE_PAYLOAD)


static func _read_flag(action_type: WorldActionRecord.ActionType, key: String) -> bool:
	var definition: Dictionary = DEFINITIONS.get(action_type, {}) as Dictionary
	return bool(definition.get(key, false))
