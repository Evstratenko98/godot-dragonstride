class_name EntityProvokedIndicatorPresenter
extends RefCounted

const INDICATOR_TEXTURE: Texture2D = preload("res://art/pointers/tool_sword_a.svg")
const INDICATOR_SCALE: Vector2 = Vector2(0.65, 0.65)
const INDICATOR_GAP: float = 4.0
const INDICATOR_MIN_Z_INDEX: int = 101

var visual_owner: Entity = null
var indicator: Sprite2D = null


func configure(owner: Entity) -> void:
	if visual_owner == owner:
		return
	visual_owner = owner
	indicator = null


func set_visible(is_visible: bool) -> void:
	var target_indicator: Sprite2D = _get_indicator()
	if target_indicator == null:
		return
	_layout(target_indicator)
	target_indicator.visible = is_visible


func _get_indicator() -> Sprite2D:
	if indicator != null and is_instance_valid(indicator):
		return indicator
	if visual_owner == null or not is_instance_valid(visual_owner):
		return null
	indicator = visual_owner.get_node_or_null("ProvokedIndicator") as Sprite2D
	if indicator == null:
		indicator = Sprite2D.new()
		indicator.name = "ProvokedIndicator"
		visual_owner.add_child(indicator)
	_configure_indicator(indicator)
	return indicator


func _configure_indicator(target_indicator: Sprite2D) -> void:
	target_indicator.scale = INDICATOR_SCALE
	target_indicator.texture = INDICATOR_TEXTURE
	target_indicator.modulate = Color(1.0, 0.08, 0.08, 1.0)
	target_indicator.visible = false
	_layout(target_indicator)


func _layout(target_indicator: Sprite2D) -> void:
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
	if target_indicator.texture != null:
		indicator_half_height = (
			target_indicator.texture.get_size().y
			* absf(target_indicator.scale.y)
			* 0.5
		)
	target_indicator.position = Vector2(
		0.0,
		visual_top - INDICATOR_GAP - indicator_half_height
	)
	target_indicator.z_index = maxi(INDICATOR_MIN_Z_INDEX, highest_visual_z_index + 1)
