class_name PlayerPortrait
extends PanelContainer

const DEFAULT_DIAMETER := 38.0
const BACKGROUND_COLOR := Color(0.10, 0.12, 0.16, 0.72)
const BORDER_COLOR := Color(0.42, 0.46, 0.54, 0.88)

var portrait: TextureRect = null
var portrait_texture: Texture2D = null


func _init() -> void:
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		set_diameter(DEFAULT_DIAMETER)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_apply_style()
	_build_portrait()
	_refresh_texture()


func set_player(player: PlayerCharacter) -> void:
	portrait_texture = null
	if player != null and player.view != null:
		portrait_texture = player.view.get_portrait_texture()
	_refresh_texture()


func set_portrait_texture(new_texture: Texture2D) -> void:
	portrait_texture = new_texture
	_refresh_texture()


func set_diameter(new_diameter: float) -> void:
	var diameter: float = maxf(new_diameter, 1.0)
	custom_minimum_size = Vector2(diameter, diameter)


func _apply_style() -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = BACKGROUND_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(64)
	style.set_content_margin_all(3.0)
	add_theme_stylebox_override("panel", style)


func _build_portrait() -> void:
	portrait = TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child.call_deferred(portrait)


func _refresh_texture() -> void:
	if portrait != null:
		portrait.texture = portrait_texture
