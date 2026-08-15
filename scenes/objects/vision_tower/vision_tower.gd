class_name VisionTower
extends GridObject

const MAX_REVEAL_REGIONS: int = 16
const COLOR_ORDER: Array[String] = ["Blue", "Purple", "Red", "Yellow"]
const COLOR_TEXTURES: Dictionary = {
	"Blue": preload("res://art/Tiny Swords (Update 010)/Factions/Knights/Buildings/Tower/Tower_Blue.png"),
	"Purple": preload("res://art/Tiny Swords (Update 010)/Factions/Knights/Buildings/Tower/Tower_Purple.png"),
	"Red": preload("res://art/Tiny Swords (Update 010)/Factions/Knights/Buildings/Tower/Tower_Red.png"),
	"Yellow": preload("res://art/Tiny Swords (Update 010)/Factions/Knights/Buildings/Tower/Tower_Yellow.png"),
}

@export var reveal_regions: Array[VisionRevealRegion] = []
@export var owner_player_id: String = ""


func _init() -> void:
	occupied_offsets = [Vector2i.ZERO]
	blocks_vision = true
	is_large_visual_object = true


func take_damage() -> bool:
	return false


func can_interact(interactor: PlayerCharacter, world_runtime: WorldRuntime) -> bool:
	return (
		interactor != null
		and world_runtime != null
		and world_runtime.visibility != null
		and not interactor.owner_player_id.is_empty()
		and owner_player_id != interactor.owner_player_id
	)


func interact(interactor: PlayerCharacter, world_runtime: WorldRuntime) -> bool:
	if not can_interact(interactor, world_runtime):
		return false
	return world_runtime.visibility.capture_tower(self, interactor)


func apply_owner_player_id(new_owner_player_id: String) -> void:
	owner_player_id = new_owner_player_id
	apply_state_visual()


func apply_reveal_region_records(records: Array[Dictionary]) -> bool:
	if records.is_empty() or records.size() > MAX_REVEAL_REGIONS:
		return false
	var next_regions: Array[VisionRevealRegion] = []
	for record: Dictionary in records:
		var rect_values: Array = record.get("rect", []) as Array
		if rect_values.size() != 4:
			return false
		var region: VisionRevealRegion = VisionRevealRegion.new()
		region.configure(
			Rect2i(
				int(rect_values[0]),
				int(rect_values[1]),
				int(rect_values[2]),
				int(rect_values[3])
			),
			int(record.get("min_elevation", WorldGridTopology.MIN_ELEVATION)),
			int(record.get("max_elevation", WorldGridTopology.MIN_ELEVATION))
		)
		next_regions.append(region)
	reveal_regions = next_regions
	return true


func apply_state_visual() -> void:
	if sprite == null:
		return
	sprite.texture = get_texture_for_owner(owner_player_id)
	sprite.modulate = get_modulate_for_owner(owner_player_id)


func get_texture_for_owner(player_id: String) -> Texture2D:
	if player_id.is_empty():
		return COLOR_TEXTURES["Blue"] as Texture2D
	var color_index: int = 0
	for player: Dictionary in GameSession.get_players():
		if str(player.get("player_id", "")) == player_id:
			color_index = clampi(int(player.get("color_index", 0)), 0, COLOR_ORDER.size() - 1)
			break
	var color_name: String = COLOR_ORDER[color_index]
	return COLOR_TEXTURES[color_name] as Texture2D


func get_modulate_for_owner(player_id: String) -> Color:
	return Color(0.42, 0.42, 0.46, 1.0) if player_id.is_empty() else Color.WHITE
