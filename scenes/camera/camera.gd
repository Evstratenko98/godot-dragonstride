class_name GameCamera
extends Camera2D

const MODE_FOLLOW := "follow"
const MODE_FREE := "free"

@export_enum("follow", "free") var camera_mode: String = MODE_FOLLOW
@export_node_path("Node2D") var target_path: NodePath
@export var edge_size: float = 16.0
@export var free_speed: float = 500.0
@export var follow_smoothing: float = 8.0
@export_range(0.1, 1.0, 0.1) var minimum_zoom: float = 0.5
@export_range(1.0, 4.0, 0.1) var maximum_zoom: float = 2.0
@export_range(0.01, 1.0, 0.01) var zoom_step: float = 0.1
@export var zoom_smoothing: float = 10.0

var target: Node2D = null
var allows_console_commands: bool = false
var target_zoom_factor: float = 1.0
var world_bounds: Rect2 = Rect2()
var has_world_bounds: bool = false


func _ready() -> void:
	if not target_path.is_empty():
		target = get_node_or_null(target_path) as Node2D
	target_zoom_factor = clampf(zoom.x, minimum_zoom, maximum_zoom)
	zoom = Vector2.ONE * target_zoom_factor
	make_current()
	if allows_console_commands:
		_register_console_commands()


func _exit_tree() -> void:
	var console: Node = get_node_or_null("/root/Console")
	if console == null or not console.has_method("remove_command"):
		return

	console.remove_command("game_camera_mode_follow")
	console.remove_command("game_camera_mode_free")


func _process(delta: float) -> void:
	_update_zoom(delta)
	if camera_mode == MODE_FOLLOW:
		if target != null:
			if follow_smoothing <= 0.0:
				global_position = target.global_position
			else:
				var follow_weight: float = 1.0 - exp(-follow_smoothing * delta)
				global_position = global_position.lerp(target.global_position, follow_weight)
	else:
		_move_free(delta)
		_clamp_to_world_bounds()


func _unhandled_input(event: InputEvent) -> void:
	if not is_current():
		return

	var mouse_button_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button_event == null or not mouse_button_event.pressed:
		return

	var zoom_direction: float = 0.0
	if mouse_button_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		zoom_direction = 1.0
	elif mouse_button_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		zoom_direction = -1.0
	else:
		return

	var zoom_delta: float = zoom_direction * zoom_step * mouse_button_event.factor
	target_zoom_factor = clampf(target_zoom_factor + zoom_delta, minimum_zoom, maximum_zoom)
	get_viewport().set_input_as_handled()


func configure_world_bounds(new_world_bounds: Rect2) -> void:
	world_bounds = new_world_bounds
	has_world_bounds = world_bounds.size.x > 0.0 and world_bounds.size.y > 0.0
	if camera_mode == MODE_FREE:
		_clamp_to_world_bounds()


func set_camera_mode(new_mode: String) -> void:
	if new_mode != MODE_FOLLOW and new_mode != MODE_FREE:
		ConsoleOutput.print_console("Unknown camera mode: %s" % new_mode)
		return

	camera_mode = new_mode
	if camera_mode == MODE_FREE:
		_clamp_to_world_bounds()
	ConsoleOutput.print_console("Camera mode: %s" % camera_mode)


func console_follow() -> void:
	if not allows_console_commands:
		return
	set_camera_mode(MODE_FOLLOW)


func console_free() -> void:
	if not allows_console_commands:
		return
	set_camera_mode(MODE_FREE)


func _move_free(delta: float) -> void:
	var mouse_position: Vector2 = get_viewport().get_mouse_position()
	var viewport_size: Vector2 = get_viewport_rect().size
	var direction: Vector2 = Vector2.ZERO

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


func _update_zoom(delta: float) -> void:
	if is_equal_approx(zoom.x, target_zoom_factor):
		zoom = Vector2.ONE * target_zoom_factor
		return

	if zoom_smoothing <= 0.0:
		zoom = Vector2.ONE * target_zoom_factor
		return

	var zoom_weight: float = 1.0 - exp(-zoom_smoothing * delta)
	var zoom_factor: float = lerpf(zoom.x, target_zoom_factor, zoom_weight)
	zoom = Vector2.ONE * zoom_factor


func _clamp_to_world_bounds() -> void:
	if not has_world_bounds:
		return

	var minimum_position: Vector2 = world_bounds.position
	var maximum_position: Vector2 = world_bounds.end
	global_position = Vector2(
		clampf(global_position.x, minimum_position.x, maximum_position.x),
		clampf(global_position.y, minimum_position.y, maximum_position.y)
	)


func _register_console_commands() -> void:
	var console: Node = get_node_or_null("/root/Console")
	if console == null or not console.has_method("add_command"):
		return

	console.add_command("game_camera_mode_follow", console_follow, 0, 0, "Follow the game character.")
	console.add_command("game_camera_mode_free", console_free, 0, 0, "Move the camera freely near screen edges.")
