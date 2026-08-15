class_name WorldVisibilityObjectChangeCoordinator
extends RefCounted

signal visibility_structure_changed
signal object_surfaces_changed(surfaces: Array[Vector3i])

var runtime: WorldRuntime = null
var bound_objects: Array[GridObject] = []
var change_pending: bool = false
var generation: int = 0


func configure(new_runtime: WorldRuntime) -> void:
	disconnect_signals()
	runtime = new_runtime
	generation += 1
	if runtime == null:
		return
	if not runtime.get_tree().node_added.is_connected(_on_scene_tree_node_added):
		runtime.get_tree().node_added.connect(_on_scene_tree_node_added)
	for object_value: Variant in runtime.get_registered_objects():
		_bind_object(object_value as GridObject)


func disconnect_signals() -> void:
	generation += 1
	change_pending = false
	if runtime != null and runtime.is_inside_tree():
		var scene_tree: SceneTree = runtime.get_tree()
		if scene_tree.node_added.is_connected(_on_scene_tree_node_added):
			scene_tree.node_added.disconnect(_on_scene_tree_node_added)
	for grid_object: GridObject in bound_objects.duplicate():
		_unbind_object(grid_object)
	bound_objects.clear()
	runtime = null


func _bind_object(grid_object: GridObject) -> bool:
	if grid_object == null or not is_instance_valid(grid_object) or bound_objects.has(grid_object):
		return false
	bound_objects.append(grid_object)
	var exiting_callable: Callable = _on_object_tree_exiting.bind(grid_object)
	if not grid_object.tree_exiting.is_connected(exiting_callable):
		grid_object.tree_exiting.connect(exiting_callable)
	return true


func _unbind_object(grid_object: GridObject) -> void:
	if grid_object == null:
		return
	var exiting_callable: Callable = _on_object_tree_exiting.bind(grid_object)
	if grid_object.tree_exiting.is_connected(exiting_callable):
		grid_object.tree_exiting.disconnect(exiting_callable)
	bound_objects.erase(grid_object)


func _schedule_structure_change() -> void:
	if change_pending:
		return
	change_pending = true
	_emit_structure_change.call_deferred(generation)


func _emit_structure_change(expected_generation: int) -> void:
	if expected_generation != generation or not change_pending:
		return
	change_pending = false
	visibility_structure_changed.emit()


func _on_scene_tree_node_added(node: Node) -> void:
	var grid_object: GridObject = node as GridObject
	if grid_object != null:
		_bind_new_object.call_deferred(grid_object)


func _bind_new_object(grid_object: GridObject) -> void:
	if _bind_object(grid_object):
		if grid_object.blocks_vision:
			_schedule_structure_change()
		else:
			object_surfaces_changed.emit(_get_object_surfaces(grid_object))


func _on_object_tree_exiting(grid_object: GridObject) -> void:
	var affected_surfaces: Array[Vector3i] = _get_object_surfaces(grid_object)
	var was_vision_blocker: bool = grid_object.blocks_vision
	_unbind_object(grid_object)
	if was_vision_blocker:
		_schedule_structure_change()
	else:
		object_surfaces_changed.emit(affected_surfaces)


func _get_object_surfaces(grid_object: GridObject) -> Array[Vector3i]:
	if runtime == null or grid_object == null:
		return []
	var anchor: Vector3i = runtime.spatial.get_object_anchor_surface(grid_object)
	return grid_object.get_occupied_surfaces(anchor)
