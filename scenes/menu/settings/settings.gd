extends Control

@onready var resolution_option_button: OptionButton = $VBoxContainer/ResolutionOptionButton

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 640),
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080)
]


func _ready() -> void:
	resolution_option_button.clear()

	var current_size := DisplayServer.window_get_size()

	for i in RESOLUTIONS.size():
		var resolution := RESOLUTIONS[i]
		resolution_option_button.add_item("%d x %d" % [resolution.x, resolution.y])

		if resolution == current_size:
			resolution_option_button.select(i)

	resolution_option_button.item_selected.connect(_on_resolution_selected)


func _on_resolution_selected(index: int) -> void:
	if index < 0 or index >= RESOLUTIONS.size():
		return

	var resolution := RESOLUTIONS[index]

	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(resolution)
	_center_window(resolution)


func _center_window(window_size: Vector2i) -> void:
	var screen := DisplayServer.window_get_current_screen()
	var usable_rect := DisplayServer.screen_get_usable_rect(screen)

	var centered_x := usable_rect.position.x + int((usable_rect.size.x - window_size.x) * 0.5)
	var centered_y := usable_rect.position.y + int((usable_rect.size.y - window_size.y) * 0.5)

	DisplayServer.window_set_position(Vector2i(centered_x, centered_y))


func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/main_menu/main_menu.tscn")
