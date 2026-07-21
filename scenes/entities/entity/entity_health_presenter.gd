class_name EntityHealthPresenter
extends RefCounted

const HEALTH_BAR_SCENE := preload("res://scenes/entities/health_bar/health_bar.tscn")

var owner_entity: Entity = null
var health_bar: Node2D = null


func configure(owner: Entity) -> void:
	owner_entity = owner


func ensure_created(offset: Vector2) -> void:
	if owner_entity == null:
		return
	if health_bar != null and is_instance_valid(health_bar):
		health_bar.position = offset
		return

	health_bar = HEALTH_BAR_SCENE.instantiate() as Node2D
	if health_bar == null:
		return
	health_bar.position = offset
	owner_entity.add_child(health_bar)


func update(current_health: int, maximum_health: int) -> void:
	if health_bar == null or not is_instance_valid(health_bar):
		return
	var progress: TextureProgressBar = health_bar.get_node_or_null("Progress") as TextureProgressBar
	if progress == null:
		return
	var safe_maximum_health: int = maxi(maximum_health, 1)
	progress.max_value = safe_maximum_health
	progress.value = clampi(current_health, 0, safe_maximum_health)
