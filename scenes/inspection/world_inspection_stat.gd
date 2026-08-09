class_name WorldInspectionStat
extends RefCounted

var label: String = ""
var value: String = ""


func _init(new_label: String, new_value: String) -> void:
	label = new_label
	value = new_value
