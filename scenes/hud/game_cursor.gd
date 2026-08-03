extends Node

const DEFAULT_CURSOR_TEXTURE: Texture2D = preload("res://art/pointers/hand_small_point_n.svg")
const DEFAULT_CURSOR_HOTSPOT := Vector2(15.0, 4.0)
const DEFAULT_CURSOR_SHAPES: Array[int] = [
	Input.CURSOR_ARROW,
	Input.CURSOR_IBEAM,
	Input.CURSOR_POINTING_HAND,
	Input.CURSOR_CROSS,
	Input.CURSOR_WAIT,
	Input.CURSOR_BUSY,
	Input.CURSOR_DRAG,
	Input.CURSOR_CAN_DROP,
	Input.CURSOR_FORBIDDEN,
	Input.CURSOR_VSIZE,
	Input.CURSOR_HSIZE,
	Input.CURSOR_BDIAGSIZE,
	Input.CURSOR_FDIAGSIZE,
	Input.CURSOR_MOVE,
	Input.CURSOR_VSPLIT,
	Input.CURSOR_HSPLIT,
	Input.CURSOR_HELP,
]


func _enter_tree() -> void:
	register_default_cursors()


func register_default_cursors() -> void:
	for cursor_shape: int in DEFAULT_CURSOR_SHAPES:
		restore_default_cursor(cursor_shape)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func restore_default_cursor(cursor_shape: int = Input.CURSOR_ARROW) -> void:
	Input.set_custom_mouse_cursor(
		DEFAULT_CURSOR_TEXTURE,
		cursor_shape,
		DEFAULT_CURSOR_HOTSPOT
	)
