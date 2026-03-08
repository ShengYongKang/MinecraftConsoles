class_name DropEntity
extends EntityBase

@export var gravity := 18.0
@export var horizontal_damping := 8.0
@export var pickup_radius := 1.25
@export var pickup_delay := 0.15
@export var item_id := 0
@export var stack_size := 1

var _age := 0.0

func _init() -> void:
	entity_category = "drop"
	entity_archetype = "drop"
	stair_assist_enabled = false

func build_ai_context() -> Dictionary:
	return {
		"pickup_radius": pickup_radius,
		"item_id": item_id,
		"stack_size": stack_size,
	}

func can_be_picked_up_by(entity: EntityBase) -> bool:
	if entity == null or entity.entity_category != "player":
		return false
	if not world_allows_drop_pickup():
		return false
	if _age < pickup_delay:
		return false
	if item_id <= 0 or stack_size <= 0:
		return false
	if not entity.has_method("can_collect_drop_item"):
		return false
	return entity.can_collect_drop_item(item_id, stack_size)

func collect_into(collector: EntityBase) -> void:
	if not can_be_picked_up_by(collector):
		return
	if not collector.has_method("collect_drop_item"):
		return
	var accepted := int(collector.collect_drop_item(item_id, stack_size))
	if accepted <= 0:
		return
	stack_size -= accepted
	if stack_size <= 0:
		request_despawn("picked_up")

func _entity_physics(delta: float) -> void:
	_age += delta
	velocity.x = move_toward(velocity.x, 0.0, horizontal_damping * delta)
	velocity.z = move_toward(velocity.z, 0.0, horizontal_damping * delta)

	if not is_on_floor():
		velocity.y = maxf(velocity.y - gravity * delta, -terminal_fall_speed)

	move_and_slide()

func _get_custom_persisted_state() -> Dictionary:
	return {
		"item_id": item_id,
		"stack_size": stack_size,
		"pickup_delay": pickup_delay,
		"age": _age,
	}

func _apply_custom_persisted_state(state: Dictionary) -> void:
	item_id = maxi(0, int(state.get("item_id", item_id)))
	stack_size = maxi(1, int(state.get("stack_size", stack_size)))
	pickup_delay = maxf(0.0, float(state.get("pickup_delay", pickup_delay)))
	_age = maxf(0.0, float(state.get("age", _age)))
