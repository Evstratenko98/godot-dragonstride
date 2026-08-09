class_name WorldInspectionCoordinator
extends Node

var runtime: WorldRuntime = null
var dialog: WorldInspectionDialog = null
var source: CellHover = null


func _exit_tree() -> void:
	_disconnect_source()


func configure(new_runtime: WorldRuntime, new_dialog: WorldInspectionDialog) -> void:
	runtime = new_runtime
	dialog = new_dialog


func bind_source(new_source: CellHover) -> void:
	_disconnect_source()
	source = new_source
	if source != null and not source.inspection_requested.is_connected(_on_inspection_requested):
		source.inspection_requested.connect(_on_inspection_requested)


func _disconnect_source() -> void:
	if source != null and source.inspection_requested.is_connected(_on_inspection_requested):
		source.inspection_requested.disconnect(_on_inspection_requested)
	source = null


func _on_inspection_requested(target: Node) -> void:
	if runtime == null or dialog == null or dialog.is_open():
		return
	var inspectable: WorldInspectable = WorldInspectable.from_target(target)
	var content: WorldInspectionContent = WorldInspectionPresenter.create_content(inspectable, runtime)
	if content != null:
		dialog.show_content(content)
