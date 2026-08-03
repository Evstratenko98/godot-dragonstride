class_name WorldInventoryNetworkBridge
extends RefCounted

var network: WorldNetwork = null


func configure(owner: WorldNetwork) -> void:
	network = owner


func on_add_requested(actor_entity_id: String, item_id: String, amount: int, expected_inventory_revision: int, match_id: String, turn_revision: int, request_id: int, requester_peer_id: int) -> void:
	if network.level == null or not network.level.allows_debug_commands():
		return
	var player: PlayerCharacter = network._get_requesting_player(requester_peer_id, actor_entity_id)
	if GameSession.is_host() and player != null:
		network.runtime.enqueue_player_action(WorldActionRecord.ActionType.INVENTORY_ADD, player, {"item_id": item_id, "amount": amount, "expected_inventory_revision": expected_inventory_revision}, request_id, requester_peer_id, turn_revision, match_id)


func on_move_requested(actor_entity_id: String, inventory_kind: String, source_slot_index: int, target_slot_index: int, expected_inventory_revision: int, match_id: String, turn_revision: int, request_id: int, requester_peer_id: int) -> void:
	var player: PlayerCharacter = network._get_requesting_player(requester_peer_id, actor_entity_id)
	if GameSession.is_host() and player != null:
		network.runtime.enqueue_player_action(WorldActionRecord.ActionType.INVENTORY_MOVE, player, {"inventory_kind": inventory_kind, "source_slot_index": source_slot_index, "target_slot_index": target_slot_index, "expected_inventory_revision": expected_inventory_revision}, request_id, requester_peer_id, turn_revision, match_id)


func on_delete_requested(actor_entity_id: String, inventory_kind: String, slot_index: int, expected_inventory_revision: int, match_id: String, turn_revision: int, request_id: int, requester_peer_id: int) -> void:
	var player: PlayerCharacter = network._get_requesting_player(requester_peer_id, actor_entity_id)
	if GameSession.is_host() and player != null:
		network.runtime.enqueue_player_action(WorldActionRecord.ActionType.INVENTORY_DELETE, player, {"inventory_kind": inventory_kind, "slot_index": slot_index, "expected_inventory_revision": expected_inventory_revision}, request_id, requester_peer_id, turn_revision, match_id)


func on_use_requested(actor_entity_id: String, slot_index: int, expected_inventory_revision: int, match_id: String, turn_revision: int, request_id: int, requester_peer_id: int) -> void:
	var player: PlayerCharacter = network._get_requesting_player(requester_peer_id, actor_entity_id)
	if GameSession.is_host() and player != null:
		network.runtime.enqueue_player_action(WorldActionRecord.ActionType.INVENTORY_USE, player, {"slot_index": slot_index, "expected_inventory_revision": expected_inventory_revision}, request_id, requester_peer_id, turn_revision, match_id)


func on_snapshot_received(snapshot: Dictionary, sequence_id: int) -> void:
	if GameSession.is_host() or network.message_buffer.buffer_inventory_snapshot(sequence_id, snapshot):
		return
	apply_snapshot(snapshot)


func apply_snapshot(snapshot: Dictionary) -> void:
	var entity_id: String = str(snapshot.get("entity_id", ""))
	var player: PlayerCharacter = network.runtime.get_entity_by_id(entity_id) as PlayerCharacter
	if player != null and player.is_locally_owned:
		player.character_inventory.apply_snapshot(snapshot)


func send_snapshot(player: PlayerCharacter, requester_peer_id: int, sequence_id: int = 0) -> void:
	if player == null or player.character_inventory == null or requester_peer_id == 0:
		return
	NetworkManager.inventory.send_inventory_snapshot(requester_peer_id, player.character_inventory.create_snapshot(), sequence_id)


func send_snapshots_to_owners() -> void:
	for entity_variant: Variant in network.runtime.get_registered_entities():
		var player: PlayerCharacter = entity_variant as PlayerCharacter
		if player == null or player.is_locally_owned or player.steam_id == 0:
			continue
		var peer_id: int = NetworkManager.peers.get_peer_id_for_steam_id(player.steam_id)
		if peer_id != 0:
			send_snapshot(player, peer_id)
