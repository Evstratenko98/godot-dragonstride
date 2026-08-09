class_name WorldMapTileSetCatalog
extends RefCounted

const GROUND_TILE_SET: TileSet = preload("res://scenes/world/map/tile_sets/sandbox_ground_tileset.tres")
const HAY_TILE_SET: TileSet = preload("res://scenes/world/map/tile_sets/sandbox_hay_tileset.tres")
const BRIDGE_TILE_SET: TileSet = preload("res://scenes/world/map/tile_sets/sandbox_bridge_tileset.tres")
const WATER_TILE_SET: TileSet = preload("res://scenes/world/map/tile_sets/sandbox_water_tileset.tres")
const CLOUDS_TILE_SET: TileSet = preload("res://scenes/world/map/tile_sets/sandbox_clouds_tileset.tres")
const PLATFORM_TILE_SET: TileSet = preload("res://scenes/world/map/tile_sets/sandbox_platform_tileset.tres")

const DEFINITIONS: Dictionary = {
	"ground": {"tile_set": GROUND_TILE_SET, "source_id": 0},
	"hay": {"tile_set": HAY_TILE_SET, "source_id": 0},
	"bridge": {"tile_set": BRIDGE_TILE_SET, "source_id": 1},
	"water": {"tile_set": WATER_TILE_SET, "source_id": 1},
	"clouds": {"tile_set": CLOUDS_TILE_SET, "source_id": 0},
	"platform": {"tile_set": PLATFORM_TILE_SET, "source_id": 1},
}


static func has_key(tile_set_key: String) -> bool:
	return DEFINITIONS.has(tile_set_key)


static func get_source_id(tile_set_key: String) -> int:
	var definition: Dictionary = DEFINITIONS.get(tile_set_key, {}) as Dictionary
	return int(definition.get("source_id", -1))


static func is_valid_tile(
	tile_set_key: String,
	source_id: int,
	atlas_coordinates: Vector2i,
	alternative_id: int
) -> bool:
	var definition: Dictionary = DEFINITIONS.get(tile_set_key, {}) as Dictionary
	var tile_set: TileSet = definition.get("tile_set") as TileSet
	if tile_set == null or source_id != int(definition.get("source_id", -1)):
		return false
	var atlas: TileSetAtlasSource = tile_set.get_source(source_id) as TileSetAtlasSource
	return (
		atlas != null
		and atlas.has_tile(atlas_coordinates)
		and atlas.has_alternative_tile(atlas_coordinates, alternative_id)
	)


static func create_tile_set(tile_set_key: String, _cells: Array) -> TileSet:
	var definition: Dictionary = DEFINITIONS.get(tile_set_key, {}) as Dictionary
	var tile_set: TileSet = definition.get("tile_set") as TileSet
	if tile_set == null:
		return null
	return tile_set.duplicate(true) as TileSet
