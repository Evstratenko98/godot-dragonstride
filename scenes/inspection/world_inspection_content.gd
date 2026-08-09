class_name WorldInspectionContent
extends RefCounted

var title: String = ""
var description: String = ""
var preview_texture: Texture2D = null
var preview_hframes: int = 1
var preview_vframes: int = 1
var preview_frame: int = 0
var preview_region_enabled: bool = false
var preview_region_rect: Rect2 = Rect2()
var preview_flip_h: bool = false
var preview_flip_v: bool = false
var preview_modulate: Color = Color.WHITE
var stats: Array[WorldInspectionStat] = []
