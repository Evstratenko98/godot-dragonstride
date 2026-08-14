class_name WorldSpawnCatalog
extends RefCounted

const KIND_ENTITY := "entity"
const KIND_OBJECT := "object"

const FAILURE_MESSAGES := {
	"network_unavailable": "Network is not ready.",
	"unknown_type": "Unknown spawn type.",
	"invalid_placement": "The requested cell cannot be used.",
	"invalid_clear_type": "Unknown clear type.",
	"registration_failed": "The spawned item could not be registered.",
}

const SHEEP_SCENE := preload("res://scenes/entities/sheep/sheep.tscn")
const WARRIOR_SCENE := preload("res://scenes/entities/enemies/warrior/warrior.tscn")
const TREE_SCENE := preload("res://scenes/objects/tree/tree.tscn")
const HOUSE_SCENE := preload("res://scenes/objects/house/house.tscn")
const MEAT_SCENE := preload("res://scenes/objects/meat/meat.tscn")
const PRECISION_STONE_SCENE := preload("res://scenes/objects/precision_stone/precision_stone.tscn")
const METEOR_SCROLL_SCENE := preload("res://scenes/objects/meteor_scroll/meteor_scroll.tscn")
const CHEST_SCENE := preload("res://scenes/objects/chest/chest.tscn")
const VISION_TOWER_SCENE := preload("res://scenes/objects/vision_tower/vision_tower.tscn")
const HEALING_WELL_SCENE := preload("res://scenes/objects/healing_well/healing_well.tscn")
const LINKED_PORTAL_SCENE := preload("res://scenes/objects/linked_portal/linked_portal.tscn")

const DEFINITIONS := {
	"sheep": {"kind": KIND_ENTITY, "scene": SHEEP_SCENE, "display_name": "Sheep"},
	"warrior": {"kind": KIND_ENTITY, "scene": WARRIOR_SCENE, "display_name": "Warrior"},
	"tree": {"kind": KIND_OBJECT, "scene": TREE_SCENE, "display_name": "Tree"},
	"house": {"kind": KIND_OBJECT, "scene": HOUSE_SCENE, "display_name": "House"},
	"meat": {"kind": KIND_OBJECT, "scene": MEAT_SCENE, "display_name": "Meat"},
	"precision_stone": {"kind": KIND_OBJECT, "scene": PRECISION_STONE_SCENE, "display_name": "Precision Stone"},
	"meteor_scroll": {"kind": KIND_OBJECT, "scene": METEOR_SCROLL_SCENE, "display_name": "Meteor Scroll"},
	"chest": {"kind": KIND_OBJECT, "scene": CHEST_SCENE, "display_name": "Chest"},
	"vision_tower": {"kind": KIND_OBJECT, "scene": VISION_TOWER_SCENE, "display_name": "Vision Tower"},
	"healing_well": {"kind": KIND_OBJECT, "scene": HEALING_WELL_SCENE, "display_name": "Healing Well"},
	"linked_portal": {"kind": KIND_OBJECT, "scene": LINKED_PORTAL_SCENE, "display_name": "Linked Portal"},
}


static func normalize_type_key(type_key: String) -> String:
	return type_key.strip_edges().to_lower()


static func has_type(type_key: String) -> bool:
	return DEFINITIONS.has(normalize_type_key(type_key))


static func get_kind(type_key: String) -> String:
	var definition: Dictionary = DEFINITIONS.get(normalize_type_key(type_key), {}) as Dictionary
	return str(definition.get("kind", ""))


static func get_scene(type_key: String) -> PackedScene:
	var definition: Dictionary = DEFINITIONS.get(normalize_type_key(type_key), {}) as Dictionary
	return definition.get("scene") as PackedScene
