class_name EntityOcclusionSilhouette
extends Node2D

const SILHOUETTE_COLOR: Color = Color(0.08, 0.16, 0.13, 0.58)

var entity: Entity = null
var source_sprite: Sprite2D = null
var silhouette_sprite: Sprite2D = null
var name_label: Label = null


func configure(owner: Entity, sprite: Sprite2D) -> void:
	entity = owner
	source_sprite = sprite
	name_label = entity.get_node_or_null("NameLabel") as Label
	z_as_relative = false
	if silhouette_sprite == null:
		silhouette_sprite = Sprite2D.new()
		silhouette_sprite.name = "SilhouetteSprite"
		silhouette_sprite.self_modulate = SILHOUETTE_COLOR
		silhouette_sprite.show_behind_parent = false
		add_child(silhouette_sprite)
	visible = false


func _exit_tree() -> void:
	_set_source_visuals_occluded(false)


func _process(_delta: float) -> void:
	if entity == null or entity.runtime == null or source_sprite == null or silhouette_sprite == null:
		_set_source_visuals_occluded(false)
		visible = false
		return
	if entity.movement_controller.is_traversing_ramp:
		_set_source_visuals_occluded(false)
		visible = false
		return
	var live_surface: Vector3i = entity.runtime.world_to_surface(
		entity.global_position,
		entity.current_surface.z
	)
	var surface_occlusion_z: int = _get_surface_occlusion_z(live_surface)
	var object_occlusion_z: int = _get_object_occlusion_z(live_surface)
	var is_occluded: bool = surface_occlusion_z >= 0 or object_occlusion_z >= 0
	_set_source_visuals_occluded(is_occluded)
	visible = is_occluded and entity.visible
	if not visible:
		return
	z_index = maxi(surface_occlusion_z, object_occlusion_z) + 1
	_sync_silhouette_sprite()


func _get_surface_occlusion_z(live_surface: Vector3i) -> int:
	var live_cell: Vector2i = Vector2i(live_surface.x, live_surface.y)
	if entity.runtime.is_ramp_footprint_cell(live_cell):
		return -1
	var highest_occluding_elevation: int = -1
	for surface: Vector3i in entity.runtime.get_surfaces_at(live_cell):
		if surface.z > entity.current_surface.z:
			highest_occluding_elevation = maxi(highest_occluding_elevation, surface.z)
	return -1 if highest_occluding_elevation < 0 else highest_occluding_elevation * 20


func _get_object_occlusion_z(live_surface: Vector3i) -> int:
	var surface_below: Vector3i = live_surface + Vector3i(0, 1, 0)
	var grid_object: GridObject = entity.runtime.get_object_at_surface(surface_below) as GridObject
	if grid_object == null or not grid_object.is_large_visual_object:
		return -1
	return grid_object.z_index


func _sync_silhouette_sprite() -> void:
	silhouette_sprite.texture = source_sprite.texture
	silhouette_sprite.hframes = source_sprite.hframes
	silhouette_sprite.vframes = source_sprite.vframes
	silhouette_sprite.frame = source_sprite.frame
	silhouette_sprite.flip_h = source_sprite.flip_h
	silhouette_sprite.flip_v = source_sprite.flip_v
	silhouette_sprite.position = source_sprite.position
	silhouette_sprite.scale = source_sprite.scale
	silhouette_sprite.offset = source_sprite.offset


func _set_source_visuals_occluded(is_occluded: bool) -> void:
	if source_sprite != null:
		source_sprite.visible = not is_occluded
	if name_label != null:
		name_label.visible = not is_occluded
