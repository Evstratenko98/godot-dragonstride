class_name PlayerSquadRegistry
extends RefCounted

var members_by_player_id: Dictionary[String, Array] = {}
var player_id_by_steam_id: Dictionary[int, String] = {}
var members_by_entity_id: Dictionary[String, PlayerCharacter] = {}
var local_player_id: String = ""


func clear() -> void:
	members_by_player_id.clear()
	player_id_by_steam_id.clear()
	members_by_entity_id.clear()
	local_player_id = ""


func register_member(member: PlayerCharacter) -> bool:
	if member == null or member.owner_player_id.is_empty() or member.entity_id.is_empty():
		return false
	if members_by_entity_id.has(member.entity_id):
		return false

	var members: Array[PlayerCharacter] = get_members_by_player_id(member.owner_player_id)
	members.append(member)
	members.sort_custom(func(first: PlayerCharacter, second: PlayerCharacter) -> bool:
		return first.squad_slot < second.squad_slot
	)
	members_by_player_id[member.owner_player_id] = members
	members_by_entity_id[member.entity_id] = member
	if member.steam_id > 0:
		player_id_by_steam_id[member.steam_id] = member.owner_player_id
	if member.is_locally_owned:
		local_player_id = member.owner_player_id
	return true


func get_members_by_player_id(player_id: String) -> Array[PlayerCharacter]:
	var result: Array[PlayerCharacter] = []
	var stored_members: Array = members_by_player_id.get(player_id, []) as Array
	for member_value: Variant in stored_members:
		var member: PlayerCharacter = member_value as PlayerCharacter
		if member != null and is_instance_valid(member):
			result.append(member)
	return result


func get_members_by_steam_id(steam_id: int) -> Array[PlayerCharacter]:
	return get_members_by_player_id(str(player_id_by_steam_id.get(steam_id, "")))


func get_local_members() -> Array[PlayerCharacter]:
	return get_members_by_player_id(local_player_id)


func get_member_by_entity_id(entity_id: String) -> PlayerCharacter:
	var member: PlayerCharacter = members_by_entity_id.get(entity_id, null) as PlayerCharacter
	return member if member != null and is_instance_valid(member) else null


func get_player_id_by_steam_id(steam_id: int) -> String:
	return str(player_id_by_steam_id.get(steam_id, ""))


func owns_member(steam_id: int, entity_id: String) -> bool:
	var member: PlayerCharacter = get_member_by_entity_id(entity_id)
	return member != null and member.steam_id == steam_id


func get_all_members() -> Array[PlayerCharacter]:
	var result: Array[PlayerCharacter] = []
	for player_id: String in members_by_player_id.keys():
		result.append_array(get_members_by_player_id(player_id))
	return result
