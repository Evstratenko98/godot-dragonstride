class_name FogChunkPresenter
extends Node2D

const MAX_CELLS: int = 64
const HIDDEN_COLOR: Color = Color(0.025, 0.03, 0.045, 0.98)
const EXPLORED_COLOR: Color = Color(0.08, 0.09, 0.11, 0.52)
const CLOUD_COLOR: Color = Color(0.09, 0.1, 0.13, 0.78)
const CLOUD_TEXTURE: Texture2D = preload(
	"res://art/Tiny Swords (Free Pack)/Terrain/Decorations/Clouds/Clouds_01.png"
)

var runtime: WorldRuntime = null
var surfaces: Array[Vector3i] = []
var mode_by_surface: Dictionary[Vector3i, int] = {}


func configure_context(new_runtime: WorldRuntime, new_surfaces: Array[Vector3i]) -> bool:
	if new_surfaces.size() > MAX_CELLS:
		return false
	runtime = new_runtime
	surfaces = new_surfaces.duplicate()
	refresh_all()
	return true


func refresh_all() -> void:
	mode_by_surface.clear()
	if runtime != null and runtime.visibility != null:
		for surface: Vector3i in surfaces:
			mode_by_surface[surface] = int(runtime.visibility.get_local_visibility_mode(surface))
	queue_redraw()


func refresh_surfaces(changed_surfaces: Array[Vector3i]) -> bool:
	if runtime == null or runtime.visibility == null:
		return false
	var was_changed: bool = false
	for surface: Vector3i in changed_surfaces:
		if not mode_by_surface.has(surface):
			continue
		var next_mode: int = int(runtime.visibility.get_local_visibility_mode(surface))
		if int(mode_by_surface[surface]) == next_mode:
			continue
		mode_by_surface[surface] = next_mode
		was_changed = true
	if was_changed:
		queue_redraw()
	return was_changed


func _draw() -> void:
	if runtime == null or runtime.visibility == null or not runtime.visibility.fog_enabled:
		return
	var cell_extent: float = float(runtime.get_cell_size())
	var cell_size: Vector2 = Vector2(cell_extent, cell_extent)
	for surface: Vector3i in surfaces:
		var mode: int = int(mode_by_surface.get(surface, WorldVisibility.VisibilityMode.HIDDEN))
		if mode == WorldVisibility.VisibilityMode.VISIBLE:
			continue
		var center: Vector2 = to_local(runtime.surface_to_world(surface))
		var rect: Rect2 = Rect2(center - cell_size * 0.5, cell_size)
		if mode == WorldVisibility.VisibilityMode.EXPLORED:
			draw_rect(rect, EXPLORED_COLOR)
			continue
		draw_rect(rect, HIDDEN_COLOR)
		draw_texture_rect(CLOUD_TEXTURE, rect, false, CLOUD_COLOR)
