class_name WorldSpawnRoots
extends RefCounted

var level: WorldLevel = null


func configure(new_level: WorldLevel) -> void:
	level = new_level
	if level != null:
		get_world_entities_root()


func get_world_entities_root() -> Node2D:
	var root: Node2D = level.get_world_entities_root()
	if root != null:
		root.y_sort_enabled = true
		return root
	root = Node2D.new()
	root.name = "WorldEntities"
	root.y_sort_enabled = true
	level.add_child(root)
	return root
