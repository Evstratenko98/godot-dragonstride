class_name InventorySlotStyle
extends RefCounted


static func create(is_selected: bool = false, is_exhausted: bool = false) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.70)
	if is_selected:
		style.border_color = Color(1.0, 0.72, 0.12, 0.94)
	elif is_exhausted:
		style.border_color = Color(0.42, 0.18, 0.18, 0.88)
	else:
		style.border_color = Color(0.65, 0.65, 0.7, 0.82)
	style.set_border_width_all(2 if is_selected else 1)
	style.set_corner_radius_all(3)
	return style
