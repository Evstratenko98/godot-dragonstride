class_name GameHud
extends CanvasLayer

signal end_game

const POINTING_HAND_CURSOR_TEXTURE: Texture2D = preload("res://art/pointers/hand_small_point_n.svg")
const POINTING_HAND_CURSOR_HOTSPOT := Vector2(15.0, 4.0)

@onready var inventory_bar: InventoryBar = get_node("InventoryBar") as InventoryBar
@onready var local_player_card: PlayerStatusCard = get_node("LocalPlayerCard") as PlayerStatusCard
@onready var turn_status_panel: TurnStatusPanel = get_node("TurnStatusPanel") as TurnStatusPanel
@onready var player_roster_panel: PlayerRosterPanel = get_node("PlayerRosterPanel") as PlayerRosterPanel

var runtime: WorldRuntime = null


func _ready() -> void:
	Input.set_custom_mouse_cursor(
		POINTING_HAND_CURSOR_TEXTURE,
		Input.CURSOR_POINTING_HAND,
		POINTING_HAND_CURSOR_HOTSPOT
	)
	Input.set_custom_mouse_cursor(
		POINTING_HAND_CURSOR_TEXTURE,
		Input.CURSOR_DRAG,
		POINTING_HAND_CURSOR_HOTSPOT
	)
	Input.set_custom_mouse_cursor(
		POINTING_HAND_CURSOR_TEXTURE,
		Input.CURSOR_CAN_DROP,
		POINTING_HAND_CURSOR_HOTSPOT
	)
	Input.set_custom_mouse_cursor(
		POINTING_HAND_CURSOR_TEXTURE,
		Input.CURSOR_FORBIDDEN,
		POINTING_HAND_CURSOR_HOTSPOT
	)
	_configure_interactive_cursor(self)
	if not get_tree().node_added.is_connected(_on_scene_tree_node_added):
		get_tree().node_added.connect(_on_scene_tree_node_added)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_scene_tree_node_added):
		get_tree().node_added.disconnect(_on_scene_tree_node_added)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_POINTING_HAND)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_DRAG)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_CAN_DROP)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_FORBIDDEN)


func configure_runtime(new_runtime: WorldRuntime) -> void:
	runtime = new_runtime
	if runtime == null:
		return
	inventory_bar.configure_runtime(runtime)
	turn_status_panel.configure_runtime(runtime)
	player_roster_panel.configure_runtime(runtime)


func bind_session() -> void:
	if runtime == null:
		return
	var local_player: PlayerCharacter = runtime.get_local_player()
	local_player_card.bind_player(local_player, "", true)
	if local_player != null:
		inventory_bar.bind_character(local_player)
	turn_status_panel.bind_session()
	player_roster_panel.bind_session()


func _configure_interactive_cursor(node: Node) -> void:
	var control: Control = node as Control
	if control is BaseButton or control is InventorySlotControl:
		control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for child: Node in node.get_children():
		_configure_interactive_cursor(child)


func _on_end_game_button_pressed() -> void:
	end_game.emit()


func _on_scene_tree_node_added(node: Node) -> void:
	if is_ancestor_of(node):
		_configure_interactive_cursor(node)
