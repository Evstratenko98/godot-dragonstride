class_name GridObject
extends StaticBody2D

enum ObjectState {
	NORMAL,
	DESTROYED,
}

@export var occupied_offsets: Array[Vector2i] = [Vector2i.ZERO]
@export var object_id: String = ""
@export var normal_texture: Texture2D
@export var destroyed_texture: Texture2D
@export var object_state: ObjectState = ObjectState.NORMAL

@onready var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D


func _ready() -> void:
	_prepare_textures()
	apply_state_visual()


func get_occupied_cells(anchor_cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for offset in occupied_offsets:
		cells.append(anchor_cell + offset)

	return cells


func set_normal() -> void:
	object_state = ObjectState.NORMAL
	apply_state_visual()


func set_destroyed() -> void:
	object_state = ObjectState.DESTROYED
	apply_state_visual()


func take_damage() -> bool:
	if object_state == ObjectState.DESTROYED:
		return false

	set_destroyed()
	return true


func apply_network_state(network_state: int) -> void:
	if network_state == ObjectState.DESTROYED:
		set_destroyed()
	else:
		set_normal()


func apply_state_visual() -> void:
	if sprite == null:
		return

	if object_state == ObjectState.DESTROYED:
		sprite.texture = destroyed_texture
	else:
		sprite.texture = normal_texture


func _prepare_textures() -> void:
	if sprite != null and normal_texture == null:
		normal_texture = sprite.texture

	if destroyed_texture == null:
		destroyed_texture = normal_texture
