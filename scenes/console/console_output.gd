extends RefCounted
class_name ConsoleOutput


static func print_console(text: String, world: Node = null) -> void:
	if world != null and world.has_method("print_console"):
		world.print_console(text)
		return

	print_line(text)


static func print_line(text: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return

	var console: Node = tree.root.get_node_or_null("Console")
	if console != null and console.has_method("print_line"):
		console.print_line(text)
