class_name WorldInspectable
extends Node

enum TitleSource {
	STORED,
	ENTITY_DISPLAY_NAME,
}

enum StatFlag {
	HEALTH = 1,
	MOVEMENT = 2,
	DAMAGE = 4,
	VISION = 8,
}

const COMPONENT_NODE_NAME := &"Inspectable"

@export var display_name: String = ""
@export_multiline var description: String = ""
@export var title_source: TitleSource = TitleSource.STORED
@export_flags("Health", "Movement", "Damage", "Vision") var stat_flags: int = 0
@export var target_path: NodePath = ^".."
@export var preview_sprite_path: NodePath = ^"../Sprite2D"

@onready var target: Node = get_node(target_path)
@onready var preview_sprite: Sprite2D = get_node(preview_sprite_path) as Sprite2D


func get_title() -> String:
	var entity: Entity = target as Entity
	if title_source == TitleSource.ENTITY_DISPLAY_NAME and entity != null:
		return entity.get_display_name()
	if not display_name.is_empty():
		return display_name
	return target.name


func has_stat(stat_flag: StatFlag) -> bool:
	return (stat_flags & int(stat_flag)) != 0


static func from_target(target_node: Node) -> WorldInspectable:
	if target_node == null:
		return null
	return target_node.get_node_or_null(NodePath(COMPONENT_NODE_NAME)) as WorldInspectable
