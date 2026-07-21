class_name WorldNetworkSignalBindings
extends RefCounted

var network: WorldNetwork = null


func configure(owner: WorldNetwork) -> void:
	network = owner


func connect_signals() -> void:
	if not GameSession.session_cleared.is_connected(network._on_session_cleared):
		GameSession.session_cleared.connect(network._on_session_cleared)
	if network.runtime.action_stream != null and not network.runtime.action_stream.action_started.is_connected(network._on_stream_action_started):
		network.runtime.action_stream.action_started.connect(network._on_stream_action_started)
	if network.runtime.action_stream != null and not network.runtime.action_stream.action_completed.is_connected(network._on_stream_action_finished):
		network.runtime.action_stream.action_completed.connect(network._on_stream_action_finished)
	if network.runtime.action_stream != null and not network.runtime.action_stream.action_cancelled.is_connected(network._on_stream_action_cancelled):
		network.runtime.action_stream.action_cancelled.connect(network._on_stream_action_cancelled)
	if network.runtime.action_stream != null and not network.runtime.action_stream.remote_snapshot_committed.is_connected(network._on_remote_snapshot_committed):
		network.runtime.action_stream.remote_snapshot_committed.connect(network._on_remote_snapshot_committed)
	if not NetworkManager.actions.action_accepted.is_connected(network._on_action_accepted):
		NetworkManager.actions.action_accepted.connect(network._on_action_accepted)
	if not NetworkManager.actions.action_rejected.is_connected(network._on_action_rejected):
		NetworkManager.actions.action_rejected.connect(network._on_action_rejected)
	if not NetworkManager.peers.peer_map_updated.is_connected(network._on_peer_map_updated):
		NetworkManager.peers.peer_map_updated.connect(network._on_peer_map_updated)

	if not NetworkManager.combat.attack_requested.is_connected(network._on_attack_requested):
		NetworkManager.combat.attack_requested.connect(network._on_attack_requested)

	if not NetworkManager.character.interaction_requested.is_connected(network._on_interaction_requested):
		NetworkManager.character.interaction_requested.connect(network._on_interaction_requested)
	if not NetworkManager.character.character_action_payload_received.is_connected(network._on_action_profile_payload_received):
		NetworkManager.character.character_action_payload_received.connect(network._on_action_profile_payload_received)
	if not NetworkManager.combat.combat_action_payload_received.is_connected(network._on_action_profile_payload_received):
		NetworkManager.combat.combat_action_payload_received.connect(network._on_action_profile_payload_received)
	if not NetworkManager.inventory.inventory_action_payload_received.is_connected(network._on_action_profile_payload_received):
		NetworkManager.inventory.inventory_action_payload_received.connect(network._on_action_profile_payload_received)

	if not NetworkManager.entity.object_state_received.is_connected(network._on_object_state_received):
		NetworkManager.entity.object_state_received.connect(network._on_object_state_received)

	if not NetworkManager.character.entity_move_received.is_connected(network._on_entity_move_received):
		NetworkManager.character.entity_move_received.connect(network._on_entity_move_received)

	if not NetworkManager.character.entity_move_requested.is_connected(network._on_entity_move_requested):
		NetworkManager.character.entity_move_requested.connect(network._on_entity_move_requested)

	if not NetworkManager.combat.entity_attack_received.is_connected(network._on_entity_attack_received):
		NetworkManager.combat.entity_attack_received.connect(network._on_entity_attack_received)

	if not NetworkManager.combat.entity_attack_result_received.is_connected(network._on_entity_attack_result_received):
		NetworkManager.combat.entity_attack_result_received.connect(network._on_entity_attack_result_received)

	if not NetworkManager.combat.entity_health_received.is_connected(network._on_entity_health_received):
		NetworkManager.combat.entity_health_received.connect(network._on_entity_health_received)

	if not NetworkManager.combat.entity_vitality_received.is_connected(network._on_entity_vitality_received):
		NetworkManager.combat.entity_vitality_received.connect(network._on_entity_vitality_received)

	if not NetworkManager.entity.entity_ai_state_received.is_connected(network._on_entity_ai_state_received):
		NetworkManager.entity.entity_ai_state_received.connect(network._on_entity_ai_state_received)

	if not NetworkManager.entity.entity_respawn_received.is_connected(network._on_entity_respawn_received):
		NetworkManager.entity.entity_respawn_received.connect(network._on_entity_respawn_received)

	if not NetworkManager.entity.entity_removed_received.is_connected(network._on_entity_removed_received):
		NetworkManager.entity.entity_removed_received.connect(network._on_entity_removed_received)

	if not NetworkManager.inventory.inventory_add_requested.is_connected(network._on_inventory_add_requested):
		NetworkManager.inventory.inventory_add_requested.connect(network._on_inventory_add_requested)

	if not NetworkManager.inventory.inventory_move_requested.is_connected(network._on_inventory_move_requested):
		NetworkManager.inventory.inventory_move_requested.connect(network._on_inventory_move_requested)

	if not NetworkManager.inventory.inventory_delete_requested.is_connected(network._on_inventory_delete_requested):
		NetworkManager.inventory.inventory_delete_requested.connect(network._on_inventory_delete_requested)

	if not NetworkManager.inventory.inventory_use_requested.is_connected(network._on_inventory_use_requested):
		NetworkManager.inventory.inventory_use_requested.connect(network._on_inventory_use_requested)

	if not NetworkManager.inventory.inventory_snapshot_received.is_connected(network._on_inventory_snapshot_received):
		NetworkManager.inventory.inventory_snapshot_received.connect(network._on_inventory_snapshot_received)

	if not NetworkManager.match_channel.match_end_requested.is_connected(network._on_end_game_requested):
		NetworkManager.match_channel.match_end_requested.connect(network._on_end_game_requested)


func disconnect_signals() -> void:
	if GameSession.session_cleared.is_connected(network._on_session_cleared):
		GameSession.session_cleared.disconnect(network._on_session_cleared)
	if network.runtime.action_stream != null and network.runtime.action_stream.action_started.is_connected(network._on_stream_action_started):
		network.runtime.action_stream.action_started.disconnect(network._on_stream_action_started)
	if network.runtime.action_stream != null and network.runtime.action_stream.action_completed.is_connected(network._on_stream_action_finished):
		network.runtime.action_stream.action_completed.disconnect(network._on_stream_action_finished)
	if network.runtime.action_stream != null and network.runtime.action_stream.action_cancelled.is_connected(network._on_stream_action_cancelled):
		network.runtime.action_stream.action_cancelled.disconnect(network._on_stream_action_cancelled)
	if network.runtime.action_stream != null and network.runtime.action_stream.remote_snapshot_committed.is_connected(network._on_remote_snapshot_committed):
		network.runtime.action_stream.remote_snapshot_committed.disconnect(network._on_remote_snapshot_committed)
	if NetworkManager.actions.action_accepted.is_connected(network._on_action_accepted):
		NetworkManager.actions.action_accepted.disconnect(network._on_action_accepted)
	if NetworkManager.actions.action_rejected.is_connected(network._on_action_rejected):
		NetworkManager.actions.action_rejected.disconnect(network._on_action_rejected)
	if NetworkManager.peers.peer_map_updated.is_connected(network._on_peer_map_updated):
		NetworkManager.peers.peer_map_updated.disconnect(network._on_peer_map_updated)

	if NetworkManager.combat.attack_requested.is_connected(network._on_attack_requested):
		NetworkManager.combat.attack_requested.disconnect(network._on_attack_requested)

	if NetworkManager.character.interaction_requested.is_connected(network._on_interaction_requested):
		NetworkManager.character.interaction_requested.disconnect(network._on_interaction_requested)
	if NetworkManager.character.character_action_payload_received.is_connected(network._on_action_profile_payload_received):
		NetworkManager.character.character_action_payload_received.disconnect(network._on_action_profile_payload_received)
	if NetworkManager.combat.combat_action_payload_received.is_connected(network._on_action_profile_payload_received):
		NetworkManager.combat.combat_action_payload_received.disconnect(network._on_action_profile_payload_received)
	if NetworkManager.inventory.inventory_action_payload_received.is_connected(network._on_action_profile_payload_received):
		NetworkManager.inventory.inventory_action_payload_received.disconnect(network._on_action_profile_payload_received)

	if NetworkManager.entity.object_state_received.is_connected(network._on_object_state_received):
		NetworkManager.entity.object_state_received.disconnect(network._on_object_state_received)

	if NetworkManager.character.entity_move_received.is_connected(network._on_entity_move_received):
		NetworkManager.character.entity_move_received.disconnect(network._on_entity_move_received)

	if NetworkManager.character.entity_move_requested.is_connected(network._on_entity_move_requested):
		NetworkManager.character.entity_move_requested.disconnect(network._on_entity_move_requested)

	if NetworkManager.combat.entity_attack_received.is_connected(network._on_entity_attack_received):
		NetworkManager.combat.entity_attack_received.disconnect(network._on_entity_attack_received)

	if NetworkManager.combat.entity_attack_result_received.is_connected(network._on_entity_attack_result_received):
		NetworkManager.combat.entity_attack_result_received.disconnect(network._on_entity_attack_result_received)

	if NetworkManager.combat.entity_health_received.is_connected(network._on_entity_health_received):
		NetworkManager.combat.entity_health_received.disconnect(network._on_entity_health_received)

	if NetworkManager.combat.entity_vitality_received.is_connected(network._on_entity_vitality_received):
		NetworkManager.combat.entity_vitality_received.disconnect(network._on_entity_vitality_received)

	if NetworkManager.entity.entity_ai_state_received.is_connected(network._on_entity_ai_state_received):
		NetworkManager.entity.entity_ai_state_received.disconnect(network._on_entity_ai_state_received)

	if NetworkManager.entity.entity_respawn_received.is_connected(network._on_entity_respawn_received):
		NetworkManager.entity.entity_respawn_received.disconnect(network._on_entity_respawn_received)

	if NetworkManager.entity.entity_removed_received.is_connected(network._on_entity_removed_received):
		NetworkManager.entity.entity_removed_received.disconnect(network._on_entity_removed_received)

	if NetworkManager.inventory.inventory_add_requested.is_connected(network._on_inventory_add_requested):
		NetworkManager.inventory.inventory_add_requested.disconnect(network._on_inventory_add_requested)

	if NetworkManager.inventory.inventory_move_requested.is_connected(network._on_inventory_move_requested):
		NetworkManager.inventory.inventory_move_requested.disconnect(network._on_inventory_move_requested)

	if NetworkManager.inventory.inventory_delete_requested.is_connected(network._on_inventory_delete_requested):
		NetworkManager.inventory.inventory_delete_requested.disconnect(network._on_inventory_delete_requested)

	if NetworkManager.inventory.inventory_use_requested.is_connected(network._on_inventory_use_requested):
		NetworkManager.inventory.inventory_use_requested.disconnect(network._on_inventory_use_requested)

	if NetworkManager.inventory.inventory_snapshot_received.is_connected(network._on_inventory_snapshot_received):
		NetworkManager.inventory.inventory_snapshot_received.disconnect(network._on_inventory_snapshot_received)

	if NetworkManager.match_channel.match_end_requested.is_connected(network._on_end_game_requested):
		NetworkManager.match_channel.match_end_requested.disconnect(network._on_end_game_requested)

