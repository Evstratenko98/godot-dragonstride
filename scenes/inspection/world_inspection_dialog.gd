class_name WorldInspectionDialog
extends Control

signal open_state_changed(is_open: bool)

const PREVIEW_PADDING := 20.0
const MAX_PREVIEW_SCALE := 3.0

@onready var panel: PanelContainer = get_node("Backdrop/Center/Panel") as PanelContainer
@onready var title_label: Label = get_node(
	"Backdrop/Center/Panel/Margin/Content/Header/TitleLabel"
) as Label
@onready var close_button: Button = get_node(
	"Backdrop/Center/Panel/Margin/Content/Header/CloseButton"
) as Button
@onready var preview_area: Control = get_node(
	"Backdrop/Center/Panel/Margin/Content/Body/PreviewPanel/PreviewArea"
) as Control
@onready var preview_sprite: Sprite2D = get_node(
	"Backdrop/Center/Panel/Margin/Content/Body/PreviewPanel/PreviewArea/PreviewSprite"
) as Sprite2D
@onready var description_label: Label = get_node(
	"Backdrop/Center/Panel/Margin/Content/Body/DetailsScroll/Details/DescriptionLabel"
) as Label
@onready var stats_title: Label = get_node(
	"Backdrop/Center/Panel/Margin/Content/Body/DetailsScroll/Details/StatsTitle"
) as Label
@onready var stats_grid: GridContainer = get_node(
	"Backdrop/Center/Panel/Margin/Content/Body/DetailsScroll/Details/StatsGrid"
) as GridContainer


func _ready() -> void:
	_apply_style()
	preview_area.resized.connect(_layout_preview)
	visible = false
	set_process_unhandled_input(false)


func _unhandled_input(_event: InputEvent) -> void:
	if visible:
		get_viewport().set_input_as_handled()


func show_content(content: WorldInspectionContent) -> bool:
	if content == null or visible or content.preview_texture == null:
		return false
	title_label.text = content.title
	description_label.text = content.description
	_apply_preview(content)
	_rebuild_stats(content.stats)
	visible = true
	set_process_unhandled_input(true)
	open_state_changed.emit(true)
	call_deferred("_focus_close_button")
	call_deferred("_layout_preview")
	return true


func is_open() -> bool:
	return visible


func close() -> void:
	if not visible:
		return
	visible = false
	set_process_unhandled_input(false)
	_release_focus()
	open_state_changed.emit(false)


func _apply_preview(content: WorldInspectionContent) -> void:
	preview_sprite.texture = content.preview_texture
	preview_sprite.hframes = content.preview_hframes
	preview_sprite.vframes = content.preview_vframes
	preview_sprite.frame = clampi(
		content.preview_frame,
		0,
		content.preview_hframes * content.preview_vframes - 1
	)
	preview_sprite.region_enabled = content.preview_region_enabled
	preview_sprite.region_rect = content.preview_region_rect
	preview_sprite.flip_h = content.preview_flip_h
	preview_sprite.flip_v = content.preview_flip_v
	preview_sprite.modulate = content.preview_modulate
	preview_sprite.centered = true
	preview_sprite.offset = Vector2.ZERO


func _layout_preview() -> void:
	if preview_sprite.texture == null or preview_area.size.x <= 0.0 or preview_area.size.y <= 0.0:
		return
	var sprite_rect: Rect2 = preview_sprite.get_rect()
	if sprite_rect.size.x <= 0.0 or sprite_rect.size.y <= 0.0:
		return
	var available_size: Vector2 = Vector2(
		maxf(preview_area.size.x - PREVIEW_PADDING * 2.0, 1.0),
		maxf(preview_area.size.y - PREVIEW_PADDING * 2.0, 1.0)
	)
	var preview_scale: float = minf(
		available_size.x / sprite_rect.size.x,
		available_size.y / sprite_rect.size.y
	)
	preview_scale = clampf(preview_scale, 0.01, MAX_PREVIEW_SCALE)
	preview_sprite.scale = Vector2.ONE * preview_scale
	preview_sprite.position = preview_area.size * 0.5 - sprite_rect.get_center() * preview_scale


func _rebuild_stats(stats: Array[WorldInspectionStat]) -> void:
	for child: Node in stats_grid.get_children():
		stats_grid.remove_child(child)
		child.queue_free()
	stats_title.visible = not stats.is_empty()
	stats_grid.visible = not stats.is_empty()
	for stat: WorldInspectionStat in stats:
		var label: Label = Label.new()
		label.text = stat.label
		label.add_theme_color_override("font_color", GameModalStyle.MUTED_TEXT_COLOR)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stats_grid.add_child.call_deferred(label)
		var value: Label = Label.new()
		value.text = stat.value
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.add_theme_color_override("font_color", GameModalStyle.TEXT_COLOR)
		value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stats_grid.add_child.call_deferred(value)


func _apply_style() -> void:
	panel.add_theme_stylebox_override("panel", GameModalStyle.create_panel_style())
	title_label.add_theme_color_override("font_color", GameModalStyle.TEXT_COLOR)
	description_label.add_theme_color_override("font_color", GameModalStyle.MUTED_TEXT_COLOR)
	stats_title.add_theme_color_override("font_color", GameModalStyle.TEXT_COLOR)
	GameModalStyle.apply_button_style(close_button)


func _focus_close_button() -> void:
	if visible and is_inside_tree():
		close_button.grab_focus()


func _release_focus() -> void:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if focus_owner != null and is_ancestor_of(focus_owner):
		focus_owner.release_focus()


func _on_close_button_pressed() -> void:
	close()
