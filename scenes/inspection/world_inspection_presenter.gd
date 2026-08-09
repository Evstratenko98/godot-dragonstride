class_name WorldInspectionPresenter
extends RefCounted


static func create_content(
	inspectable: WorldInspectable,
	runtime: WorldRuntime
) -> WorldInspectionContent:
	if inspectable == null or inspectable.target == null or inspectable.preview_sprite == null:
		return null

	var content: WorldInspectionContent = WorldInspectionContent.new()
	content.title = inspectable.get_title()
	content.description = inspectable.description
	_copy_preview(inspectable.preview_sprite, content)
	_append_entity_stats(inspectable, runtime, content)
	return content


static func _copy_preview(sprite: Sprite2D, content: WorldInspectionContent) -> void:
	content.preview_texture = sprite.texture
	content.preview_hframes = maxi(sprite.hframes, 1)
	content.preview_vframes = maxi(sprite.vframes, 1)
	content.preview_frame = sprite.frame
	content.preview_region_enabled = sprite.region_enabled
	content.preview_region_rect = sprite.region_rect
	content.preview_flip_h = sprite.flip_h
	content.preview_flip_v = sprite.flip_v
	content.preview_modulate = sprite.modulate * sprite.self_modulate


static func _append_entity_stats(
	inspectable: WorldInspectable,
	runtime: WorldRuntime,
	content: WorldInspectionContent
) -> void:
	var entity: Entity = inspectable.target as Entity
	if entity == null:
		return
	if inspectable.has_stat(WorldInspectable.StatFlag.HEALTH):
		content.stats.append(WorldInspectionStat.new(
			"Здоровье",
			"%d / %d" % [entity.health, entity.max_health]
		))
	if inspectable.has_stat(WorldInspectable.StatFlag.MOVEMENT):
		content.stats.append(WorldInspectionStat.new(
			"Очки перемещения",
			_get_movement_text(entity, runtime)
		))
	if inspectable.has_stat(WorldInspectable.StatFlag.DAMAGE):
		content.stats.append(WorldInspectionStat.new("Урон", str(entity.damage)))
	if inspectable.has_stat(WorldInspectable.StatFlag.VISION):
		content.stats.append(WorldInspectionStat.new("Радиус обзора", str(entity.vision_radius)))


static func _get_movement_text(entity: Entity, runtime: WorldRuntime) -> String:
	var maximum_steps: int = entity.get_max_movement_steps_per_turn()
	var player: PlayerCharacter = entity as PlayerCharacter
	var turn_manager: WorldTurns = null if runtime == null else runtime.turn_manager
	if player != null and turn_manager != null and turn_manager.is_entity_active_in_turn(player):
		return "%d / %d" % [turn_manager.get_steps_left(player.entity_id), maximum_steps]
	return "%d за ход" % maximum_steps
