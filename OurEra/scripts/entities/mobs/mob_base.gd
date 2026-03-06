class_name MobBase
extends EntityBase

@export var move_speed := 4.0
@export var jump_velocity := 4.6
@export var gravity := 18.0
@export var max_health := 20.0
@export var ai_enabled := true

var health := 20.0

func _init() -> void:
	entity_category = "mob"
	entity_archetype = "mob"

func _ready() -> void:
	health = clamp(health, 0.0, max_health)
	if health <= 0.0:
		health = max_health
	super._ready()

func build_ai_context() -> Dictionary:
	return {
		"position": global_position,
		"velocity": velocity,
		"health": health,
		"max_health": max_health,
	}

func handle_damage(amount: float, source: EntityBase = null, context: Dictionary = {}) -> void:
	if amount <= 0.0:
		return

	health = maxf(0.0, health - amount)
	_on_damage_taken(amount, source, context)

	if health <= 0.0:
		_on_killed(source, context)
		request_despawn("killed")

func _entity_physics(delta: float) -> void:
	var movement := get_ai_movement_command(delta)
	var wish_dir := Vector3.ZERO
	var wish_variant: Variant = movement.get("wish_dir", Vector3.ZERO)
	if wish_variant is Vector3:
		wish_dir = wish_variant

	var wants_jump := bool(movement.get("jump", false))
	step_character_movement(delta, wish_dir, move_speed, jump_velocity, wants_jump, gravity)

func get_ai_movement_command(_delta: float) -> Dictionary:
	if not ai_enabled:
		return {}
	return {
		"wish_dir": Vector3.ZERO,
		"jump": false,
	}

func _get_custom_persisted_state() -> Dictionary:
	return {
		"health": health,
	}

func _apply_custom_persisted_state(state: Dictionary) -> void:
	health = clamp(float(state.get("health", max_health)), 0.0, max_health)

func _on_damage_taken(_amount: float, _source: EntityBase, _context: Dictionary) -> void:
	pass

func _on_killed(_source: EntityBase, _context: Dictionary) -> void:
	pass