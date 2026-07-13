extends CanvasLayer

signal end_game

@export var runtime_path: NodePath = ^"../WorldRuntime"

@onready var inventory_bar: InventoryBar = get_node("InventoryBar") as InventoryBar

var runtime: WorldRuntime = null


func _ready() -> void:
	runtime = get_node(runtime_path) as WorldRuntime
	inventory_bar.configure_runtime(runtime)
	set_process(true)


func _process(_delta: float) -> void:
	var local_player: PlayerCharacter = runtime.get_local_player()
	if local_player == null:
		return

	inventory_bar.bind_character(local_player)
	set_process(false)


func _on_end_game_button_pressed() -> void:
	end_game.emit()
