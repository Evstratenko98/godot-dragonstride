class_name FogWorldContentPresenter
extends Node2D

const PROXY_COLOR: Color = Color(0.48, 0.5, 0.54, 0.82)

var runtime: WorldRuntime = null
var proxy_by_object_id: Dictionary[String, Sprite2D] = {}
var proxy_surfaces_by_object_id: Dictionary[String, Array] = {}
var bound_entities: Array[Entity] = []
var effects_root: Node2D = null


func configure_context(new_runtime: WorldRuntime) -> void:
	_restore_live_nodes()
	_disconnect_entity_signals()
	_clear_proxies()
	runtime = new_runtime
	effects_root = null
	if runtime == null:
		return
	effects_root = runtime.get_node_or_null("SpellEffects") as Node2D
	if not runtime.get_tree().node_added.is_connected(_on_scene_tree_node_added):
		runtime.get_tree().node_added.connect(_on_scene_tree_node_added)
	for entity_value: Variant in runtime.get_registered_entities():
		_bind_entity(entity_value as Entity)
	refresh([], true)


func _exit_tree() -> void:
	_restore_live_nodes()
	_disconnect_entity_signals()


func refresh(changed_surfaces: Array[Vector3i], full_refresh: bool) -> void:
	if runtime == null or runtime.visibility == null:
		return
	if full_refresh:
		_update_all_entities()
		_update_all_static_objects()
		_update_effects({}, true)
		return
	if changed_surfaces.is_empty():
		return
	var dirty_surfaces: Dictionary[Vector3i, bool] = {}
	for surface: Vector3i in changed_surfaces:
		dirty_surfaces[surface] = true
	_update_entities_at_surfaces(changed_surfaces)
	_update_static_objects_at_surfaces(changed_surfaces, dirty_surfaces)
	_update_effects(dirty_surfaces, false)


func _update_all_entities() -> void:
	for entity: Entity in bound_entities:
		_update_entity_visibility(entity)


func _update_entities_at_surfaces(changed_surfaces: Array[Vector3i]) -> void:
	var updated_ids: Dictionary[String, bool] = {}
	for surface: Vector3i in changed_surfaces:
		var entity: Entity = runtime.get_entity_at_surface(surface) as Entity
		if entity == null or updated_ids.has(entity.entity_id):
			continue
		updated_ids[entity.entity_id] = true
		_update_entity_visibility(entity)


func _update_entity_visibility(entity: Entity) -> void:
	if entity == null or not is_instance_valid(entity):
		return
	var player_character: PlayerCharacter = entity as PlayerCharacter
	if (
		player_character != null
		and player_character.owner_player_id == runtime.visibility.get_local_player_id()
	):
		entity.visible = true
		return
	entity.visible = runtime.visibility.is_surface_visible_for_local_player(entity.current_surface)


func _update_all_static_objects() -> void:
	var local_player_id: String = runtime.visibility.get_local_player_id()
	var memories: Dictionary = runtime.visibility.get_object_memories(local_player_id)
	var live_ids: Dictionary[String, bool] = {}
	for object_value: Variant in runtime.get_registered_objects():
		var grid_object: GridObject = object_value as GridObject
		if grid_object == null or grid_object.object_id.is_empty():
			continue
		live_ids[grid_object.object_id] = true
		_update_live_object(grid_object, local_player_id, memories)
	for object_id_value: Variant in memories.keys():
		var object_id: String = str(object_id_value)
		if live_ids.has(object_id):
			continue
		_update_missing_object(object_id, memories[object_id_value] as Dictionary)
	for object_id: String in proxy_by_object_id.keys():
		if not memories.has(object_id):
			_set_proxy_visibility(object_id, false)


func _update_static_objects_at_surfaces(
	changed_surfaces: Array[Vector3i],
	dirty_surfaces: Dictionary[Vector3i, bool]
) -> void:
	var local_player_id: String = runtime.visibility.get_local_player_id()
	var memories: Dictionary = runtime.visibility.get_object_memories_for_surfaces(
		local_player_id,
		changed_surfaces
	)
	var touched_objects: Dictionary[String, GridObject] = {}
	for surface: Vector3i in dirty_surfaces.keys():
		var grid_object: GridObject = runtime.get_object_at_surface(surface) as GridObject
		if grid_object != null and not grid_object.object_id.is_empty():
			touched_objects[grid_object.object_id] = grid_object
	for grid_object: GridObject in touched_objects.values():
		_update_live_object(grid_object, local_player_id, memories)
	for object_id_value: Variant in memories.keys():
		var memory: Dictionary = memories[object_id_value] as Dictionary
		if not _surfaces_intersect(memory.get("occupied_surfaces", []), dirty_surfaces):
			continue
		var object_id: String = str(object_id_value)
		if not touched_objects.has(object_id):
			_update_missing_object(object_id, memory)
	for object_id: String in proxy_surfaces_by_object_id.keys():
		if runtime.visibility.has_object_memory(local_player_id, object_id):
			continue
		if _surfaces_intersect(proxy_surfaces_by_object_id[object_id], dirty_surfaces):
			_set_proxy_visibility(object_id, false)


func _update_live_object(grid_object: GridObject, local_player_id: String, memories: Dictionary) -> void:
	var mode: WorldVisibility.VisibilityMode = runtime.visibility.get_object_visibility_mode(local_player_id, grid_object)
	grid_object.visible = mode == WorldVisibility.VisibilityMode.VISIBLE
	if mode == WorldVisibility.VisibilityMode.VISIBLE:
		_update_proxy_from_live(grid_object)
	elif mode == WorldVisibility.VisibilityMode.EXPLORED and memories.has(grid_object.object_id):
		_update_proxy_from_memory(grid_object.object_id, memories[grid_object.object_id] as Dictionary, grid_object)
	_set_proxy_visibility(grid_object.object_id, mode == WorldVisibility.VisibilityMode.EXPLORED)


func _update_missing_object(object_id: String, memory: Dictionary) -> void:
	var surface: Vector3i = memory.get("surface", WorldGridTopology.INVALID_SURFACE)
	_update_proxy_from_memory(object_id, memory, null)
	_set_proxy_visibility(
		object_id,
		runtime.visibility.get_local_visibility_mode(surface) == WorldVisibility.VisibilityMode.EXPLORED
	)


func _update_proxy_from_live(grid_object: GridObject) -> void:
	if grid_object.sprite == null:
		return
	var proxy: Sprite2D = _get_or_create_proxy(grid_object.object_id)
	proxy.texture = grid_object.sprite.texture
	proxy.global_transform = grid_object.sprite.global_transform
	proxy.offset = grid_object.sprite.offset
	proxy.centered = grid_object.sprite.centered
	proxy.hframes = grid_object.sprite.hframes
	proxy.vframes = grid_object.sprite.vframes
	proxy.frame = grid_object.sprite.frame
	proxy.modulate = PROXY_COLOR
	proxy.z_index = 1
	proxy.visible = false
	var anchor: Vector3i = runtime.spatial.get_object_anchor_surface(grid_object)
	proxy_surfaces_by_object_id[grid_object.object_id] = grid_object.get_occupied_surfaces(anchor)


func _update_proxy_from_memory(object_id: String, memory: Dictionary, live_object: GridObject) -> void:
	var texture_path: String = str(memory.get("texture_path", ""))
	if texture_path.is_empty():
		return
	var texture: Texture2D = load(texture_path) as Texture2D
	if texture == null:
		return
	var proxy: Sprite2D = _get_or_create_proxy(object_id)
	proxy.texture = texture
	if live_object != null and live_object.sprite != null:
		proxy.global_transform = live_object.sprite.global_transform
	else:
		var surface: Vector3i = memory.get("surface", WorldGridTopology.INVALID_SURFACE)
		proxy.global_position = runtime.surface_to_world(surface) + (memory.get("sprite_position", Vector2.ZERO) as Vector2)
		proxy.scale = memory.get("sprite_scale", Vector2.ONE) as Vector2
	proxy.offset = memory.get("sprite_offset", Vector2.ZERO) as Vector2
	proxy.centered = bool(memory.get("sprite_centered", true))
	proxy.modulate = (memory.get("sprite_modulate", Color.WHITE) as Color) * PROXY_COLOR
	proxy.z_index = 1
	proxy_surfaces_by_object_id[object_id] = (memory.get("occupied_surfaces", []) as Array).duplicate()


func _get_or_create_proxy(object_id: String) -> Sprite2D:
	var proxy: Sprite2D = proxy_by_object_id.get(object_id) as Sprite2D
	if proxy != null:
		return proxy
	proxy = Sprite2D.new()
	proxy.name = "LastSeen_" + object_id
	proxy_by_object_id[object_id] = proxy
	add_child.call_deferred(proxy)
	return proxy


func _set_proxy_visibility(object_id: String, should_show: bool) -> void:
	var proxy: Sprite2D = proxy_by_object_id.get(object_id) as Sprite2D
	if proxy != null:
		proxy.visible = should_show


func _update_effects(dirty_surfaces: Dictionary[Vector3i, bool], full_refresh: bool) -> void:
	if effects_root == null:
		return
	for effect: Node in effects_root.get_children():
		var node_2d: Node2D = effect as Node2D
		if node_2d == null:
			continue
		var surface: Vector3i = runtime.resolve_surface_at_world(node_2d.global_position, 0)
		if full_refresh or dirty_surfaces.has(surface):
			_update_effect_visibility(node_2d)


func _update_effect_visibility(effect: Node2D) -> void:
	if effect == null or runtime == null or runtime.visibility == null:
		return
	var surface: Vector3i = runtime.resolve_surface_at_world(effect.global_position, 0)
	effect.visible = runtime.visibility.is_surface_visible_for_local_player(surface)


func _bind_entity(entity: Entity) -> void:
	if entity == null or bound_entities.has(entity):
		return
	bound_entities.append(entity)
	var movement_callable: Callable = _on_entity_movement_finished.bind(entity)
	var exiting_callable: Callable = _on_entity_tree_exiting.bind(entity)
	if not entity.movement_finished.is_connected(movement_callable):
		entity.movement_finished.connect(movement_callable)
	if not entity.tree_exiting.is_connected(exiting_callable):
		entity.tree_exiting.connect(exiting_callable)
	_update_entity_visibility(entity)


func _unbind_entity(entity: Entity) -> void:
	if entity == null:
		return
	var movement_callable: Callable = _on_entity_movement_finished.bind(entity)
	var exiting_callable: Callable = _on_entity_tree_exiting.bind(entity)
	if entity.movement_finished.is_connected(movement_callable):
		entity.movement_finished.disconnect(movement_callable)
	if entity.tree_exiting.is_connected(exiting_callable):
		entity.tree_exiting.disconnect(exiting_callable)
	bound_entities.erase(entity)


func _disconnect_entity_signals() -> void:
	if runtime != null and runtime.is_inside_tree():
		var scene_tree: SceneTree = runtime.get_tree()
		if scene_tree.node_added.is_connected(_on_scene_tree_node_added):
			scene_tree.node_added.disconnect(_on_scene_tree_node_added)
	for entity: Entity in bound_entities.duplicate():
		_unbind_entity(entity)
	bound_entities.clear()


func _restore_live_nodes() -> void:
	for entity: Entity in bound_entities:
		if is_instance_valid(entity):
			entity.visible = true
	if runtime != null:
		for object_value: Variant in runtime.get_registered_objects():
			if object_value is CanvasItem:
				(object_value as CanvasItem).visible = true


func _clear_proxies() -> void:
	for proxy: Sprite2D in proxy_by_object_id.values():
		if is_instance_valid(proxy):
			proxy.queue_free()
	proxy_by_object_id.clear()
	proxy_surfaces_by_object_id.clear()


func _surfaces_intersect(surface_values: Array, dirty_surfaces: Dictionary[Vector3i, bool]) -> bool:
	for surface_value: Variant in surface_values:
		if surface_value is Vector3i and dirty_surfaces.has(surface_value as Vector3i):
			return true
	return false


func _on_scene_tree_node_added(node: Node) -> void:
	var entity: Entity = node as Entity
	if entity != null:
		_bind_entity.call_deferred(entity)
		return
	var effect: Node2D = node as Node2D
	if effect != null and effects_root != null and effects_root.is_ancestor_of(effect):
		_update_effect_visibility.call_deferred(effect)


func _on_entity_movement_finished(
	_from_surface: Vector3i,
	_target_surface: Vector3i,
	entity: Entity
) -> void:
	_update_entity_visibility(entity)


func _on_entity_tree_exiting(entity: Entity) -> void:
	_unbind_entity(entity)
