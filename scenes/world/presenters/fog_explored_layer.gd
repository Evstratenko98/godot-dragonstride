class_name FogExploredLayer
extends Node2D

const DESATURATION_SHADER_CODE := """
shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;

void fragment() {
	vec3 screen_color = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	float luminance = dot(screen_color, vec3(0.299, 0.587, 0.114));
	vec3 desaturated = mix(screen_color, vec3(luminance), 0.9) * 0.48;
	COLOR = vec4(desaturated, 1.0);
}
"""

var runtime: WorldRuntime = null


func _ready() -> void:
	var shader: Shader = Shader.new()
	shader.code = DESATURATION_SHADER_CODE
	var shader_material: ShaderMaterial = ShaderMaterial.new()
	shader_material.shader = shader
	material = shader_material


func configure_context(new_runtime: WorldRuntime) -> void:
	runtime = new_runtime
	queue_redraw()


func _draw() -> void:
	if runtime == null or runtime.visibility == null or not runtime.visibility.fog_enabled:
		return
	var cell_extent: float = float(runtime.get_cell_size())
	var cell_size: Vector2 = Vector2(cell_extent, cell_extent)
	for surface: Vector3i in runtime.visibility.display_surfaces:
		if runtime.visibility.get_local_visibility_mode(surface) != WorldVisibility.VisibilityMode.EXPLORED:
			continue
		var center: Vector2 = to_local(runtime.surface_to_world(surface))
		draw_rect(Rect2(center - cell_size * 0.5, cell_size), Color.WHITE)
