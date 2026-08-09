class_name FogOfWarPresenter
extends Node2D

const HIDDEN_COLOR := Color(0.025, 0.03, 0.045, 0.98)
const PROXY_COLOR := Color(0.48, 0.5, 0.54, 0.82)
const CLOUD_TEXTURE: Texture2D = preload(
	"res://art/Tiny Swords (Free Pack)/Terrain/Decorations/Clouds/Clouds_01.png"
)

var runtime: WorldRuntime = null
var level: WorldLevel = null
var proxy_by_object_id: Dictionary[String, Sprite2D] = {}
@onready var explored_layer: Node2D = get_node("ExploredLayer") as Node2D


func configure_context(new_runtime: WorldRuntime, new_level: WorldLevel) -> void:
	_disconnect_visibility()
	_restore_live_nodes()
	_clear_proxies()
	runtime = new_runtime
	level = new_level
	explored_layer.call("configure_context", runtime)
	if runtime != null and runtime.visibility != null:
		if not runtime.visibility.local_visibility_changed.is_connected(_refresh):
			runtime.visibility.local_visibility_changed.connect(_refresh)
		if not runtime.visibility.fog_enabled_changed.is_connected(_on_fog_enabled_changed):
			runtime.visibility.fog_enabled_changed.connect(_on_fog_enabled_changed)
	_refresh()


func _exit_tree() -> void:
	_disconnect_visibility()
	_restore_live_nodes()


func _draw() -> void:
	if runtime == null or runtime.visibility == null or not runtime.visibility.fog_enabled:
		return
	var cell_extent: float = float(runtime.get_cell_size())
	var cell_size: Vector2 = Vector2(cell_extent, cell_extent)
	for surface: Vector3i in runtime.visibility.display_surfaces:
		var mode: WorldVisibility.VisibilityMode = runtime.visibility.get_local_visibility_mode(surface)
		if mode != WorldVisibility.VisibilityMode.HIDDEN:
			continue
		var center: Vector2 = to_local(runtime.surface_to_world(surface))
		var rect: Rect2 = Rect2(center - cell_size * 0.5, cell_size)
		draw_rect(rect, HIDDEN_COLOR)
		draw_texture_rect(CLOUD_TEXTURE, rect, false, Color(0.09, 0.1, 0.13, 0.78))


func _refresh() -> void:
	if runtime == null or runtime.visibility == null:
		return
	_update_live_entities()
	_update_static_objects()
	_update_effects()
	explored_layer.queue_redraw()
	queue_redraw()


func _update_live_entities() -> void:
	for entity_value: Variant in runtime.get_registered_entities():
		var entity: Entity = entity_value as Entity
		if entity != null:
			entity.visible = runtime.visibility.is_surface_visible_for_local_player(entity.current_surface)


func _update_static_objects() -> void:
	var local_player_id: String = runtime.visibility.get_local_player_id()
	var memories: Dictionary = runtime.visibility.get_object_memories(local_player_id)
	for proxy: Sprite2D in proxy_by_object_id.values():
		if is_instance_valid(proxy):
			proxy.visible = false
	var live_ids: Dictionary[String, bool] = {}
	for object_value: Variant in runtime.get_registered_objects():
		var grid_object: GridObject = object_value as GridObject
		if grid_object == null or grid_object.object_id.is_empty():
			continue
		live_ids[grid_object.object_id] = true
		var mode: WorldVisibility.VisibilityMode = runtime.visibility.get_object_visibility_mode(local_player_id, grid_object)
		grid_object.visible = mode == WorldVisibility.VisibilityMode.VISIBLE
		if mode == WorldVisibility.VisibilityMode.VISIBLE:
			_update_proxy_from_live(grid_object)
		elif mode == WorldVisibility.VisibilityMode.EXPLORED and memories.has(grid_object.object_id):
			_update_proxy_from_memory(grid_object.object_id, memories[grid_object.object_id] as Dictionary, grid_object)
		_set_proxy_visibility(grid_object.object_id, mode == WorldVisibility.VisibilityMode.EXPLORED)
	for object_id_value: Variant in memories.keys():
		var object_id: String = str(object_id_value)
		if live_ids.has(object_id):
			continue
		var memory: Dictionary = memories[object_id_value] as Dictionary
		var memory_surface: Vector3i = memory.get("surface", WorldGridTopology.INVALID_SURFACE)
		_update_proxy_from_memory(object_id, memory, null)
		_set_proxy_visibility(
			object_id,
			runtime.visibility.get_local_visibility_mode(memory_surface) == WorldVisibility.VisibilityMode.EXPLORED
		)


func _update_proxy_from_live(grid_object: GridObject) -> void:
	if grid_object.sprite == null:
		return
	var proxy: Sprite2D = proxy_by_object_id.get(grid_object.object_id) as Sprite2D
	if proxy == null:
		proxy = Sprite2D.new()
		proxy.name = "LastSeen_" + grid_object.object_id
		proxy_by_object_id[grid_object.object_id] = proxy
		add_child(proxy)
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


func _update_proxy_from_memory(object_id: String, memory: Dictionary, live_object: GridObject) -> void:
	var texture_path: String = str(memory.get("texture_path", ""))
	if texture_path.is_empty():
		return
	var texture: Texture2D = load(texture_path) as Texture2D
	if texture == null:
		return
	var proxy: Sprite2D = proxy_by_object_id.get(object_id) as Sprite2D
	if proxy == null:
		proxy = Sprite2D.new()
		proxy.name = "LastSeen_" + object_id
		proxy_by_object_id[object_id] = proxy
		add_child(proxy)
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


func _set_proxy_visibility(object_id: String, should_show: bool) -> void:
	var proxy: Sprite2D = proxy_by_object_id.get(object_id) as Sprite2D
	if proxy != null:
		proxy.visible = should_show


func _update_effects() -> void:
	var effects_root: Node = runtime.get_node_or_null("SpellEffects")
	if effects_root == null:
		return
	for effect: Node in effects_root.get_children():
		if effect is CanvasItem and effect is Node2D:
			var surface: Vector3i = runtime.resolve_surface_at_world((effect as Node2D).global_position, 0)
			(effect as CanvasItem).visible = runtime.visibility.is_surface_visible_for_local_player(surface)


func _restore_live_nodes() -> void:
	if runtime == null:
		return
	for entity_value: Variant in runtime.get_registered_entities():
		if entity_value is CanvasItem:
			(entity_value as CanvasItem).visible = true
	for object_value: Variant in runtime.get_registered_objects():
		if object_value is CanvasItem:
			(object_value as CanvasItem).visible = true


func _clear_proxies() -> void:
	for proxy: Sprite2D in proxy_by_object_id.values():
		if is_instance_valid(proxy):
			proxy.queue_free()
	proxy_by_object_id.clear()


func _disconnect_visibility() -> void:
	if runtime == null or runtime.visibility == null:
		return
	if runtime.visibility.local_visibility_changed.is_connected(_refresh):
		runtime.visibility.local_visibility_changed.disconnect(_refresh)
	if runtime.visibility.fog_enabled_changed.is_connected(_on_fog_enabled_changed):
		runtime.visibility.fog_enabled_changed.disconnect(_on_fog_enabled_changed)


func _on_fog_enabled_changed(_is_enabled: bool) -> void:
	_refresh()
