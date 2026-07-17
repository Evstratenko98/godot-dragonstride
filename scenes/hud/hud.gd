extends CanvasLayer

signal end_game

@export var runtime_path: NodePath = ^"../WorldRuntime"

@onready var inventory_bar: InventoryBar = get_node("InventoryBar") as InventoryBar
@onready var action_status_label: Label = get_node("ActionStatusLabel") as Label

var runtime: WorldRuntime = null
var is_inventory_bound: bool = false
var action_status_deadline_msec: int = 0

const REJECTION_MESSAGES := {
	"wrong_match": "This action belongs to another match.",
	"stale_turn": "The turn has already changed.",
	"not_active_player": "You can act only during your turn.",
	"actor_busy": "This character is already performing an action.",
	"duplicate_request": "This action was already submitted.",
	"queue_full": "The action queue is full. Try again shortly.",
	"rate_limited": "Too many actions. Slow down.",
	"invalid_action": "This action is not available.",
	"actor_unavailable": "This character cannot act now.",
	"actor_disconnected": "This player is disconnected.",
	"stale_inventory": "The inventory changed. Its current state was restored.",
	"effect_failed": "The item effect could not be applied.",
	"invalid_payload": "The action data is invalid.",
	"payload_too_large": "The action data is too large.",
	"sequence_gap": "Synchronizing the current match state...",
	"state_sync_failed": "The match state could not be synchronized.",
	"world_turn": "Wait for the world turn to finish.",
}


func _ready() -> void:
	runtime = get_node(runtime_path) as WorldRuntime
	inventory_bar.configure_runtime(runtime)
	if not runtime.action_rejected.is_connected(_on_runtime_action_rejected):
		runtime.action_rejected.connect(_on_runtime_action_rejected)
	set_process(true)


func _process(_delta: float) -> void:
	if not is_inventory_bound:
		var local_player: PlayerCharacter = runtime.get_local_player()
		if local_player != null:
			inventory_bar.bind_character(local_player)
			is_inventory_bound = true
	if action_status_deadline_msec > 0 and Time.get_ticks_msec() >= action_status_deadline_msec:
		action_status_deadline_msec = 0
		action_status_label.text = ""


func _exit_tree() -> void:
	if runtime != null and runtime.action_rejected.is_connected(_on_runtime_action_rejected):
		runtime.action_rejected.disconnect(_on_runtime_action_rejected)


func _on_end_game_button_pressed() -> void:
	end_game.emit()


func _on_runtime_action_rejected(reason_code: String) -> void:
	action_status_label.text = str(REJECTION_MESSAGES.get(reason_code, "Action rejected."))
	action_status_deadline_msec = Time.get_ticks_msec() + 3000
