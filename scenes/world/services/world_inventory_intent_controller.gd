class_name WorldInventoryIntentController
extends RefCounted

var runtime: WorldRuntime = null


func configure(new_runtime: WorldRuntime) -> void:
	runtime = new_runtime


func request_add(item_id: String, amount: int) -> void:
	var actor: PlayerCharacter = _get_selected_actor()
	if actor == null:
		return
	var request_id: int = runtime.create_action_request_id()
	var inventory_revision: int = actor.character_inventory.revision
	if GameSession.is_singleplayer():
		runtime.enqueue_player_action(
			WorldActionRecord.ActionType.INVENTORY_ADD,
			actor,
			{"item_id": item_id, "amount": amount, "expected_inventory_revision": inventory_revision},
			request_id,
			0
		)
		return
	NetworkManager.inventory.request_inventory_add(actor.entity_id, item_id, amount, inventory_revision, GameSession.get_match_id(), runtime.get_turn_revision(), request_id)


func request_move(inventory_kind: String, source_slot_index: int, target_slot_index: int) -> void:
	var actor: PlayerCharacter = _get_selected_actor()
	if actor == null:
		return
	var request_id: int = runtime.create_action_request_id()
	var inventory_revision: int = actor.character_inventory.revision
	if GameSession.is_singleplayer():
		runtime.enqueue_player_action(
			WorldActionRecord.ActionType.INVENTORY_MOVE,
			actor,
			{
				"inventory_kind": inventory_kind,
				"source_slot_index": source_slot_index,
				"target_slot_index": target_slot_index,
				"expected_inventory_revision": inventory_revision,
			},
			request_id,
			0
		)
		return
	NetworkManager.inventory.request_inventory_move(actor.entity_id, inventory_kind, source_slot_index, target_slot_index, inventory_revision, GameSession.get_match_id(), runtime.get_turn_revision(), request_id)


func request_delete(inventory_kind: String, slot_index: int) -> void:
	var actor: PlayerCharacter = _get_selected_actor()
	if actor == null:
		return
	var request_id: int = runtime.create_action_request_id()
	var inventory_revision: int = actor.character_inventory.revision
	if GameSession.is_singleplayer():
		runtime.enqueue_player_action(
			WorldActionRecord.ActionType.INVENTORY_DELETE,
			actor,
			{"inventory_kind": inventory_kind, "slot_index": slot_index, "expected_inventory_revision": inventory_revision},
			request_id,
			0
		)
		return
	NetworkManager.inventory.request_inventory_delete(actor.entity_id, inventory_kind, slot_index, inventory_revision, GameSession.get_match_id(), runtime.get_turn_revision(), request_id)


func request_use(slot_index: int) -> void:
	var actor: PlayerCharacter = _get_selected_actor()
	if actor == null:
		return
	var request_id: int = runtime.create_action_request_id()
	var inventory_revision: int = actor.character_inventory.revision
	if GameSession.is_singleplayer():
		runtime.enqueue_player_action(
			WorldActionRecord.ActionType.INVENTORY_USE,
			actor,
			{"slot_index": slot_index, "expected_inventory_revision": inventory_revision},
			request_id,
			0
		)
		return
	NetworkManager.inventory.request_inventory_use(actor.entity_id, slot_index, inventory_revision, GameSession.get_match_id(), runtime.get_turn_revision(), request_id)


func _get_selected_actor() -> PlayerCharacter:
	return null if runtime == null else runtime.get_selected_local_character()
