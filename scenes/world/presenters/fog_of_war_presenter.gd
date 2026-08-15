class_name FogOfWarPresenter
extends Node2D

const CHUNK_SIZE: int = 8

var runtime: WorldRuntime = null
var level: WorldLevel = null
var chunks_by_coordinates: Dictionary[Vector2i, FogChunkPresenter] = {}
var chunk_generation: int = 0
@onready var content_presenter: FogWorldContentPresenter = get_node("WorldContentPresenter") as FogWorldContentPresenter


func configure_context(new_runtime: WorldRuntime, new_level: WorldLevel) -> void:
	_disconnect_visibility()
	_clear_chunks()
	runtime = new_runtime
	level = new_level
	content_presenter.configure_context(runtime)
	if runtime != null and runtime.visibility != null:
		if not runtime.visibility.local_visibility_changed.is_connected(_on_local_visibility_changed):
			runtime.visibility.local_visibility_changed.connect(_on_local_visibility_changed)
	chunk_generation += 1
	_rebuild_chunks.call_deferred(chunk_generation)


func _exit_tree() -> void:
	_disconnect_visibility()
	content_presenter.configure_context(null)


func _rebuild_chunks(expected_generation: int) -> void:
	if expected_generation != chunk_generation or runtime == null or runtime.visibility == null:
		return
	_clear_chunks()
	var surfaces_by_chunk: Dictionary[Vector2i, Array] = {}
	for surface: Vector3i in runtime.visibility.display_surfaces:
		var chunk_coordinates: Vector2i = _get_chunk_coordinates(surface)
		if not surfaces_by_chunk.has(chunk_coordinates):
			surfaces_by_chunk[chunk_coordinates] = []
		(surfaces_by_chunk[chunk_coordinates] as Array).append(surface)
	for chunk_coordinates: Vector2i in surfaces_by_chunk.keys():
		var chunk_surfaces: Array[Vector3i] = []
		for surface_value: Variant in surfaces_by_chunk[chunk_coordinates]:
			chunk_surfaces.append(surface_value as Vector3i)
		var chunk: FogChunkPresenter = FogChunkPresenter.new()
		chunk.name = "FogChunk_%d_%d" % [chunk_coordinates.x, chunk_coordinates.y]
		if not chunk.configure_context(runtime, chunk_surfaces):
			chunk.free()
			continue
		chunks_by_coordinates[chunk_coordinates] = chunk
		add_child.call_deferred(chunk)


func _refresh_dirty_chunks(changed_surfaces: Array[Vector3i]) -> void:
	var surfaces_by_chunk: Dictionary[Vector2i, Dictionary] = {}
	for changed_surface: Vector3i in changed_surfaces:
		var cell: Vector2i = Vector2i(changed_surface.x, changed_surface.y)
		if not runtime.visibility.display_surface_by_cell.has(cell):
			continue
		var display_surface: Vector3i = runtime.visibility.display_surface_by_cell[cell]
		var chunk_coordinates: Vector2i = _get_chunk_coordinates(display_surface)
		if not surfaces_by_chunk.has(chunk_coordinates):
			surfaces_by_chunk[chunk_coordinates] = {}
		(surfaces_by_chunk[chunk_coordinates] as Dictionary)[display_surface] = true
	for chunk_coordinates: Vector2i in surfaces_by_chunk.keys():
		var chunk: FogChunkPresenter = chunks_by_coordinates.get(chunk_coordinates) as FogChunkPresenter
		if chunk == null:
			continue
		var chunk_surfaces: Array[Vector3i] = []
		for surface_value: Variant in (surfaces_by_chunk[chunk_coordinates] as Dictionary).keys():
			chunk_surfaces.append(surface_value as Vector3i)
		chunk.refresh_surfaces(chunk_surfaces)


func _refresh_all_chunks() -> void:
	for chunk: FogChunkPresenter in chunks_by_coordinates.values():
		if is_instance_valid(chunk):
			chunk.refresh_all()


func _clear_chunks() -> void:
	for chunk: FogChunkPresenter in chunks_by_coordinates.values():
		if is_instance_valid(chunk):
			chunk.queue_free()
	chunks_by_coordinates.clear()


func _get_chunk_coordinates(surface: Vector3i) -> Vector2i:
	return Vector2i(floori(float(surface.x) / CHUNK_SIZE), floori(float(surface.y) / CHUNK_SIZE))


func _disconnect_visibility() -> void:
	if runtime == null or runtime.visibility == null:
		return
	if runtime.visibility.local_visibility_changed.is_connected(_on_local_visibility_changed):
		runtime.visibility.local_visibility_changed.disconnect(_on_local_visibility_changed)


func _on_local_visibility_changed(changed_surfaces: Array[Vector3i], full_refresh: bool) -> void:
	if runtime == null or runtime.visibility == null:
		return
	content_presenter.refresh(changed_surfaces, full_refresh)
	if full_refresh:
		_refresh_all_chunks()
		return
	_refresh_dirty_chunks(changed_surfaces)
