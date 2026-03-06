class_name DropEntity
extends EntityBase

@export var gravity := 18.0
@export var horizontal_damping := 8.0
@export var pickup_radius := 1.25
@export var item_id: String = ""
@export var stack_size := 1

func _init() -> void:
	entity_category = "drop"
	entity_archetype = "drop"

func build_ai_context() -> Dictionary:
	return {
		"pickup_radius": pickup_radius,
		"item_id": item_id,
		"stack_size": stack_size,
	}

func can_be_picked_up_by(entity: EntityBase) -> bool:
	return entity != null and entity.entity_category == "player"

func collect_into(_collector: EntityBase) -> void:
	request_despawn("picked_up")

func _entity_physics(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, horizontal_damping * delta)
	velocity.z = move_toward(velocity.z, 0.0, horizontal_damping * delta)

	if not is_on_floor():
		velocity.y = maxf(velocity.y - gravity * delta, -terminal_fall_speed)

	move_and_slide()

func _get_custom_persisted_state() -> Dictionary:
	return {
		"item_id": item_id,
		"stack_size": stack_size,
	}

func _apply_custom_persisted_state(state: Dictionary) -> void:
	item_id = String(state.get("item_id", item_id))
	stack_size = maxi(1, int(state.get("stack_size", stack_size)))