extends Node

@onready var connection: NetworkConnectionChannel = get_node(^"Connection") as NetworkConnectionChannel
@onready var character: NetworkCharacterChannel = get_node(^"Character") as NetworkCharacterChannel
@onready var combat: NetworkCombatChannel = get_node(^"Combat") as NetworkCombatChannel
@onready var entity: NetworkEntityChannel = get_node(^"Entity") as NetworkEntityChannel
@onready var world: NetworkWorldChannel = get_node(^"World") as NetworkWorldChannel
@onready var inventory: NetworkInventoryChannel = get_node(^"Inventory") as NetworkInventoryChannel
@onready var turns: NetworkTurnChannel = get_node(^"Turns") as NetworkTurnChannel
@onready var spells: NetworkSpellChannel = get_node(^"Spells") as NetworkSpellChannel
@onready var actions: NetworkActionChannel = get_node(^"Actions") as NetworkActionChannel
@onready var match_channel: NetworkMatchChannel = get_node(^"Match") as NetworkMatchChannel

var peers: NetworkPeerRegistry = NetworkPeerRegistry.new()
var store: NetworkReplicationStore = NetworkReplicationStore.new()


func _ready() -> void:
	connection.configure_context(peers, store)
	character.configure_context(connection, peers, store)
	combat.configure_context(connection, peers, store)
	entity.configure_context(connection, peers, store)
	world.configure_context(connection, peers, store)
	inventory.configure_context(connection, peers, store)
	turns.configure_context(connection, peers, store)
	spells.configure_context(connection, peers, store)
	actions.configure_context(connection, peers, store)
	match_channel.configure_context(connection, peers, store)
