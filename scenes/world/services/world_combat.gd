class_name WorldCombat
extends Node

var runtime: WorldRuntime = null
var level: WorldLevel = null


func configure_context(new_runtime: WorldRuntime, new_level: WorldLevel) -> void:
	runtime = new_runtime
	level = new_level


func apply_attack_to_cell(
	attacker: Node,
	cell: Vector2i,
	should_broadcast: bool = true,
	should_broadcast_action: bool = true
) -> void:
	if should_broadcast_action and should_broadcast and GameSession.is_multiplayer() and attacker.get("entity_id") != null:
		NetworkManager.broadcast_entity_attack(str(attacker.get("entity_id")), cell)

	var target_entity: Node = runtime.get_entity_at_cell(cell)
	if target_entity != null and target_entity != attacker:
		_apply_entity_attack(attacker, target_entity, should_broadcast)
		return

	var target_object: GridObject = runtime.get_object_at_cell(cell) as GridObject
	if target_object != null:
		print_non_entity_attack_result(attacker, cell)
		target_object.take_damage()
		runtime.broadcast_object_state(target_object)
		return

	print_non_entity_attack_result(attacker, cell)


func get_entity_id(entity: Node) -> String:
	if entity == null or entity.get("entity_id") == null:
		return ""

	return str(entity.get("entity_id"))


func get_entity_display_name(entity: Node) -> String:
	if entity is Entity:
		return (entity as Entity).get_display_name()

	if entity != null and entity.get("entity_name") != null and not str(entity.get("entity_name")).is_empty():
		return str(entity.get("entity_name"))

	if entity != null:
		return entity.name

	return "entity"


func print_entity_attack_result(
	attacker_entity_id: String,
	target_entity_id: String,
	damage_amount: int,
	target_health: int,
	target_max_health: int
) -> void:
	var attacker_name: String = _get_entity_display_name_by_id(attacker_entity_id)
	var target_name: String = _get_entity_display_name_by_id(target_entity_id)
	runtime.print_console("%s hit %s for %d damage. %s HP: %d/%d" % [
		attacker_name,
		target_name,
		damage_amount,
		target_name,
		target_health,
		target_max_health,
	])


func _apply_entity_attack(attacker: Node, target_entity: Node, should_broadcast: bool) -> void:
	var damage_amount: int = 25
	if attacker.get("damage") != null:
		damage_amount = int(attacker.get("damage"))

	var previous_health: int = 0
	if target_entity.get("health") != null:
		previous_health = int(target_entity.get("health"))

	if target_entity is Entity:
		(target_entity as Entity).take_damage(damage_amount)

	var target_health: int = 0
	if target_entity.get("health") != null:
		target_health = int(target_entity.get("health"))

	var target_max_health: int = 100
	if target_entity.get("max_health") != null:
		target_max_health = int(target_entity.get("max_health"))

	var attacker_id: String = get_entity_id(attacker)
	var target_id: String = get_entity_id(target_entity)
	print_entity_attack_result(
		attacker_id,
		target_id,
		damage_amount,
		target_health,
		target_max_health
	)

	if should_broadcast:
		if not attacker_id.is_empty() and not target_id.is_empty():
			NetworkManager.broadcast_entity_attack_result(
				attacker_id,
				target_id,
				damage_amount,
				target_health,
				target_max_health
			)
		_broadcast_entity_damage_result(target_entity, previous_health > 0 and previous_health <= damage_amount)


func _broadcast_entity_damage_result(target_entity: Node, was_lethal: bool) -> void:
	if not GameSession.is_multiplayer():
		return

	var target_id: String = get_entity_id(target_entity)
	if target_id.is_empty():
		return

	var target_health: int = 0
	if target_entity.get("health") != null:
		target_health = int(target_entity.get("health"))

	if was_lethal:
		var target_type: int = int(target_entity.get("entity_type"))
		if target_type == Entity.EntityType.CHARACTER:
			var target_cell: Vector2i = target_entity.get("current_cell")
			NetworkManager.broadcast_entity_respawn(target_id, target_cell, target_health)
		else:
			NetworkManager.broadcast_entity_removed(target_id)
		return

	NetworkManager.broadcast_entity_health(target_id, target_health)


func print_non_entity_attack_result(attacker: Node, cell: Vector2i) -> void:
	var target_entity: Node = runtime.get_entity_at_cell(cell)
	if target_entity != null and target_entity != attacker:
		return

	var target_object: GridObject = runtime.get_object_at_cell(cell) as GridObject
	if target_object != null:
		runtime.print_console("%s deals damage to %s" % [get_entity_display_name(attacker), target_object.name])
		return

	runtime.print_console("%s hit %s" % [get_entity_display_name(attacker), runtime.get_cell_display_name(cell)])


func _get_entity_display_name_by_id(entity_id: String) -> String:
	var entity: Node = runtime.get_entity_by_id(entity_id)
	if entity != null:
		return get_entity_display_name(entity)

	if not entity_id.is_empty():
		return entity_id

	return "entity"
