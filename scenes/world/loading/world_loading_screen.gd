class_name WorldLoadingScreen
extends CanvasLayer

const MINIMUM_VISIBLE_MSEC: int = 1000

var root: ColorRect = null
var phase_label: Label = null
var detail_label: Label = null
var progress_bar: ProgressBar = null
var shown_at_msec: int = 0
var is_indeterminate: bool = true
var animation_step: int = 0
var next_animation_msec: int = 0
var phase_text: String = ""


func _ready() -> void:
	layer = 10_000
	_build_ui()
	show_loading()
	set_process(true)
	set_process_input(true)


func _input(_event: InputEvent) -> void:
	if visible:
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not visible or not is_indeterminate or Time.get_ticks_msec() < next_animation_msec:
		return
	animation_step = (animation_step + 1) % 4
	phase_label.text = phase_text + ".".repeat(animation_step)
	next_animation_msec = Time.get_ticks_msec() + 300


func show_loading() -> void:
	visible = true
	shown_at_msec = Time.get_ticks_msec()
	set_phase("Подготовка мира")


func set_phase(text: String) -> void:
	phase_text = text
	phase_label.text = text
	detail_label.text = ""
	progress_bar.visible = false
	is_indeterminate = true


func set_progress(text: String, completed: int, total: int) -> void:
	phase_text = text
	phase_label.text = text
	is_indeterminate = false
	progress_bar.visible = true
	progress_bar.max_value = float(maxi(total, 1))
	progress_bar.value = float(clampi(completed, 0, maxi(total, 1)))
	detail_label.text = "%d / %d" % [completed, total]


func show_failure(reason_code: String) -> void:
	is_indeterminate = false
	progress_bar.visible = false
	phase_text = "Не удалось загрузить мир"
	phase_label.text = phase_text
	detail_label.text = _get_failure_text(reason_code)


func hide_after_minimum() -> void:
	while Time.get_ticks_msec() - shown_at_msec < MINIMUM_VISIBLE_MSEC:
		await get_tree().process_frame
	visible = false


func wait_until_minimum_visible() -> void:
	while Time.get_ticks_msec() - shown_at_msec < MINIMUM_VISIBLE_MSEC:
		await get_tree().process_frame


func _build_ui() -> void:
	root = ColorRect.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.color = Color(0.025, 0.035, 0.055, 1.0)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var content: VBoxContainer = VBoxContainer.new()
	content.custom_minimum_size = Vector2(420, 0)
	content.add_theme_constant_override("separation", 14)
	center.add_child(content)

	var title: Label = Label.new()
	title.text = "DragonStride"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	content.add_child(title)
	phase_label = Label.new()
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label.add_theme_font_size_override("font_size", 20)
	content.add_child(phase_label)
	progress_bar = ProgressBar.new()
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size = Vector2(420, 18)
	content.add_child(progress_bar)
	detail_label = Label.new()
	detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(detail_label)


func _get_failure_text(reason_code: String) -> String:
	match reason_code:
		"map_invalid":
			return "Описание карты не прошло проверку."
		"map_sync_timeout":
			return "Истекло время ожидания карты от host."
		"map_too_large":
			return "Описание карты превышает допустимый размер."
		"map_build_failed":
			return "Полученные данные не удалось превратить в игровой мир."
		"state_sync_timeout", "spawn_snapshot_timeout", "world_timeout":
			return "Истекло время синхронизации игрового мира."
		"state_sync_invalid", "invalid_spawn_snapshot":
			return "Состояние игрового мира не прошло проверку."
		"snapshot_too_large":
			return "Состояние мира превышает сетевой лимит."
		_:
			return "Запуск матча был отменён."
