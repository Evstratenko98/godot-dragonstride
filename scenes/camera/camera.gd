extends Camera2D

const MODE_FOLLOW := "follow"
const MODE_FREE := "free"

@export_enum("follow", "free") var camera_mode := MODE_FOLLOW
@export_node_path("Node2D") var target_path: NodePath
@export var edge_size := 16.0
@export var free_speed := 500.0
@export var follow_smoothing := 8.0

var target: Node2D = null


func _ready() -> void:
	target = get_node_or_null(target_path)
	make_current()
	_register_console_commands()


func _exit_tree() -> void:
	var console := get_node_or_null("/root/Console")
	if console == null or not console.has_method("remove_command"):
		return

	console.remove_command("game_camera_mode_follow")
	console.remove_command("game_camera_mode_free")


func _process(delta: float) -> void:
	if camera_mode == MODE_FOLLOW:
		if target != null:
			if follow_smoothing <= 0.0:
				global_position = target.global_position
			else:
				var follow_weight := 1.0 - exp(-follow_smoothing * delta)
				global_position = global_position.lerp(target.global_position, follow_weight)
	else:
		_move_free(delta)


func set_camera_mode(new_mode: String) -> void:
	if new_mode != MODE_FOLLOW and new_mode != MODE_FREE:
		ConsoleOutput.print_console("Unknown camera mode: %s" % new_mode)
		return

	camera_mode = new_mode
	ConsoleOutput.print_console("Camera mode: %s" % camera_mode)


func console_follow() -> void:
	set_camera_mode(MODE_FOLLOW)


func console_free() -> void:
	set_camera_mode(MODE_FREE)


func _move_free(delta: float) -> void:
	var mouse_position := get_viewport().get_mouse_position()
	var viewport_size := get_viewport_rect().size
	var direction := Vector2.ZERO

	if mouse_position.x <= edge_size:
		direction.x -= 1.0
	elif mouse_position.x >= viewport_size.x - edge_size:
		direction.x += 1.0

	if mouse_position.y <= edge_size:
		direction.y -= 1.0
	elif mouse_position.y >= viewport_size.y - edge_size:
		direction.y += 1.0

	if direction != Vector2.ZERO:
		global_position += direction.normalized() * free_speed * delta


func _register_console_commands() -> void:
	var console := get_node_or_null("/root/Console")
	if console == null or not console.has_method("add_command"):
		return

	console.add_command("game_camera_mode_follow", console_follow, 0, 0, "Follow the game character.")
	console.add_command("game_camera_mode_free", console_free, 0, 0, "Move the camera freely near screen edges.")
