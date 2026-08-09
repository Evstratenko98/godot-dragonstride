class_name GridObject
extends StaticBody2D

enum ObjectState {
	NORMAL,
	DESTROYED,
	OPENED,
}

@export var occupied_offsets: Array[Vector2i] = [Vector2i.ZERO]
@export_range(0, 15, 1) var surface_height: int = 0
@export var blocks_vision: bool = false
@export var is_large_visual_object: bool = false
@export var object_id: String = ""
@export var normal_texture: Texture2D
@export var destroyed_texture: Texture2D
@export var object_state: ObjectState = ObjectState.NORMAL

@onready var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D


func _ready() -> void:
	z_index = surface_height * 20 + 10
	_prepare_textures()
	apply_state_visual()


func get_occupied_surfaces(anchor_surface: Vector3i) -> Array[Vector3i]:
	var surfaces: Array[Vector3i] = []
	for offset: Vector2i in occupied_offsets:
		surfaces.append(Vector3i(
			anchor_surface.x + offset.x,
			anchor_surface.y + offset.y,
			anchor_surface.z
		))
	return surfaces


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


func interact(_interactor: PlayerCharacter, _world_runtime: WorldRuntime) -> bool:
	return false


func can_interact(_interactor: PlayerCharacter, _world_runtime: WorldRuntime) -> bool:
	return false


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
