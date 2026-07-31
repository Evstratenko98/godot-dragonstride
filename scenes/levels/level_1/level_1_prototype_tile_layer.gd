class_name Level1PrototypeTileLayer
extends TileMapLayer

@export var fill_rects: Array[Rect2i] = []
@export var cutout_rects: Array[Rect2i] = []
@export var source_id: int = 0
@export var atlas_coordinates: Vector2i = Vector2i.ZERO
@export var alternative_tile: int = 0


func _ready() -> void:
	clear()
	for fill_rect: Rect2i in fill_rects:
		_fill_rect(fill_rect)
	for cutout_rect: Rect2i in cutout_rects:
		_clear_rect(cutout_rect)


func _fill_rect(fill_rect: Rect2i) -> void:
	for y: int in range(fill_rect.position.y, fill_rect.end.y):
		for x: int in range(fill_rect.position.x, fill_rect.end.x):
			set_cell(Vector2i(x, y), source_id, atlas_coordinates, alternative_tile)


func _clear_rect(cutout_rect: Rect2i) -> void:
	for y: int in range(cutout_rect.position.y, cutout_rect.end.y):
		for x: int in range(cutout_rect.position.x, cutout_rect.end.x):
			erase_cell(Vector2i(x, y))
