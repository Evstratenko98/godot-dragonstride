class_name NonPlayerView
extends Node

const PROVOKED_INDICATOR_TEXTURE: Texture2D = preload("res://art/pointers/tool_sword_a.svg")
const PROVOKED_INDICATOR_SCALE: Vector2 = Vector2(0.65, 0.65)
const PROVOKED_INDICATOR_GAP: float = 4.0
const PROVOKED_INDICATOR_MIN_Z_INDEX: int = 101

var provoked_indicator: Sprite2D = null


func face_direction(_direction: Vector2i) -> void:
	pass


func play_idle() -> void:
	pass


func play_walk() -> void:
	pass


func play_guard() -> void:
	pass


func play_attack(_attack_facing_left: bool, _update_horizontal_facing: bool) -> void:
	pass


func get_attack_duration() -> float:
	return 0.0


func get_facing_left() -> bool:
	return false


func set_provoked_indicator_visible(is_visible: bool) -> void:
	var indicator: Sprite2D = _get_provoked_indicator()
	if indicator != null:
		_layout_provoked_indicator(indicator)
		indicator.visible = is_visible


func _get_provoked_indicator() -> Sprite2D:
	if provoked_indicator != null and is_instance_valid(provoked_indicator):
		return provoked_indicator
	provoked_indicator = get_node_or_null("../ProvokedIndicator") as Sprite2D
	if provoked_indicator != null:
		_configure_provoked_indicator(provoked_indicator)
		return provoked_indicator
	var visual_owner: Node2D = get_parent() as Node2D
	if visual_owner == null:
		return null
	provoked_indicator = Sprite2D.new()
	provoked_indicator.name = "ProvokedIndicator"
	visual_owner.add_child(provoked_indicator)
	_configure_provoked_indicator(provoked_indicator)
	return provoked_indicator


func _configure_provoked_indicator(indicator: Sprite2D) -> void:
	indicator.scale = PROVOKED_INDICATOR_SCALE
	indicator.texture = PROVOKED_INDICATOR_TEXTURE
	indicator.modulate = Color(1.0, 0.08, 0.08, 1.0)
	indicator.visible = false
	_layout_provoked_indicator(indicator)


func _layout_provoked_indicator(indicator: Sprite2D) -> void:
	var visual_owner: Entity = get_parent() as Entity
	if visual_owner == null:
		return

	var visual_top: float = visual_owner.health_bar_offset.y
	var highest_visual_z_index: int = 0
	var health_bar: Node2D = visual_owner.health_presenter.health_bar
	if health_bar != null and is_instance_valid(health_bar):
		visual_top = minf(visual_top, health_bar.position.y)
		highest_visual_z_index = maxi(highest_visual_z_index, health_bar.z_index)

	var name_label: Label = visual_owner.get_node_or_null("NameLabel") as Label
	if name_label != null:
		visual_top = minf(visual_top, name_label.position.y)
		highest_visual_z_index = maxi(highest_visual_z_index, name_label.z_index)

	var indicator_half_height: float = 0.0
	if indicator.texture != null:
		indicator_half_height = indicator.texture.get_size().y * absf(indicator.scale.y) * 0.5
	indicator.position = Vector2(
		0.0,
		visual_top - PROVOKED_INDICATOR_GAP - indicator_half_height
	)
	indicator.z_index = maxi(PROVOKED_INDICATOR_MIN_Z_INDEX, highest_visual_z_index + 1)
