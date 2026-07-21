class_name WorldRuntimeResolver
extends RefCounted


static func from_node(source_node: Node) -> WorldRuntime:
	var ancestor: Node = source_node.get_parent()
	while ancestor != null:
		if ancestor is WorldRuntime:
			return ancestor as WorldRuntime
		if ancestor is WorldLevel:
			return (ancestor as WorldLevel).get_runtime()
		ancestor = ancestor.get_parent()
	return null
