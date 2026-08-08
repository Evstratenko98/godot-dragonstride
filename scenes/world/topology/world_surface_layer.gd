class_name WorldSurfaceLayer
extends Node

@export_range(0, 15, 1) var elevation: int = 0
@export var source_layer_path: NodePath
@export var explicit_cells: Array[Vector2i] = []
@export var excluded_cells: Array[Vector2i] = []
@export var character_only: bool = false
@export var display_name: String = "ground"


func collect_surfaces(level: WorldLevel) -> Array[Vector3i]:
	var surfaces: Array[Vector3i] = []
	var seen: Dictionary[Vector2i, bool] = {}
	if level != null and not source_layer_path.is_empty():
		var source_layer: TileMapLayer = level.get_node_or_null(source_layer_path) as TileMapLayer
		if source_layer != null:
			for cell: Vector2i in source_layer.get_used_cells():
				if not excluded_cells.has(cell):
					seen[cell] = true
	for cell: Vector2i in explicit_cells:
		if not excluded_cells.has(cell):
			seen[cell] = true
	for cell: Vector2i in seen.keys():
		surfaces.append(Vector3i(cell.x, cell.y, elevation))
	return surfaces
