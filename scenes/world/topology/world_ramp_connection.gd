class_name WorldRampConnection
extends Node

enum TraversalKind {
	NORMAL,
	RAMP,
	JUMP,
}

@export var connection_id: String = ""
@export var low_surface: Vector3i = Vector3i.ZERO
@export var high_surface: Vector3i = Vector3i.ZERO
@export var low_input_direction: Vector2i = Vector2i.ZERO
@export var high_input_direction: Vector2i = Vector2i.ZERO
@export var visual_footprint: Array[Vector2i] = []
@export var blocked_lower_cells: Array[Vector2i] = []
@export var traversal_kind: TraversalKind = TraversalKind.RAMP


func get_other_surface(surface: Vector3i) -> Vector3i:
	if surface == low_surface:
		return high_surface
	if surface == high_surface:
		return low_surface
	return Vector3i(-1, -1, -1)


func get_input_direction(surface: Vector3i) -> Vector2i:
	if surface == low_surface:
		return low_input_direction
	if surface == high_surface:
		return high_input_direction
	return Vector2i.ZERO
