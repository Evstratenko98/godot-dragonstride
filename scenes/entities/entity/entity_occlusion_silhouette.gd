class_name EntityOcclusionSilhouette
extends Node2D

const SILHOUETTE_COLOR: Color = Color(0.08, 0.16, 0.13, 0.58)

var entity: Entity = null
var source_sprite: Sprite2D = null
var silhouette_sprite: Sprite2D = null


func configure(owner: Entity, sprite: Sprite2D) -> void:
	entity = owner
	source_sprite = sprite
	z_as_relative = false
	if silhouette_sprite == null:
		silhouette_sprite = Sprite2D.new()
		silhouette_sprite.name = "SilhouetteSprite"
		silhouette_sprite.self_modulate = SILHOUETTE_COLOR
		silhouette_sprite.show_behind_parent = false
		add_child(silhouette_sprite)
	visible = false


func _process(_delta: float) -> void:
	if entity == null or entity.runtime == null or source_sprite == null or silhouette_sprite == null:
		visible = false
		return
	var column: Array[Vector3i] = entity.runtime.get_surfaces_at(
		Vector2i(entity.current_surface.x, entity.current_surface.y)
	)
	var highest_occluding_elevation: int = -1
	for surface: Vector3i in column:
		if surface.z > entity.current_surface.z:
			highest_occluding_elevation = maxi(highest_occluding_elevation, surface.z)
	visible = highest_occluding_elevation >= 0 and entity.visible
	if not visible:
		return
	z_index = highest_occluding_elevation * 20 + 1
	silhouette_sprite.texture = source_sprite.texture
	silhouette_sprite.hframes = source_sprite.hframes
	silhouette_sprite.vframes = source_sprite.vframes
	silhouette_sprite.frame = source_sprite.frame
	silhouette_sprite.flip_h = source_sprite.flip_h
	silhouette_sprite.flip_v = source_sprite.flip_v
	silhouette_sprite.position = source_sprite.position
	silhouette_sprite.scale = source_sprite.scale
	silhouette_sprite.offset = source_sprite.offset
