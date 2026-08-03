class_name WorldActionSchemaValidator
extends RefCounted


static func get_rejection_reason(action: WorldActionRecord) -> String:
	if action == null or action.request_id <= 0 or action.actor_entity_id.is_empty():
		return WorldActionStream.REJECTION_INVALID_ACTION
	if GameSession.is_multiplayer() and action.requester_steam_id <= 0:
		return WorldActionStream.REJECTION_INVALID_ACTION
	if not NetworkProtocol.is_valid_identifier(action.actor_entity_id):
		return WorldActionStream.REJECTION_INVALID_ACTION
	if not NetworkProtocol.is_valid_intent_payload(action.payload):
		return "payload_too_large"
	if not WorldActionCatalog.is_external(action.action_type):
		return WorldActionStream.REJECTION_INVALID_ACTION

	match action.action_type:
		WorldActionRecord.ActionType.MOVE_PATH:
			if not NetworkProtocol.is_valid_move_path(action.payload.get("requested_path")):
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
				or int(action.payload.get("amount", 0)) > CharacterInventory.get_max_intent_amount()
				or int(action.payload.get("expected_inventory_revision", -1)) < 0
			):
				return WorldActionStream.REJECTION_INVALID_ACTION
			if str(action.payload.get(WorldLoot.PAYLOAD_SOURCE_KIND, "")) == WorldLoot.SOURCE_KIND_CHEST:
				var inventory_kind: String = str(action.payload.get(WorldLoot.PAYLOAD_INVENTORY_KIND, ""))
				if (
					not NetworkProtocol.is_valid_identifier(str(action.payload.get(WorldLoot.PAYLOAD_SOURCE_CHEST_ID, "")))
					or not CharacterInventory.is_valid_slot_index_for_kind(
						inventory_kind,
						int(action.payload.get(WorldLoot.PAYLOAD_TARGET_SLOT_INDEX, -1))
					)
				):
					return WorldActionStream.REJECTION_INVALID_ACTION
		WorldActionRecord.ActionType.INVENTORY_MOVE:
			var move_inventory_kind: String = str(action.payload.get("inventory_kind", ""))
			if not CharacterInventory.is_valid_inventory_kind(move_inventory_kind) or int(action.payload.get("expected_inventory_revision", -1)) < 0:
				return WorldActionStream.REJECTION_INVALID_ACTION
			if not CharacterInventory.is_valid_slot_index_for_kind(move_inventory_kind, int(action.payload.get("source_slot_index", -1))) or not CharacterInventory.is_valid_slot_index_for_kind(move_inventory_kind, int(action.payload.get("target_slot_index", -1))):
				return WorldActionStream.REJECTION_INVALID_ACTION
		WorldActionRecord.ActionType.INVENTORY_DELETE:
			var delete_inventory_kind: String = str(action.payload.get("inventory_kind", ""))
			if not CharacterInventory.is_valid_slot_index_for_kind(delete_inventory_kind, int(action.payload.get("slot_index", -1))) or int(action.payload.get("expected_inventory_revision", -1)) < 0:
				return WorldActionStream.REJECTION_INVALID_ACTION
		WorldActionRecord.ActionType.INVENTORY_USE:
			if not CharacterInventory.is_valid_slot_index_for_kind(CharacterInventory.INVENTORY_KIND_ITEM, int(action.payload.get("slot_index", -1))) or int(action.payload.get("expected_inventory_revision", -1)) < 0:
				return WorldActionStream.REJECTION_INVALID_ACTION
		WorldActionRecord.ActionType.CHARACTER_KILL, WorldActionRecord.ActionType.END_PLAYER_TURN:
			pass
		_:
			return WorldActionStream.REJECTION_INVALID_ACTION
	return ""
